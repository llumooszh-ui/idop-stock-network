from __future__ import annotations

import argparse
import lightgbm as lgb

def make_model(args: argparse.Namespace) -> lgb.LGBMRegressor:
    return lgb.LGBMRegressor(
        objective="regression",
        n_estimators=args.n_estimators,
        learning_rate=args.learning_rate,
        num_leaves=args.num_leaves,
        min_child_samples=args.min_child_samples,
        subsample=args.subsample,
        subsample_freq=1,
        colsample_bytree=args.colsample_bytree,
        reg_alpha=0.0,
        reg_lambda=1.0,
        random_state=42,
        n_jobs=args.n_jobs,
        verbose=-1,
        force_col_wise=True,
    )
