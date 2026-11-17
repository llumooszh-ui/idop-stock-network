from __future__ import annotations
import csv
from pathlib import Path
import numpy as np
import pandas as pd


def read_wide(path, encoding="utf-8-sig"):
    with Path(path).open(encoding=encoding, newline="") as stream:
        header = next(csv.reader(stream), [])
    if len(header) < 2 or len(header) != len(set(header)) or any(not x.strip() for x in header[1:]):
        raise ValueError("宽表需有日期及唯一非空股票列")
    frame = pd.read_csv(path, index_col=0, encoding=encoding)
    dates = pd.to_datetime(frame.index.astype(str), errors="coerce")
    if frame.empty or dates.isna().any() or dates.duplicated().any() or (dates != dates.normalize()).any():
        raise ValueError("日期为空、无效、重复或含时分秒")
    frame.index = dates.strftime("%Y-%m-%d")
    frame = frame.apply(pd.to_numeric, errors="raise")
    return frame.replace([np.inf, -np.inf], np.nan).sort_index()


def monthly_truth(frame, coverage=.8, include_last=False):
    """Daily decimal returns -> formation-date calendar-month compound returns."""
    if not 0 < coverage <= 1:
        raise ValueError("coverage 必须在 (0,1] 内")
    months = pd.to_datetime(frame.index).to_period("M")
    result = []
    for month in months.unique():
        if month == months.max() and not include_last:
            continue
        part = frame.loc[months == month]
        value = (1 + part).prod() - 1
        value[part.count() / len(part) < coverage] = np.nan
        value.name = part.index[0]
        result.append(value)
    if not result:
        raise ValueError("没有完整月份可评估")
    return pd.DataFrame(result).rename_axis("Date")


def to_long(frame: pd.DataFrame, value: str) -> pd.DataFrame:
    return frame.rename_axis("Date").reset_index().melt(
        id_vars="Date", var_name="stock", value_name=value
    )
