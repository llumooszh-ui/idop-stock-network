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

run_factor_alpha_tests <- function(context) {
  execution <- new.env(parent=context)
  evalq({

# 4.4.3 CAPM and FF3 Alpha Tests
# 每月月初构造当月多空组合收益，再与同一自然月的因子合并回归。

assigned_panel <- assign_decile_portfolios(panel, N_GROUPS)
group_returns <- build_group_returns(assigned_panel)
long_short_returns <- build_long_short_returns(group_returns, N_GROUPS)
factor_data <- load_factor_data(FACTOR_PATH)

reg_data <- long_short_returns %>%
  left_join(factor_data, by = "year_month") %>%
  drop_na(R_LS, RiskPremium1, SMB1, HML1, RMW1, CMA1)

if (nrow(reg_data) == 0) {
  stop("多空组合收益与 factors_filtered.csv 没有共同月份，无法做 Alpha 检验。")
}

alpha_results <- reg_data %>%
  split(.$model) %>%
  imap_dfr(function(.x, model_name) {
    capm <- run_nw_regression(R_LS ~ RiskPremium1, .x, lag = NW_LAG_MONTHLY)
    ff3 <- run_nw_regression(R_LS ~ RiskPremium1 + SMB1 + HML1, .x, lag = NW_LAG_MONTHLY)
    ff5 <- run_nw_regression(R_LS ~ RiskPremium1 + SMB1 + HML1 + RMW1 + CMA1, .x, lag = NW_LAG_MONTHLY)
    bind_rows(
      extract_regression_table(capm, model_name, "CAPM"),
      extract_regression_table(ff3, model_name, "FF3"),
      extract_regression_table(ff5, model_name, "FF5")
    )
  })

alpha_table <- alpha_results %>%
  filter(
    term %in% c("(Intercept)", "RiskPremium1", "SMB1", "HML1"),
    specification %in% c("CAPM", "FF3")
  ) %>%
  mutate(
    item = case_when(
      specification == "CAPM" & term == "(Intercept)" ~ "CAPM alpha",
      specification == "CAPM" & term == "RiskPremium1" ~ "Market beta",
      specification == "FF3" & term == "(Intercept)" ~ "FF3 alpha",
      specification == "FF3" & term == "RiskPremium1" ~ "MKT loading",
      specification == "FF3" & term == "SMB1" ~ "SMB loading",
      specification == "FF3" & term == "HML1" ~ "HML loading",
      TRUE ~ term
    ),
    cell = sprintf("%.6f (%.2f)", estimate, t_stat)
  ) %>%
  select(model, item, cell) %>%
  pivot_wider(names_from = item, values_from = cell)

adj_r2_table <- alpha_results %>%
  distinct(model, specification, adj_r_squared) %>%
  filter(specification %in% c("CAPM", "FF3")) %>%
  mutate(item = paste0(specification, " adjusted R2")) %>%
  select(model, item, adj_r_squared) %>%
  pivot_wider(names_from = item, values_from = adj_r_squared)

alpha_table <- alpha_table %>% left_join(adj_r2_table, by = "model")

# 直接检验网络增强策略相对传统策略的增量风险调整收益。
# 增量组合为零投资多空组合之差，因此直接以 delta_R_LS 为被解释变量。
conventional_label <- PREDICTED_FILES$model[[1]]
network_enhanced_label <- PREDICTED_FILES$model[[3]]

incremental_reg_data <- reg_data %>%
  filter(model %in% c(conventional_label, network_enhanced_label)) %>%
  mutate(
    strategy = ifelse(model == conventional_label, "conventional", "network_enhanced")
  ) %>%
  select(year_month, strategy, R_LS, RiskPremium1, SMB1, HML1, RMW1, CMA1) %>%
  pivot_wider(names_from = strategy, values_from = R_LS) %>%
  drop_na(conventional, network_enhanced) %>%
  mutate(delta_R_LS = network_enhanced - conventional)

incremental_models <- list(
  CAPM = run_nw_regression(
    delta_R_LS ~ RiskPremium1,
    incremental_reg_data,
    lag = NW_LAG_MONTHLY
  ),
  FF3 = run_nw_regression(
    delta_R_LS ~ RiskPremium1 + SMB1 + HML1,
    incremental_reg_data,
    lag = NW_LAG_MONTHLY
  ),
  FF5 = run_nw_regression(
    delta_R_LS ~ RiskPremium1 + SMB1 + HML1 + RMW1 + CMA1,
    incremental_reg_data,
    lag = NW_LAG_MONTHLY
  )
)

incremental_alpha_results <- imap_dfr(
  incremental_models,
  ~ extract_regression_table(.x, "Network-enhanced minus conventional", .y)
)

incremental_alpha_table <- incremental_alpha_results %>%
  filter(term == "(Intercept)") %>%
  transmute(
    specification,
    alpha = estimate,
    newey_west_se = nw_se,
    t_statistic = t_stat,
    p_value,
    adjusted_R2 = adj_r_squared,
    n_obs = nrow(incremental_reg_data),
    nw_lag = NW_LAG_MONTHLY
  )

write.csv(group_returns, file.path(OUT_DIR, "4_4_3_月度十分组收益.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(long_short_returns, file.path(OUT_DIR, "4_4_3_月度多空组合收益.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(reg_data, file.path(OUT_DIR, "4_4_3_Alpha回归样本.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(alpha_results, file.path(OUT_DIR, "4_4_3_CAPM_FF3_FF5_完整回归结果.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(alpha_table, file.path(OUT_DIR, "4_4_3_Table_Risk_Adjusted_Performance.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(incremental_reg_data, file.path(OUT_DIR, "4_4_3_增量组合Alpha回归样本.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(incremental_alpha_results, file.path(OUT_DIR, "4_4_3_增量组合CAPM_FF3_FF5完整回归结果.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(incremental_alpha_table, file.path(OUT_DIR, "4_4_3_Table_Incremental_Risk_Adjusted_Performance.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cat("4.4.3 CAPM and FF3 Alpha Tests 完成。\n")
cat("\n网络增强相对传统策略的增量 Alpha：\n")
print(incremental_alpha_table)
cat("输出目录：", OUT_DIR, "\n")

invisible(as.list(environment(), all.names=TRUE))

  }, envir=execution)
}

if(sys.nframe()==0L) {
  runner<-new.env()
  source(file.path(AP_DIR,"run_asset_pricing.R"),local=runner)
  runner$main(default_analysis="factor_alpha_tests")
}
