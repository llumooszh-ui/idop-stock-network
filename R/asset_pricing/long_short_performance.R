#!/usr/bin/env Rscript
local({
  sources <- Filter(Negate(is.null), lapply(sys.frames(), function(f)
    get0("ofile", envir=f, inherits=FALSE)))
  ofile <- if(length(sources)) sources[[length(sources)]] else NULL
  if(is.null(ofile)) {
    arg<-grep("^--file=", commandArgs(), value=TRUE)
    if(!length(arg)) stop("Cannot resolve script path")
    ofile<-sub("^--file=", "", arg[[1L]])
  }
  assign("AP_DIR", dirname(normalizePath(ofile)), envir=parent.env(environment()))
})

run_long_short_performance <- function(context) {
  execution <- new.env(parent=context)
  evalq({
FONT_CN <- "sans"
# 4.4.2 Long-Short Portfolio Performance
# 每月月初做多 G10、做空 G1，持有至当月月末。

assigned_panel <- assign_decile_portfolios(panel, N_GROUPS)
group_returns <- build_group_returns(assigned_panel)
long_short_returns <- build_long_short_returns(group_returns, N_GROUPS)

ls_summary <- performance_summary(
  long_short_returns,
  return_col = "R_LS",
  lag = NW_LAG_MONTHLY,
  periods_per_year = PERIODS_PER_YEAR
)

increment_test_data <- long_short_returns %>%
  filter(model %in% c("Conventional-factor", "Network-enhanced")) %>%
  select(Date, model, R_LS) %>%
  pivot_wider(names_from = model, values_from = R_LS) %>%
  drop_na(`Conventional-factor`, `Network-enhanced`) %>%
  mutate(delta_R_LS = `Network-enhanced` - `Conventional-factor`)

increment_test <- nw_mean_test(increment_test_data$delta_R_LS, lag = NW_LAG_MONTHLY) %>%
  transmute(
    comparison = "Conventional + Network minus Conventional",
    mean_return_diff = mean, nw_se, t_stat, p_value,
    n_obs = nrow(increment_test_data)
  )

# 自然月持有区间不重叠，可直接连续复利。
cumulative_returns <- long_short_returns %>%
  arrange(model, Date) %>%
  group_by(model) %>%
  mutate(cumulative_return = cumprod(1 + R_LS) - 1) %>%
  ungroup()

model_colors <- c(
  "Conventional-factor" = "#2E5E7E",
  "Network-factor" = "#6F8F72",
  "Network-enhanced" = "#B24A3A"
)

plot_data_cum <- cumulative_returns %>%
  mutate(model = factor(model, levels = c("Conventional-factor", "Network-factor", "Network-enhanced")))

cum_plot <- ggplot(plot_data_cum, aes(x = Date, y = cumulative_return, color = model, group = model)) +
  geom_hline(yintercept = 0, color = "grey60", linewidth = 0.4, linetype = "dashed") +
  geom_line(linewidth = 1) +
  scale_x_date(
    date_breaks = "1 year",
    date_labels = "%Y",
    expand = expansion(mult = c(0.02, 0.03))
  ) +
  scale_y_continuous(
    labels = scales::label_percent(accuracy = 1),
    expand = expansion(mult = c(0.06, 0.08))
  ) +
  scale_color_manual(
    values = model_colors,
    breaks = c("Network-enhanced", "Conventional-factor", "Network-factor"),
    labels = c("Combined-Characteristic", "Conventional-Characteristic", "Network-Characteristic")
  ) +
  labs(
    title = "Cumulative Long-Short Portfolio Returns",
    x = NULL, y = "Cumulative long-short return", color = NULL
  ) +
  theme_minimal(base_size = 10, base_family = FONT_CN) +
  theme(
    plot.title = element_text(size = 11, face = "bold", color = "grey15",
                              margin = margin(b = 10), hjust = 0),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey88", linewidth = 0.35),
    axis.line.x = element_line(color = "grey30", linewidth = 0.4),
    axis.ticks.x = element_line(color = "grey30", linewidth = 0.4),
    axis.ticks.length.x = unit(3, "pt"),
    axis.text = element_text(color = "grey20"),
    axis.title.y = element_text(color = "grey20", margin = margin(r = 10)),
    legend.position = "bottom",
    legend.title = element_blank(),
    legend.text = element_text(size = rel(0.75)),
    legend.key.width = unit(18, "pt"),
    legend.margin = margin(t = -4),
    plot.margin = margin(t = 10, r = 16, b = 4, l = 4)
  )


write.csv(ls_summary, file.path(OUT_DIR, "4_4_2_Table_Long_Short_Portfolio_Performance.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(increment_test, file.path(OUT_DIR, "4_4_2_网络增强相对传统组合增量检验.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(cumulative_returns, file.path(OUT_DIR, "4_4_2_累计多空收益.csv"), row.names = FALSE, fileEncoding = "UTF-8")
if (!NO_PLOTS) ggsave(file.path(OUT_DIR, "4_4_2_累计多空收益曲线.png"), cum_plot, width = 8, height = 5, dpi = 300)

cat("4.4.2 Long-Short Portfolio Performance 完成。\n")
cat("输出目录：", OUT_DIR, "\n")

invisible(as.list(environment(), all.names=TRUE))

  }, envir=execution)
}

if(sys.nframe()==0L) {
  runner<-new.env()
  source(file.path(AP_DIR,"run_asset_pricing.R"),local=runner)
  runner$main(default_analysis="long_short_performance")
}
