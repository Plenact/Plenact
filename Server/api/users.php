<?php
/**************************************************************************************************
 * @file       users.php
 * @brief      Shared demo user directory and Jim-managed member provisioning
 * @details    Exposes minimal directory fields and creates member accounts for the Board editor
 *
 **************************************************************************************************/
declare(strict_types=1);

require_once __DIR__ . '/common.php';


// -------------------------------------- MARK: - User Directory Route ------------------------ //

try {
    require_https();
    require_method(['GET', 'POST']);
    $pdo   = database_connection();    /* Runtime database connection */
    $actor = authenticated_user($pdo); /* Verified request identity   */

    if (strtoupper($_SERVER['REQUEST_METHOD'] ?? '') === 'GET') {
        // -------------------------------------- MARK: - Directory Read ----------------------- //

        $statement = $pdo->query( /* Active directory projection */
            "SELECT user_id, username, display_name
             FROM demo_users WHERE account_status = 'active'
             ORDER BY username ASC"
        );
        respond_json(200, ['users' => $statement->fetchAll()]);
    }

    // -------------------------------------- MARK: - Member Provisioning ---------------------- //

    require_board_editor($actor);
    $request     = read_json_body(); /* Decoded member-provisioning request */
    $username    = strtolower(trim(is_string($request['username'] ?? null) ? $request['username'] : '')); /* Normalized account handle */
    $displayName = trim(is_string($request['display_name'] ?? null) ? $request['display_name'] : '');   /* Directory display name    */
    $password    = $request['password'] ?? null;                                                        /* New member password       */
    $emailValue  = $request['email'] ?? null;                                                           /* Optional email input      */
    $email       = is_string($emailValue) ? trim($emailValue) : null;                                   /* Normalized optional email */

    if (!preg_match('/\A[a-z0-9][a-z0-9._-]{2,39}\z/', $username)
        || !is_nonempty_text($displayName)
        || utf8_character_count($displayName) > 100
        || !is_demo_password($password)
        || ($email !== null && $email !== '' && (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 254))) {
        respond_json(422, ['error' => 'invalid_user']);
    }

    // -------------------------------------- MARK: - Persist Member --------------------------- //

    $activeCount = (int)$pdo->query("SELECT COUNT(*) FROM demo_users WHERE account_status = 'active'")->fetchColumn(); /* Current active-account count */
    if ($activeCount >= 100) {
        respond_json(409, ['error' => 'demo_user_limit_reached']);
    }

    $userID    = new_uuid();       /* Stable server-side account identity */
    $statement = $pdo->prepare(   /* Member account insert */
        'INSERT INTO demo_users (
            user_id, username, display_name, email, password_hash, account_status, account_role,
            schema_version, record_revision, created_at_utc, updated_at_utc,
            created_by_user_id, updated_by_user_id, storage_origin
         ) VALUES (
            :user_id, :username, :display_name, :email, :password_hash, \'active\', \'member\',
            1, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6), :actor_id, :actor_id_update, \'admin_action\'
         )'
    );

    try {
        $statement->execute([ /* Persist hash and verified creator */
            'user_id' => $userID,
            'username' => $username,
            'display_name' => $displayName,
            'email' => $email === '' ? null : $email,
            'password_hash' => password_hash($password, PASSWORD_DEFAULT),
            'actor_id' => $actor['user_id'],
            'actor_id_update' => $actor['user_id'],
        ]);
    } catch (PDOException $error) { /* Resolve expected uniqueness conflicts */
        if ($error->getCode() === '23000') {
            respond_json(409, ['error' => 'username_or_email_unavailable']);
        }
        throw $error;
    }

    respond_json(201, [
        'user' => [
            'user_id' => $userID,
            'username' => $username,
            'display_name' => $displayName,
        ],
    ]);
} catch (Throwable) { /* Return a generic response for unexpected failures */
    respond_json(500, ['error' => 'server_error']);
}
