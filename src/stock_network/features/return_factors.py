from __future__ import annotations
from typing import Iterable
import numpy as np
import pandas as pd

def cumulative_return(values: np.ndarray) -> float:
    """窗口期复合收益率。"""
    values = values[~np.isnan(values)]
    if len(values) == 0:
        return np.nan
    return float(np.prod(1.0 + values) - 1.0)

def downside_std(values: np.ndarray) -> float:
    """窗口期下行波动率, 只统计负收益。"""
    values = values[~np.isnan(values)]
    negative = values[values < 0]
    if len(negative) < 2:
        return np.nan
    return float(negative.std())

def max_drawdown(values: np.ndarray) -> float:
    """窗口期最大回撤, 基于收益率序列复合净值计算。"""
    values = values[~np.isnan(values)]
    if len(values) == 0:
        return np.nan

    wealth = np.cumprod(1.0 + values)
    drawdown = wealth / np.maximum.accumulate(wealth) - 1.0
    return float(drawdown.min())

def positive_rate(values: np.ndarray) -> float:
    """窗口期正收益占比。"""
    values = values[~np.isnan(values)]
    if len(values) == 0:
        return np.nan
    return float(np.mean(values > 0))

def add_rolling_factors(history: pd.DataFrame, windows: Iterable[int]) -> dict[str, pd.DataFrame]:
    """计算滚动窗口因子。"""
    factor_frames: dict[str, pd.DataFrame] = {}

    for window in windows:
        rolling = history.rolling(window=window, min_periods=max(3, window // 2))

        factor_frames[f"ret_mean_{window}d"] = rolling.mean()
        factor_frames[f"ret_std_{window}d"] = rolling.std()
        factor_frames[f"ret_min_{window}d"] = rolling.min()
        factor_frames[f"ret_max_{window}d"] = rolling.max()
        factor_frames[f"ret_win_rate_{window}d"] = rolling.apply(positive_rate, raw=True)
        factor_frames[f"ret_cum_{window}d"] = rolling.apply(cumulative_return, raw=True)

    # 计算成本较高的因子只放在常用 20 日窗口上。
    rolling_20 = history.rolling(window=20, min_periods=10)
    factor_frames["ret_downside_std_20d"] = rolling_20.apply(downside_std, raw=True)
    factor_frames["ret_max_drawdown_20d"] = rolling_20.apply(max_drawdown, raw=True)
    factor_frames["ret_skew_20d"] = rolling_20.skew()
    factor_frames["ret_kurt_20d"] = rolling_20.kurt()

    return factor_frames

def build_return_factors(
    wide_returns: pd.DataFrame,
    start_date: str,
    end_date: str,
) -> pd.DataFrame:
    """生成预测区间内的历史收益率因子长表。"""
    wide_returns = wide_returns.sort_index()

    # history 的每一行只包含该日期之前已经知道的收益率。
    history = wide_returns.shift(1)
    factor_frames: dict[str, pd.DataFrame] = {}

    for lag in (1, 2, 3, 5, 10, 20, 60):
        factor_frames[f"ret_lag_{lag}d"] = wide_returns.shift(lag)

    factor_frames.update(add_rolling_factors(history, windows=(5, 10, 20, 60)))

    # 与横截面相对位置有关的因子, 用 pct rank 保持不同股票数量下可比。
    rank_source_columns = [
        "ret_lag_1d",
        "ret_lag_5d",
        "ret_mean_20d",
        "ret_cum_20d",
        "ret_std_20d",
        "ret_max_drawdown_20d",
    ]
    for col in rank_source_columns:
        factor_frames[f"{col}_cs_rank"] = factor_frames[col].rank(axis=1, pct=True)

    features_wide = pd.concat(factor_frames, axis=1)
    features_wide.columns.names = ["factor", "stock"]
    long_features = features_wide.stack(level="stock", future_stack=True).reset_index()

    target = (
        wide_returns.stack(future_stack=True)
        .rename("target_return")
        .rename_axis(index=["Date", "stock"])
        .reset_index()
    )
    result = target.merge(long_features, on=["Date", "stock"], how="left")

    mask = (result["Date"] >= pd.to_datetime(start_date)) & (
        result["Date"] <= pd.to_datetime(end_date)
    )
    result = result.loc[mask].sort_values(["Date", "stock"]).reset_index(drop=True)

    factor_columns = [col for col in result.columns if col not in ("Date", "stock", "target_return")]
    result = result.dropna(subset=factor_columns, how="all")

    return result
