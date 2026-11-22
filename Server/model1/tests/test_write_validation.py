import copy, importlib.util, json, subprocess, sys, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('write_validator',ROOT/'Server/model1/validation/validator.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)

class WriteValidationTests(unittest.TestCase):
    def test_request_fixture_and_duplicate_keys(self):
        raw=(v.CONTRACTS/'Fixtures/transaction-create.json').read_bytes()
        v.validate_request(raw)
        with self.assertRaises(v.ContractError): v.validate_request(raw.rstrip()[:-1]+b',"protocol_version":"1.0"}')
        for raw in [b'{"a":NaN}',b'{"a":1e9999}',b'{"a":"\\ud800"}']:
            with self.assertRaises((v.ContractError,ValueError)): v.validate_request(raw)

    def fixture(self):
        base=v.load_json(v.CONTRACTS/'Fixtures/complete-workspace-candidate.json')
        records=[base[k] for k in v.ONE.values() if base[k] is not None]
        records += [r for k in v.MANY.values() for r in base[k]]
        records += [r for k in v.CONTENT.values() for r in base['planning']['content'][k]]
        records += [r for k in v.PLANNING.values() for r in base['planning'][k]]
        heads={r['id']:{'record_type':r['record_type'],'record_id':r['id'],'workspace_id':r['workspace_id'],'deleted':False,'document':json.dumps(r)} for r in records}
        for t in base['tombstones']:
            heads[t['record_id']]={**t,'document':None}
        return {'account_id':base['account']['id'],'workspace_id':base['workspace']['id'],'heads':heads}

    def test_complete_graph(self):
        value=self.fixture();v.validate_candidate(value)
        bad=copy.deepcopy(value);bad['account_id']='11111111-1111-4111-8111-111111111111'
        with self.assertRaises(v.ContractError):v.validate_candidate(bad)
        card=next(h for h in value['heads'].values() if h['record_type']=='card' and not h['deleted'])
        doc=json.loads(card['document']);doc['payload']['list_id']='11111111-1111-4111-8111-111111111111';card['document']=json.dumps(doc)
        with self.assertRaises(v.ContractError):v.validate_candidate(value)

    def test_empty_invited_workspace(self):
        envelopes=json.loads(subprocess.check_output(['php',str(Path(__file__).with_name('bootstrap_fixture.php'))]))
        heads={e['record_id']:{**e,'document':json.dumps(e['document'])} for e in envelopes}
        v.validate_candidate({'account_id':envelopes[0]['record_id'],'workspace_id':envelopes[0]['workspace_id'],'heads':heads})

if __name__=='__main__':unittest.main()
