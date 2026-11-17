from __future__ import annotations

import csv
from pathlib import Path
import numpy as np
import pandas as pd


def read_panel(path, encoding="utf-8-sig"):
    """Read strict Date/stock keys, preserving leading zeros in stock codes."""
    with Path(path).open(encoding=encoding, newline="") as stream:
        columns = next(csv.reader(stream), [])
    if len(columns) != len(set(columns)):
        raise ValueError("CSV 存在重复列名")
    df = pd.read_csv(path, encoding=encoding, dtype={"stock": "string"})
    if not {"Date", "stock"}.issubset(df.columns):
        raise ValueError("必须包含 Date、stock")
    dates = pd.to_datetime(df["Date"], errors="coerce")
    if df.empty or dates.isna().any() or (dates != dates.dt.normalize()).any():
        raise ValueError("Date 必须为有效的日日期，数据不能为空")
    df["Date"] = dates
    if df["stock"].isna().any() or df["stock"].str.strip().eq("").any():
        raise ValueError("stock 不能为空")
    if df["stock"].str.strip().ne(df["stock"]).any():
        raise ValueError("stock 不能含首尾空白")
    if df.duplicated(["Date", "stock"]).any():
        raise ValueError("存在重复 Date+stock 主键")
    return df


def load_factor_data(path, target_source=None, encoding="utf-8-sig"):
    df = read_panel(path, encoding)
    if target_source is not None:
        if "target_return" in df:
            raise ValueError("因子表已有 target_return，不能再提供 target-source")
        target = read_panel(target_source, encoding)
        if "target_return" not in target:
            raise ValueError("target-source 缺少 target_return")
        df = df.merge(target[["Date", "stock", "target_return"]],
                      on=["Date", "stock"], how="left", validate="one_to_one")
    if "target_return" not in df:
        raise ValueError("缺少 target_return；请提供 target-source")
    features = [c for c in df if c not in ("Date", "stock", "target_return")]
    if not features:
        raise ValueError("没有特征列")
    for col in ["target_return", *features]:
        df[col] = pd.to_numeric(df[col], errors="raise")
    if np.isinf(df["target_return"]).any() or df["target_return"].dropna().lt(-1).any():
        raise ValueError("target_return 必须为小数收益率（>= -1），不能为无穷值")
    df[features] = df[features].replace([np.inf, -np.inf], np.nan)
    return df.sort_values(["Date", "stock"]).reset_index(drop=True), features


def validate_calendar(df, path, encoding="utf-8-sig", monthly=False,
                      include_last_observed_month=False):
    """Optional authoritative calendar catches omitted dates and partial months."""
    calendar = pd.read_csv(path, encoding=encoding)
    if "Date" not in calendar:
        raise ValueError("calendar 必须有 Date 列")
    dates = pd.to_datetime(calendar["Date"], errors="coerce")
    if dates.empty or dates.isna().any() or dates.duplicated().any():
        raise ValueError("calendar 日期无效或重复")
    if (dates != dates.dt.normalize()).any():
        raise ValueError("calendar 必须是日日期")
    observed = pd.DatetimeIndex(df["Date"].unique()).sort_values()
    expected = pd.DatetimeIndex(dates).sort_values()
    if not observed.isin(expected).all():
        raise ValueError("因子日期不在 calendar 中")
    within = expected[(expected >= observed.min()) & (expected <= observed.max())]
    if not within.equals(observed):
        raise ValueError("因子表缺失整个交易日")
    if monthly:
        months = observed.to_period("M").unique()
        if not include_last_observed_month:
            months = months[:-1]
        for month in months:
            actual = observed[observed.to_period("M") == month]
            full = expected[expected.to_period("M") == month]
            if not actual.equals(full):
                raise ValueError("月频输入包含不完整自然月: " + str(month))


def build_calendar_month_panel(
    factor_df: pd.DataFrame,
    min_month_coverage: float,
    include_last_observed_month: bool = False,
) -> pd.DataFrame:
    """构造月初因子 -> 当月自然月复合收益的月度面板。

    Date=t 的因子在上游已滞后至 t-1 及以前，因此每月第一个交易日的截面
    可用于预测从该日开始到月末的实现收益。
    """
    if not 0 < min_month_coverage <= 1:
        raise ValueError("min_month_coverage 必须在 (0, 1] 区间内。")

    df = factor_df.sort_values(["Date", "stock"]).copy()
    df["year_month"] = df["Date"].dt.to_period("M")
    if not include_last_observed_month:
        last_observed_month = df["year_month"].max()
        df = df.loc[df["year_month"].lt(last_observed_month)].copy()
        if df.empty:
            raise ValueError("排除最后观察月后没有可用数据。")

    month_calendar = (
        df[["Date", "year_month"]]
        .drop_duplicates()
        .groupby("year_month", as_index=False)
        .agg(
            formation_date=("Date", "min"),
            month_end_date=("Date", "max"),
            month_trading_days=("Date", "nunique"),
        )
    )

    monthly_target = (
        df.groupby(["year_month", "stock"], as_index=False)
        .agg(
            valid_return_days=("target_return", "count"),
            target_month_return=(
                "target_return",
                lambda x: (1.0 + x.dropna()).prod() - 1.0,
            ),
        )
        .merge(
            month_calendar[["year_month", "month_end_date", "month_trading_days"]],
            on="year_month",
            how="left",
        )
    )
    monthly_target["month_coverage"] = (
        monthly_target["valid_return_days"] / monthly_target["month_trading_days"]
    )
    monthly_target.loc[
        monthly_target["month_coverage"] < min_month_coverage,
        "target_month_return",
    ] = np.nan

    formation_rows = df.merge(
        month_calendar[["year_month", "formation_date"]],
        on="year_month",
        how="left",
    )
    formation_rows = formation_rows.loc[
        formation_rows["Date"].eq(formation_rows["formation_date"])
    ].copy()

    panel = formation_rows.merge(
        monthly_target,
        on=["year_month", "stock"],
        how="left",
    )
    return panel.sort_values(["year_month", "stock"]).reset_index(drop=True)
