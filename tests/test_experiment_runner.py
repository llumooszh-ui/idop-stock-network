import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import numpy as np
import pandas as pd

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('runner',ROOT/'scripts/run_experiment.py')
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)

class RunnerTests(unittest.TestCase):
    def test_pipeline(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);dates=pd.bdate_range('2020-01-01','2020-05-29')
            frame=pd.MultiIndex.from_product([dates,[f'{i:06}' for i in range(8)]],names=['Date','stock']).to_frame(index=False)
            rng=np.random.default_rng(42)
            frame['signal']=rng.normal(size=len(frame));frame['target_return']=frame.signal*.01
            frame.to_csv(p/'f.csv',index=False)
            frame.pivot(index='Date',columns='stock',values='target_return').to_csv(p/'truth.csv')
            config={'frequency':'daily','start_date':'2020-04-01','end_date':'2020-04-30','output_dir':'out',
                    'truth':'truth.csv','models':{'a':{'factor_path':'f.csv'},'b':{'factor_path':'f.csv'}},
                    'comparisons':[['a','b']],'prediction':{'n_jobs':1,'n_estimators':3,'min_child_samples':5}}
            file=p/'config.json';file.write_text(json.dumps(config))
            runner.main(['--config',str(file),'--dry-run'])
            self.assertFalse((p/'out').exists())
            runner.main(['--config',str(file)])
            state=json.loads((p/'out/run_manifest.json').read_text())
            self.assertEqual(state['status'],'complete');self.assertEqual(len(state['steps']),3)
            self.assertTrue((p/'out/evaluation/a__vs__b/model_summary.csv').exists())
            with self.assertRaises(FileExistsError):runner.main(['--config',str(file)])
            config['output_dir']='failed';config['prediction']['num_leaves']=1
            file.write_text(json.dumps(config))
            with self.assertRaises(RuntimeError):runner.main(['--config',str(file)])
            self.assertEqual(json.loads((p/'failed/run_manifest.json').read_text())['status'],'failed')

    def test_reject_paths(self):
        config={'frequency':'daily','start_date':'2020-01-01','end_date':'2020-02-01','output_dir':'out',
                'truth':'out/truth.csv','models':{'a':{'factor_path':'a.csv'},'b':{'factor_path':'b.csv'}},'comparisons':[['a','b']]}
        with self.assertRaises(ValueError):runner.build_plan(config,Path('/tmp'))

if __name__=='__main__':unittest.main()
