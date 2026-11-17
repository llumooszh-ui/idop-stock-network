from __future__ import annotations
import argparse
import json
import importlib.metadata
from pathlib import Path
import numpy as np
import pandas as pd
from .data import read_wide, to_long, monthly_truth
from .ic_metrics import safe_spearman, safe_pearson
from .prediction_metrics import error_metrics
from .compare_models import nw_mean_test, holm_adjust
import hashlib

def file_record(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"path": str(path.resolve()), "sha256": digest.hexdigest()}


OUTPUTS = ["model_summary.csv", "period_metrics.csv", "period_method_differences.csv",
           "newey_west_tests.csv", "common_sample_panel.csv", "manifest.json"]

def prepare_outputs(args):
    inputs = {p.resolve() for p in (args.model_a, args.model_b, args.truth)}
    for name in OUTPUTS:
        path = args.output_dir / name
        if path.resolve() in inputs:
            raise ValueError("输出不能覆盖输入")
        if path.exists() and not args.overwrite:
            raise FileExistsError(str(path))


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-a", required=True, type=Path)
    parser.add_argument("--model-b", required=True, type=Path)
    parser.add_argument("--label-a", default="IdopNetwork")
    parser.add_argument("--label-b", default="Correlation")
    parser.add_argument("--truth", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--nw-lag", type=int, default=5)
    parser.add_argument("--truth-encoding", default="gb18030")
    parser.add_argument("--frequency", choices=["daily", "monthly"], required=True)
    parser.add_argument("--min-month-coverage", type=float, default=.8)
    parser.add_argument("--include-last-observed-month", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args(argv)
    if args.nw_lag < 0 or not 0 < args.min_month_coverage <= 1:
        parser.error("nw-lag 必须非负，覆盖率须在 (0,1] 内")
    return args

def main(argv=None) -> None:
    args = parse_args(argv)
    prepare_outputs(args)
    if args.label_a == args.label_b:
        raise ValueError("The two labels must differ")
    a_col, b_col = "model_a", "model_b"
    a = to_long(read_wide(args.model_a), a_col)
    b = to_long(read_wide(args.model_b), b_col)
    truth_wide = read_wide(args.truth, args.truth_encoding)
    if (truth_wide < -1).any().any():
        raise ValueError("实际收益必须为小数单位且 >= -1")
    if args.frequency == "monthly":
        truth_wide = monthly_truth(truth_wide, args.min_month_coverage, args.include_last_observed_month)
        for pred in (a, b):
            dates = pd.DatetimeIndex(pred.Date.unique())
            if dates.to_period("M").duplicated().any():
                raise ValueError("月频预测每月只能有一个形成日期")
            known = set(pd.to_datetime(truth_wide.index).to_period("M"))
            relevant = pred.loc[pd.to_datetime(pred.Date).dt.to_period("M").isin(known), "Date"]
            if not relevant.isin(truth_wide.index).all():
                raise ValueError("月频预测日期必须为收益日历月首交易日")
    truth = to_long(truth_wide, "truth")
    panel = a.merge(b, on=["Date", "stock"], how="inner")
    panel = panel.merge(truth, on=["Date", "stock"], how="inner").dropna()
    if panel.empty:
        raise ValueError("No common non-missing observations")

    labels = {a_col: args.label_a, b_col: args.label_b}
    summary_rows: list[dict[str, float | int | str]] = []
    daily_rows: list[dict[str, float | int | str]] = []
    for column, label in labels.items():
        error = panel[column] - panel["truth"]
        row: dict[str, float | int | str] = {
            "model": label, "observations": len(panel),
            "pooled_pearson": safe_pearson(panel[column], panel["truth"]),
            "pooled_spearman": safe_spearman(panel[column], panel["truth"]),
            **error_metrics(panel[column], panel["truth"]),
        }
        for date, group in panel.groupby("Date", sort=True):
            day_error = group[column] - group["truth"]
            daily_rows.append({
                "Date": date, "model": label, "n_stocks": len(group),
                "pearson_ic": safe_pearson(group[column], group["truth"]),
                "rank_ic": safe_spearman(group[column], group["truth"]),
                "mse": float(np.mean(day_error ** 2)),
                "mae": float(np.mean(np.abs(day_error))),
            })
        summary_rows.append(row)

    daily = pd.DataFrame(daily_rows)
    for row in summary_rows:
        values = daily.loc[daily["model"].eq(row["model"]), "rank_ic"].dropna()
        row["mean_daily_rank_ic"] = values.mean()
        row["ic_std"] = values.std(ddof=1)
        row["icir"] = values.mean() / values.std(ddof=1) if values.std(ddof=1) > 0 else np.nan
        row["ic_positive_days"] = int((values > 0).sum())
        row["ic_positive_fraction"] = float((values > 0).mean())
        row["n_days"] = len(values)
        pearson = daily.loc[daily["model"].eq(row["model"]), "pearson_ic"].dropna()
        row["mean_pearson_ic"] = pearson.mean()
        row["pearson_icir"] = pearson.mean() / pearson.std(ddof=1) if pearson.std(ddof=1) > 0 else np.nan
    summary = pd.DataFrame(summary_rows)

    wide = daily.pivot(index="Date", columns="model", values=["rank_ic", "mse", "mae"])
    differences = pd.DataFrame({
        "rank_ic_gain_a": wide[("rank_ic", args.label_a)] - wide[("rank_ic", args.label_b)],
        "mse_reduction_a": wide[("mse", args.label_b)] - wide[("mse", args.label_a)],
        "mae_reduction_a": wide[("mae", args.label_b)] - wide[("mae", args.label_a)],
    })
    tests = pd.DataFrame([
        {"measure": name, **nw_mean_test(differences[name], args.nw_lag)}
        for name in differences.columns
    ])
    tests["p_value_holm"] = holm_adjust(tests["p_value"])
    tests["positive_favors"] = args.label_a

    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "manifest.json").unlink(missing_ok=True)
    summary.to_csv(args.output_dir / "model_summary.csv", index=False, encoding="utf-8-sig")
    daily.to_csv(args.output_dir / "period_metrics.csv", index=False, encoding="utf-8-sig")
    differences.to_csv(args.output_dir / "period_method_differences.csv", encoding="utf-8-sig")
    tests.to_csv(args.output_dir / "newey_west_tests.csv", index=False, encoding="utf-8-sig")
    panel.to_csv(args.output_dir / "common_sample_panel.csv", index=False, encoding="utf-8-sig")
    manifest = {"parameters": {k: str(v) if isinstance(v, Path) else v for k,v in vars(args).items()},
                "inputs": [file_record(x) for x in (args.model_a, args.model_b, args.truth)],
                "common_observations": len(panel), "common_periods": panel.Date.nunique(),
                "rows_before_alignment": {"model_a": len(a), "model_b": len(b), "truth": len(truth)},
                "versions": {x: importlib.metadata.version(x) for x in ("numpy", "pandas", "scipy")}}
    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(summary.to_string(index=False))
    print(f"\nPositive differences favor {args.label_a}.")
    print(tests.to_string(index=False))


if __name__ == "__main__":
    main()
