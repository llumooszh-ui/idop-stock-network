"""Shared command-line interface; imported only by prediction entry points."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import platform
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

from .data import load_factor_data, build_calendar_month_panel, validate_calendar
from .preprocessing import cross_sectional_standardize
from .importance import plot_feature_importance


def parse_args(mode, argv=None):
    parser = argparse.ArgumentParser(description=f"LightGBM {mode} 扩展窗口预测")
    parser.add_argument("--factor-path", type=Path, required=True)
    parser.add_argument("--target-source", type=Path)
    parser.add_argument("--calendar", type=Path, help="可选：覆盖完整月份的交易日 CSV（Date 列）")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--start-date", required=True)
    parser.add_argument("--end-date", required=True)
    parser.add_argument("--min-train-days", type=int, default=60)
    parser.add_argument("--min-train-months", type=int, default=12)
    parser.add_argument("--min-month-coverage", type=float, default=0.8)
    parser.add_argument("--include-last-observed-month", action="store_true")
    parser.add_argument("--global-features", choices=["legacy", "include", "exclude"], default="legacy")
    parser.add_argument("--cs-clip", type=float, default=5.0)
    parser.add_argument("--n-estimators", type=int, default=80)
    parser.add_argument("--learning-rate", type=float, default=0.05)
    parser.add_argument("--num-leaves", type=int, default=15)
    parser.add_argument("--min-child-samples", type=int, default=200)
    parser.add_argument("--subsample", type=float, default=0.8)
    parser.add_argument("--colsample-bytree", type=float, default=0.8)
    parser.add_argument("--n-jobs", type=int, default=-1)
    parser.add_argument("--input-encoding", default="utf-8-sig")
    parser.add_argument("--encoding", default="utf-8-sig", help="输出 CSV 编码")
    parser.add_argument("--plot", action="store_true")
    parser.add_argument("--importance-top-n", type=int, default=15)
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args(argv)
    start, end = pd.to_datetime(args.start_date), pd.to_datetime(args.end_date)
    if pd.isna(start) or pd.isna(end) or start > end or start != start.normalize() or end != end.normalize():
        parser.error("开始/结束日期无效")
    for name in ("min_train_days", "min_train_months", "n_estimators", "min_child_samples", "importance_top_n"):
        if getattr(args, name) < 1:
            parser.error(name + " 必须 >= 1")
    if args.num_leaves < 2 or args.n_jobs == 0:
        parser.error("num-leaves 必须 >= 2，n-jobs 不能为 0")
    for name in ("min_month_coverage", "subsample", "colsample_bytree"):
        if not 0 < getattr(args, name) <= 1:
            parser.error(name + " 必须在 (0, 1] 内")
    if not np.isfinite(args.learning_rate) or args.learning_rate <= 0 or not np.isfinite(args.cs_clip):
        parser.error("learning-rate 必须为正有限数，cs-clip 必须为有限数")
    return args


def file_record(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"path": str(path.resolve()), "sha256": digest.hexdigest()}


def run(mode, argv=None):
    args = parse_args(mode, argv)
    names = ["predictions.csv", "importance.csv", "importance_monthly.csv", "manifest.json"]
    if args.plot:
        names.append("importance.png")
    outputs = {name: args.output_dir / name for name in names}
    # Protect inputs even when --overwrite is explicit. Existing optional plots
    # are also rejected to avoid leaving a plot from a previous run unnoticed.
    inputs = [p for p in (args.factor_path, args.target_source, args.calendar) if p is not None]
    for path in outputs.values():
        if path.resolve() in [p.resolve() for p in inputs]:
            raise ValueError("输出不能覆盖输入文件")
    known_paths = [args.output_dir / name for name in set(names + ["importance.png"])]
    existing = [str(p) for p in known_paths if p.exists()]
    if existing and not args.overwrite:
        raise FileExistsError("输出已存在；显式 --overwrite 才覆盖: " + ", ".join(existing))
    if args.overwrite and not args.plot and (args.output_dir / "importance.png").exists():
        raise ValueError("输出目录有旧 importance.png；请选择新目录或加 --plot 重建")
    input_records = [file_record(p) for p in inputs]
    df, features = load_factor_data(args.factor_path, args.target_source, args.input_encoding)
    excluded = []
    if args.global_features == "exclude" or (args.global_features == "legacy" and mode == "daily"):
        excluded = [c for c in features if c.startswith("net_global_")]
        features = [c for c in features if c not in excluded]
        df = df.drop(columns=excluded)
    if not features:
        raise ValueError("排除全局指标后没有特征")
    if args.calendar:
        validate_calendar(df, args.calendar, args.input_encoding, mode == "monthly",
                          args.include_last_observed_month)
    else:
        print("未提供 calendar：以因子表日期并集作为交易日历；请确认无整日缺失且月份完整。", flush=True)
    prepared = cross_sectional_standardize(df, features, args.cs_clip)
    if mode == "daily":
        from .daily_prediction import build_daily_predictions
        wide, summary, monthly = build_daily_predictions(prepared, features, args)
        target = "Date=t 的单日收益率；上游特征应仅使用 t-1 及以前可得信息"
    else:
        from .monthly_prediction import build_calendar_month_predictions
        panel = build_calendar_month_panel(prepared, args.min_month_coverage,
                                           args.include_last_observed_month)
        wide, summary, monthly = build_calendar_month_predictions(panel, features, args)
        target = "Date 为月首交易日，目标为该自然月复合收益率"
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "mode": mode, "target": target,
        "parameters": {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        "inputs": input_records, "features": features, "excluded_features": excluded,
        "input_rows": len(df), "missing_targets": int(df.target_return.isna().sum()),
        "input_date_range": [str(df.Date.min().date()), str(df.Date.max().date())],
        "prediction_date_range": [str(wide.index.min()), str(wide.index.max())],
        "prediction_shape": list(wide.shape), "fitted_months": sorted(monthly.predict_month.unique().tolist()),
        "model_random_state": 42, "python": platform.python_version(),
        "versions": {p: importlib.metadata.version(p) for p in ["numpy", "pandas", "lightgbm", "scikit-learn", "matplotlib"]},
        "limitations": ["特征已在上游滞后，本模块不再次滞后，也不能消除阶段网络估计的前视信息。",
                         "无有效训练或预测样本、历史期数不足的月份跳过；结果未自动补齐。",
                         "历史期数按观察到的日期/月计数，缺失目标或全空特征行在拟合前删除。"],
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    # Remove a prior success marker before rewriting any outputs.
    outputs["manifest.json"].unlink(missing_ok=True)
    wide.to_csv(outputs["predictions.csv"], encoding=args.encoding)
    summary.to_csv(outputs["importance.csv"], index=False, encoding=args.encoding)
    monthly.to_csv(outputs["importance_monthly.csv"], index=False, encoding=args.encoding)
    if args.plot:
        plot_feature_importance(summary, monthly, outputs["importance.png"],
                                args.importance_top_n, "Daily return" if mode == "daily" else "Formation calendar-month return")
    manifest["outputs"] = [file_record(p) for name, p in outputs.items() if name != "manifest.json"]
    outputs["manifest.json"].write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"完成 {mode}: {wide.shape[0]} 个日期 × {wide.shape[1]} 只股票 -> {outputs['predictions.csv']}")
    return wide, summary, monthly
