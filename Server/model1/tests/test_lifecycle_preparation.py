import hashlib,re,unittest
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]/'migrations'
class LifecyclePreparationTests(unittest.TestCase):
 def test_staging_only_no_deletion(self):
  source=(BASE/'005_lifecycle_jobs.sql').read_text();code='\n'.join(x for x in source.splitlines() if not x.startswith('--'))
  self.assertEqual(re.findall(r'CREATE TABLE `([^`]+)`',code),['justirl2_plenact_m1_stage']*3)
  self.assertNotRegex(code,r'(?i)\b(USE|DROP|ALTER|INSERT|DELETE|GRANT|TRUNCATE)\b')
  self.assertEqual(code.count('ENGINE=InnoDB'),3)
  jobs=code.split('CREATE TABLE')[1]
  self.assertNotIn('FOREIGN KEY',jobs) # Minimal receipt survives primary account/workspace removal.
  self.assertIn('requesting_session_sha256 BINARY(32)',jobs)
  self.assertIn('UNIQUE KEY m1_lifecycle_account_operation',jobs)
 def test_import_fingerprint(self):
  source=(BASE/'005_lifecycle_jobs.sql').read_bytes();artifact=(BASE/'005_lifecycle_jobs_import_qualified.sql').read_text()
  self.assertTrue(artifact.startswith(source.decode()));self.assertIn(hashlib.sha256(source).hexdigest(),artifact)
  self.assertEqual(artifact.count('INSERT INTO'),1)
if __name__=='__main__':unittest.main()
