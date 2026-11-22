<?php
/**************************************************************************************************
 * @file       inventory_host.php
 * @brief      Read-only hosting capability inventory for private Model 1.0 staging
 * @details    Reports allowlisted runtime/database metadata, never credentials or authored records.
 *             Run privately through CLI; database access uses existing server configuration.
 **************************************************************************************************/
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

/**
 * @fcn        inventory_grant_summary
 * @brief      Remove identities, schema names, and authentication clauses from SHOW GRANTS
 * @return     (array) privilege names and coarse scope only
 */
function inventory_grant_summary(string $grant, string $database): array
{
    if (!preg_match('/^GRANT (.+?) ON (.+?) TO /i', $grant, $matches)) {
        return ['scope' => 'unrecognized', 'privileges' => [], 'grant_option' => false];
    }
    $scope = str_replace('`', '', $matches[2]);
    // SHOW GRANTS may escape literal underscores/percent signs in database identifiers.
    $scope = str_replace(['\\_', '\\%'], ['_', '%'], $scope);
    $privileges = [];
    $allowed = ['ALL PRIVILEGES', 'USAGE', 'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CREATE', 'ALTER',
        'DROP', 'INDEX', 'REFERENCES', 'TRIGGER', 'EXECUTE', 'EVENT', 'LOCK TABLES', 'SHOW VIEW',
        'CREATE VIEW', 'CREATE ROUTINE', 'ALTER ROUTINE', 'CREATE TEMPORARY TABLES', 'PROCESS',
        'FILE', 'SUPER', 'RELOAD', 'REPLICATION CLIENT', 'REPLICATION SLAVE'];
    foreach (preg_split('/,\s*(?![^()]*\))/', $matches[1]) as $clause) {
        // Column-limited grants retain their privilege name without exposing column names.
        $privilege = strtoupper(trim((string)preg_replace('/\s*\(.*\)$/s', '', $clause)));
        if (in_array($privilege, $allowed, true)) {
            $privileges[] = $privilege;
        }
    }
    return [
        'scope' => $scope === '*.*' ? 'global' : ($scope === $database . '.*' ? 'selected_database' : 'other_or_table'),
        'privileges' => $privileges,
        'grant_option' => (bool)preg_match('/ WITH GRANT OPTION\s*$/i', $grant),
    ];
}

/**
 * @fcn        inventory_host_report
 * @brief      Inspect capabilities without creating files or changing database state
 * @return     (array) sanitized report; hosting quotas, web PHP, and recovery remain manual checks
 */
function inventory_host_report(array $options): array
{
    $report = [
        'inventory_format' => 1,
        'collected_at_utc' => gmdate('c'),
        'runtime' => [
            'php_cli_version' => PHP_VERSION,
            'sapi' => PHP_SAPI,
            'pdo_drivers' => class_exists('PDO') ? PDO::getAvailableDrivers() : [],
            'extensions' => [],
            'limits' => [],
        ],
        'database' => ['status' => 'not_requested'],
        'storage' => ['status' => 'not_requested'],
        'manual_verification_required' => [
            'Web/FPM PHP version and limits (CLI may differ)',
            'Account disk/inode/database quotas and available headroom',
            'Staging database, API path and private storage namespace',
            'Backup retention, off-host copy, access and actual restore rehearsal',
            'DDL/migration operator grants (runtime grants are a separate account)',
            'HTTPS configuration for the intended staging API',
        ],
    ];
    foreach (['pdo_mysql', 'openssl', 'curl', 'mbstring', 'fileinfo', 'intl', 'sodium', 'gd'] as $extension) {
        $report['runtime']['extensions'][$extension] = extension_loaded($extension);
    }
    foreach (['memory_limit', 'max_execution_time', 'upload_max_filesize', 'post_max_size', 'max_file_uploads'] as $limit) {
        $report['runtime']['limits'][$limit] = ini_get($limit);
    }
    if (isset($options['storage'])) {
        $path = realpath((string)$options['storage']);
        $valid = $path !== false && is_dir($path);
        $mode = $valid ? @fileperms($path) : false;
        $report['storage'] = [
            'status' => $valid ? 'inspected' : 'unavailable',
            'readable' => $valid && is_readable($path),
            'writable_permission_only' => $valid && is_writable($path),
            'unix_mode' => $mode === false ? null : sprintf('%04o', $mode & 0777),
            'filesystem_free_bytes_not_account_quota' => $valid ? @disk_free_space($path) : null,
        ];
    }
    if (!isset($options['runtime-only'])) {
        try {
            $common = $options['common'] ?? __DIR__ . '/../api/common.php';
            if (!is_string($common) || !is_file($common)) {
                throw new RuntimeException('Unavailable helper');
            }
            require_once $common;
            $pdo = database_connection_from_config((string)($options['config'] ?? 'plenact-database.json'));
            $database = (string)$pdo->query('SELECT DATABASE()')->fetchColumn();
            $grants = $pdo->query('SHOW GRANTS FOR CURRENT_USER')->fetchAll(PDO::FETCH_COLUMN);
            $report['database'] = [
                'status' => 'inspected',
                'server_version' => $pdo->query('SELECT VERSION()')->fetchColumn(),
                'table_engines' => $pdo->query(
                    'SELECT ENGINE AS engine, COUNT(*) AS table_count FROM information_schema.TABLES '
                    . 'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = \'BASE TABLE\' GROUP BY ENGINE'
                )->fetchAll(PDO::FETCH_ASSOC),
                'grants' => array_map(fn(string $grant): array => inventory_grant_summary($grant, $database), $grants),
            ];
        } catch (Throwable) {
            // PDO/configuration errors can contain credentials or private host identifiers.
            $report['database'] = ['status' => 'unavailable', 'reason' => 'Check existing private configuration, helper path and PDO access locally.'];
        }
    }
    return $report;
}

if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    $options = getopt('', ['help', 'runtime-only', 'common:', 'config:', 'storage:']);
    if (isset($options['help'])) {
        fwrite(STDOUT, "Usage: php inventory_host.php [--runtime-only] [--common=/private/path/common.php] [--config=plenact-database.json] [--storage=/private/path]\n");
        exit(0);
    }
    ini_set('display_errors', '0');
    $report = inventory_host_report($options);
    fwrite(STDOUT, json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL);
    exit($report['database']['status'] === 'unavailable' ? 2 : 0);
}
