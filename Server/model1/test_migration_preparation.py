#!/usr/bin/env python3
# --------------------------------------------------------------------------------------------------
# @file       test_migration_preparation.py
# @brief      Check staging-only DDL guards and deterministic import provenance without a database
# --------------------------------------------------------------------------------------------------
import hashlib
import json
from pathlib import Path
import re
import unittest
from build_core_import import build_import

BASE = Path(__file__).parent / 'migrations'


class CoreMigrationPreparationTests(unittest.TestCase):
    # @fcn test_target_and_operation_boundary
    # @brief Reject cross-database targets, destructive operations and runtime provisioning.
    def test_target_and_operation_boundary(self):
        code = '\n'.join(line for line in (BASE / '001_core.sql').read_text().splitlines()
                         if not line.lstrip().startswith('--'))
        self.assertNotRegex(code, r'(?i)\bUSE\b')
        self.assertEqual(re.findall(r'CREATE TABLE `([^`]+)`', code), ['justirl2_plenact_m1_stage'] * 8)
        self.assertNotRegex(code, r'CREATE TABLE m1_|REFERENCES m1_')
        self.assertEqual(re.findall(r'ALTER DATABASE\s+`([^`]+)`', code), ['justirl2_plenact_m1_stage'])
        self.assertNotRegex(code, r'(?i)\b(DROP|TRUNCATE|DELETE|GRANT|REVOKE|INSERT|REPLACE)\b')
        self.assertNotIn('IF NOT EXISTS', code)
        self.assertNotIn('FOREIGN_KEY_CHECKS', code)
        self.assertIn('CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci', code)

    # @fcn test_foreign_keys_reference_existing_typed_columns
    # @brief Verify every core foreign key points to earlier-created tables and actual columns.
    def test_foreign_keys_reference_existing_typed_columns(self):
        ddl = (BASE / '001_core.sql').read_text()
        tables = re.findall(r'CREATE TABLE `justirl2_plenact_m1_stage`\.`(m1_\w+)` \((.*?)\) ENGINE=InnoDB', ddl, re.S)
        self.assertEqual(len(tables), 8)
        known = {}
        for name, body in tables:
            columns = set(re.findall(r'^    (\w+) (?:CHAR|VARCHAR|BIGINT|JSON|DATETIME|TINYINT|BINARY)\b', body, re.M))
            for source, target, destination in re.findall(
                    r'FOREIGN KEY \(([^)]+)\)\s+REFERENCES `justirl2_plenact_m1_stage`\.`(\w+)`\(([^)]+)\)', body):
                self.assertIn(target, known)
                self.assertTrue(set(source.replace(' ', '').split(',')) <= columns)
                self.assertTrue(set(destination.replace(' ', '').split(',')) <= known[target])
            known[name] = columns
        self.assertEqual(ddl.count(') ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'), 8)

    # @fcn test_import_matches_exact_source_checksum
    # @brief Keep the operator import reproducible and its ledger linked to the exact reviewed DDL.
    def test_import_matches_exact_source_checksum(self):
        source = (BASE / '001_core.sql').read_bytes()
        generated = (BASE / '001_core_import_qualified.sql').read_text()
        self.assertEqual(generated, build_import())
        self.assertTrue(generated.startswith(source.decode()))
        self.assertIn(hashlib.sha256(source).hexdigest(), generated)
        self.assertEqual(generated.count('INSERT INTO `justirl2_plenact_m1_stage`.`m1_schema_migrations`'), 1)

    # @fcn test_applied_source_is_immutable
    # @brief Prevent silently rewriting migration bytes already observed on staging.
    def test_applied_source_is_immutable(self):
        evidence = json.loads((BASE / 'applied-staging.json').read_text())
        for migration in evidence['migrations']:
            self.assertEqual(hashlib.sha256((BASE / migration['source']).read_bytes()).hexdigest(),
                             migration['source_sha256'])

    # @fcn test_storage_probe_rolls_back_only_synthetic_dml
    # @brief Keep the operator diagnostic free of commits, schema changes and ambient schema assumptions.
    def test_storage_probe_rolls_back_only_synthetic_dml(self):
        source = (BASE.parent / 'tests/core_storage_probe.sql').read_text()
        code = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('--'))
        self.assertEqual(code.count('START TRANSACTION;'), 1)
        self.assertEqual(code.count('ROLLBACK;'), 1)
        self.assertNotRegex(code, r'(?i)\b(COMMIT|DELETE|UPDATE|CREATE|ALTER|DROP|TRUNCATE|GRANT|USE)\b')
        self.assertEqual(len(re.findall(r'INSERT INTO `justirl2_plenact_m1_stage`\.`m1_', code)), 7)
        self.assertNotRegex(code, r'(?i)(FROM|JOIN|INSERT INTO)\s+m1_')
        self.assertIn('UUID()', code)
        self.assertIn('f09f8cb1', code)
        self.assertLess(code.index('ROLLBACK;'), code.index('AS accounts_remaining'))


if __name__ == '__main__':
    unittest.main()
