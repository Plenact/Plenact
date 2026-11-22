import hashlib,re,unittest
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]/'migrations'
class AssetPreparationTests(unittest.TestCase):
 def test_staging_schema_only(self):
  source=(BASE/'004_asset_transfer.sql').read_text();code='\n'.join(x for x in source.splitlines() if not x.startswith('--'))
  self.assertEqual(re.findall(r'CREATE TABLE `([^`]+)`',code),['justirl2_plenact_m1_stage']*4)
  self.assertEqual(code.count('ENGINE=InnoDB'),4)
  self.assertNotRegex(code,r'(?i)\b(USE|DROP|ALTER|INSERT|DELETE|GRANT|TRUNCATE)\b')
  self.assertEqual(set(re.findall(r'REFERENCES `([^`]+)`',code)),{'justirl2_plenact_m1_stage'})
  self.assertIn('chunk_bytes MEDIUMBLOB NOT NULL',code)
  self.assertIn('PRIMARY KEY (upload_id, chunk_index)',code)
  self.assertIn('PRIMARY KEY (workspace_id, operation_id)',code)
 def test_import_fingerprint(self):
  source=(BASE/'004_asset_transfer.sql').read_bytes();artifact=(BASE/'004_asset_transfer_import_qualified.sql').read_text()
  self.assertTrue(artifact.startswith(source.decode()));self.assertIn(hashlib.sha256(source).hexdigest(),artifact)
  self.assertEqual(artifact.count('INSERT INTO'),1)
if __name__=='__main__':unittest.main()
