#!/usr/bin/env Rscript
# Resolve helpers for Rscript and source(); importing a module never runs the CLI.
local({
  sources <- Filter(Negate(is.null), lapply(sys.frames(), function(f)
    get0("ofile", envir = f, inherits = FALSE)))
  ofile <- if (length(sources)) sources[[length(sources)]] else NULL
  if (is.null(ofile)) {
    arg <- grep("^--file=", commandArgs(), value = TRUE)
    if (!length(arg)) stop("Cannot resolve script path")
    ofile <- sub("^--file=", "", arg[[1L]])
  }
  assign("FEATURES_DIR", dirname(normalizePath(ofile)), envir = parent.env(environment()))
  sys.source(file.path(dirname(normalizePath(ofile)), "feature_common.R"),
             envir = parent.env(environment()))
})

compute_influence <- function(W, returns_row, target_date, return_date,
                              weight_date, min_coverage) {
  stocks <- rownames(W)
  available_stocks <- intersect(stocks, names(returns_row)[is.finite(returns_row)])
  empty <- data.table(
    Date = as.IDate(target_date), stock = stocks,
    net_return_influence = NA_real_,
    net_return_influence_pos_edges = NA_real_,
    net_return_influence_neg_edges = NA_real_,
    net_return_influence_abs = NA_real_,
    net_return_influence_coverage = 0
  )
  if (!length(available_stocks)) return(empty)

  W_valid <- W[available_stocks, stocks, drop = FALSE]
  r <- as.numeric(returns_row[available_stocks])
  coverage <- colSums(abs(W_valid))
  usable <- is.finite(coverage) & coverage > 0 & coverage >= min_coverage

  net <- pos <- neg <- magnitude <- rep(NA_real_, length(stocks))
  if (any(usable)) {
    denom <- coverage[usable]
    net[usable] <- as.numeric(r %*% W_valid[, usable, drop = FALSE]) / denom
    pos[usable] <- as.numeric(r %*% pmax(W_valid[, usable, drop = FALSE], 0)) / denom
    neg[usable] <- as.numeric(r %*% pmax(-W_valid[, usable, drop = FALSE], 0)) / denom
    magnitude[usable] <- as.numeric(abs(r) %*%
      abs(W_valid[, usable, drop = FALSE])) / denom
  }

  data.table(
    Date = as.IDate(target_date), stock = stocks,
    net_return_influence = net,
    net_return_influence_pos_edges = pos,
    net_return_influence_neg_edges = neg,
    net_return_influence_abs = magnitude,
    net_return_influence_coverage = coverage
  )
}


add_return_influence <- function(matrices, metric_object, returns, min_coverage = 0) {
  feature_validate_matrices(matrices)
  if (!is.finite(min_coverage) || min_coverage < 0 || min_coverage > 1) stop("min_coverage must be in [0,1]")
  metrics <- copy(as.data.table(metric_object$data)); check_keys(metrics)
  if (any(FEATURE_GROUPS$NWR %in% names(metrics))) stop("NWR features already present")
  dates <- names(matrices)
  rows <- list()
  if (length(matrices) >= 3L) for (k in seq.int(3L, length(matrices))) {
    rd <- dates[[k-1L]]
    if (!rd %in% rownames(returns)) stop("Missing lagged return date: ", rd)
    r <- setNames(as.numeric(returns[rd, , drop=FALSE]), colnames(returns))
    rows[[length(rows)+1L]] <- compute_influence(matrices[[k-2L]], r, dates[[k]],
                                                rd, dates[[k-2L]], min_coverage)
  }
  influence <- if (length(rows)) rbindlist(rows) else empty_features(FEATURE_GROUPS$NWR)
  check_keys(influence)
  result <- merge(metrics, influence, by=c("Date","stock"), all.x=TRUE, sort=FALSE)
  setcolorder(result, c(names(metrics), FEATURE_GROUPS$NWR)); setorder(result,Date,stock)
  stopifnot(nrow(result)==nrow(metrics)); check_keys(result)
  metric_object$data <- result
  metric_object$rows <- nrow(result); metric_object$columns <- ncol(result)
  metric_object$return_influence <- list(formula="R[t-1] with W[t-2] divided by available absolute incoming weight",
    min_coverage=min_coverage, lagged=TRUE)
  metric_object
}
main <- function() {
  cfg <- feature_args(list(matrices=NULL,metrics=NULL,returns=NULL,output=NULL,csv=NULL,
    encoding="GB18030",min_coverage="0",overwrite=FALSE),c("matrices","metrics","returns","output"))
  nw_preflight(list(cfg$output,cfg$csv),c(cfg$matrices,cfg$metrics,cfg$returns),cfg$overwrite)
  result <- add_return_influence(readRDS(cfg$matrices),readRDS(cfg$metrics),
     nw_read_panel(cfg$returns,cfg$encoding),as.numeric(cfg$min_coverage))
  nw_save_rds(result,cfg$output)
  if (!is.null(cfg$csv)) feature_write_csv(result$data,cfg$csv)
}
if (sys.nframe()==0L) main()
