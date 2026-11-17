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

run_transaction_cost_tests <- function(context) {
  execution <- new.env(parent=context)
  evalq({

# 交易成本检验：每月月初调仓，估计 G10-G1 目标权重换手率。


assigned_panel <- assign_decile_portfolios(panel, N_GROUPS)
group_returns <- build_group_returns(assigned_panel)
long_short_returns <- build_long_short_returns(group_returns, N_GROUPS)

positions <- assigned_panel %>%
  filter(group %in% c(1, N_GROUPS)) %>%
  group_by(model, Date, group) %>%
  mutate(
    side = ifelse(group == N_GROUPS, 1, -1),
    weight = side / n()
  ) %>%
  ungroup() %>%
  select(model, Date, stock_id, weight)

positions_full <- positions %>%
  group_by(model) %>%
  complete(Date, stock_id, fill = list(weight = 0)) %>%
  ungroup()

turnover <- positions_full %>%
  arrange(model, stock_id, Date) %>%
  group_by(model, stock_id) %>%
  mutate(prev_weight = lag(weight, default = 0)) %>%
  ungroup() %>%
  mutate(abs_trade = abs(weight - prev_weight)) %>%
  group_by(model, Date) %>%
  summarise(turnover = sum(abs_trade, na.rm = TRUE), .groups = "drop")

net_returns <- long_short_returns %>%
  left_join(turnover, by = c("model", "Date")) %>%
  mutate(turnover = replace_na(turnover, 0)) %>%
  crossing(cost_bps = COST_LEVELS * 10000) %>%
  mutate(
    cost_rate = cost_bps / 10000,
    net_R_LS = R_LS - cost_rate * turnover
  )

cost_summary <- net_returns %>%
  group_by(model, cost_bps) %>%
  summarise(
    mean_net_return = mean(net_R_LS, na.rm = TRUE),
    cumulative_net_return = prod(1 + net_R_LS, na.rm = TRUE) - 1,
    .groups = "drop"
  ) %>%
  left_join(
    long_short_returns %>%
      group_by(model) %>%
      summarise(gross_return = mean(R_LS, na.rm = TRUE), .groups = "drop"),
    by = "model"
  ) %>%
  left_join(
    turnover %>%
      group_by(model) %>%
      summarise(mean_turnover = mean(turnover, na.rm = TRUE), .groups = "drop"),
    by = "model"
  ) %>%
  select(model, cost_bps, gross_return, mean_turnover, mean_net_return, cumulative_net_return)

cost_wide <- cost_summary %>%
  mutate(cost_label = paste0("Net return at ", cost_bps, " bps")) %>%
  select(model, gross_return, mean_turnover, cost_label, mean_net_return) %>%
  pivot_wider(names_from = cost_label, values_from = mean_net_return)

write.csv(turnover, file.path(OUT_DIR, "4_4_4_多空组合换手率.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(net_returns, file.path(OUT_DIR, "4_4_4_交易成本调整后月度收益.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(cost_summary, file.path(OUT_DIR, "4_4_4_交易成本检验明细.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(cost_wide, file.path(OUT_DIR, "4_4_4_Table_Transaction_Cost_Test.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cat("交易成本检验完成。\n")
cat("输出目录：", OUT_DIR, "\n")

invisible(as.list(environment(), all.names=TRUE))

  }, envir=execution)
}

if(sys.nframe()==0L) {
  runner<-new.env()
  source(file.path(AP_DIR,"run_asset_pricing.R"),local=runner)
  runner$main(default_analysis="transaction_cost_tests")
}
