import sys, json, subprocess, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'Tools/UserDataModel'))
from validate_contract import validate_instance,load_json,CONTRACTS
class DataContractTests(unittest.TestCase):
    def test_structured_errors(self):
        errors=json.loads(subprocess.check_output(['php',str(Path(__file__).with_name('error_fixture.php'))]))
        for error in errors:
            validate_instance(error,load_json(CONTRACTS/'api-error.schema.json'),'api-error.schema.json')

    def test_initial_server_owned_records(self):
        records=json.loads(subprocess.check_output(['php',str(Path(__file__).with_name('bootstrap_fixture.php'))]))
        for record in records:
            validate_instance(record,load_json(CONTRACTS/'server-record.schema.json'),'server-record.schema.json')
        self.assertEqual([r['change_sequence'] for r in records],['1','2'])
        self.assertEqual([r['record_type'] for r in records],['account','workspace'])
if __name__=='__main__': unittest.main()
