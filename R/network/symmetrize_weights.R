#!/usr/bin/env Rscript

# Directionality ablation: convert each signed directed W to a signed,
# symmetric matrix without changing dates or node sets.
# Default rule: U = (W + t(W)) / 2.

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


parse_args <- function(args) {
  cfg <- list(input = NULL, output = NULL, method = "mean", overwrite = FALSE,
              self_test = FALSE)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key == "--overwrite") {
      cfg$overwrite <- TRUE
      i <- i + 1L
    } else if (key == "--self-test") {
      cfg$self_test <- TRUE
      i <- i + 1L
    } else {
      if (i == length(args)) stop("参数缺少取值: ", key)
      value <- args[[i + 1L]]
      if (key == "--input") cfg$input <- value
      else if (key == "--output") cfg$output <- value
      else if (key == "--method") cfg$method <- value
      else stop("未知参数: ", key)
      i <- i + 2L
    }
  }
  if (!cfg$method %in% c("mean", "sum", "max_abs")) {
    stop("--method 必须是 mean、sum 或 max_abs")
  }
  cfg
}

symmetrize_one <- function(W, method = "mean") {
  W <- as.matrix(W)
  if (is.null(rownames(W)) || is.null(colnames(W)) ||
      !identical(rownames(W), colnames(W))) {
    stop("矩阵必须具有相同且同顺序的行列名")
  }
  nw_validate_matrix(W)
  diag(W) <- 0
  if (method == "mean") {
    U <- (W + t(W)) / 2
  } else if (method == "sum") {
    U <- W + t(W)
  } else {
    # Keep the direction with the larger absolute effect, including its sign.
    U <- matrix(0, nrow(W), ncol(W), dimnames = dimnames(W))
    for (i in seq_len(max(0L, nrow(W) - 1L))) {
      for (j in seq.int(i + 1L, ncol(W))) {
        value <- if (abs(W[i, j]) >= abs(W[j, i])) W[i, j] else W[j, i]
        U[i, j] <- U[j, i] <- value
      }
    }
  }
  diag(U) <- 0
  U[!is.finite(U)] <- 0
  if (!isTRUE(all.equal(U, t(U), tolerance = 1e-12))) {
    stop("无向化后矩阵不对称")
  }
  U
}

run_self_test <- function() {
  W <- matrix(c(0, 2, -1, -4, 0, 3, 5, 1, 0), 3, 3, byrow = TRUE,
              dimnames = list(LETTERS[1:3], LETTERS[1:3]))
  U <- symmetrize_one(W, "mean")
  stopifnot(isTRUE(all.equal(U, t(U))), U[1, 2] == -1, U[1, 3] == 2)
  V <- symmetrize_one(W, "max_abs")
  stopifnot(V[1, 2] == -4, V[2, 1] == -4, V[1, 3] == 5)
  cat("自测试通过\n")
}

main <- function() {
  cfg <- parse_args(commandArgs(trailingOnly = TRUE))
  if (cfg$self_test) {
    run_self_test()
    return(invisible(NULL))
  }
  if (is.null(cfg$input) || is.null(cfg$output)) {
    stop("必须指定 --input 和 --output")
  }
  if (!file.exists(cfg$input)) stop("输入不存在: ", cfg$input)
  nw_preflight(list(cfg$output), cfg$input, cfg$overwrite)
  dir.create(dirname(cfg$output), recursive = TRUE, showWarnings = FALSE)

  matrices <- readRDS(cfg$input)
  if (!is.list(matrices) || !length(matrices) || is.null(names(matrices))) {
    stop("输入必须是以日期命名的矩阵列表")
  }
  nw_validate_daily(matrices)
  result <- vector("list", length(matrices))
  names(result) <- names(matrices)
  for (i in seq_along(matrices)) {
    result[[i]] <- symmetrize_one(matrices[[i]], cfg$method)
    if (i %% 50L == 0L || i == length(matrices)) {
      cat(sprintf("进度 %d/%d [%s]\n", i, length(matrices), names(matrices)[[i]]))
    }
  }
  nw_validate_daily(result)
  nw_save_rds(result, cfg$output)
  cat(sprintf("完成: %d 个日矩阵; method=%s; output=%s\n",
              length(result), cfg$method, cfg$output))
}

if (sys.nframe() == 0L) main()
