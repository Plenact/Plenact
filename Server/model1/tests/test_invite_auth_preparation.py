import hashlib
from pathlib import Path
import re
import unittest

BASE = Path(__file__).resolve().parents[1] / 'migrations'

class InviteAuthPreparationTests(unittest.TestCase):
    def test_schema_boundary_and_credentials(self):
        source = (BASE / '002_invite_auth.sql').read_text()
        code = '\n'.join(x for x in source.splitlines() if not x.startswith('--'))
        self.assertEqual(re.findall(r'CREATE TABLE `([^`]+)`', code), ['justirl2_plenact_m1_stage'] * 3)
        self.assertNotRegex(code, r'(?i)\b(USE|DROP|ALTER|INSERT|DELETE|GRANT|TRUNCATE)\b')
        self.assertEqual(code.count('ENGINE=InnoDB'), 3)
        self.assertEqual(code.count('REFERENCES `justirl2_plenact_m1_stage`.`m1_accounts`(account_id)'), 2)
        self.assertIn('UNIQUE KEY m1_password_email (email_normalized)', code)
        self.assertIn('token_sha256 BINARY(32)', code)
        self.assertIn('revoked_at_utc DATETIME(6) NULL', code)
        self.assertEqual(code.count('credential_version BIGINT'), 2)

    def test_import_provenance(self):
        source = (BASE / '002_invite_auth.sql').read_bytes()
        artifact = (BASE / '002_invite_auth_import_qualified.sql').read_text()
        self.assertTrue(artifact.startswith(source.decode()))
        self.assertIn(hashlib.sha256(source).hexdigest(), artifact)
        self.assertEqual(artifact.count('INSERT INTO'), 1)
        self.assertIn("VALUES ('002_invite_auth',", artifact)

    def test_preflight_is_read_only(self):
        code = '\n'.join(x for x in (BASE / '002_preflight.sql').read_text().splitlines() if not x.startswith('--'))
        self.assertEqual(code.count('SELECT '), 3)
        self.assertNotRegex(code, r'(?i)\b(USE|CREATE|UPDATE|INSERT|DELETE|ALTER|DROP)\b')

if __name__ == '__main__':
    unittest.main()
