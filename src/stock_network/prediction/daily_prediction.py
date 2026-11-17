from __future__ import annotations

import argparse
import warnings
import numpy as np
import pandas as pd
from .lightgbm_model import make_model
from .importance import summarize_importance_records

def build_daily_predictions(
    factor_df: pd.DataFrame,
    feature_cols: list[str],
    args: argparse.Namespace,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    start = pd.to_datetime(args.start_date)
    end = pd.to_datetime(args.end_date)
    all_dates = np.array(sorted(factor_df["Date"].unique()))
    predict_dates = [date for date in all_dates if start <= date <= end]
    predict_months = pd.PeriodIndex(predict_dates, freq="M").unique()

    predictions: list[pd.DataFrame] = []
    importance_records: list[pd.DataFrame] = []

    for i, predict_month in enumerate(predict_months, start=1):
        month_dates = [
            date
            for date in predict_dates
            if pd.Timestamp(date).to_period("M") == predict_month
        ]
        if not month_dates:
            continue

        month_start = pd.Timestamp(month_dates[0])
        available_train_dates = all_dates[all_dates < month_start]
        if len(available_train_dates) < args.min_train_days:
            continue

        train_df = factor_df.loc[
            factor_df["Date"].lt(month_start),
            ["target_return", *feature_cols],
        ].copy()
        pred_df = factor_df.loc[
            factor_df["Date"].isin(month_dates),
            ["Date", "stock", *feature_cols],
        ].copy()

        train_df = train_df.dropna(subset=["target_return"])
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
                train_df["target_return"].to_numpy(dtype="float32"),
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

        day_pred = pred_df[["Date", "stock"]].copy()
        day_pred["predicted_return"] = np.where(np.isfinite(predicted), predicted, np.nan)
        predictions.append(day_pred)

        if i == 1 or i % 3 == 0 or i == len(predict_months):
            print(
                f"[{i}/{len(predict_months)}] 预测 {predict_month}, "
                f"训练样本 {len(train_df)}, 预测样本 {len(day_pred)}",
                flush=True,
            )

    if not predictions:
        raise RuntimeError("没有生成任何日频预测，请检查日期范围和训练数据。")

    pred_long = pd.concat(predictions, ignore_index=True)
    pred_wide = pred_long.pivot(index="Date", columns="stock", values="predicted_return")
    pred_wide = pred_wide.sort_index()
    pred_wide.index = pd.to_datetime(pred_wide.index).strftime("%Y-%m-%d")
    pred_wide.index.name = "Date"
    importance_summary, importance_monthly = summarize_importance_records(importance_records)
    return pred_wide, importance_summary, importance_monthly



def main(argv=None):
    from .cli import run
    return run("daily", argv)


if __name__ == "__main__":
    main()
