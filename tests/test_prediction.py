"""Run from repository root: PYTHONPATH=src python3 -m unittest discover -s tests -p test_prediction.py"""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
import pandas as pd
from pandas.testing import assert_frame_equal

from stock_network.prediction.cli import parse_args, run
from stock_network.prediction.data import load_factor_data, build_calendar_month_panel, validate_calendar
from stock_network.prediction.preprocessing import cross_sectional_standardize
from stock_network.prediction.daily_prediction import build_daily_predictions
from stock_network.prediction.monthly_prediction import build_calendar_month_predictions


def fixture():
    rng = np.random.default_rng(12)
    dates = pd.bdate_range("2020-01-01", "2021-04-30")
    df = pd.MultiIndex.from_product([dates, [f"{i:06d}" for i in range(8)]], names=["Date", "stock"]).to_frame(index=False)
    df["ret_signal"] = rng.normal(size=len(df))
    df["net_metric"] = rng.normal(size=len(df))
    df["target_return"] = 0.01 * df.ret_signal + rng.normal(0, .002, len(df))
    return df


class PredictionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.df = fixture()
        self.path = self.root / "factors.csv"
        self.df.to_csv(self.path, index=False)
        self.features = ["ret_signal", "net_metric"]

    def args(self, mode):
        return parse_args(mode, ["--factor-path", str(self.path), "--output-dir", str(self.root / mode),
                                "--start-date", "2021-01-01", "--end-date", "2021-03-31",
                                "--n-estimators", "5", "--min-child-samples", "5", "--n-jobs", "1"])

    def test_input_contract(self):
        loaded, features = load_factor_data(self.path)
        self.assertEqual(loaded.stock.iloc[0], "000000")
        self.assertEqual(features, self.features)
        for mutation in [pd.concat([self.df, self.df.iloc[:1]]), self.df.assign(Date="bad"),
                         self.df.assign(target_return=np.inf), self.df.assign(ret_signal="text")]:
            mutation.to_csv(self.path, index=False)
            with self.assertRaises(ValueError):
                load_factor_data(self.path)
        self.df.drop(columns="target_return").to_csv(self.path, index=False)
        target = self.root / "targets.csv"
        self.df[["Date", "stock", "target_return"]].to_csv(target, index=False)
        loaded, _ = load_factor_data(self.path, target)
        np.testing.assert_allclose(loaded.target_return, self.df.target_return)

    def test_standardization_and_month_targets(self):
        prepared = cross_sectional_standardize(self.df, self.features, 5)
        np.testing.assert_allclose(prepared.groupby("Date")[self.features].mean(), 0, atol=1e-15)
        panel = build_calendar_month_panel(prepared, .8)
        row = panel.iloc[0]
        returns = self.df.loc[(self.df.stock == row.stock) & (self.df.Date.dt.to_period("M") == row.year_month), "target_return"]
        self.assertAlmostEqual(row.target_month_return, (1 + returns).prod() - 1)
        self.assertEqual(panel.year_month.max(), pd.Period("2021-03"))
        missing = prepared.copy()
        missing.loc[(missing.stock == "000000") & (missing.Date.dt.month == 1), "target_return"] = np.nan
        self.assertTrue(pd.isna(build_calendar_month_panel(missing, .8).query("stock == '000000'").iloc[0].target_month_return))

    def test_calendar_detects_omitted_dates(self):
        calendar = self.root / "calendar.csv"
        self.df[["Date"]].drop_duplicates().to_csv(calendar, index=False)
        validate_calendar(self.df, calendar, monthly=True)
        with self.assertRaises(ValueError):
            validate_calendar(self.df.loc[self.df.Date != pd.Timestamp("2020-05-05")], calendar)
        with self.assertRaises(ValueError):
            validate_calendar(self.df.loc[self.df.Date >= "2020-01-02"], calendar, monthly=True)

    def test_predictions_do_not_use_current_or_future_targets(self):
        prepared = cross_sectional_standardize(self.df, self.features, 5)
        changed = prepared.copy()
        changed.loc[changed.Date >= "2021-01-01", "target_return"] = .7
        with contextlib.redirect_stdout(io.StringIO()):
            for mode, builder in [("daily", build_daily_predictions), ("monthly", build_calendar_month_predictions)]:
                args = self.args(mode)
                before = build_calendar_month_panel(prepared, .8) if mode == "monthly" else prepared
                after = build_calendar_month_panel(changed, .8) if mode == "monthly" else changed
                first, _, _ = builder(before, self.features, args)
                second, _, _ = builder(after, self.features, args)
                assert_frame_equal(first.loc["2021-01-01":"2021-01-31"], second.loc["2021-01-01":"2021-01-31"])

    def test_training_cutoff(self):
        prepared = cross_sectional_standardize(self.df, self.features, 5)
        # Sentinel labels make an accidental fit on prediction-month rows visible.
        prepared.loc[prepared.Date >= "2021-01-01", "target_return"] = .987
        class Model:
            def fit(inner, x, y):
                self.assertFalse(np.isclose(y, .987).any())
                inner.booster_ = inner
                return inner
            def predict(inner, x):
                return np.zeros(len(x))
            def feature_importance(inner, importance_type):
                return np.ones(2)
        args = self.args("daily")
        args.end_date = "2021-01-31"
        with patch("stock_network.prediction.daily_prediction.make_model", return_value=Model()):
            build_daily_predictions(prepared, self.features, args)

    def test_cli_outputs_and_overwrite(self):
        for mode in ["daily", "monthly"]:
            args = self.args(mode)
            argv = ["--factor-path", str(self.path), "--output-dir", str(args.output_dir),
                    "--start-date", args.start_date, "--end-date", args.end_date,
                    "--n-estimators", "5", "--min-child-samples", "5", "--n-jobs", "1"]
            with contextlib.redirect_stdout(io.StringIO()):
                run(mode, argv)
            manifest = json.loads((args.output_dir / "manifest.json").read_text())
            self.assertEqual(manifest["mode"], mode)
            self.assertEqual(len(manifest["inputs"][0]["sha256"]), 64)
            wide = pd.read_csv(args.output_dir / "predictions.csv")
            if mode == "monthly":
                self.assertEqual(len(wide), 3)
                self.assertEqual(wide.Date.tolist(), ["2021-01-01", "2021-02-01", "2021-03-01"])
            with self.assertRaises(FileExistsError):
                run(mode, argv)


if __name__ == "__main__":
    unittest.main()
