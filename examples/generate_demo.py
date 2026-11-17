"""Generate small synthetic panels and runnable daily/monthly configurations."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import pandas as pd


def generate(output, seed=42):
    output=Path(output).resolve()
    if output.exists():
        raise FileExistsError('Choose a new demo directory: '+str(output))
    rng=np.random.default_rng(seed)
    # Weekdays form a synthetic calendar, not an exchange holiday calendar.
    dates=pd.bdate_range('2020-01-01','2021-04-30')
    stocks=[f'{i:06d}' for i in range(1,13)]
    n,m=len(dates),len(stocks)
    returns=np.zeros((n,m)); signal=np.zeros((n,m))
    # Fixed directed incoming exposures, column-L1 normalized, without self-loops.
    weights=rng.normal(size=(m,m));np.fill_diagonal(weights,0)
    weights/=np.abs(weights).sum(axis=0)
    for t in range(n):
        previous=returns[t-1] if t else np.zeros(m)
        signal[t]=previous @ weights
        returns[t]=.12*previous + .3*signal[t] + rng.normal(0,.01,m)
    lagged=np.vstack([np.zeros(m),returns[:-1]])
    # The rolling statistic shifts before rolling: no target-day information.
    volatility=pd.DataFrame(returns).shift(1).rolling(5,min_periods=2).std().fillna(0).to_numpy()
    keys=pd.MultiIndex.from_product([dates,stocks],names=['Date','stock']).to_frame(index=False)
    keys['target_return']=returns.ravel()
    conventional=keys.assign(ret_lag1=lagged.ravel(),ret_volatility5=volatility.ravel())
    network=keys.assign(net_demo_influence=signal.ravel(),net_demo_abs_influence=np.einsum("ti,ij->tj", np.abs(lagged), np.abs(weights), optimize=False).ravel())
    combined=conventional.merge(network.drop(columns='target_return'),on=['Date','stock'],validate='one_to_one')
    output.mkdir(parents=True)
    data=output/'data';data.mkdir()
    for name,frame in [('conventional',conventional),('network',network),('combined',combined)]:
        frame.to_csv(data/(name+'.csv'),index=False,encoding='utf-8-sig')
    pd.DataFrame(returns,index=dates,columns=stocks).rename_axis('Date').to_csv(data/'daily_returns.csv',encoding='utf-8-sig')
    pd.DataFrame({'Date':dates}).to_csv(data/'calendar.csv',index=False)
    configs=output/'configs';configs.mkdir()
    for mode in ('daily','monthly'):
        config={'frequency':mode,'start_date':'2021-01-01','end_date':'2021-03-31',
                'output_dir':'../runs/'+mode,'truth':'../data/daily_returns.csv','truth_encoding':'utf-8-sig',
                'calendar':'../data/calendar.csv',
                'models':{name:{'factor_path':'../data/'+name+'.csv'} for name in ('conventional','network','combined')},
                'comparisons':[['network','conventional'],['combined','conventional']],
                'prediction':{'n_jobs':1,'n_estimators':10,'num_leaves':7,'min_child_samples':10,
                              'min_train_days':60,'min_train_months':12,'min_month_coverage':.8},
                'nw_lag':5 if mode=='daily' else 1}
        (configs/(mode+'.json')).write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
    files=sorted([*data.glob('*.csv'),*configs.glob('*.json')])
    manifest={'synthetic':True,'seed':seed,'dates':n,'stocks':m,'rows':n*m,
              'numpy_version':np.__version__,'pandas_version':pd.__version__,
              'files':{str(p.relative_to(output)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    (output/'demo_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Generated synthetic demo:',output)
    return manifest


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--seed',type=int,default=42)
    args=parser.parse_args(argv)
    generate(args.output_dir,args.seed)


if __name__=='__main__':main()
