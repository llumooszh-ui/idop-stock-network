#!/usr/bin/env Rscript

# 按 IdopNetwork 已有阶段边界和节点集，用同期收盘价构建阶段静态相关性网络。
# 每个阶段只估计一次 Pearson/Spearman 矩阵，然后在该阶段的每个交易日复用。
# 多层网络（大网+行业网）按日叠加，同时保持相关矩阵对称。

# Resolve sibling helpers when called with Rscript or source().
local({
  sources <- Filter(Negate(is.null), lapply(sys.frames(), function(f)
    get0("ofile", envir = f, inherits = FALSE)))
  ofile <- if (length(sources)) sources[[length(sources)]] else NULL
  if (is.null(ofile)) {
    arg <- grep("^--file=", commandArgs(), value = TRUE)
    if (!length(arg)) stop("Cannot resolve script path")
    ofile <- sub("^--file=", "", arg[[1L]])
  }
  sys.source(file.path(dirname(normalizePath(ofile)), "network_common.R"),
             envir = parent.env(environment()))
})


`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

parse_args <- function(args) {
  cfg <- list(
    input_dirs = character(), prices = NULL, price_dir = NULL,
    big_prices = NULL, all_prices = NULL, name_reference = NULL, output = NULL,
    pattern = "^results_.+\\.rds$", method = "pearson",
    sparsify = "density_match", threshold = 0.3,
    min_obs = 3L, overwrite = FALSE, self_test = FALSE, calendar = NULL
  )
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key == "--overwrite") {
      cfg$overwrite <- TRUE; i <- i + 1L
    } else if (key == "--self-test") {
      cfg$self_test <- TRUE; i <- i + 1L
    } else {
      if (i == length(args)) stop("参数缺少取值: ", key)
      value <- args[[i + 1L]]
      if (key == "--calendar") cfg$calendar <- value
      else if (key == "--input-dir") cfg$input_dirs <- c(cfg$input_dirs, value)
      else if (key == "--prices") cfg$prices <- value
      else if (key == "--price-dir") cfg$price_dir <- value
      else if (key == "--big-prices") cfg$big_prices <- value
      else if (key == "--all-prices") cfg$all_prices <- value
      else if (key == "--name-reference") cfg$name_reference <- value
      else if (key == "--output") cfg$output <- value
      else if (key == "--pattern") cfg$pattern <- value
      else if (key == "--method") cfg$method <- value
      else if (key == "--sparsify") cfg$sparsify <- value
      else if (key == "--threshold") cfg$threshold <- as.numeric(value)
      else if (key == "--min-obs") cfg$min_obs <- as.integer(value)
      else stop("未知参数: ", key)
      i <- i + 2L
    }
  }
  if (!cfg$method %in% c("pearson", "spearman")) {
    stop("--method 必须是 pearson 或 spearman")
  }
  if (!cfg$sparsify %in% c("density_match", "threshold", "none")) {
    stop("--sparsify 必须是 density_match、threshold 或 none")
  }
  if (!is.finite(cfg$threshold) || cfg$threshold < 0 || cfg$threshold > 1) {
    stop("--threshold 必须在 [0,1] 内")
  }
  if (is.na(cfg$min_obs) || cfg$min_obs < 2L) stop("--min-obs 至少为2")
  cfg
}

parse_date <- function(x) {
  suppressWarnings(as.Date(gsub("/", "-", trimws(as.character(x)), fixed = TRUE),
                           format = "%Y-%m-%d"))
}

read_price_panel <- function(path) {
  if (!file.exists(path)) stop("收盘价文件不存在: ", path)
  encodings <- c("UTF-8-BOM", "UTF-8", "GB18030", "GBK", "")
  raw <- NULL
  dates <- NULL
  for (enc in encodings) {
    candidate <- tryCatch(withCallingHandlers(read.csv(
      path, check.names = FALSE, fileEncoding = enc, stringsAsFactors = FALSE
    ), warning = function(w) stop(conditionMessage(w))), error = function(e) NULL)
    if (is.null(candidate) || ncol(candidate) < 2L) next
    candidate_dates <- parse_date(candidate[[1L]])
    if (!any(!is.na(candidate_dates))) next
    raw <- candidate
    dates <- candidate_dates
    break
  }
  if (is.null(raw) || ncol(raw) < 2L) stop("无法读取收盘价文件: ", path)
  valid <- !is.na(dates)
  if (!any(valid)) stop("收盘价第一列没有可识别日期")
  values <- as.matrix(raw[valid, -1L, drop = FALSE])
  suppressWarnings(storage.mode(values) <- "double")
  rownames(values) <- as.character(dates[valid])
  if (anyDuplicated(rownames(values))) stop("收盘价存在重复日期")
  values[order(as.Date(rownames(values))), , drop = FALSE]
}

merge_price_panels <- function(panels) {
  all_dates <- sort(unique(unlist(lapply(panels, rownames))))
  all_stocks <- unique(unlist(lapply(panels, colnames)))
  ans <- matrix(NA_real_, length(all_dates), length(all_stocks),
                dimnames = list(all_dates, all_stocks))
  for (panel in panels) {
    old <- ans[rownames(panel), colnames(panel), drop = FALSE]
    fill <- is.na(old) & is.finite(panel)
    old[fill] <- panel[fill]
    ans[rownames(panel), colnames(panel)] <- old
  }
  ans
}

read_big_price_panel <- function(big_path, price_dir) {
  paths <- big_path
  if (!is.null(price_dir) && dir.exists(price_dir)) {
    candidates <- list.files(
      price_dir, pattern = "^科创板[0-9]+类数据_收盘价\\.csv$", full.names = TRUE
    )
    paths <- unique(c(paths, sort(candidates)))
  }
  cat(sprintf("大网收盘价由%d个文件合并补齐\n", length(paths)))
  merge_price_panels(lapply(paths, read_price_panel))
}

read_header_and_first_row <- function(path) {
  encodings <- c("UTF-8-BOM", "UTF-8", "GB18030", "GBK", "")
  for (enc in encodings) {
    candidate <- tryCatch(withCallingHandlers(read.csv(
      path, check.names = FALSE, fileEncoding = enc, stringsAsFactors = FALSE,
      nrows = 1L
    ), warning = function(w) stop(conditionMessage(w))), error = function(e) NULL)
    if (!is.null(candidate) && nrow(candidate) >= 1L && ncol(candidate) > 2L) {
      return(candidate)
    }
  }
  stop("无法读取名称映射参考文件: ", path)
}

read_all_price_panel <- function(price_path, name_reference) {
  panel <- read_price_panel(price_path)
  ref <- read_header_and_first_row(name_reference)
  ref_codes <- trimws(as.character(unlist(
    ref[1L, -1L, drop = FALSE], use.names = FALSE
  )))
  ref_names <- names(ref)[-1L]
  mapping <- setNames(ref_names, ref_codes)
  mapped <- unname(mapping[colnames(panel)])
  if (anyNA(mapped)) {
    stop("全市场收盘价有代码无法通过参考文件映射为股票名称")
  }
  if (anyDuplicated(mapped)) stop("代码到股票名称的映射不唯一")
  colnames(panel) <- mapped
  panel
}

pair_observations <- function(X) {
  ok <- is.finite(X)
  crossprod(ok * 1L)
}

stage_correlation <- function(X, method, min_obs) {
  p <- ncol(X)
  stocks <- colnames(X)
  if (p < 1L) return(matrix(numeric(), 0L, 0L))
  if (nrow(X) < 2L) {
    W <- matrix(0, p, p, dimnames = list(stocks, stocks))
    return(W)
  }
  W <- suppressWarnings(cor(X, use = "pairwise.complete.obs", method = method))
  W <- as.matrix(W)
  dimnames(W) <- list(stocks, stocks)
  n_pair <- pair_observations(X)
  W[!is.finite(W) | n_pair < min_obs] <- 0
  diag(W) <- 0
  # 浮点误差可能破坏完全对称，显式对称化。
  W <- (W + t(W)) / 2
  diag(W) <- 0
  W
}

idop_pair_budget <- function(stage, p) {
  adj <- stage$result$adj %||% stage$adj
  if (is.null(adj)) stop("Density audit requires a stage adjacency matrix")
  adj <- as.matrix(adj)
  if (!identical(dim(adj), c(as.integer(p), as.integer(p)))) stop("Stage adjacency size differs from node set")
  if (any(!is.finite(adj))) stop("Stage adjacency contains non-finite values")
  diag(adj) <- 0
  # Idop 是有向边；一条无向相关边占据两个矩阵元素。
  max_pairs <- as.integer(p * (p - 1L) / 2L)
  min(max_pairs, as.integer(round(sum(adj != 0) / 2)))
}

stage_stock_names <- function(stage) {
  stocks <- stage$stocks
  if (!is.null(stocks) && length(stocks)) return(as.character(stocks))
  adj <- stage$result$adj %||% stage$adj
  if (!is.null(adj) && !is.null(colnames(adj))) return(colnames(adj))
  effects <- stage$result$effects %||% stage$effects
  if (!is.null(effects) && length(effects) && !is.null(colnames(effects[[1L]]))) {
    return(colnames(effects[[1L]]))
  }
  stop("阶段中无法识别股票节点名称")
}

sparsify_matrix <- function(W, mode, threshold, pair_budget = NULL) {
  p <- nrow(W)
  if (p < 2L) return(W)
  upper <- upper.tri(W)
  valid <- upper & is.finite(W) & W != 0
  keep <- matrix(FALSE, p, p)
  if (mode == "none") {
    keep[valid] <- TRUE
  } else if (mode == "threshold") {
    keep[valid & abs(W) >= threshold] <- TRUE
  } else {
    budget <- max(0L, min(as.integer(pair_budget %||% 0L), sum(valid)))
    if (budget > 0L) {
      idx <- which(valid)
      # ties.method=首次出现，保证在相同输入上可重现。
      chosen <- idx[order(abs(W[idx]), decreasing = TRUE, method = "radix")[
        seq_len(budget)
      ]]
      keep[chosen] <- TRUE
    }
  }
  keep <- keep | t(keep)
  W[!keep] <- 0
  diag(W) <- 0
  W
}

normalize_symmetric <- function(W) {
  strength <- colSums(abs(W))
  scale <- mean(strength[is.finite(strength) & strength > 0])
  if (is.finite(scale) && scale > 0) W / scale else W * 0
}

add_matrix <- function(target, source) {
  if (is.null(target)) return(source)
  stocks <- union(rownames(target), rownames(source))
  ans <- matrix(0, length(stocks), length(stocks), dimnames = list(stocks, stocks))
  ans[rownames(target), colnames(target)] <-
    ans[rownames(target), colnames(target), drop = FALSE] + target
  ans[rownames(source), colnames(source)] <-
    ans[rownames(source), colnames(source), drop = FALSE] + source
  diag(ans) <- 0
  ans
}

safe_save_rds <- function(object, path, overwrite = FALSE) {
  if (file.exists(path) && !overwrite) stop("输出已存在：", path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = paste0(basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  saveRDS(object, tmp, compress = "xz")
  if (!file.rename(tmp, path)) stop("无法写入输出: ", path)
}

process_stage <- function(stage, prices, cfg) {
  start <- parse_date(stage$start_date)
  end <- parse_date(stage$end_date)
  if (is.na(start) || is.na(end) || start > end) stop("阶段日期非法")
  requested_stocks <- stage_stock_names(stage)
  nw_check_names(requested_stocks, "Stage stocks")
  absent <- setdiff(requested_stocks, colnames(prices))
  if (length(absent)) stop("Stage prices lack stocks: ", paste(absent, collapse = ", "))
  stocks <- requested_stocks
  dates <- as.Date(rownames(prices))
  rows <- dates >= start & dates <= end
  X <- prices[rows, stocks, drop = FALSE]
  if (!is.null(cfg$trading_days)) {
    expected <- cfg$trading_days[cfg$trading_days >= start & cfg$trading_days <= end]
    if (!identical(as.character(dates[rows]), as.character(expected)))
      stop("Stage prices and --calendar dates differ")
  }
  if (nrow(X) < cfg$min_obs || any(colSums(is.finite(X)) < cfg$min_obs))
    stop("Insufficient observations for a stage stock")
  W <- stage_correlation(X, cfg$method, cfg$min_obs)
  budget <- idop_pair_budget(stage, length(stocks))
  adj <- as.matrix(stage$result$adj %||% stage$adj)
  diag(adj) <- 0
  directed_edges <- sum(adj != 0)
  W <- sparsify_matrix(W, cfg$sparsify, cfg$threshold, budget)
  W <- normalize_symmetric(W)
  list(
    W = W, dates = as.character(dates[rows]),
    audit = data.frame(
      stage = stage$stage %||% NA_integer_, start_date = as.character(start),
      end_date = as.character(end), n_days = nrow(X), n_stocks = length(stocks),
      idop_directed_edges = directed_edges,
      target_correlation_pairs = budget,
      actual_correlation_pairs = sum(W[upper.tri(W)] != 0),
      stringsAsFactors = FALSE
    )
  )
}

resolve_price_path <- function(rds_path, cfg) {
  if (!is.null(cfg$prices)) return(cfg$prices)
  name <- basename(rds_path)
  if (grepl("大网", name, fixed = TRUE)) {
    if (is.null(cfg$big_prices)) stop("大网RDS需要 --big-prices: ", name)
    return(cfg$big_prices)
  }
  hit <- regmatches(name, regexec("results_([0-9]+)类", name))[[1L]]
  if (length(hit) != 2L) stop("无法从RDS文件名推断收盘价文件: ", name)
  if (is.null(cfg$price_dir)) stop("行业RDS需要 --price-dir: ", name)
  file.path(cfg$price_dir, paste0("科创板", hit[[2L]], "类数据_收盘价.csv"))
}

run_self_test <- function() {
  X <- cbind(A = 1:8, B = 2 * (1:8), C = 8:1, D = c(1, 3, 2, 5, 4, 7, 6, 8))
  W <- stage_correlation(X, "pearson", 3L)
  stopifnot(isTRUE(all.equal(W, t(W))), all(diag(W) == 0),
            W["A", "B"] > 0.99, W["A", "C"] < -0.99)
  S <- sparsify_matrix(W, "density_match", 0.3, 2L)
  stopifnot(sum(S[upper.tri(S)] != 0) == 2L, isTRUE(all.equal(S, t(S))))
  N <- normalize_symmetric(S)
  stopifnot(abs(mean(colSums(abs(N))[colSums(abs(N)) > 0]) - 1) < 1e-12)
  cat("内置测试通过：相关系数、对称性、密度匹配和对称归一化正确。\n")
}

main <- function() {
  cfg <- parse_args(commandArgs(trailingOnly = TRUE))
  if (cfg$self_test) return(run_self_test())
  if (!length(cfg$input_dirs) || is.null(cfg$output)) {
    stop("必须指定 --input-dir 和 --output")
  }
  if (is.null(cfg$prices) && (is.null(cfg$price_dir) || is.null(cfg$big_prices))) {
    stop("请指定单一 --prices，或同时指定 --price-dir 和 --big-prices")
  }
  missing <- cfg$input_dirs[!dir.exists(cfg$input_dirs)]
  if (length(missing)) stop("阶段RDS目录不存在: ", paste(missing, collapse = ", "))
  candidates <- unlist(lapply(cfg$input_dirs, function(d) {
    list.files(d, pattern = cfg$pattern, full.names = TRUE)
  }))
  # Avoid silently replacing a layer with a same-named file.
  if (anyDuplicated(basename(candidates))) stop("Duplicate layer filenames in input directories")
  files <- candidates
  files <- files[order(basename(files))]
  if (!length(files)) stop("未找到阶段RDS")
  cat(sprintf("阶段RDS: %d个\n", length(files)))

  nw_preflight(list(cfg$output, paste0(cfg$output, ".audit.csv")), files, cfg$overwrite)
  if (is.null(cfg$calendar)) stop("Supply --calendar to enforce comparable trading dates")
  cfg$trading_days <- nw_calendar(cfg$calendar)
  matrices <- list()
  audits <- list()
  price_cache <- list()
  all_panel <- NULL
  if (!is.null(cfg$all_prices) || !is.null(cfg$name_reference)) {
    if (is.null(cfg$all_prices) || is.null(cfg$name_reference)) {
      stop("--all-prices 和 --name-reference 必须同时指定")
    }
    all_panel <- read_all_price_panel(cfg$all_prices, cfg$name_reference)
    cat(sprintf("全市场收盘价补充面板: %d天 x %d股\n",
                nrow(all_panel), ncol(all_panel)))
  }
  for (path in files) {
    price_path <- resolve_price_path(path, cfg)
    if (!file.exists(price_path)) stop("匹配的收盘价文件不存在: ", price_path)
    is_big <- grepl("大网", basename(path), fixed = TRUE)
    cache_key <- if (is_big) paste0("BIG::", price_path) else price_path
    if (is.null(price_cache[[cache_key]])) {
      primary <- if (is_big && is.null(cfg$prices)) {
        read_big_price_panel(price_path, cfg$price_dir)
      } else {
        read_price_panel(price_path)
      }
      price_cache[[cache_key]] <- if (is.null(all_panel)) primary else {
        # 分类/大网文件为主，全市场代码表只补齐缺失日期。
        merge_price_panels(list(primary, all_panel))
      }
    }
    prices <- price_cache[[cache_key]]
    stages <- readRDS(path)
    if (!is.list(stages)) stop("RDS不是阶段列表: ", path)
    layer_dates <- character()
    for (s in seq_along(stages)) {
      ans <- process_stage(stages[[s]], prices, cfg)
      if (length(intersect(layer_dates, ans$dates))) stop("Overlapping stages in layer: ", path)
      layer_dates <- c(layer_dates, ans$dates)
      # 各分层先调整到相同的平均节点强度，再进行多层叠加。
      for (date in ans$dates) matrices[[date]] <- add_matrix(matrices[[date]], ans$W)
      audit <- ans$audit
      audit$file <- basename(path)
      audit$price_file <- basename(price_path)
      audit$missing_stage_stocks <- length(setdiff(stage_stock_names(stages[[s]]),
                                                   colnames(prices)))
      audits[[length(audits) + 1L]] <- audit
    }
    cat(sprintf("已处理: %s（%d阶段）\n", basename(path), length(stages)))
  }
  matrices <- lapply(matrices, normalize_symmetric)
  matrices <- matrices[order(as.Date(names(matrices)))]
  nw_validate_daily(matrices)
  safe_save_rds(matrices, cfg$output, cfg$overwrite)
  audit <- do.call(rbind, audits)
  audit_path <- paste0(cfg$output, ".audit.csv")
  write.csv(audit, audit_path, row.names = FALSE, fileEncoding = "UTF-8")
  cat(sprintf("完成: %d个逐日矩阵，%s ~ %s\n",
              length(matrices), names(matrices)[1L], names(matrices)[length(matrices)]))
  cat("权重矩阵: ", cfg$output, "\n审计表: ", audit_path, "\n", sep = "")
}

if (sys.nframe() == 0L) main()
