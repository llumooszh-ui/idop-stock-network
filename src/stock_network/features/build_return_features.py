"""Build the 41 historical return features with the original research formulas."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import pandas as pd
from ..evaluation.data import read_wide
from ..prediction.cli import file_record
from .return_factors import build_return_factors


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--returns',required=True,type=Path)
    parser.add_argument('--output-dir',required=True,type=Path)
    parser.add_argument('--start-date',required=True)
    parser.add_argument('--end-date',required=True)
    parser.add_argument('--encoding',default='utf-8-sig')
    args=parser.parse_args(argv)
    start,end=pd.Timestamp(args.start_date),pd.Timestamp(args.end_date)
    if pd.isna(start) or pd.isna(end) or start>end:raise ValueError('Invalid date range')
    if args.output_dir.exists():raise FileExistsError(args.output_dir)
    source=file_record(args.returns)
    wide=read_wide(args.returns,args.encoding)
    if (wide < -1).any().any():raise ValueError('Returns must be decimal and >= -1')
    wide.index=pd.to_datetime(wide.index);wide.index.name='Date'
    result=build_return_factors(wide,args.start_date,args.end_date).dropna(subset=['target_return'])
    if result.empty:raise ValueError('No usable rows; provide preceding history')
    features=[c for c in result if c not in ('Date','stock','target_return')]
    args.output_dir.mkdir(parents=True)
    output=args.output_dir/'return_features.csv';result.to_csv(output,index=False,encoding='utf-8-sig')
    record={'input':source,'output':file_record(output),'features':features,'rows':len(result),
            'start_date':args.start_date,'end_date':args.end_date,
            'drawdown_rule':'legacy: running maximum begins at first compounded return, without initial wealth 1'}
    (args.output_dir/'manifest.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(output)


if __name__=='__main__':main()
