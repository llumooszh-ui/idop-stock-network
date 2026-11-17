from __future__ import annotations

import argparse
import warnings
import numpy as np
import pandas as pd
from .lightgbm_model import make_model
from .importance import summarize_importance_records

def build_calendar_month_predictions(
    monthly_panel: pd.DataFrame,
    feature_cols: list[str],
    args: argparse.Namespace,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """每月首个交易日用当日可用因子预测当月自然月收益。"""
    start_month = pd.Period(pd.to_datetime(args.start_date), freq="M")
    end_month = pd.Period(pd.to_datetime(args.end_date), freq="M")
    all_months = sorted(monthly_panel["year_month"].dropna().unique())
    predict_months = [month for month in all_months if start_month <= month <= end_month]

    predictions: list[pd.DataFrame] = []
    importance_records: list[pd.DataFrame] = []

    for i, predict_month in enumerate(predict_months, start=1):
        train_months = [month for month in all_months if month < predict_month]
        if len(train_months) < args.min_train_months:
            continue

        train_df = monthly_panel.loc[
            monthly_panel["year_month"].lt(predict_month),
            ["target_month_return", *feature_cols],
        ].copy()
        pred_df = monthly_panel.loc[
            monthly_panel["year_month"].eq(predict_month),
            ["Date", "stock", *feature_cols],
        ].copy()

        train_df = train_df.dropna(subset=["target_month_return"])
        train_df = train_df.dropna(subset=feature_cols, how="all")
        pred_df = pred_df.dropna(subset=feature_cols, how="all")
        if train_df.empty or pred_df.empty:
            continue

        model = make_model(args)
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", category=RuntimeWarning)
            warnings.filterwarnings("ignore", message="X does not have valid feature names.*")
            model.fit(
                train_df[feature_cols].to_numpy(dtype="float32"),
                train_df["target_month_return"].to_numpy(dtype="float32"),
            )
            predicted = model.predict(pred_df[feature_cols].to_numpy(dtype="float32"))

        booster = model.booster_
        importance_records.append(
            pd.DataFrame(
                {
                    "predict_month": str(predict_month),
                    "feature": feature_cols,
                    "importance_gain": booster.feature_importance(importance_type="gain"),
                    "importance_split": booster.feature_importance(importance_type="split"),
                    "train_samples": len(train_df),
                    "predict_samples": len(pred_df),
                }
            )
        )

        month_pred = pred_df[["Date", "stock"]].copy()
        month_pred["predicted_return"] = np.where(np.isfinite(predicted), predicted, np.nan)
        predictions.append(month_pred)

        if i == 1 or i % 3 == 0 or i == len(predict_months):
            print(
                f"[{i}/{len(predict_months)}] 预测 {predict_month}, "
                f"历史月数 {len(train_months)}, 训练样本 {len(train_df)}, "
                f"预测股票 {len(month_pred)}",
                flush=True,
            )

    if not predictions:
        raise RuntimeError("没有生成任何自然月预测，请检查日期范围和最小训练月数。")

    pred_long = pd.concat(predictions, ignore_index=True)
    pred_wide = pred_long.pivot(index="Date", columns="stock", values="predicted_return").sort_index()
    pred_wide.index = pd.to_datetime(pred_wide.index).strftime("%Y-%m-%d")
    pred_wide.index.name = "Date"
    importance_summary, importance_long = summarize_importance_records(importance_records)
    return pred_wide, importance_summary, importance_long



def main(argv=None):
    from .cli import run
    return run("monthly", argv)


if __name__ == "__main__":
    main()
