from __future__ import annotations

import numpy as np
import pandas as pd

def cross_sectional_standardize(
    factor_df: pd.DataFrame,
    feature_cols: list[str],
    clip_value: float,
) -> pd.DataFrame:
    """对每个交易日的因子做横截面 z-score 标准化。"""
    df = factor_df.copy()

    grouped = df.groupby("Date", sort=False)[feature_cols]
    mean = grouped.transform("mean")
    std = grouped.transform("std").replace(0.0, np.nan)
    df[feature_cols] = (df[feature_cols] - mean) / std

    if clip_value > 0:
        df[feature_cols] = df[feature_cols].clip(lower=-clip_value, upper=clip_value)

    df[feature_cols] = df[feature_cols].replace([np.inf, -np.inf], np.nan)
    return df
