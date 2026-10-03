<?php
/**************************************************************************************************
 * @file       common.php
 * @brief      Shared HTTP, configuration, database, and authenticated-session helpers
 * @details    Keep credentials outside the web root and emit generic JSON errors
 *
 **************************************************************************************************/
declare(strict_types=1);


// -------------------------------------- MARK: - Configuration ------------------------------- //

const PLENACT_JSON_DEPTH          = 512;        /* Maximum depth for JSON decoding            */
const PLENACT_MAX_REQUEST_BYTES   = 1048576;    /* Maximum allowed request body size in bytes */
const PLENACT_SESSION_TOKEN_BYTES = 32;         /* Length of session tokens in bytes          */
const PLENACT_MAX_PASSWORD_BYTES  = 72;         /* Maximum allowed password length in bytes   */

ini_set('display_errors', '0');


// -------------------------------------- MARK: - HTTP ---------------------------------------- //

/**
 * @fcn        respond_json
 * @brief      Send a no-store JSON response and terminate request handling
 * @details    The function sets the appropriate HTTP headers for a JSON response, attempts to 
 *             encode the response body as JSON, and handles any encoding errors by returning a 
 *             generic server error
 * 
 * @param[in]  $status HTTP status code
 * @param[in]  $body   JSON response fields
 * 
 * @return     (never) execution terminates after output
 */
function respond_json(int $status, array $body): never
{
    http_response_code($status);

    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');

    try {
        echo json_encode($body, JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE);

    } catch (Throwable) {

        http_response_code(500);

        echo '{"error":"server_error"}';
    }

    exit;
}


/**
 * @fcn        require_method
 * @brief      Enforce an endpoint's allowed HTTP methods
 * @details    The function checks the incoming request's HTTP method against a list of 
 *             allowed methods and responds with a 405 error if the method is not permitted
 * 
 * @param[in]  $allowed List of allowed uppercase method names
 * 
 * @return     (void) returns only when the method is allowed
 */
function require_method(array $allowed): void
{
    $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? ''); /* Incoming HTTP method */

    if (!in_array($method, $allowed, true)) {
        header('Allow: ' . implode(', ', $allowed));
        respond_json(405, ['error' => 'method_not_allowed']);
    }
}


/**
 * @fcn        require_https
 * @brief      Refuse API requests when the web server did not receive HTTPS
 * @details    The function checks the 'HTTPS' server variable to determine if the request 
 *             was made over a secure connection
 * 
 * @return     (void) returns only for a verified TLS request
 */
function require_https(): void
{
    $https = strtolower((string)($_SERVER['HTTPS'] ?? '')); /* Server TLS indicator */

    if ($https === '' || $https === 'off' || $https === '0') {
        respond_json(400, ['error' => 'https_required']);
    }
}


/**
 * @fcn        read_json_body
 * @brief      Decode a bounded application/json request body
 * @details    The request body must be a valid JSON object and is subject to size limitations 
 *             defined by PLENACT_MAX_REQUEST_BYTES
 * 
 * @return     (array) decoded JSON object
 */
function read_json_body(): array
{
    $contentType = strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0])); /* Normalized media type */

    if ($contentType !== 'application/json') {
        respond_json(415, ['error' => 'unsupported_media_type']);
    }

    $contentLength = $_SERVER['CONTENT_LENGTH'] ?? null; /* Declared request byte count */

    if (is_string($contentLength) && ctype_digit($contentLength) && (int)$contentLength > PLENACT_MAX_REQUEST_BYTES) {
        respond_json(413, ['error' => 'request_too_large']);
    }

    $input = fopen('php://input', 'rb'); /* Raw request stream */
    $body  = $input === false ? false : stream_get_contents($input, PLENACT_MAX_REQUEST_BYTES + 1); /* Bounded request bytes */

    if (is_resource($input)) {
        fclose($input);
    }

    if (!is_string($body) || $body === '') {
        respond_json(400, ['error' => 'invalid_json']);
    }

    if (strlen($body) > PLENACT_MAX_REQUEST_BYTES) {
        respond_json(413, ['error' => 'request_too_large']);
    }

    try {
        $decoded = json_decode($body, true, PLENACT_JSON_DEPTH, JSON_THROW_ON_ERROR); /* Parsed JSON object */
    } catch (JsonException) {
        respond_json(400, ['error' => 'invalid_json']);
    }

    if (!is_array($decoded) || array_is_list($decoded)) {
        respond_json(400, ['error' => 'invalid_json']);
    }

    return $decoded;
}


// -------------------------------------- MARK: - Private Configuration ----------------------- //

/**
 * @fcn        private_config_directory
 * @brief      Resolve configuration stored outside the deployed public document root
 * @details    The private configuration directory is expected to be located outside the web root 
 *             and contain sensitive configuration files
 * 
 * @return     (string) canonical private configuration directory
 * 
 * @throws     RuntimeException when configuration is missing or inside the web root
 */
function private_config_directory(): string
{
    $configured = getenv('PLENACT_PRIVATE_DIR'); /* Optional operator override */
    $candidate  = is_string($configured) && $configured !== ''
        ? $configured
        : dirname(__DIR__, 3) . '/plenact-private'; /* Default private config path */
    $privateDirectory = realpath($candidate); /* Canonical private directory */

    if ($privateDirectory === false || !is_dir($privateDirectory)) {
        throw new RuntimeException('Private configuration directory unavailable');
    }

    $documentRoot = realpath($_SERVER['DOCUMENT_ROOT'] ?? ''); /* Canonical web root */

    if ($documentRoot !== false && str_starts_with($privateDirectory . DIRECTORY_SEPARATOR, $documentRoot . DIRECTORY_SEPARATOR)) {
        throw new RuntimeException('Private configuration must be outside the document root');
    }

    return $privateDirectory;
}


/**
 * @fcn        load_private_json
 * @brief      Read one server-side JSON configuration file
 * @details    The file is expected to be a JSON object with key-value pairs representing configuration 
 *             settings
 * 
 * @param[in]  $fileName Basename of the private configuration file
 * 
 * @return     (array) decoded private configuration
 * 
 * @throws     RuntimeException when the file cannot be read or decoded
 */
function load_private_json(string $fileName): array
{
    $path     = private_config_directory() . DIRECTORY_SEPARATOR . $fileName; /* Private config file path */
    $contents = @file_get_contents($path);                                    /* Raw config bytes         */

    if ($contents === false) {
        throw new RuntimeException('Private configuration unavailable');
    }

    $decoded = json_decode($contents, true, PLENACT_JSON_DEPTH, JSON_THROW_ON_ERROR); /* Parsed config object */

    if (!is_array($decoded) || array_is_list($decoded)) {
        throw new RuntimeException('Private configuration invalid');
    }

    return $decoded;
}


/**
 * @fcn        database_connection_from_config
 * @brief      Open a strict PDO connection using private server configuration
 * @details    The configuration file must contain 'host', 'database', 'username', and 'password' keys
 * 
 * @param[in]  $fileName Safe private JSON config filename
 * 
 * @return     (PDO) configured database connection
 * 
 * @throws     RuntimeException when database configuration is invalid
 */
function database_connection_from_config(string $fileName): PDO
{
    if (!preg_match('/\A[a-z0-9-]+\.json\z/i', $fileName)) {
        throw new RuntimeException('Database configuration invalid');
    }
    $config = load_private_json($fileName); /* Validated private DB settings */

    foreach (['host', 'database', 'username', 'password'] as $key) { /* Validate each required setting */
        if (!isset($config[$key]) || !is_string($config[$key]) || $config[$key] === '') {
            throw new RuntimeException('Database configuration invalid');
        }
    }

    return new PDO(
        "mysql:host={$config['host']};dbname={$config['database']};charset=utf8mb4",
        $config['username'],
        $config['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_TIMEOUT => 5,
        ]
    );
}


/**
 * @fcn        database_connection
 * @brief      Open the least-privilege runtime PDO connection
 *
 * @return     (PDO) configured database connection
 */
function database_connection(): PDO
{
    return database_connection_from_config('database.json');
}


// -------------------------------------- MARK: - Identity And Sessions ----------------------- //

/**
 * @fcn        new_uuid
 * @brief      Generate a server-side RFC 4122 version-4 UUID
 *
 * @return     (string) lowercase UUID text
 */
function new_uuid(): string
{
    $bytes    = random_bytes(16);                  /* Cryptographically random UUID bytes */
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40); /* RFC 4122 version-four marker     */
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80); /* RFC 4122 variant marker          */
    $hex      = bin2hex($bytes);                   /* Lowercase UUID hex source         */

    return sprintf('%s-%s-%s-%s-%s', substr($hex, 0, 8), substr($hex, 8, 4), substr($hex, 12, 4), substr($hex, 16, 4), substr($hex, 20, 12));
}


/**
 * @fcn        deterministic_uuid
 * @brief      Produce a namespace-stable version-5 UUID for an import identity
 *
 * @param[in]  $name Stable seed/version string
 *
 * @return     (string) lowercase UUID text
 */
function deterministic_uuid(string $name): string
{
    $namespace = hex2bin('6ba7b8109dad11d180b400c04fd430c8'); /* Fixed RFC 4122 namespace */
    $hex       = bin2hex(substr(hash('sha1', $namespace . 'plenact-demo:' . $name, true), 0, 16)); /* Name-derived UUID bytes */
    $hex[12]   = '5'; /* RFC 4122 version-five marker */
    $hex[16]   = dechex((hexdec($hex[16]) & 0x3) | 0x8); /* RFC 4122 variant marker */

    return sprintf('%s-%s-%s-%s-%s', substr($hex, 0, 8), substr($hex, 8, 4), substr($hex, 12, 4), substr($hex, 16, 4), substr($hex, 20, 12));
}


/**
 * @fcn        authenticated_user
 * @brief      Resolve the active user for a bearer session token
 *
 * @param[in]  $pdo Database connection used for session lookup
 *
 * @return     (array) safe user identity and role fields
 */
function authenticated_user(PDO $pdo): array
{
    $authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? ''; /* Incoming bearer header */

    if (!preg_match('/\ABearer ([A-Fa-f0-9]{64})\z/', $authorization, $matches)) { /* Capture the bearer token */
        header('WWW-Authenticate: Bearer realm="plenact"');
        respond_json(401, ['error' => 'unauthorized']);
    }

    $tokenHash = hash('sha256', $matches[1]); /* One-way session-token digest */
    $statement = $pdo->prepare( /* Active account/session lookup */
        'SELECT s.session_id, u.user_id, u.username, u.display_name, u.account_role
         FROM demo_user_sessions s
         INNER JOIN demo_users u ON u.user_id = s.user_id
         WHERE s.token_sha256 = :token_hash
           AND s.revoked_at_utc IS NULL
           AND s.expires_at_utc > UTC_TIMESTAMP(6)
           AND u.account_status = \'active\'
         LIMIT 1'
    );
    $statement->execute(['token_hash' => $tokenHash]);
    $user = $statement->fetch(); /* Safe identity and role projection */

    if ($user === false) {
        header('WWW-Authenticate: Bearer realm="plenact"');
        respond_json(401, ['error' => 'unauthorized']);
    }

    return $user;
}


/**
 * @fcn        require_board_editor
 * @brief      Restrict canonical Board content writes to the configured editor
 *
 * @param[in]  $user Authenticated user record
 *
 * @return     (void) returns only for the Board editor
 */
function require_board_editor(array $user): void
{
    if (($user['account_role'] ?? null) !== 'board_editor') {
        respond_json(403, ['error' => 'forbidden']);
    }
}


// -------------------------------------- MARK: - Input Validation ---------------------------- //

/**
 * @fcn        resolve_assignment_target_user_id
 * @brief      Apply the member self-assignment boundary before database access
 *
 * @param[in]  $actor     Authenticated session user
 * @param[in]  $requested Client-requested target ID, if any
 *
 * @return     (array) [target user ID or null, error code or null]
 */
function resolve_assignment_target_user_id(array $actor, mixed $requested): array
{
    if (($actor['account_role'] ?? null) === 'board_editor') {
        if (!is_uuid($requested)) {
            return [null, 'target_user_required'];
        }
        return [strtolower($requested), null];
    }

    $actorID = $actor['user_id'] ?? null; /* Verified account identity */
    if (!is_string($actorID) || !is_uuid($actorID)) {
        return [null, 'unauthorized'];
    }
    if ($requested !== null
        && (!is_string($requested) || strtolower($requested) !== strtolower($actorID))) {
        return [null, 'members_may_change_own_assignment_only'];
    }

    return [strtolower($actorID), null];
}


/**
 * @fcn        is_nonempty_text
 * @brief      Validate nonempty UTF-8 display text without control characters
 *
 * @param[in]  $value Candidate untrusted JSON value
 *
 * @return     (bool) true when the input is acceptable display text
 */
function is_nonempty_text(mixed $value): bool
{
    if (!is_string($value) || preg_match('//u', $value) !== 1) {
        return false;
    }

    $trimmed = trim($value); /* Normalized text for validation */

    return $trimmed !== '' && preg_match('/\A[^\x00-\x1F\x7F]+\z/u', $trimmed) === 1;
}


/**
 * @fcn        utf8_character_count
 * @brief      Count Unicode code points for SQL character-column limits
 *
 * @param[in]  $value Valid UTF-8 string
 *
 * @return     (int) number of Unicode code points, or PHP_INT_MAX for invalid UTF-8
 */
function utf8_character_count(string $value): int
{
    $count = preg_match_all('/./us', $value, $matches); /* Unicode count and match captures */

    return $count === false ? PHP_INT_MAX : $count;
}


/**
 * @fcn        is_demo_password
 * @brief      Check the minimum and maximum byte length supported by the demo hash policy
 *
 * @param[in]  $value Candidate password
 *
 * @return     (bool) true when the value can be hashed without bcrypt truncation
 */
function is_demo_password(mixed $value): bool
{
    return is_string($value)
        && strlen($value) >= 12
        && strlen($value) <= PLENACT_MAX_PASSWORD_BYTES;
}


/**
 * @fcn        is_uuid
 * @brief      Validate a canonical UUID string
 *
 * @param[in]  $value Candidate JSON value
 *
 * @return     (bool) true when the value is a UUID string
 */
function is_uuid(mixed $value): bool
{
    return is_string($value)
        && preg_match('/\A[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z/', $value) === 1;
}


/**
 * @fcn        validate_comment_list
 * @brief      Validate Codable comment rows before they enter a Board snapshot
 *
 * @param[in]  $comments Candidate comment list
 *
 * @return     (string|null) validation error code, or null when valid
 */
function validate_comment_list(mixed $comments): ?string
{
    if (!is_array($comments) || !array_is_list($comments)) {
        return 'invalid_comments';
    }

    foreach ($comments as $comment) { /* Validate each comment record */
        if (!is_array($comment)
            || !is_uuid($comment['id'] ?? null)
            || !is_nonempty_text($comment['author'] ?? null)
            || !is_string($comment['body'] ?? null)
            || preg_match('//u', $comment['body']) !== 1
            || (!is_int($comment['createdAt'] ?? null) && !is_float($comment['createdAt'] ?? null))) {
            return 'invalid_comment';
        }
    }

    return null;
}


/**
 * @fcn        validate_checklist_groups
 * @brief      Validate checklist/action Codable shapes, including reduced nested Action Details
 *
 * @param[in]  $checklists Candidate checklist groups
 * @param[in]  $depth      Current nested Action Detail depth
 *
 * @return     (string|null) validation error code, or null when valid
 */
function validate_checklist_groups(mixed $checklists, int $depth = 0): ?string
{
    if (!is_array($checklists) || !array_is_list($checklists)) {
        return 'invalid_checklist';
    }
    if ($depth > 8) {
        return 'action_detail_too_deep';
    }

    foreach ($checklists as $checklist) { /* Validate each checklist group */
        if (!is_array($checklist)
            || !is_uuid($checklist['id'] ?? null)
            || !is_nonempty_text($checklist['title'] ?? null)
            || !is_array($checklist['items'] ?? null)
            || !array_is_list($checklist['items'])) {
            return 'invalid_checklist';
        }

        foreach ($checklist['items'] as $item) { /* Validate each checklist action */
            if (!is_array($item)
                || !is_uuid($item['id'] ?? null)
                || !is_nonempty_text($item['title'] ?? null)
                || !is_bool($item['isCompleted'] ?? null)
                || !is_array($item['content'] ?? null)) {
                return 'invalid_checklist_action';
            }

            $content = $item['content']; /* Typed action payload */
            $kind    = $content['kind'] ?? null; /* Action discriminator */
            if (!in_array($kind, ['standard', 'linkedCard', 'actionDetail'], true)) {
                return 'invalid_checklist_action_kind';
            }

            if ($kind === 'linkedCard'
                && (!is_int($content['cardID'] ?? null) || $content['cardID'] < 0)) {
                return 'invalid_linked_card';
            }

            if ($kind === 'actionDetail') {
                $detail = $content['detail'] ?? null; /* Reduced Action Detail payload */
                if (!is_array($detail)
                    || !is_uuid($detail['id'] ?? null)
                    || !is_string($detail['description'] ?? null)
                    || preg_match('//u', $detail['description']) !== 1
                    || !is_array($detail['checklists'] ?? null)
                    || !array_is_list($detail['checklists'])) {
                    return 'invalid_action_detail';
                }

                $nestedError = validate_checklist_groups($detail['checklists'], $depth + 1); /* Nested checklist validation */
                if ($nestedError !== null) {
                    return $nestedError;
                }
                $commentError = validate_comment_list($detail['comments'] ?? null); /* Detail comment validation */
                if ($commentError !== null) {
                    return $commentError;
                }
            }
        }
    }

    return null;
}


/**
 * @fcn        validate_shared_attachments
 * @brief      Accept only Codable HTTPS link records in shared Board snapshots
 *
 * @param[in]  $attachments Candidate attachment metadata list
 *
 * @return     (string|null) validation error code, or null when valid
 */
function validate_shared_attachments(mixed $attachments): ?string
{
    if ($attachments === null) {
        return null;
    }
    if (!is_array($attachments) || !array_is_list($attachments)) {
        return 'invalid_attachments';
    }

    foreach ($attachments as $attachment) { /* Validate each shared attachment */
        $url = is_array($attachment) ? ($attachment['url'] ?? null) : null; /* Candidate link URL */
        if (!is_array($attachment)
            || !is_uuid($attachment['id'] ?? null)
            || ($attachment['mediaKind'] ?? null) !== 'link'
            || !is_string($url)
            || filter_var($url, FILTER_VALIDATE_URL) === false
            || strtolower((string)parse_url($url, PHP_URL_SCHEME)) !== 'https'
            || !is_string(parse_url($url, PHP_URL_HOST))
            || (!is_int($attachment['addedAt'] ?? null) && !is_float($attachment['addedAt'] ?? null))) {
            return 'invalid_shared_attachment';
        }
    }

    return null;
}


// -------------------------------------- MARK: - Board Document ------------------------------ //

/**
 * @fcn        shared_board_document
 * @brief      Remove device-local photo/video references while retaining HTTPS links
 *
 * @param[in]  $document Candidate Board document
 *
 * @return     (array) document normalized for the shared demo
 */
function shared_board_document(array $document): array
{
    if (!is_array($document['lists'] ?? null) || !array_is_list($document['lists'])) {
        return $document;
    }

    foreach ($document['lists'] as &$list) { /* Process each Board list */
        if (!is_array($list) || !is_array($list['cards'] ?? null) || !array_is_list($list['cards'])) {
            continue;
        }

        foreach ($list['cards'] as &$card) { /* Process each list card */
            if (!is_array($card) || !is_array($card['attachments'] ?? null)) {
                continue;
            }

            $card['attachments'] = array_values(array_filter( /* Keep only remote HTTPS links */
                $card['attachments'],
                static fn ($attachment /* Candidate attachment metadata */): bool => is_array($attachment)
                    && ($attachment['mediaKind'] ?? null) === 'link'
                    && is_string($attachment['url'] ?? null)
                    && preg_match('/\Ahttps:\/\//i', $attachment['url']) === 1
            ));
        }
        unset($card);
    }
    unset($list);

    return $document;
}


/**
 * @fcn        validate_board_document
 * @brief      Validate the Plenact Board snapshot envelope and nested stable identities
 * @details    Confirms lists/cards, linked-action payloads, labels, and registered assignee
 *             references before a snapshot can be stored
 *
 * @param[in]  $document         Decoded Board JSON object
 * @param[in]  $activeUserIDs    Set-like map of active registered user IDs
 *
 * @return     (string|null) validation message, or null for a valid document
 */
function validate_board_document(mixed $document, array $activeUserIDs): ?string
{
    if (!is_array($document)
        || ($document['schema_version'] ?? null) !== 1
        || ($document['board_key'] ?? null) !== 'shared-demo'
        || !is_array($document['lists'] ?? null)
        || !array_is_list($document['lists'])
        || !is_array($document['label_library'] ?? null)
        || !is_array($document['label_library']['categories'] ?? null)
        || !array_is_list($document['label_library']['categories'])
        || !is_array($document['label_library']['labels'] ?? null)
        || !array_is_list($document['label_library']['labels'])) {
        return 'invalid_document_envelope';
    }

    $categoryIDs = []; /* Category IDs defined in the label library */
    foreach ($document['label_library']['categories'] as $category) { /* Validate each category record */
        if (!is_array($category)
            || !is_nonempty_text($category['id'] ?? null)
            || !is_nonempty_text($category['name'] ?? null)
            || isset($categoryIDs[$category['id']])) {
            return 'invalid_label_category';
        }
        $categoryIDs[$category['id']] = true; /* Register validated category ID */
    }

    $labelIDs    = []; /* Label IDs defined in the library */
    $labelColors = ['mint', 'yellow', 'orange', 'coral', 'pink', 'purple', 'blue', 'green', 'red', 'gray']; /* Supported Swift color tokens */
    foreach ($document['label_library']['labels'] as $label) { /* Validate each reusable label record */
        if (!is_array($label)
            || !is_nonempty_text($label['id'] ?? null)
            || !is_nonempty_text($label['name'] ?? null)
            || !isset($categoryIDs[$label['categoryID'] ?? ''])
            || !in_array($label['color'] ?? null, $labelColors, true)
            || isset($labelIDs[$label['id']])) {
            return 'invalid_label';
        }
        $labelIDs[$label['id']] = true; /* Register validated label ID */
    }

    $listIDs = []; /* List IDs already accepted */
    $cardIDs = []; /* Card IDs already accepted */

    foreach ($document['lists'] as $list) { /* Validate ordered Board lists */
        if (!is_array($list)
            || !is_int($list['id'] ?? null)
            || $list['id'] < 0
            || isset($listIDs[$list['id']])
            || !is_nonempty_text($list['title'] ?? null)
            || !is_array($list['cards'] ?? null)
            || !array_is_list($list['cards'])) {
            return 'invalid_board_list';
        }

        $listIDs[$list['id']] = true; /* Register validated list ID */

        foreach ($list['cards'] as $card) { /* Validate each nested card */
            if (!is_array($card)
                || !is_int($card['id'] ?? null)
                || $card['id'] < 0
                || isset($cardIDs[$card['id']])
                || !is_nonempty_text($card['word'] ?? null)
                || ($card['listTitle'] ?? null) !== $list['title']
                || !is_bool($card['isDivider'] ?? null)
                || !is_bool($card['isTitleChecked'] ?? null)
                || !is_array($card['members'] ?? null)
                || !array_is_list($card['members'])
                || !is_array($card['checklists'] ?? null)
                || !array_is_list($card['checklists'])
                || !is_array($card['comments'] ?? null)
                || !array_is_list($card['comments'])
                || !is_array($card['labelIDs'] ?? null)
                || !array_is_list($card['labelIDs'])
                || !is_array($card['dismissedActivityIDs'] ?? null)
                || !array_is_list($card['dismissedActivityIDs'])) {
                return 'invalid_board_card';
            }

            $cardIDs[$card['id']] = true; /* Register validated card ID */

            foreach ($card['labelIDs'] as $labelID) { /* Resolve every assigned label ID */
                if (!is_string($labelID) || !isset($labelIDs[$labelID])) {
                    return 'unknown_card_label';
                }
            }

            foreach ($card['dismissedActivityIDs'] as $activityID) { /* Validate dismissed activity IDs */
                if (!is_string($activityID) || $activityID === '') {
                    return 'invalid_dismissed_activity_id';
                }
            }

            foreach (['startDate', 'dueDate'] as $dateKey) { /* Check optional JSON date values */
                if (array_key_exists($dateKey, $card)
                    && $card[$dateKey] !== null
                    && !is_int($card[$dateKey])
                    && !is_float($card[$dateKey])) {
                    return 'invalid_card_date';
                }
            }

            foreach (['descriptionOverride', 'subtitleOverride'] as $textKey) { /* Check optional card text values */
                if (array_key_exists($textKey, $card)
                    && $card[$textKey] !== null
                    && (!is_string($card[$textKey]) || preg_match('//u', $card[$textKey]) !== 1)) {
                    return 'invalid_card_text';
                }
            }

            foreach ($card['members'] as $assignee) { /* Validate typed card assignments */
                if (!is_array($assignee)
                    || !is_uuid($assignee['id'] ?? null)
                    || !is_nonempty_text($assignee['displayName'] ?? null)) {
                    return 'invalid_card_assignee';
                }

                if (($assignee['kind'] ?? null) === 'registeredUser') {
                    $userID = $assignee['userID'] ?? null; /* Stable registered account reference */
                    if (!is_uuid($userID) || !isset($activeUserIDs[strtolower($userID)])) {
                        return 'unknown_card_assignee';
                    }
                } elseif (($assignee['kind'] ?? null) === 'manual') {
                    if (($assignee['userID'] ?? null) !== null) {
                        return 'invalid_manual_assignee';
                    }
                } else {
                    return 'invalid_assignee_kind';
                }
            }

            $checklistError = validate_checklist_groups($card['checklists']); /* Nested checklist result */
            if ($checklistError !== null) {
                return $checklistError;
            }

            $commentError = validate_comment_list($card['comments']); /* Card activity validation result */
            if ($commentError !== null) {
                return $commentError;
            }

            $attachmentError = validate_shared_attachments($card['attachments'] ?? null); /* Shared-link validation result */
            if ($attachmentError !== null) {
                return $attachmentError;
            }
        }
    }

    return null;
}
