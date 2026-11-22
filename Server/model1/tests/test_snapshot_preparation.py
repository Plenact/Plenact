import hashlib,re,unittest
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]/'migrations'
class SnapshotPreparationTests(unittest.TestCase):
 def test_staging_boundary(self):
  source=(BASE/'003_snapshot_leases.sql').read_text()
  code='\n'.join(x for x in source.splitlines() if not x.startswith('--'))
  self.assertEqual(re.findall(r'CREATE TABLE `([^`]+)`',code),['justirl2_plenact_m1_stage']*2)
  self.assertEqual(code.count('ENGINE=InnoDB'),2)
  self.assertNotRegex(code,r'(?i)\b(USE|DROP|ALTER|INSERT|DELETE|GRANT|TRUNCATE)\b')
  self.assertEqual(re.findall(r'REFERENCES `([^`]+)`',code),['justirl2_plenact_m1_stage']*3)
  self.assertIn('UNIQUE KEY m1_snapshot_record_identity',code)
 def test_exact_import_provenance(self):
  source=(BASE/'003_snapshot_leases.sql').read_bytes()
  artifact=(BASE/'003_snapshot_leases_import_qualified.sql').read_text()
  self.assertTrue(artifact.startswith(source.decode()))
  self.assertIn(hashlib.sha256(source).hexdigest(),artifact)
  self.assertEqual(artifact.count('INSERT INTO'),1)
if __name__=='__main__':unittest.main()
