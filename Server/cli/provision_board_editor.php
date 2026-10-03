<?php
/**************************************************************************************************
 * @file       provision_board_editor.php
 * @brief      Provision Jim as the shared Board's first canonical editor
 * @details    Read administrator configuration privately and enter the password without echo
 *
 **************************************************************************************************/
declare(strict_types=1);

$commonFile = getenv('PLENACT_API_COMMON') ?: __DIR__ . '/../api/common.php'; /* Shared API helper path */
require_once $commonFile;

// -------------------------------------- MARK: - CLI Guard ------------------------------------ //

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "This tool must run from PHP CLI.\n");
    exit(1);
}

// -------------------------------------- MARK: - Terminal Input ------------------------------- //

/**
 * @fcn        prompt
 * @brief      Read one visible value from the operator terminal
 *
 * @param[in]  $label Prompt displayed before input
 *
 * @return     (string) trimmed terminal input
 */
function prompt(string $label): string /* Visible operator input */
{
    fwrite(STDOUT, $label);
    return trim((string)fgets(STDIN));
}

/**
 * @fcn        prompt_secret
 * @brief      Read a password without echoing it to the terminal
 *
 * @param[in]  $label Prompt displayed before hidden input
 *
 * @return     (string) untrimmed password input
 *
 * @throws     RuntimeException when a terminal is unavailable
 */
function prompt_secret(string $label): string /* Hidden operator password input */
{
    $terminalMode = trim((string)shell_exec('stty -g 2>/dev/null')); /* Original terminal settings */
    if ($terminalMode === '') {
        throw new RuntimeException('A terminal is required to enter the account password safely');
    }

    fwrite(STDOUT, $label);
    shell_exec('stty -echo');
    try {
        $secret = rtrim((string)fgets(STDIN), "\r\n"); /* Password read without echo */
    } finally {
        shell_exec('stty ' . escapeshellarg($terminalMode));
        fwrite(STDOUT, PHP_EOL);
    }

    return $secret;
}

// -------------------------------------- MARK: - Board Editor Provisioning -------------------- //

try {
    $username     = strtolower(prompt('Jim account username: ')); /* Normalized account handle */
    $displayName  = prompt('Jim display name: ');                  /* Public directory name     */
    $password     = prompt_secret('New unique demo password (12+ characters): '); /* New account secret */
    $confirmation = prompt_secret('Confirm password: ');                          /* Secret confirmation */

    if (!preg_match('/\A[a-z0-9][a-z0-9._-]{2,39}\z/', $username)
        || !is_nonempty_text($displayName)
        || utf8_character_count($displayName) > 100
        || !is_demo_password($password)
        || !hash_equals($password, $confirmation)) {
        throw new RuntimeException('Account details are invalid or passwords do not match');
    }
    unset($confirmation);

    $pdo                 = database_connection_from_config('admin-database.json'); /* Temporary admin connection */
    $existingEditorCount = (int)$pdo->query("SELECT COUNT(*) FROM demo_users WHERE account_role = 'board_editor'")->fetchColumn(); /* Existing editor count */
    if ($existingEditorCount !== 0) {
        throw new RuntimeException('A Board editor already exists; refusing to create a second editor');
    }

    $userID    = new_uuid();      /* Stable server-side account identity */
    $statement = $pdo->prepare(  /* Initial Board-editor account insert */
        'INSERT INTO demo_users (
            user_id, username, display_name, email, password_hash, account_status, account_role,
            schema_version, record_revision, created_at_utc, updated_at_utc,
            created_by_user_id, updated_by_user_id, storage_origin
         ) VALUES (
            :user_id, :username, :display_name, NULL, :password_hash, \'active\', \'board_editor\',
            1, 1, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6), NULL, NULL, \'admin_action\'
         )'
    );
    $statement->execute([ /* Store the password hash and public identity */
        'user_id' => $userID,
        'username' => $username,
        'display_name' => $displayName,
        'password_hash' => password_hash($password, PASSWORD_DEFAULT),
    ]);

    fwrite(STDOUT, "Board editor provisioned. User ID: {$userID}\n");
} catch (Throwable $error) { /* Report an operator-safe failure */
    fwrite(STDERR, "Provisioning failed: {$error->getMessage()}\n");
    exit(1);
}
