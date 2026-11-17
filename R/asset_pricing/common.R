# Shared functions only. Importing this file never reads project data.
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(sandwich)
  library(lmtest)
})
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

wide_to_long <- function(wide_df, value_name) {
  wide_df %>%
    pivot_longer(-Date, names_to = "stock_id", values_to = value_name) %>%
    mutate("{value_name}" := as.numeric(.data[[value_name]]))
}

build_calendar_month_return <- function(return_wide, formation_dates,
                                        min_coverage = MIN_MONTH_COVERAGE) {
  return_long <- wide_to_long(return_wide, "daily_return") %>%
    mutate(year_month = format(Date, "%Y-%m"))

  month_days <- return_wide %>%
    transmute(Date, year_month = format(Date, "%Y-%m")) %>%
    semi_join(formation_dates, by = "year_month") %>%
    group_by(year_month) %>%
    summarise(month_trading_days = n_distinct(Date), .groups = "drop")

  return_long %>%
    semi_join(formation_dates, by = "year_month") %>%
    left_join(month_days, by = "year_month") %>%
    group_by(year_month, stock_id) %>%
    summarise(
      valid_return_days = sum(!is.na(daily_return)),
      month_trading_days = first(month_trading_days),
      true_month_return = ifelse(
        valid_return_days / month_trading_days >= min_coverage,
        prod(1 + daily_return[!is.na(daily_return)]) - 1,
        NA_real_
      ),
      .groups = "drop"
    ) %>%
    mutate(month_coverage = valid_return_days / month_trading_days)
}

assign_decile_portfolios <- function(panel, n_groups = N_GROUPS) {
  panel %>%
    group_by(model, Date) %>%
    filter(n() >= max(n_groups, MIN_STOCKS_PER_DATE)) %>%
    mutate(group = ntile(predicted_return, n_groups)) %>%
    ungroup()
}

build_group_returns <- function(assigned_panel) {
  assigned_panel %>%
    group_by(model, Date, year_month, group) %>%
    summarise(
      n_stocks = n(),
      avg_predicted = mean(predicted_return, na.rm = TRUE),
      group_return = mean(true_month_return, na.rm = TRUE),
      .groups = "drop"
    )
}

build_long_short_returns <- function(group_returns, n_groups = N_GROUPS) {
  group_returns %>%
    filter(group %in% c(1, n_groups)) %>%
    select(model, Date, year_month, group, group_return) %>%
    pivot_wider(names_from = group, values_from = group_return, names_prefix = "G") %>%
    filter(!is.na(.data[[paste0("G", 1)]]), !is.na(.data[[paste0("G", n_groups)]])) %>%
    mutate(R_LS = .data[[paste0("G", n_groups)]] - .data[[paste0("G", 1)]]) %>%
    select(model, Date, year_month, R_LS)
}

nw_mean_test <- function(x, lag = NW_LAG_MONTHLY) {
  data <- tibble(x = as.numeric(x)) %>% drop_na()
  if (nrow(data) < 3) {
    return(tibble(mean = NA_real_, nw_se = NA_real_, t_stat = NA_real_, p_value = NA_real_))
  }
  model <- lm(x ~ 1, data = data)
  test <- coeftest(model, vcov = NeweyWest(model, lag = lag, prewhite = FALSE))
  tibble(
    mean = unname(test["(Intercept)", "Estimate"]),
    nw_se = unname(test["(Intercept)", "Std. Error"]),
    t_stat = unname(test["(Intercept)", "t value"]),
    p_value = unname(test["(Intercept)", "Pr(>|t|)"])
  )
}

max_drawdown <- function(r) {
  r <- r[!is.na(r)]
  if (length(r) == 0) {
    return(NA_real_)
  }
  wealth <- c(1, cumprod(1 + r))
  drawdown <- wealth / cummax(wealth) - 1
  min(drawdown, na.rm = TRUE)
}

performance_summary <- function(data, return_col, lag = NW_LAG_MONTHLY,
                                periods_per_year = PERIODS_PER_YEAR) {
  data %>%
    group_by(model) %>%
    summarise(
      n_obs = sum(!is.na(.data[[return_col]])),
      mean_monthly_return = mean(.data[[return_col]], na.rm = TRUE),
      annualized_return = prod(1 + .data[[return_col]], na.rm = TRUE) ^
        (periods_per_year / n_obs) - 1,
      return_sd = sd(.data[[return_col]], na.rm = TRUE),
      annualized_volatility = return_sd * sqrt(periods_per_year),
      sharpe_ratio = ifelse(return_sd == 0, NA_real_,
                            mean_monthly_return / return_sd * sqrt(periods_per_year)),
      maximum_drawdown = max_drawdown(.data[[return_col]]),
      positive_return_ratio = mean(.data[[return_col]] > 0, na.rm = TRUE),
      cumulative_return = prod(1 + .data[[return_col]], na.rm = TRUE) - 1,
      .groups = "drop"
    ) %>%
    left_join(
      data %>%
        group_by(model) %>%
        group_modify(~ nw_mean_test(.x[[return_col]], lag = lag)) %>%
        ungroup() %>%
        rename(nw_mean = mean, nw_se = nw_se, nw_t_stat = t_stat, nw_p_value = p_value),
      by = "model"
    )
}

run_nw_regression <- function(formula, data, lag = NW_LAG_MONTHLY) {
  model <- lm(formula, data = data)
  if(model$rank < ncol(model.matrix(model)) || nobs(model) <= model$rank)
    stop("Regression has insufficient observations or collinear factors")
  test <- coeftest(model, vcov = NeweyWest(model, lag = lag, prewhite = FALSE))
  list(model = model, test = test)
}

extract_regression_table <- function(res, model_label, spec_label) {
  coef_tbl <- as.data.frame(unclass(res$test))
  names(coef_tbl)[1:4] <- c("estimate_raw", "nw_se_raw", "t_stat_raw", "p_value_raw")
  coef_tbl$term <- rownames(coef_tbl)
  rownames(coef_tbl) <- NULL
  coef_tbl %>%
    transmute(
      model = model_label,
      specification = spec_label,
      term,
      estimate = estimate_raw,
      nw_se = nw_se_raw,
      t_stat = t_stat_raw,
      p_value = p_value_raw,
      adj_r_squared = summary(res$model)$adj.r.squared
    )
}

ANALYSIS_OUTPUTS <- list(
  portfolio_sorting = c("4_4_1_十分组月度收益.csv","4_4_1_十分组收益统计.csv","4_4_1_Table_Returns_of_Portfolios_Sorted_by_Predicted_Returns.csv","4_4_1_十分组平均收益曲线.png"),
  long_short_performance = c("4_4_2_Table_Long_Short_Portfolio_Performance.csv","4_4_2_网络增强相对传统组合增量检验.csv","4_4_2_累计多空收益.csv","4_4_2_累计多空收益曲线.png"),
  factor_alpha_tests = c("4_4_3_月度十分组收益.csv","4_4_3_月度多空组合收益.csv","4_4_3_Alpha回归样本.csv","4_4_3_CAPM_FF3_FF5_完整回归结果.csv","4_4_3_Table_Risk_Adjusted_Performance.csv","4_4_3_增量组合Alpha回归样本.csv","4_4_3_增量组合CAPM_FF3_FF5完整回归结果.csv","4_4_3_Table_Incremental_Risk_Adjusted_Performance.csv"),
  transaction_cost_tests = c("4_4_4_多空组合换手率.csv","4_4_4_交易成本调整后月度收益.csv","4_4_4_交易成本检验明细.csv","4_4_4_Table_Transaction_Cost_Test.csv"),
  market_state_performance = c("4_4_5_市场状态多空月度收益样本.csv","4_4_5_Table_Market_State_Performance.csv")
)

ap_month_index <- function(x) {
  as.integer(substr(x,1,4))*12L+as.integer(substr(x,6,7))
}
ap_months <- function(x) {
  y<-gsub('年','-',gsub('月','',trimws(as.character(x)),fixed=TRUE),fixed=TRUE)
  date<-suppressWarnings(as.Date(paste0(y,'-01')))
  if(anyNA(date)) stop('Invalid monthly factor date; use YYYY-MM or YYYY年M月')
  format(date,'%Y-%m')
}
ap_date <- function(x) suppressWarnings(as.Date(gsub('/','-',as.character(x),fixed=TRUE),format='%Y-%m-%d'))

read_wide_return <- function(path, encoding='UTF-8') {
  data<-withCallingHandlers(read.csv(path,check.names=FALSE,fileEncoding=encoding,
    stringsAsFactors=FALSE),warning=function(w)stop('CSV read failed: ',conditionMessage(w)))
  if(ncol(data)<2L||!nrow(data)||anyDuplicated(names(data))) stop('Invalid wide CSV: ',path)
  names(data)[1L]<-'Date'
  data$Date<-ap_date(data$Date)
  if(anyNA(data$Date)||anyDuplicated(data$Date)) stop('Invalid/duplicate dates; remove metadata rows: ',path)
  for(n in names(data)[-1L]) {
    original<-data[[n]];v<-suppressWarnings(as.numeric(as.character(original)))
    if(any(!is.na(original)&nzchar(trimws(as.character(original)))&is.na(v))||any(is.infinite(v)))
      stop('Non-numeric or infinite value in ',path,' column ',n)
    data[[n]]<-v
  }
  if(any(!nzchar(names(data)[-1L]))) stop('Blank stock name')
  as_tibble(data) %>% arrange(Date)
}

prepare_model_panel <- function(model_name,predicted_path,predicted_encoding='UTF-8') {
  predicted_wide<-read_wide_return(predicted_path,predicted_encoding) %>%
    filter(format(Date,'%Y-%m')>=START_MONTH,format(Date,'%Y-%m')<=END_MONTH)
  if(!nrow(predicted_wide)) stop('No predictions in requested range: ',model_name)
  months<-format(predicted_wide$Date,'%Y-%m')
  if(anyDuplicated(months)) stop('Expected one prediction formation date per month; daily predictions are not supported')
  first_days<-TRUE_DAILY %>% mutate(year_month=format(Date,'%Y-%m')) %>%
    group_by(year_month) %>% summarise(first_date=min(Date),.groups='drop')
  expected<-first_days$first_date[match(months,first_days$year_month)]
  if(anyNA(expected)||any(predicted_wide$Date!=expected))
    stop('Predictions must be formed on the first trading date of the same holding month')
  if(!is.null(TRADING_CALENDAR)) {
    required_days<-TRADING_CALENDAR[format(TRADING_CALENDAR,'%Y-%m') %in% months]
    if(!all(required_days %in% TRUE_DAILY$Date)) stop('Returns do not cover supplied calendar months')
    calendar_first<-tapply(as.numeric(required_days),format(required_days,'%Y-%m'),min)
    if(!all(months %in% names(calendar_first)) ||
       any(as.numeric(predicted_wide$Date)!=calendar_first[months])) stop('Formation dates differ from calendar')
  }
  formation_dates<-predicted_wide %>% transmute(Date,year_month=format(Date,'%Y-%m'))
  common_stocks<-intersect(setdiff(names(predicted_wide),'Date'),setdiff(names(TRUE_DAILY),'Date'))
  if(!length(common_stocks)) stop('No common prediction/return stocks: ',model_name)
  predicted_long<-predicted_wide %>% select(Date,all_of(common_stocks)) %>%
    wide_to_long('predicted_return') %>% mutate(year_month=format(Date,'%Y-%m'))
  true_month_long<-TRUE_DAILY %>% select(Date,all_of(common_stocks)) %>%
    build_calendar_month_return(formation_dates)
  result<-predicted_long %>% inner_join(true_month_long,by=c('year_month','stock_id')) %>%
    filter(is.finite(predicted_return),is.finite(true_month_return)) %>% mutate(model=model_name)
  attr(result,'input_alignment')<-list(
    prediction_stocks_without_returns=setdiff(setdiff(names(predicted_wide),'Date'),common_stocks),
    formation_months=months,eligible_rows=nrow(result),prediction_rows_before_filter=nrow(predicted_long))
  result
}

load_factor_data <- function(path=FACTOR_PATH) {
  if(is.null(path)) stop('Supply --factors for alpha tests')
  if(is.null(FACTOR_UNITS)||!FACTOR_UNITS %in% c('decimal','percent'))
    stop('Explicit --factor-units decimal|percent is required for alpha tests')
  d<-read.csv(path,check.names=FALSE,fileEncoding=FACTOR_ENCODING,stringsAsFactors=FALSE)
  if('year_month' %in% names(d)) d$year_month<-ap_months(d$year_month)
  else if('TradingMonth' %in% names(d)) d$year_month<-ap_months(d$TradingMonth)
  else stop('Factor file needs TradingMonth or year_month')
  required<-c('RiskPremium1','SMB1','HML1','RMW1','CMA1')
  if(!all(required %in% names(d))||anyDuplicated(d$year_month)) stop('Missing factor columns or duplicate factor months')
  for(n in required) {
    old<-d[[n]];d[[n]]<-suppressWarnings(as.numeric(as.character(old)))
    if(any(!is.na(old)&nzchar(trimws(as.character(old)))&is.na(d[[n]]))||any(is.infinite(d[[n]])))
      stop('Invalid numeric factor: ',n)
    if(FACTOR_UNITS=='percent') d[[n]]<-d[[n]]/100
  }
  as_tibble(d) %>% arrange(year_month)
}

ap_check_consecutive <- function(panel) {
  months<-panel %>% distinct(model,year_month) %>% arrange(model,year_month)
  for(m in unique(months$model)) {
    ix<-ap_month_index(months$year_month[months$model==m])
    if(any(diff(ix)!=1L)) stop('Missing portfolio months for ',m,
      '; select a continuous input interval instead of treating missing months as adjacent')
  }
  invisible(NULL)
}

create_context <- function(cfg) {
  ctx<-new.env(parent=globalenv())
  source(file.path(AP_DIR,'common.R'),local=ctx)
  constants<-list(N_GROUPS=cfg$n_groups,PERIODS_PER_YEAR=12,NW_LAG_MONTHLY=cfg$nw_lag,
    MIN_STOCKS_PER_DATE=cfg$min_stocks,START_MONTH=cfg$start_month,END_MONTH=cfg$end_month,
    MIN_MONTH_COVERAGE=cfg$min_month_coverage,FONT_CN='sans',OUT_DIR=cfg$output_dir,
    TRUE_RETURN_PATH=cfg$returns,FACTOR_PATH=cfg$factors,FACTOR_ENCODING=cfg$factor_encoding,
    FACTOR_UNITS=cfg$factor_units,COST_LEVELS=cfg$cost_bps/10000,VOL_WINDOW_MONTHS=cfg$vol_window,
    NO_PLOTS=cfg$no_plots,TRADING_CALENDAR=NULL)
  list2env(constants,envir=ctx)
  ctx$TRUE_DAILY<-ctx$read_wide_return(cfg$returns,cfg$return_encoding)
  if(cfg$return_units=='percent') ctx$TRUE_DAILY[-1L]<-ctx$TRUE_DAILY[-1L]/100
  if(any(as.matrix(ctx$TRUE_DAILY[-1L]) < -1,na.rm=TRUE)) stop('Daily simple return below -1; check units')
  if(any(rowSums(is.finite(as.matrix(ctx$TRUE_DAILY[-1L])))==0L)) stop('A market day has no finite return')
  if(!is.null(cfg$calendar)) {
    cal<-read.csv(cfg$calendar,check.names=FALSE,fileEncoding=cfg$return_encoding)
    ctx$TRADING_CALENDAR<-ap_date(cal[[1L]])
    if(anyNA(ctx$TRADING_CALENDAR)||anyDuplicated(ctx$TRADING_CALENDAR)) stop('Invalid calendar')
    ctx$TRADING_CALENDAR<-sort(ctx$TRADING_CALENDAR)
  }
  ctx$PREDICTED_FILES<-tibble(model=c('Conventional-factor','Network-factor','Network-enhanced'),
    path=c(cfg$conventional,cfg$network,cfg$enhanced),encoding=cfg$prediction_encoding)
  model_panels<-pmap(ctx$PREDICTED_FILES,~ctx$prepare_model_panel(..1,..2,..3))
  ctx$input_alignment<-setNames(lapply(model_panels,attr,'input_alignment'),ctx$PREDICTED_FILES$model)
  panel<-bind_rows(model_panels)
  if(anyDuplicated(panel[,c('model','Date','stock_id')])) stop('Duplicate model/date/stock keys')
  ctx$sample_counts_before<-panel %>% count(model,Date,year_month,name='eligible_stocks')
  if(cfg$sample_mode=='common') {
    keys<-panel %>% count(Date,stock_id) %>% filter(n==3L) %>% select(Date,stock_id)
    panel<-semi_join(panel,keys,by=c('Date','stock_id'))
  }
  ctx$panel<-panel
  assigned<-ctx$assign_decile_portfolios(panel,cfg$n_groups)
  if(!all(ctx$PREDICTED_FILES$model %in% assigned$model)) stop('A model has no valid portfolio dates')
  ctx$ap_check_consecutive(assigned)
  ctx$assigned_panel<-assigned
  ctx$group_returns<-ctx$build_group_returns(assigned)
  ctx$long_short_returns<-ctx$build_long_short_returns(ctx$group_returns,cfg$n_groups)
  ctx$sample_counts<-ctx$sample_counts_before %>% left_join(
    assigned %>% count(model,Date,name='portfolio_stocks'),by=c('model','Date')) %>%
    mutate(portfolio_stocks=replace_na(portfolio_stocks,0L))
  if('factor_alpha_tests' %in% cfg$analyses) ctx$factor_data_checked<-ctx$load_factor_data()
  ctx
}
