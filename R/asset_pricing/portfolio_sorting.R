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

run_portfolio_sorting <- function(context) {
  execution <- new.env(parent=context)
  evalq({

# 4.4.1 Portfolio Sorting Analysis
# 每月月初按预测自然月收益排序，构造 G1-G10 等权组合，并用当月实现收益评价。

assigned_panel <- assign_decile_portfolios(panel, N_GROUPS)
group_returns <- build_group_returns(assigned_panel)
long_short_returns <- build_long_short_returns(group_returns, N_GROUPS)

group_summary <- group_returns %>%
  group_by(model, group) %>%
  summarise(
    n_obs = n(),
    mean_return = mean(group_return, na.rm = TRUE),
    annualized_return = (1 + mean_return) ^ PERIODS_PER_YEAR - 1,
    return_sd = sd(group_return, na.rm = TRUE),
    sharpe_ratio = ifelse(return_sd == 0, NA_real_, mean_return / return_sd * sqrt(PERIODS_PER_YEAR)),
    .groups = "drop"
  ) %>%
  left_join(
    group_returns %>%
      group_by(model, group) %>%
      group_modify(~ nw_mean_test(.x$group_return, lag = NW_LAG_MONTHLY)) %>%
      ungroup() %>%
      select(model, group, nw_se, nw_t_stat = t_stat, nw_p_value = p_value),
    by = c("model", "group")
  )

ls_summary <- long_short_returns %>%
  group_by(model) %>%
  group_modify(~ nw_mean_test(.x$R_LS, lag = NW_LAG_MONTHLY)) %>%
  ungroup() %>%
  mutate(group = paste0("G", N_GROUPS, "-G1")) %>%
  select(model, group, mean_return = mean, nw_se, nw_t_stat = t_stat, nw_p_value = p_value)

table_returns <- group_summary %>%
  transmute(
    model,
    group = paste0("G", group),
    cell = sprintf("%.6f (%.2f)", mean_return, nw_t_stat)
  ) %>%
  bind_rows(
    ls_summary %>%
      transmute(model, group, cell = sprintf("%.6f (%.2f)", mean_return, nw_t_stat))
  ) %>%
  pivot_wider(names_from = group, values_from = cell) %>%
  select(model, all_of(c(paste0("G", 1:N_GROUPS), paste0("G", N_GROUPS, "-G1"))))

plot_data <- group_summary %>%
  mutate(group_label = paste0("G", group))

model_colors <- c(
  "Conventional-factor" = "#2E5E7E",
  "Network-factor" = "#6F8F72",
  "Network-enhanced" = "#B24A3A"
)

rmodel_colors <- c(
  "Conventional-factor" = "#2E5E7E",
  "Network-factor" = "#6F8F72",
  "Network-enhanced" = "#B24A3A"
)

plot_data <- plot_data %>%
  mutate(model = factor(model, levels = c("Conventional-factor", "Network-factor", "Network-enhanced")))

sorting_plot <- ggplot(
  plot_data,
  aes(x = group, y = mean_return, color = model, group = model)
) +
  geom_line(linewidth = 0.75) +
  geom_point(size = 2.2, shape = 21, fill = "white", stroke = 0.75) +
  scale_x_continuous(
    breaks = 1:N_GROUPS,
    labels = paste0("G", 1:N_GROUPS),
    expand = expansion(mult = c(0.03, 0.05))
  ) +
  scale_y_continuous(
    expand = expansion(mult = c(0.08, 0.10))
  ) +
  scale_color_manual(
    values = model_colors,
    breaks = c("Network-enhanced", "Conventional-factor", "Network-factor"),
    labels = c("Combined-Characteristic", "Conventional-Characteristic", "Network-Characteristic")
  ) +
  labs(
    title = sprintf("Mean Returns Across %d Predicted-Return Groups", N_GROUPS),
    x = NULL,
    y = "Mean monthly return",
    color = NULL
  ) +
  theme_minimal(base_size = 10, base_family = FONT_CN) +
  theme(
    plot.title = element_text(
      size = 11,
      face = "bold",
      color = "grey15",
      margin = margin(b = 8),
      hjust = 0
    ),
    axis.text = element_text(size = 9, color = "grey20"),
    axis.title.y = element_text(
      size = 10,
      color = "grey20",
      margin = margin(r = 8)
    ),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(
      color = "grey88",
      linewidth = 0.3
    ),
    axis.line.x = element_line(color = "grey30", linewidth = 0.35),
    axis.ticks.x = element_line(color = "grey30", linewidth = 0.35),
    legend.position = "bottom",
    legend.text = element_text(size = 9),
    legend.key.width = unit(15, "pt"),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA),
    plot.margin = margin(8, 10, 4, 6)
  )

write.csv(group_returns, file.path(OUT_DIR, "4_4_1_十分组月度收益.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(group_summary, file.path(OUT_DIR, "4_4_1_十分组收益统计.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(table_returns, file.path(OUT_DIR, "4_4_1_Table_Returns_of_Portfolios_Sorted_by_Predicted_Returns.csv"), row.names = FALSE, fileEncoding = "UTF-8")
if (!NO_PLOTS) ggsave(file.path(OUT_DIR, "4_4_1_十分组平均收益曲线.png"), sorting_plot, width = 8, height = 5, dpi = 300)

cat("4.4.1 Portfolio Sorting Analysis 完成。\n")
cat("输出目录：", OUT_DIR, "\n")

invisible(as.list(environment(), all.names=TRUE))

  }, envir=execution)
}

if(sys.nframe()==0L) {
  runner<-new.env()
  source(file.path(AP_DIR,"run_asset_pricing.R"),local=runner)
  runner$main(default_analysis="portfolio_sorting")
}
