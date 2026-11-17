from __future__ import annotations

from pathlib import Path
import numpy as np
import pandas as pd

def feature_group(feature: str) -> str:
    if feature.startswith("ret_"):
        return "Return"
    if feature.startswith("trd_"):
        return "Trading"
    if feature.startswith("mkt_"):
        return "Valuation"
    if feature.startswith("margin_"):
        return "Margin"
    if feature.startswith("net_global_"):
        return "Network-global"
    # All remaining network features share the net_ prefix. This includes
    # both the older net_* names and the newer net_new_* names.
    if feature.startswith("net_"):
        return "Network"
    if feature.startswith("fin_"):
        return "Financial"
    if feature.startswith("af_"):
        return "Analyst"
    if feature.startswith("rating_"):
        return "Rating"
    return "Other"


def plot_feature_importance(
    importance_summary: pd.DataFrame,
    importance_monthly: pd.DataFrame,
    output_path: Path,
    top_n: int,
    target_label: str,
) -> None:
    if importance_summary.empty:
        return

    import matplotlib.pyplot as plt
    from matplotlib.colors import LinearSegmentedColormap, to_rgb
    from matplotlib.ticker import PercentFormatter

    paper_bg = "#FFFFFF"
    panel_bg = "#FFFFFF"
    ink = "#1D252D"
    muted_ink = "#5E6772"
    grid_color = "#DEDAD0"
    divider_color = "#F1EFE8"

    # Muted, colorblind-friendly journal palette inspired by Nature/Science figures.
    palette = {
        "Return": "#3B5F7A",
        "Trading": "#4F8A83",
        "Valuation": "#7A9B58",
        "Margin": "#D6A34A",
        "Network-global": "#8CBBD9",
        "Network": "#2F6F9F",
        "Financial": "#B85C54",
        "Analyst": "#C47A49",
        "Rating": "#6F6F6F",
        "Other": "#A8A29A",
    }
    heatmap_cmap = LinearSegmentedColormap.from_list(
        "journal_blue",
        ["#FFFFFF", "#E5EEF1", "#B7CED8", "#6D97AD", "#2F6380", "#123247"],
    )

    plt.rcParams.update(
        {
            "figure.dpi": 160,
            "savefig.dpi": 320,
            "font.family": "DejaVu Sans",
            "axes.unicode_minus": False,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.titleweight": "bold",
            "axes.labelcolor": ink,
            "axes.edgecolor": grid_color,
            "xtick.color": muted_ink,
            "ytick.color": ink,
        }
    )

    def contrast_text_color(hex_color: str, alpha: float) -> str:
        rgb = np.array(to_rgb(hex_color))
        bg = np.array(to_rgb(panel_bg))
        blended = alpha * rgb + (1.0 - alpha) * bg
        luminance = 0.2126 * blended[0] + 0.7152 * blended[1] + 0.0722 * blended[2]
        return "#FFFFFF" if luminance < 0.50 else "#1D252D"

    summary_df = importance_summary.copy()
    summary_df["group"] = summary_df["feature"].map(feature_group)

    group_totals = (
        summary_df.groupby("group", as_index=False)["gain_importance_pct"]
        .sum()
        .sort_values("gain_importance_pct", ascending=True)
        .reset_index(drop=True)
    )
    group_order = group_totals["group"].tolist()

    top_factor_count = max(1, min(15, top_n, len(summary_df)))
    top_features = summary_df.head(top_factor_count)["feature"].tolist()

    heatmap_df = pd.DataFrame()
    if not importance_monthly.empty:
        monthly_df = importance_monthly.copy()
        monthly_df["predict_month"] = pd.PeriodIndex(monthly_df["predict_month"], freq="M").astype(str)
        heatmap_df = (
            monthly_df[monthly_df["feature"].isin(top_features)]
            .pivot_table(
                index="feature",
                columns="predict_month",
                values="gain_importance_pct_month",
                aggfunc="sum",
            )
            .reindex(index=top_features)
            .fillna(0.0)
        )

    fig_height = max(8.0, 0.38 * top_factor_count + 3.8, 0.62 * len(group_order) + 3.8)
    fig, (ax_group, ax_heat) = plt.subplots(
        ncols=2,
        figsize=(19.8, fig_height),
        gridspec_kw={"width_ratios": [1.18, 1.72], "wspace": 0.30},
        constrained_layout=False,
    )
    fig.subplots_adjust(left=0.065, right=0.965, bottom=0.115, top=0.835, wspace=0.30)
    fig.patch.set_facecolor(paper_bg)
    ax_group.set_facecolor(panel_bg)
    ax_heat.set_facecolor(panel_bg)

    max_group_width = max(float(group_totals["gain_importance_pct"].max()), 0.001)
    for y_pos, group in enumerate(group_order):
        group_df = (
            summary_df.loc[summary_df["group"] == group]
            .sort_values("gain_importance_pct", ascending=False)
            .reset_index(drop=True)
        )
        left = 0.0
        base_color = palette.get(group, "#ADB5BD")
        top_row = group_df.iloc[0] if len(group_df) else None
        for i, row in group_df.iterrows():
            width = float(row["gain_importance_pct"]) if pd.notna(row["gain_importance_pct"]) else 0.0
            alpha = max(0.42, 0.94 - 0.032 * i)
            ax_group.barh(
                y_pos,
                width,
                left=left,
                height=0.62,
                color=base_color,
                edgecolor=divider_color,
                linewidth=0.65,
                alpha=alpha,
            )

            # Keep labels sparse: dense stacked bars become unreadable if every segment is labeled.
            # Label only the dominant factor in a group, and only when the segment is wide enough.
            if (
                top_row is not None
                and row["feature"] == top_row["feature"]
                and width >= max_group_width * 0.135
            ):
                ax_group.text(
                    left + width / 2,
                    y_pos,
                    str(row["feature"]),
                    ha="center",
                    va="center",
                    fontsize=7.8,
                    color=contrast_text_color(base_color, alpha),
                    clip_on=True,
                )
            left += width

        ax_group.text(
            left + max_group_width * 0.015,
            y_pos,
            f"{left:.1%}",
            va="center",
            ha="left",
            fontsize=9.0,
            color=ink,
        )

    ax_group.set_yticks(np.arange(len(group_order)))
    ax_group.set_yticklabels(group_order, fontsize=9.4)
    ax_group.xaxis.set_major_formatter(PercentFormatter(xmax=1.0))
    ax_group.grid(axis="x", color=grid_color, linewidth=0.75, alpha=0.78)
    ax_group.set_axisbelow(True)
    ax_group.set_xlabel("Share of total weighted gain", fontsize=10.0, labelpad=9)
    ax_group.set_title(
        "Grouped Gain Importance",
        loc="left",
        fontsize=14.5,
        pad=22,
        color=ink,
    )
    ax_group.text(
        0,
        1.018,
        "Stacked by factors within each group",
        transform=ax_group.transAxes,
        ha="left",
        va="bottom",
        fontsize=9.2,
        color=muted_ink,
    )
    ax_group.set_xlim(0, max_group_width * 1.27)

    if heatmap_df.empty:
        ax_heat.text(
            0.5,
            0.5,
            "No monthly importance records",
            transform=ax_heat.transAxes,
            ha="center",
            va="center",
            fontsize=11,
            color=muted_ink,
        )
        ax_heat.set_xticks([])
        ax_heat.set_yticks([])
    else:
        values = heatmap_df.to_numpy(dtype=float)
        vmax = max(float(np.nanmax(values)), 0.001)
        image = ax_heat.imshow(values, aspect="auto", cmap=heatmap_cmap, vmin=0.0, vmax=vmax)
        ax_heat.set_xticks(np.arange(len(heatmap_df.columns)))
        ax_heat.set_xticklabels(heatmap_df.columns, rotation=50, ha="right", fontsize=7.6)
        ax_heat.set_yticks(np.arange(len(heatmap_df.index)))
        ax_heat.set_yticklabels(heatmap_df.index, fontsize=9.0)
        ax_heat.set_xticks(np.arange(-0.5, len(heatmap_df.columns), 1), minor=True)
        ax_heat.set_yticks(np.arange(-0.5, len(heatmap_df.index), 1), minor=True)
        ax_heat.grid(which="minor", color=divider_color, linestyle="-", linewidth=0.85)
        ax_heat.tick_params(which="minor", bottom=False, left=False)
        colorbar = fig.colorbar(image, ax=ax_heat, fraction=0.028, pad=0.015)
        colorbar.ax.yaxis.set_major_formatter(PercentFormatter(xmax=1.0))
        colorbar.ax.tick_params(labelsize=8, colors=muted_ink)
        colorbar.outline.set_edgecolor(grid_color)
        colorbar.set_label("Monthly gain share", fontsize=9, color=ink)

    ax_heat.set_title(
        f"Monthly Importance Heatmap, Top {top_factor_count}",
        loc="left",
        fontsize=14.5,
        pad=22,
        color=ink,
    )
    ax_heat.text(
        0,
        1.018,
        "Rows ranked by overall weighted gain; columns are prediction months",
        transform=ax_heat.transAxes,
        ha="left",
        va="bottom",
        fontsize=9.2,
        color=muted_ink,
    )

    fig.suptitle(
        f"LightGBM Factor Importance | Monthly expanding window | {target_label}",
        x=0.012,
        y=0.965,
        ha="left",
        fontsize=17,
        fontweight="bold",
        color=ink,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)


def summarize_importance_records(
    importance_records: list[pd.DataFrame],
) -> tuple[pd.DataFrame, pd.DataFrame]:
    if not importance_records:
        return pd.DataFrame(), pd.DataFrame()

    importance_long = pd.concat(importance_records, ignore_index=True)
    monthly_total_gain = importance_long.groupby("predict_month")["importance_gain"].transform("sum")
    importance_long["gain_importance_pct_month"] = np.where(
        monthly_total_gain > 0,
        importance_long["importance_gain"] / monthly_total_gain,
        np.nan,
    )
    importance_long["gain_weighted"] = (
        importance_long["importance_gain"] * importance_long["train_samples"]
    )
    importance_long["split_weighted"] = (
        importance_long["importance_split"] * importance_long["train_samples"]
    )

    importance_summary = (
        importance_long.groupby("feature", as_index=False)
        .agg(
            months_used=("predict_month", "nunique"),
            total_train_samples=("train_samples", "sum"),
            gain_mean=("importance_gain", "mean"),
            gain_weighted_mean=("gain_weighted", "sum"),
            split_mean=("importance_split", "mean"),
            split_weighted_mean=("split_weighted", "sum"),
        )
    )
    importance_summary["gain_weighted_mean"] /= importance_summary["total_train_samples"]
    importance_summary["split_weighted_mean"] /= importance_summary["total_train_samples"]
    total_gain = importance_summary["gain_weighted_mean"].sum()
    total_split = importance_summary["split_weighted_mean"].sum()
    importance_summary["gain_importance_pct"] = np.where(
        total_gain > 0,
        importance_summary["gain_weighted_mean"] / total_gain,
        np.nan,
    )
    importance_summary["split_importance_pct"] = np.where(
        total_split > 0,
        importance_summary["split_weighted_mean"] / total_split,
        np.nan,
    )
    importance_summary = importance_summary.sort_values(
        ["gain_weighted_mean", "split_weighted_mean"],
        ascending=False,
    ).reset_index(drop=True)
    importance_summary.insert(0, "rank", np.arange(1, len(importance_summary) + 1))
    return importance_summary, importance_long
