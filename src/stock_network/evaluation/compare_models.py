from __future__ import annotations
import numpy as np
import pandas as pd
from scipy.stats import norm

def nw_mean_test(values: pd.Series, lag: int) -> dict[str, float | int]:
    x = values[np.isfinite(values)].to_numpy(float)
    n = len(x)
    if n < 3:
        return {"mean_difference": np.nan, "newey_west_se": np.nan,
                "z_statistic": np.nan, "p_value": np.nan,
                "n_days": n, "nw_lag": lag}
    centered = x - x.mean()
    long_run = np.dot(centered, centered) / n
    for j in range(1, min(lag, n - 1) + 1):
        gamma = np.dot(centered[j:], centered[:-j]) / n
        long_run += 2 * (1 - j / (lag + 1)) * gamma
    se = np.sqrt(max(long_run, 0) / n)
    z = x.mean() / se if se > 0 else np.nan
    p = 2 * norm.sf(abs(z)) if np.isfinite(z) else np.nan
    return {"mean_difference": x.mean(), "newey_west_se": se,
            "z_statistic": z, "p_value": p, "n_days": n, "nw_lag": lag}

def holm_adjust(p_values: pd.Series) -> np.ndarray:
    values = p_values.to_numpy(float)
    adjusted = np.full(len(values), np.nan)
    valid = np.flatnonzero(np.isfinite(values))
    if not len(valid):
        return adjusted
    order = valid[np.argsort(values[valid])]
    sorted_adjusted = np.maximum.accumulate(
        (len(valid) - np.arange(len(valid))) * values[order]
    )
    adjusted[order] = np.minimum(sorted_adjusted, 1.0)
    return adjusted
