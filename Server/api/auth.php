<?php
/**************************************************************************************************
 * @file       auth.php
 * @brief      Login and logout for invited Plenact demo users
 * @details    Hash passwords server-side and store only hashes of opaque session tokens
 *
 **************************************************************************************************/
declare(strict_types=1);

require_once __DIR__ . '/common.php';


// -------------------------------------- MARK: - Authentication Route ------------------------ //

try {
    require_https();
    require_method(['POST']);
    $request = read_json_body();       /* Decoded authentication request */
    $action  = $request['action'] ?? null; /* Requested session operation     */
    $pdo     = database_connection();  /* Runtime database connection     */

    // -------------------------------------- MARK: - Logout ----------------------------------- //

    if ($action === 'logout') {
        $user      = authenticated_user($pdo); /* Verified bearer-session user */
        $sessionID = $user['session_id'];      /* Current session identifier  */
        $statement = $pdo->prepare( /* Current-session revocation query */
            'UPDATE demo_user_sessions SET revoked_at_utc = UTC_TIMESTAMP(6)
             WHERE session_id = :session_id AND revoked_at_utc IS NULL'
        );
        $statement->execute(['session_id' => $sessionID]);
        respond_json(200, ['logged_out' => true]);
    }

    if ($action !== 'login') {
        respond_json(400, ['error' => 'invalid_action']);
    }

    // -------------------------------------- MARK: - Login ------------------------------------ //

    $username = strtolower(trim(is_string($request['username'] ?? null) ? $request['username'] : '')); /* Normalized account handle */
    $password = $request['password'] ?? null;                                                         /* Submitted password       */

    if (!preg_match('/\A[a-z0-9][a-z0-9._-]{2,39}\z/', $username)
        || !is_string($password)
        || $password === ''
        || strlen($password) > PLENACT_MAX_PASSWORD_BYTES) {
        respond_json(401, ['error' => 'invalid_credentials']);
    }

    $usernameHash = hash('sha256', $username); /* Private throttle key */
    $pdo->beginTransaction();

    $limitInsert = $pdo->prepare( /* Ensure the throttle row exists */
        'INSERT INTO demo_login_limits (username_key_sha256, failure_count, window_started_at_utc, updated_at_utc)
         VALUES (:key_hash, 0, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))
         ON DUPLICATE KEY UPDATE failure_count = failure_count'
    );
    $limitInsert->execute(['key_hash' => $usernameHash]);

    $limitQuery = $pdo->prepare( /* Lock and read the throttle window */
        'SELECT failure_count, window_started_at_utc, locked_until_utc,
                TIMESTAMPDIFF(SECOND, window_started_at_utc, UTC_TIMESTAMP(6)) AS window_age_seconds,
                (locked_until_utc IS NOT NULL AND locked_until_utc > UTC_TIMESTAMP(6)) AS is_locked
         FROM demo_login_limits WHERE username_key_sha256 = :key_hash FOR UPDATE'
    );
    $limitQuery->execute(['key_hash' => $usernameHash]);
    $limit = $limitQuery->fetch(); /* Current attempt and lock state */

    if ($limit !== false && (int)$limit['is_locked'] === 1) {
        $pdo->commit();
        respond_json(429, ['error' => 'try_again_later']);
    }

    if ($limit !== false && (int)$limit['window_age_seconds'] > 900) {
        $reset = $pdo->prepare( /* Expired window reset query */
            'UPDATE demo_login_limits SET failure_count = 0,
             window_started_at_utc = UTC_TIMESTAMP(6), locked_until_utc = NULL,
             updated_at_utc = UTC_TIMESTAMP(6) WHERE username_key_sha256 = :key_hash'
        );
        $reset->execute(['key_hash' => $usernameHash]);
        $limit['failure_count'] = 0; /* Reset failures for the new window */
    }

    $userQuery = $pdo->prepare( /* Account lookup by normalized username */
        'SELECT user_id, username, display_name, password_hash, account_role, account_status
         FROM demo_users WHERE username = :username LIMIT 1'
    );
    $userQuery->execute(['username' => $username]);
    $user = $userQuery->fetch(); /* Matching account record, if present */

    if ($user === false
        || $user['account_status'] !== 'active'
        || !password_verify($password, $user['password_hash'])) {
        $failures      = (int)($limit['failure_count'] ?? 0) + 1; /* Consecutive failed login count */
        $updateFailure = $pdo->prepare( /* Failure count and lockout update */
            'UPDATE demo_login_limits SET failure_count = :failures,
             locked_until_utc = CASE WHEN :lock_condition = 1 THEN DATE_ADD(UTC_TIMESTAMP(6), INTERVAL 15 MINUTE) ELSE NULL END,
             updated_at_utc = UTC_TIMESTAMP(6) WHERE username_key_sha256 = :key_hash'
        );
        $updateFailure->execute([
            'failures' => $failures,
            'lock_condition' => $failures >= 5 ? 1 : 0,
            'key_hash' => $usernameHash,
        ]);
        $pdo->commit();
        respond_json($failures >= 5 ? 429 : 401, ['error' => $failures >= 5 ? 'try_again_later' : 'invalid_credentials']);
    }

    $clearFailures = $pdo->prepare('DELETE FROM demo_login_limits WHERE username_key_sha256 = :key_hash'); /* Successful-login cleanup */
    $clearFailures->execute(['key_hash' => $usernameHash]);

    // -------------------------------------- MARK: - Session Creation ------------------------- //

    $sessionToken  = bin2hex(random_bytes(PLENACT_SESSION_TOKEN_BYTES)); /* One-time bearer credential */
    $sessionID     = new_uuid();                                       /* Server-issued session identity */
    $sessionInsert = $pdo->prepare(                                    /* Session persistence query */
        'INSERT INTO demo_user_sessions (session_id, user_id, token_sha256, issued_at_utc, expires_at_utc)
         VALUES (:session_id, :user_id, :token_hash, UTC_TIMESTAMP(6), DATE_ADD(UTC_TIMESTAMP(6), INTERVAL 30 DAY))'
    );
    $sessionInsert->execute([
        'session_id' => $sessionID,
        'user_id' => $user['user_id'],
        'token_hash' => hash('sha256', $sessionToken),
    ]);

    $expiryQuery = $pdo->prepare('SELECT expires_at_utc FROM demo_user_sessions WHERE session_id = :session_id'); /* Expiry lookup */
    $expiryQuery->execute(['session_id' => $sessionID]);
    $expiresAt = $expiryQuery->fetchColumn(); /* Server-calculated expiration */
    $pdo->commit();

    respond_json(200, [
        'access_token' => $sessionToken,
        'expires_at_utc' => $expiresAt,
        'user' => [
            'user_id' => $user['user_id'],
            'username' => $user['username'],
            'display_name' => $user['display_name'],
            'account_role' => $user['account_role'],
        ],
    ]);
} catch (Throwable) { /* Return a generic response for unexpected failures */
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    respond_json(500, ['error' => 'server_error']);
}
