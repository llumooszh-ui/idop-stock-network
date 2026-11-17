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

run_market_state_performance <- function(context) {
  execution <- new.env(parent=context)
  evalq({

# 自然月市场状态检验。
# 方向状态按当月实现的等权市场收益划分，属于事后描述性分组。
# 波动率状态使用月初可知的过去 6 个完整自然月市场收益标准差。


rolling_sd <- function(x, window) {
  vapply(
    seq_along(x),
    function(i) {
      if (i < window || any(is.na(x[(i - window + 1):i]))) {
        return(NA_real_)
      }
      sd(x[(i - window + 1):i])
    },
    numeric(1)
  )
}

true_daily_wide <- TRUE_DAILY

market_state <- true_daily_wide %>%
  mutate(
    market_daily_return = rowMeans(across(-Date), na.rm = TRUE),
    year_month = format(Date, "%Y-%m")
  ) %>%
  group_by(year_month) %>%
  summarise(
    market_month_return = prod(1 + market_daily_return, na.rm = TRUE) - 1,
    .groups = "drop"
  ) %>%
  arrange(year_month) %>%
  mutate(
    direction_state = ifelse(market_month_return >= 0, "Up market", "Down market"),
    trailing_market_volatility = rolling_sd(lag(market_month_return), VOL_WINDOW_MONTHS),
    volatility_state = ifelse(
      trailing_market_volatility >= median(trailing_market_volatility, na.rm = TRUE),
      "High volatility",
      "Low volatility"
    )
  )

assigned_panel <- assign_decile_portfolios(panel, N_GROUPS)
long_short_returns <- build_group_returns(assigned_panel) %>%
  build_long_short_returns(N_GROUPS) %>%
  left_join(market_state, by = "year_month")

state_summary <- bind_rows(
  long_short_returns %>%
    filter(!is.na(direction_state)) %>%
    group_by(model, state_type = "Contemporaneous market direction", state = direction_state) %>%
    group_modify(~ nw_mean_test(.x$R_LS, lag = NW_LAG_MONTHLY)) %>%
    ungroup(),
  long_short_returns %>%
    filter(!is.na(volatility_state)) %>%
    group_by(model, state_type = "Lagged market volatility", state = volatility_state) %>%
    group_modify(~ nw_mean_test(.x$R_LS, lag = NW_LAG_MONTHLY)) %>%
    ungroup()
) %>%
  rename(mean_R_LS = mean, nw_t_stat = t_stat, nw_p_value = p_value)

write.csv(long_short_returns, file.path(OUT_DIR, "4_4_5_市场状态多空月度收益样本.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(state_summary, file.path(OUT_DIR, "4_4_5_Table_Market_State_Performance.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cat("市场状态表现检验完成。\n")
cat("输出目录：", OUT_DIR, "\n")

invisible(as.list(environment(), all.names=TRUE))

  }, envir=execution)
}

if(sys.nframe()==0L) {
  runner<-new.env()
  source(file.path(AP_DIR,"run_asset_pricing.R"),local=runner)
  runner$main(default_analysis="market_state_performance")
}
