"""Run prediction and pairwise evaluation from a JSON experiment configuration."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OPTIONS = {'min_train_days', 'min_train_months', 'min_month_coverage',
           'include_last_observed_month', 'global_features', 'cs_clip', 'n_estimators',
           'learning_rate', 'num_leaves', 'min_child_samples', 'subsample',
           'colsample_bytree', 'n_jobs', 'input_encoding', 'plot', 'importance_top_n'}


def build_plan(config, base, root=ROOT):
    allowed = {'frequency','start_date','end_date','output_dir','truth','truth_encoding',
               'models','comparisons','prediction','nw_lag','calendar'}
    if set(config) - allowed:
        raise ValueError('Unknown configuration keys: '+str(set(config)-allowed))
    mode = config['frequency']
    if mode not in ('daily','monthly'):
        raise ValueError('frequency must be daily or monthly')
    def path(value):
        return (base / value).resolve()
    output = path(config['output_dir'])
    models = config['models']
    if not isinstance(models,dict) or len(models) < 2:
        raise ValueError('Provide at least two named models')
    for name, spec in models.items():
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*',name):
            raise ValueError('Model names must contain only ASCII letters, digits, underscores')
        if set(spec) - {'factor_path','target_source'}:
            raise ValueError('Unknown model options')
    options = config.get('prediction',{})
    if set(options)-OPTIONS:
        raise ValueError('Unknown prediction options: '+str(set(options)-OPTIONS))
    pairs = config['comparisons']
    if not pairs or any(len(pair)!=2 or pair[0]==pair[1] or any(x not in models for x in pair) for pair in pairs):
        raise ValueError('comparisons must contain pairs of distinct configured models')
    if len({tuple(pair) for pair in pairs}) != len(pairs):
        raise ValueError('Duplicate comparisons')
    inputs = [path(config['truth'])]
    if config.get('calendar'): inputs.append(path(config['calendar']))
    commands=[]
    def add_options(command, values):
        for key,value in values.items():
            flag='--'+key.replace('_','-')
            if isinstance(value,bool):
                if value: command.append(flag)
            elif isinstance(value,(str,int,float)):
                command.extend([flag,str(value)])
            else: raise ValueError('Invalid option value: '+key)
    for name,spec in models.items():
        factor=path(spec['factor_path']);inputs.append(factor)
        command=[sys.executable,'-m','stock_network.prediction.'+mode+'_prediction',
                 '--factor-path',str(factor),'--output-dir',str(output/'prediction'/name),
                 '--start-date',config['start_date'],'--end-date',config['end_date']]
        if spec.get('target_source'):
            target=path(spec['target_source']);inputs.append(target)
            command.extend(['--target-source',str(target)])
        if config.get('calendar'): command.extend(['--calendar',str(path(config['calendar']))])
        add_options(command,options)
        commands.append(('predict_'+name,command))
    for a,b in pairs:
        command=[sys.executable,'-m','stock_network.evaluation.run_evaluation',
                 '--model-a',str(output/'prediction'/a/'predictions.csv'),
                 '--model-b',str(output/'prediction'/b/'predictions.csv'),
                 '--label-a',a,'--label-b',b,'--truth',str(path(config['truth'])),
                 '--truth-encoding',config.get('truth_encoding','utf-8-sig'),
                 '--frequency',mode,'--nw-lag',str(config.get('nw_lag',5)),
                 '--output-dir',str(output/'evaluation'/(a+'__vs__'+b))]
        add_options(command,{k:options[k] for k in ('min_month_coverage','include_last_observed_month') if k in options})
        commands.append(('evaluate_'+a+'__vs__'+b,command))
    for source in inputs:
        if source == output or output in source.parents:
            raise ValueError('Inputs must be outside the output directory')
    return output, inputs, commands


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',required=True,type=Path)
    parser.add_argument('--dry-run',action='store_true',help='Print commands without reading datasets or writing outputs')
    args=parser.parse_args(argv)
    config_path=args.config.resolve()
    config=json.loads(config_path.read_text(encoding='utf-8'))
    output,inputs,commands=build_plan(config,config_path.parent)
    for name,command in commands:
        print(name+': '+shlex.join(command),flush=True)
    if args.dry_run: return
    if config_path == output or output in config_path.parents:
        raise ValueError('Configuration must be outside output directory')
    for source in inputs:
        if not source.is_file(): raise FileNotFoundError(source)
    # Require a new run directory: no accidental mixing of experiments or stale manifests.
    output.mkdir(parents=True,exist_ok=False)
    (output/'logs').mkdir()
    (output/'config.json').write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    env=os.environ.copy()
    env['PYTHONPATH']=str(ROOT/'src')+os.pathsep+env.get('PYTHONPATH','')
    state={'status':'running','config_source':str(config_path),
           'config_sha256':hashlib.sha256(config_path.read_bytes()).hexdigest(),'steps':[]}
    def save():
        temp=output/'run_manifest.tmp'
        temp.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        temp.replace(output/'run_manifest.json')
    save()
    try:
        for name,command in commands:
            step={'name':name,'command':command,'status':'running'}
            state['steps'].append(step);save()
            with (output/'logs'/(name+'.log')).open('w',encoding='utf-8') as log:
                result=subprocess.run(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,check=False)
            step['returncode']=result.returncode
            step['status']='complete' if result.returncode==0 else 'failed'
            save()
            if result.returncode: raise RuntimeError('Step failed: '+name+'; see '+str(output/'logs'/(name+'.log')))
        state['status']='complete';save()
    except BaseException as error:
        state['status']='failed';state['error']=str(error);save()
        raise


if __name__=='__main__': main()
