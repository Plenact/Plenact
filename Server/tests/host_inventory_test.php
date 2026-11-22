<?php
/**************************************************************************************************
 * @file       host_inventory_test.php
 * @brief      Verify sanitized read-only hosting inventory output
 **************************************************************************************************/
declare(strict_types=1);
require_once __DIR__ . '/../cli/inventory_host.php';

/** @fcn inventory_check @brief Fail a synthetic inventory assertion without printing private data. */
function inventory_check(bool $condition, string $label): void
{
    if (!$condition) {
        throw new RuntimeException($label);
    }
}

$grant = "GRANT SELECT, INSERT, UPDATE, DELETE ON `synthetic_db`.* TO 'private-user'@'localhost' IDENTIFIED BY PASSWORD '*SYNTHETIC_SECRET_HASH'";
$summary = inventory_grant_summary($grant, 'synthetic_db');
inventory_check($summary['scope'] === 'selected_database', 'Database-scoped grant');
$escaped = inventory_grant_summary("GRANT SELECT ON `synthetic\\_db`.* TO 'x'@'localhost'", 'synthetic_db');
inventory_check($escaped['scope'] === 'selected_database', 'Escaped literal underscore in database grant');
inventory_check($summary['privileges'] === ['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'Exact DML grants');
$output = json_encode($summary, JSON_THROW_ON_ERROR);
foreach (['private-user', 'localhost', 'synthetic_db', 'SYNTHETIC_SECRET_HASH'] as $privateValue) {
    inventory_check(!str_contains($output, $privateValue), 'Grant identifiers must be omitted');
}
$view = inventory_grant_summary("GRANT CREATE VIEW, SHOW VIEW ON `synthetic_db`.* TO 'x'@'localhost'", 'synthetic_db');
inventory_check($view['privileges'] === ['CREATE VIEW', 'SHOW VIEW'], 'Do not overstate CREATE privileges');
$columns = inventory_grant_summary("GRANT SELECT (`secret_column`, `other_column`) ON `synthetic_db`.`t` TO 'x'@'localhost'", 'synthetic_db');
inventory_check($columns['privileges'] === ['SELECT'], 'Column-limited privilege parsing');
inventory_check(!str_contains(json_encode($columns), 'secret_column'), 'Column names omitted');
$global = inventory_grant_summary("GRANT ALL PRIVILEGES ON *.* TO 'x'@'localhost' WITH GRANT OPTION", 'synthetic_db');
inventory_check($global['scope'] === 'global' && $global['grant_option'], 'Global and delegation flags');
$report = inventory_host_report(['runtime-only' => false, 'storage' => sys_get_temp_dir()]);
inventory_check($report['database']['status'] === 'not_requested', 'Runtime-only must skip database access');
inventory_check($report['storage']['status'] === 'inspected', 'Inspect existing storage without writing');
inventory_check(!array_key_exists('path', $report['storage']), 'Storage paths omitted');
echo "Host inventory tests passed.\n";
