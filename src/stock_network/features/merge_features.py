"""Merge identical Date/stock samples without relying on row order."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import numpy as np
from ..prediction.data import load_factor_data
from ..prediction.cli import file_record


def merge_features(traditional, network):
    keys=['Date','stock']
    common=set(traditional.columns)&set(network.columns)
    if common != {'Date','stock','target_return'}:
        raise ValueError('Shared fields must be exactly Date, stock, target_return: '+str(common))
    for frame in (traditional,network):
        if frame.empty or frame[keys].isna().any().any() or frame.duplicated(keys).any():
            raise ValueError('Empty data, missing keys or duplicate Date+stock')
    merged=traditional.merge(network,on=keys,how='outer',validate='one_to_one',indicator=True,suffixes=('','_network'),sort=False)
    if not merged['_merge'].eq('both').all():
        raise ValueError('Samples differ: '+str(merged['_merge'].value_counts().to_dict()))
    a=merged.target_return.to_numpy(float);b=merged.target_return_network.to_numpy(float)
    # Missing labels in both inputs are allowed for out-of-sample prediction.
    if not np.isclose(a,b,rtol=1e-12,atol=1e-12,equal_nan=True).all():
        raise ValueError('target_return mismatch')
    merged=merged.drop(columns=['target_return_network','_merge'])
    # Recover traditional input order explicitly; outer merge may sort keys.
    return traditional[keys].merge(merged,on=keys,how='left',validate='one_to_one',sort=False)


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--traditional',type=Path,required=True)
    parser.add_argument('--network',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--encoding',default='utf-8-sig')
    args=parser.parse_args(argv)
    if args.output_dir.exists():raise FileExistsError(args.output_dir)
    inputs=[file_record(p) for p in (args.traditional,args.network)]
    t,tf=load_factor_data(args.traditional,encoding=args.encoding)
    n,nf=load_factor_data(args.network,encoding=args.encoding)
    result=merge_features(t,n)
    args.output_dir.mkdir(parents=True)
    output=args.output_dir/'combined_features.csv'
    result.to_csv(output,index=False,encoding='utf-8-sig')
    record={'inputs':inputs,'rows':len(result),'traditional_features':tf,'network_features':nf,
            'sample_rule':'identical keys; no silent intersection','output':file_record(output)}
    (args.output_dir/'manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(output)


if __name__=='__main__':main()
