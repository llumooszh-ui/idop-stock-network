from __future__ import annotations
import numpy as np
import pandas as pd
from scipy.stats import spearmanr

def safe_spearman(x: pd.Series, y: pd.Series) -> float:
    if len(x) < 5 or x.nunique() < 2 or y.nunique() < 2:
        return np.nan
    return float(spearmanr(x, y).statistic)

def safe_pearson(x, y):
    if len(x) < 5 or x.nunique() < 2 or y.nunique() < 2:
        return np.nan
    return float(x.corr(y))
