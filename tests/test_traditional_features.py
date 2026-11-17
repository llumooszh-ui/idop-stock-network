import unittest
import numpy as np
import pandas as pd
from pandas.testing import assert_frame_equal
from stock_network.features.return_factors import build_return_factors
from stock_network.features.merge_features import merge_features

class TraditionalTests(unittest.TestCase):
    def test_return_timing(self):
        rng=np.random.default_rng(42)
        wide=pd.DataFrame(rng.normal(0,.01,(100,6)),index=pd.bdate_range('2020-01-01',periods=100),columns=list('abcdef'))
        wide.index.name='Date'
        original=build_return_factors(wide,'2020-01-01','2021-01-01')
        self.assertEqual(len(original.columns)-3,41)
        changed=wide.copy();date=wide.index[80];changed.loc[date:]=.5
        later=build_return_factors(changed,'2020-01-01','2021-01-01')
        assert_frame_equal(original.loc[original.Date<=date].drop(columns='target_return'),later.loc[later.Date<=date].drop(columns='target_return'))

    def test_keyed_merge(self):
        a=pd.DataFrame({'Date':pd.to_datetime(['2020-01-01','2020-01-02']),'stock':['001','001'],'target_return':[.1,np.nan],'ret_a':[1,2]})
        b=a.rename(columns={'ret_a':'net_b'}).iloc[::-1]
        merged=merge_features(a,b)
        self.assertEqual(merged.net_b.tolist(),[1,2])
        with self.assertRaises(ValueError):merge_features(a,b.iloc[:1])
        with self.assertRaises(ValueError):merge_features(a,pd.concat([b,b.iloc[:1]]))
        bad=b.copy();bad['target_return']=.9
        with self.assertRaises(ValueError):merge_features(a,bad)
        with self.assertRaises(ValueError):merge_features(a,a)

if __name__=='__main__':unittest.main()
