import tempfile
import unittest
from pathlib import Path
import numpy as np
import pandas as pd
from stock_network.evaluation.data import monthly_truth, read_wide
from stock_network.evaluation.ic_metrics import safe_spearman
from stock_network.evaluation.compare_models import holm_adjust, nw_mean_test
from stock_network.evaluation.run_evaluation import main

class EvaluationTests(unittest.TestCase):
    def test_metrics(self):
        x=pd.Series(range(6))
        self.assertAlmostEqual(safe_spearman(x,-x),-1)
        self.assertTrue(np.isnan(safe_spearman(x,x*0)))
        np.testing.assert_allclose(holm_adjust(pd.Series([.01,.04,.03])),[.03,.06,.06])
        self.assertEqual(nw_mean_test(pd.Series([1.,2.]),5)['n_days'],2)

    def test_month(self):
        x=pd.DataFrame({'001':[.1,.2,.3]},index=['2020-01-02','2020-01-03','2020-02-03'])
        self.assertAlmostEqual(monthly_truth(x).iloc[0,0],.32)
        x.iloc[0,0]=np.nan
        self.assertTrue(pd.isna(monthly_truth(x).iloc[0,0]))

    def test_cli_common_sample(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); rng=np.random.default_rng(42)
            y=pd.DataFrame(rng.normal(0,.01,(10,8)),index=pd.bdate_range('2020-01-01',periods=10).strftime('%Y-%m-%d'),columns=[f'{i:03}' for i in range(8)])
            y.to_csv(root/'truth.csv',index_label='Date')
            y.to_csv(root/'a.csv',index_label='Date')
            b=y*.8;b.iloc[0,0]=np.nan;b.to_csv(root/'b.csv',index_label='Date')
            args=['--model-a',str(root/'a.csv'),'--model-b',str(root/'b.csv'),'--truth',str(root/'truth.csv'),'--truth-encoding','utf-8-sig','--frequency','daily','--output-dir',str(root/'out')]
            main(args)
            summary=pd.read_csv(root/'out/model_summary.csv')
            self.assertEqual(summary.observations.tolist(),[79,79])
            self.assertAlmostEqual(summary.rmse.iloc[0],0)
            self.assertAlmostEqual(summary.mean_daily_rank_ic.iloc[0],1)
            with self.assertRaises(FileExistsError):main(args)
            duplicate=pd.concat([y,y.iloc[:1]]);duplicate.to_csv(root/'bad.csv')
            with self.assertRaises(ValueError):read_wide(root/'bad.csv')

if __name__=='__main__':unittest.main()
