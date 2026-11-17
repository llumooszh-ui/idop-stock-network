import importlib.util
from pathlib import Path
import tempfile
import unittest
import pandas as pd
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('demo',ROOT/'examples/generate_demo.py')
demo=importlib.util.module_from_spec(spec);spec.loader.exec_module(demo)

class DemoTests(unittest.TestCase):
    def test_reproducibility_and_lags(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            a=demo.generate(p/'a');b=demo.generate(p/'b')
            self.assertEqual(a['files'],b['files'])
            frame=pd.read_csv(p/'a/data/combined.csv',dtype={'stock':str})
            expected=frame.groupby('stock').target_return.shift(1).fillna(0)
            np.testing.assert_allclose(frame.ret_lag1,expected)
            self.assertEqual(frame.stock.nunique(),12)
            self.assertFalse(frame.duplicated(['Date','stock']).any())
            with self.assertRaises(FileExistsError):demo.generate(p/'a')

if __name__=='__main__':unittest.main()
