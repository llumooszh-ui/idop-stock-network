#!/usr/bin/env Rscript
# Stage estimation and effects reconstruction are separate modes.
# Rebuild mode does not load training packages or run MTODEs.
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

load_estimation_packages <- function() {
  pkgs <- c("deSolve", "Matrix", "orthopolynom", "ADSIHT", "SGL", "grpreg", "glmnet", "splines")
  for (p in pkgs) {
    if (!requireNamespace(p, quietly = TRUE)) stop("Missing estimation package: ", p)
    suppressPackageStartupMessages(library(p, character.only = TRUE))
  }
}

MTODEs <- function(data,return_data,time=NULL,M=3,basis_type = 'poly', seed = 20260922L){
  load_estimation_packages()
  set.seed(seed)
  #Here data should be a p*m matrix

  #0.basic process 一些初始化操作
  if(is.null(time)){
    if (is.null(rownames(data))) {
      times = 1:nrow(data)
    } else{
      times = rownames(data)
    }
  }
  if (is.null(colnames(data))) {
    colnames(data)=paste0("x",1:ncol(data))
  }
  orig_times = time
  times = 1:nrow(data)
  p = ncol(data) #number of nodes
  n = nrow(data)
  if (!identical(dim(data), dim(return_data)) ||
      !identical(dimnames(data), dimnames(return_data))) stop("Price/return axes differ")
  if (any(!is.finite(data)) || any(!is.finite(return_data))) stop("Non-finite stage input")
  if (p < 2L || n < max(4L, M + 1L)) stop("Stage too small for spline/polynomial fit")
  if (any(apply(data, 2L, sd) == 0)) stop("Constant price series in stage")

  #1. scale times and pre-estimate
  #对时间进行标准化，用样条函数对每列进行拟合，得到X^
  #画图展示，图中点为原始数据，曲线为拟合得到的X^
  times = as.numeric(scaleX(times,u = 0,v= 1))
  #smooth estimate data using splines
  fit <- lapply(1:p, function (xi)
    smooth.spline(times, as.numeric(data[,xi])))
  x_smooth <- sapply(1:p, function(xi) predict(fit[[xi]], x = times)$y)
  colnames(x_smooth) <- colnames(data)
  rownames(x_smooth) <- rownames(data)

  #2. calculate Matrix of integral values of basis functions
  # 计算基函数数值矩阵以及基函数积分矩阵，x为x_smooth的某列，M是设定基函数的数量
  get_basis <- function(x, M, times, name = NULL, basis_type = "lop") {
    x <- as.numeric(x)
    # 1. Generate spline (or polynomial) basis
    # x_basis 的形状是 (n_timepoints) × M，第 j 列是基函数fai_j在x上的数值
    x_basis <- switch(
      basis_type,
      "bs" = bs(x, df = M),
      "ns" = ns(x, df = M),
      "poly" = poly(x, degree = M, raw = FALSE),
      "lop" = Reduce(cbind,
                     polynomial.values(polynomials=legendre.polynomials(n = M),
                                       x = x))[,2:(M+1)],
      stop("Unsupported basis type. Use 'bs', 'ns', 'poly', 'lop'.")
    )

    # 2. Create spline functions for each basis column
    # fs 始终是一个列表，里面装着基函数对应的插值函数
    if(M>=2){
      fs <- apply(x_basis, 2, splinefun, x = times)
    } else{
      fs <- list(splinefun(times,x_basis))
    }

    # 3. Define ODE system for integrating basis
    mod <- function(Time, State, Pars, basis) {
      with(as.list(c(State, Pars)), {
        dy <- basis(Time)
        return(list(dy))
      })
    }

    # 4. Numerically integrate each basis function over time
    # 计算基函数的积分值，得到基函数积分值矩阵
    Pars <- NULL
    State <- rep(0, length(fs))
    phi <- sapply(seq_along(fs), function(i)
      ode(
        func = mod, y = State[[i]], parms = Pars,
        basis = fs[[i]], times = times
      )[, 2]
    )

    # 5. Name the basis columns
    # 设置基函数积分值矩阵的列名
    if (is.null(name)) {
      colnames(phi) <- paste0("basis", 1:M)
    } else {
      colnames(phi) <- paste0(name, "_basis", 1:M)
    }

    return(phi)
  }

  # PHI：维度 = (时间点数 × (p×M))，把所有基函数积分值矩阵整合起来
  PHI <- Reduce(cbind, lapply(1:p, function(xi) {
    get_basis(x = x_smooth[, xi],
              M = M,
              times = times,
              name = colnames(data)[xi],
              basis_type = basis_type)
  }))

  # add phi0(time) and normalize phi
  # 就是把时间向量作为 第一列 拼接到基函数矩阵前面
  PHI_scaled = scale(cbind(times,PHI))

  #3, 高维组回归
  # Construct the group
  # 下面代码得到一个长度为 (p*p*M + p) 的向量 group，指明每个回归系数属于哪个组
  group_size <- M
  total_groups <- p * p # 每个基因对每个基因的影响算一个组

  # Generate group labels for each element
  # group = 1 1 1 2 2 2 3 3 3 4 4 4
  group <- rep(seq_len(total_groups), each = group_size)

  # we define phi0 belong to j-th group，截距项的组
  group0 = seq(1,total_groups, p)

  # add group0 to group
  group = sort(c(group0,group))

  # construct the final diagonal matrix
  # 把矩阵复制p次后放入对角阵中，维度 = (n_timepoints * p) × (p * (p * M + 1))
  X <- as.matrix(bdiag(rep(list(PHI_scaled), p)))

  # construct Y
  # 4. 转换为数值矩阵（最简单直接的方法）
  data_numeric <- apply(data, 2, as.numeric)
  # 5. 恢复行名和列名
  rownames(data_numeric) <- rownames(data)
  colnames(data_numeric) <- colnames(data)
  y_scaled <- scale(data_numeric) # 原始测量数据标准化
  Y <- matrix(as.vector(y_scaled), ncol = 1) # 将矩阵拉成一列

  check_beta_zero <- function(beta_scaled, phi0_pos, p, M) {
    # 去掉截距位置，剩下 basis 系数
    basis_coefs <- beta_scaled[-phi0_pos]
    # reshape 成 (p*M) x p，每列对应一个基因
    basis_matrix <- matrix(basis_coefs, nrow = p * M, ncol = p)
    # 任意一列全为零即判定失败
    any_col_all_zero <- any(apply(basis_matrix, 2, function(col) all(abs(col) < 1e-10)))
    return(any_col_all_zero)
  }
  # 计算 phi0_pos
  group_counts          <- table(group)
  max_freq              <- max(group_counts)
  most_frequent_groups  <- as.numeric(names(group_counts[group_counts == max_freq]))
  phi0_pos              <- vapply(most_frequent_groups,
                                  function(g) which(group == g)[1], integer(1))
  # ============================================================
  # 初始化标志
  # ============================================================
  use_adsiht          <- FALSE
  use_sgl             <- FALSE
  use_grouplasso      <- FALSE
  use_grouplasso_relaxed <- FALSE
  final_method        <- "未完成"

  # ------ 第一层：ADSIHT ------
  tryCatch({
    res <- ADSIHT(x = X, y = Y, group = group)

    if (!is.null(res$beta) && ncol(res$beta) > 0) {
      best_idx     <- which.min(res[["ic"]])
      beta_scaled  <- res$beta[, best_idx]
      beta0_scaled <- res$intercept[best_idx]
      lambda       <- res$lambda[best_idx]

      if (check_beta_zero(beta_scaled, phi0_pos, p, M)) {
        warning("ADSIHT结果全为零，改用Sparse Group Lasso")
      } else {
        use_adsiht   <- TRUE
        final_method <- "ADSIHT"
      }
    } else {
      warning("ADSIHT结果无效，改用Sparse Group Lasso")
    }

  }, error = function(e) {
    warning("ADSIHT失败：", e$message)
  })

  # ------ 第二层：Sparse Group Lasso ------
  if (!use_adsiht) {
    tryCatch({
      group_int <- as.integer(as.factor(group))
      # 构造 SGL 需要的 data list
      sgl_data <- list(x = X, y = as.vector(Y))
      fit_sgl  <- SGL(data = sgl_data, index = group_int,
                      type = "linear", alpha = 0.7,
                      standardize = FALSE) # 已经 scale 过了

      # 用 BIC 选 lambda：BIC = n*log(RSS/n) + log(n)*df
      n_obs    <- length(Y)
      bic_sgl  <- sapply(seq_len(ncol(fit_sgl$beta)), function(k) {
        beta_k  <- fit_sgl$beta[, k]
        resid_k <- Y - fit_sgl$beta0[k] - X %*% beta_k
        rss_k   <- sum(resid_k^2)
        df_k    <- sum(abs(beta_k) > 1e-10)
        n_obs * log(rss_k / n_obs) + log(n_obs) * df_k
      })
      best_idx     <- which.min(bic_sgl)
      beta_scaled  <- fit_sgl$beta[, best_idx]
      beta0_scaled <- fit_sgl$beta0[best_idx]
      lambda       <- fit_sgl$lambda[best_idx]

      if (check_beta_zero(beta_scaled, phi0_pos, p, M)) {
        warning("Sparse Group Lasso结果全为零，改用Group Lasso")
      } else {
        use_sgl      <- TRUE
        final_method <- "Sparse Group Lasso"
      }

    }, error = function(e) {
      warning("Sparse Group Lasso失败：", e$message)
    })
  }

  # ------ 第三层：Group Lasso ------
  if (!use_adsiht && !use_sgl) {
    tryCatch({
      group_int <- as.integer(as.factor(group))
      fit_gl    <- grpreg(X, Y, group = group_int, penalty = "grLasso")
      bic_vals  <- BIC(fit_gl)
      best_idx  <- which.min(bic_vals)

      beta_all     <- coef(fit_gl)
      beta0_scaled <- beta_all[1, best_idx]
      beta_scaled  <- beta_all[-1, best_idx]
      lambda       <- fit_gl$lambda[best_idx]

      if (check_beta_zero(beta_scaled, phi0_pos, p, M)) {
        warning("Group Lasso结果全为零，尝试宽松lambda")

        # 宽松 lambda
        relaxed_idx  <- max(1, best_idx - 5)
        beta0_scaled <- beta_all[1, relaxed_idx]
        beta_scaled  <- beta_all[-1, relaxed_idx]
        lambda       <- fit_gl$lambda[relaxed_idx]

        if (!check_beta_zero(beta_scaled, phi0_pos, p, M)) {
          use_grouplasso_relaxed <- TRUE
          final_method           <- "Group Lasso（宽松lambda）"
        } else {
          warning("宽松lambda仍全为零，进入Ridge兜底")
        }
      } else {
        use_grouplasso <- TRUE
        final_method   <- "Group Lasso"
      }

    }, error = function(e) {
      warning("Group Lasso失败：", e$message)
    })
  }

  # ------ 第四层：Ridge 兜底 ------
  if (!use_adsiht && !use_sgl && !use_grouplasso && !use_grouplasso_relaxed) {
    tryCatch({
      n_obs   <- nrow(X)
      n_folds <- min(10, max(3, n_obs))

      fit_ridge <- cv.glmnet(X, Y,
                             alpha       = 0,
                             nfolds      = n_folds,
                             standardize = FALSE)

      ridge_coef   <- as.vector(coef(fit_ridge, s = "lambda.min"))
      beta0_scaled <- ridge_coef[1]
      beta_scaled  <- ridge_coef[-1]
      lambda       <- fit_ridge$lambda.min
      final_method <- "Ridge兜底"

      cat("  [Ridge兜底] lambda =", round(lambda, 6),
          "，非零系数数 =", sum(abs(beta_scaled) > 1e-10), "\n")

    }, error = function(e) {
      # cv.glmnet 本身失败（极少见），用固定 lambda 的单次 Ridge
      warning("cv.glmnet失败，使用固定lambda Ridge：", e$message)

      fit_ridge_fixed <- glmnet(X, Y,
                                alpha       = 0,
                                lambda      = 0.1,   # 经验值，可调
                                standardize = FALSE)

      ridge_coef   <- as.vector(coef(fit_ridge_fixed))
      beta0_scaled <<- ridge_coef[1]
      beta_scaled  <<- ridge_coef[-1]
      lambda       <<- 0.1
      final_method <<- "Ridge兜底（固定lambda）"
    })
  }

  cat("最终使用方法：", final_method, "\n")

  get_B_est <- function(beta,beta0,x_scaled,y_scaled,phi0_pos) {
    beta_est <- matrix(beta[-phi0_pos], nrow = p * M, ncol = p)
    # 完整的回归系数矩阵(标准尺度下），每列对应一个基因的回归方程
    beta_est <- rbind(beta[phi0_pos],beta_est)

    sY <- attr(y_scaled, "scaled:scale")
    mY <- attr(y_scaled, "scaled:center")
    sX <- attr(x_scaled, "scaled:scale")
    mX <- attr(x_scaled, "scaled:center")

    BETA <- lapply(1:p, function(xi) {
      beta_orig <- beta_est[, xi] * (sY[xi] / sX)
      return(beta_orig)
    })
    BETA0 <- lapply(1:p, function(xi) {
      orig_int <- beta0 * sY[xi] + mY[xi] - sum(BETA[[xi]] * mX)
      return(orig_int)
    })
    B_est = t(cbind(unlist(BETA0),t(Reduce(cbind,BETA))))
    rownames(B_est)[1:2] = c("xj_0","thetaj_0")
    # B_est:还原到原始数据尺度下的回归系数估计矩阵。
    return(B_est)
  }

  B_est <- get_B_est(beta_scaled,beta0_scaled,PHI_scaled,y_scaled,phi0_pos)
  x_basis_est <- cbind(1,times,PHI)

  #计算邻接矩阵adj，p*p，其中值代表i个基因是否影响j个基因
  get_adj <- function(B_est, group) {
    #acquire adj matrix of the data
    p = ncol(B_est)
    adj <- matrix(0, nrow = p, ncol = p)

    B_est2 = B_est[-c(1:2),] # 移除截距项和时间项

    # 对于每个目标基因 j
    for (j in 1:p) {
      # 获取影响基因 j 的所有系数
      start_idx <- (j-1) * M + 1
      end_idx <- j * M

      # 对于每个可能的源基因 i
      for (i in 1:p) {
        # 获取基因 i 对基因 j 的 M 个基函数系数
        coef_idx <- (i-1) * M + 1:M
        coefs <- B_est2[coef_idx, j]

        # 如果这些系数不全为零，则存在从 i 到 j 的边
        if (any(coefs != 0, na.rm = TRUE)) {
          adj[i, j] <- 1
        }
      }
    }

    colnames(adj) = colnames(B_est)
    rownames(adj) = colnames(B_est)
    return(adj)
  }
  colnames(B_est) <- colnames(data)
  adj = get_adj(B_est, group)

  #计算影响权重矩阵
  get_w <- function(xi,x_basis_est = x_basis_est, B_est = B_est){
    p = ncol(data)
    n = nrow(data)
    tmpx = x_basis_est[,-c(1:2)]
    groups <- split(1:ncol(tmpx), rep(1:p,each = M))
    idx = split(group, cut(seq_along(group), breaks = p, labels = FALSE))
    names(groups) = colnames(data)

    for (i in 1:p) {
      idx[[i]] = idx[[i]] - p*(i-1)
    }
    B_est2 = B_est[-c(1:2),]

    w_matrix = sapply(groups, function(idx) {
      rowSums(tmpx[, idx] * rep(B_est2[idx, xi], each = nrow(tmpx)))
    })
    w_matrix = data.frame(w_matrix,check.names = F)

  }
  w_matrix = lapply(1:p,function(xi) get_w(xi, x_basis_est, B_est))

  time_weights <- lapply(1:n, function(t) {
    # 为每个时间点构建权重矩阵
    W <- sapply(1:p, function(j) {
      influences <- unlist(w_matrix[[j]][t, ])
      abs_inf <- abs(influences)
      if(sum(abs_inf) > 0) abs_inf / sum(abs_inf) else rep(0, length(abs_inf))
    })
    colnames(W) <- rownames(W) <- colnames(w_matrix[[1]])
    return(W)
  })

  #计算收益率
  calculated_returns <- matrix(NA, nrow = n, ncol = p)

  for(t in 1:n) {
    return_t <- as.numeric(return_data[t, ])
    W_t <- time_weights[[t]]
    calculated_returns[t, ] <- return_t %*% W_t
  }
  colnames(calculated_returns) <- colnames(return_data)
  rownames(calculated_returns) <- rownames(return_data)

  #计算效应分解矩阵，p个list，每个list有p个double，分别代表第i个基因对第j个基因表达量的贡献
  #长度代表时间点，这些double相加代表该基因的表达量
  get_effect <- function(xi,x_basis_est=x_basis_est, B_est = B_est){
    p = ncol(data)
    tmpx = x_basis_est[,-c(1:2)]
    groups <- split(1:ncol(tmpx), rep(1:p,each = M))
    idx = split(group, cut(seq_along(group), breaks = p, labels = FALSE))
    names(groups) = colnames(data)

    for (i in 1:p) {
      idx[[i]] = idx[[i]] - p*(i-1)
    }
    B_est2 = B_est[-c(1:2),]

    effect = sapply(groups, function(idx) {
      rowSums(tmpx[, idx] * rep(B_est2[idx, xi], each = nrow(tmpx)))
    })
    effect = data.frame(effect,check.names = F)
    names(effect)[xi] = 'independent'

    effect$independent = effect$independent+B_est[1,xi]+B_est[2,xi]*x_basis_est[,2]

    names(effect)[xi] = colnames(data)[xi]
    return(effect)
  }
  effects = lapply(1:p,function(xi) get_effect(xi, x_basis_est, B_est))

  return(list(
    adj          = adj,
    B_est        = B_est,
    effects      = effects,
    weight_matrix = time_weights,
    weight_matrix_semantics = "legacy_absolute_including_self; not final network",
    estimation = list(method = final_method, lambda = lambda, seed = seed,
                      M = M, basis_type = basis_type, R = as.character(getRversion())),
    calculated_returns = calculated_returns
  ))
}

estimate_stages <- function(prices, returns, M = 3L, basis_type = 'poly',
                            seed = 20260922L, short_stage = 'error') {
  returns <- nw_align_returns(prices, returns)
  masks <- is.finite(prices)
  change <- c(TRUE, vapply(seq_len(nrow(prices) - 1L) + 1L, function(i)
    !identical(masks[i, ], masks[i - 1L, ]), logical(1)))
  starts <- which(change)
  ends <- c(starts[-1L] - 1L, nrow(prices))
  results <- list(); audit <- list(); stocks <- character()
  for (s in seq_along(starts)) {
    rows <- seq.int(starts[s], ends[s])
    active <- colnames(prices)[masks[starts[s], ]]
    stocks <- c(intersect(stocks, active), setdiff(active, stocks))
    ok <- length(stocks) >= 2L && length(rows) >= max(4L, M + 1L)
    audit[[s]] <- data.frame(stage = s, start_date = rownames(prices)[starts[s]],
      end_date = rownames(prices)[ends[s]], n_days = length(rows),
      n_stocks = length(stocks), status = if (ok) 'estimated' else 'skipped_short_stage')
    if (!ok) {
      if (short_stage != 'skip') stop('Stage ', s,
        ' has fewer than 2 stocks or too few observations; use --short-stage skip explicitly to audit omissions')
      next
    }
    stage_prices <- prices[rows, stocks, drop = FALSE]
    stage_returns <- returns[rows, stocks, drop = FALSE]
    fit <- MTODEs(stage_prices, stage_returns, time = rownames(stage_prices),
                  M = M, basis_type = basis_type, seed = seed + s - 1L)
    results[[length(results) + 1L]] <- list(stage = s,
      start_date = rownames(prices)[starts[s]], end_date = rownames(prices)[ends[s]],
      dates = rownames(stage_prices), stocks = stocks, result = fit)
  }
  if (!length(results)) stop('No estimable stages')
  list(stages = results, audit = do.call(rbind, audit))
}

parse_estimate_args <- function(args) {
  cfg <- list(mode = 'rebuild', input_dirs = character(), input_rds = character(),
    calendar = NULL, prices = NULL, returns = NULL, output = NULL, stage_output = NULL,
    encoding = 'GB18030', seed = 20260922L, M = 3L, basis_type = 'poly',
    alignment = 'strict', zero_tol = 0, short_stage = 'error', overwrite = FALSE,
    self_test = FALSE, help = FALSE, pattern = '^results_.+\\.rds$')
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key %in% c('--overwrite', '--self-test', '--help')) {
      cfg[[gsub('-', '_', substring(key, 3L))]] <- TRUE; i <- i + 1L; next
    }
    if (i == length(args)) stop('Missing value: ', key)
    value <- args[[i + 1L]]
    if (key == '--input-dir') cfg$input_dirs <- c(cfg$input_dirs, value)
    else if (key == '--input-rds') cfg$input_rds <- c(cfg$input_rds, value)
    else {
      field <- gsub('-', '_', substring(key, 3L))
      if (!field %in% names(cfg) || field %in% c('input_dirs', 'input_rds')) stop('Unknown option: ', key)
      cfg[[field]] <- value
    }
    i <- i + 2L
  }
  cfg$M <- as.integer(cfg$M); cfg$seed <- as.integer(cfg$seed); cfg$zero_tol <- as.numeric(cfg$zero_tol)
  if (!cfg$mode %in% c('estimate', 'rebuild')) stop('--mode must be estimate or rebuild')
  if (!cfg$alignment %in% c('strict', 'head', 'tail')) stop('Invalid --alignment')
  if (!cfg$short_stage %in% c('error', 'skip')) stop('Invalid --short-stage')
  if (!cfg$basis_type %in% c('poly', 'bs', 'ns', 'lop')) stop('Invalid --basis-type')
  if (is.na(cfg$M) || cfg$M < 2L || is.na(cfg$seed) || cfg$seed < 0L ||
      !is.finite(cfg$zero_tol) || cfg$zero_tol < 0) stop('Invalid numeric parameter')
  cfg
}

estimate_usage <- function() {
  cat(paste0(
    'Rebuild saved effects without training (default mode):\n',
    '  Rscript R/network/estimate_stage_networks.R --mode rebuild ',
    '--input-dir STAGES --calendar dates.csv --output daily.rds\n',
    '  --input-rds FILE may be repeated instead of --input-dir\n',
    'Train only when explicitly requested:\n',
    '  Rscript R/network/estimate_stage_networks.R --mode estimate ',
    '--prices prices.csv --returns returns.csv --stage-output results_layer.rds ',
    '--output daily.rds\n',
    'Options: --encoding GB18030 --seed 20260922 --M 3 --basis-type poly\n',
    '         --alignment strict|head|tail --zero-tol 0 --short-stage error|skip\n',
    '         --overwrite --self-test --help\n',
    'strict refuses ambiguous historical dates; head/tail require explicit selection.\n'))
}

# Numerical reconstruction rules copied from the approved legacy effects rebuilder.
`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

effect_stock_names <- function(effects) {
  if (!is.list(effects) || !length(effects)) stop("effects 不是非空列表")
  first <- effects[[1L]]
  if (is.null(dim(first))) stop("effects[[1]] 不是二维对象")
  stocks <- colnames(first)
  if (is.null(stocks) || !length(stocks)) stop("effects[[1]] 缺少股票列名")
  if (length(effects) != length(stocks)) {
    stop(sprintf("effects 长度(%d)与股票列数(%d)不一致",
                 length(effects), length(stocks)))
  }
  nw_check_names(stocks, "Effects stocks")
  for (x in effects) {
    if (!identical(colnames(x), stocks)) stop("Effects stock columns or order differ")
  }
  if (!is.null(names(effects)) && !identical(names(effects), stocks))
    stop("Named effects recipients must follow source column order")
  stocks
}

effect_time_count <- function(effects) {
  counts <- vapply(effects, nrow, integer(1))
  if (anyNA(counts) || any(counts <= 0L)) stop("effects 中存在空对象")
  if (length(unique(counts)) != 1L) {
    stop("同一阶段各接收股票的 effect 时间长度不一致: ",
         paste(unique(counts), collapse = ", "))
  }
  counts[[1L]]
}

extract_raw_weight <- function(effects, time_index, zero_tol = 0) {
  stocks <- effect_stock_names(effects)
  n_time <- effect_time_count(effects)
  if (time_index < 1L || time_index > n_time) stop("time_index 越界")

  # E[j, i] = i 对 j 的效应；W[i, j] = i -> j，所以 W = t(E)。
  E <- t(vapply(
    effects,
    function(x) as.numeric(x[time_index, stocks, drop = TRUE]),
    numeric(length(stocks))
  ))
  dimnames(E) <- list(stocks, stocks)
  W <- t(E)
  dimnames(W) <- list(stocks, stocks)

  diag(W) <- 0
  W[!is.finite(W)] <- 0
  W[abs(W) < zero_tol] <- 0
  W
}

normalize_signed_columns <- function(W) {
  scale <- colSums(abs(W))
  nonzero <- is.finite(scale) & scale > 0
  ans <- matrix(0, nrow(W), ncol(W), dimnames = dimnames(W))
  if (any(nonzero)) {
    ans[, nonzero] <- sweep(W[, nonzero, drop = FALSE], 2L,
                            scale[nonzero], "/")
  }
  ans
}

stage_dates <- function(stage, trading_days, n_time, alignment = "strict") {
  start_date <- nw_date(stage$start_date); end_date <- nw_date(stage$end_date)
  if (length(start_date) != 1L || length(end_date) != 1L ||
      is.na(start_date) || is.na(end_date) || start_date > end_date)
    stop("Invalid stage start_date/end_date")
  dates <- trading_days[trading_days >= start_date & trading_days <= end_date]
  if (!is.null(stage$dates)) {
    explicit <- nw_date(stage$dates)
    if (length(explicit) != n_time || anyNA(explicit) || any(diff(explicit) <= 0) ||
        any(explicit < start_date | explicit > end_date) ||
        !all(explicit %in% trading_days)) stop("Invalid explicit stage dates")
    if (alignment == "strict" && !identical(explicit, dates))
      stop("Explicit stage dates do not cover the calendar stage")
    return(explicit)
  }
  if (length(dates) == n_time) return(dates)
  msg <- sprintf("Stage %s~%s: calendar=%d days, effects=%d rows",
                 start_date, end_date, length(dates), n_time)
  if (alignment == "strict" || length(dates) < n_time) stop(msg)
  warning(msg, "; explicit alignment=", alignment, call. = FALSE)
  if (alignment == "head") head(dates, n_time) else tail(dates, n_time)
}

old_weight_max_difference <- function(effects, old_weights, zero_tol) {
  if (is.null(old_weights) || !length(old_weights)) return(NA_real_)
  n_time <- effect_time_count(effects)
  candidates <- unique(pmax(1L, pmin(n_time,
                                     round(seq(1, n_time, length.out = 3L)))))
  candidates <- candidates[candidates <= length(old_weights)]
  if (!length(candidates)) return(NA_real_)

  differences <- vapply(candidates, function(k) {
    rebuilt <- abs(normalize_signed_columns(
      extract_raw_weight(effects, k, zero_tol)
    ))
    old <- as.matrix(old_weights[[k]])
    common <- Reduce(intersect, list(rownames(rebuilt), colnames(rebuilt),
                                     rownames(old), colnames(old)))
    if (!length(common)) return(NA_real_)
    # 旧构造先把自身效应纳入列归一化，网络分析时才删除对角线。
    # 为与“先删除自身效应、再归一化”的有效网络口径一致，需要重新归一化。
    old <- old[common, common, drop = FALSE]
    diag(old) <- 0
    old <- normalize_signed_columns(old)
    max(abs(rebuilt[common, common, drop = FALSE] -
              old), na.rm = TRUE)
  }, numeric(1))
  if (all(is.na(differences))) NA_real_ else max(differences, na.rm = TRUE)
}

add_matrix <- function(target, source) {
  if (is.null(target)) return(source)
  stocks <- union(rownames(target), rownames(source))
  ans <- matrix(0, length(stocks), length(stocks),
                dimnames = list(stocks, stocks))
  ans[rownames(target), colnames(target)] <-
    ans[rownames(target), colnames(target), drop = FALSE] + target
  ans[rownames(source), colnames(source)] <-
    ans[rownames(source), colnames(source), drop = FALSE] + source
  diag(ans) <- 0
  ans
}

process_rds_file <- function(path, trading_days, zero_tol, alignment,
                             signed_by_date, raw_by_date = NULL) {
  cat(sprintf("读取 %s\n", path))
  stages <- readRDS(path)
  if (!is.list(stages)) stop("RDS 顶层不是阶段列表: ", path)

  validation <- list()
  seen_dates <- character()
  for (s in seq_along(stages)) {
    stage <- stages[[s]]
    effects <- stage$result$effects %||% stage$effects
    if (is.null(effects)) {
      stop(sprintf("%s stage %d lacks effects", basename(path), s))
    }

    effect_stock_names(effects)
    n_time <- effect_time_count(effects)
    dates <- stage_dates(stage, trading_days, n_time, alignment)
    if (length(intersect(seen_dates, as.character(dates))))
      stop("Overlapping stages within layer: ", path)
    seen_dates <- c(seen_dates, as.character(dates))
    old_weights <- stage$result$weight_matrix %||%
      stage$result$weightMatrix %||% stage$weight_matrix
    max_diff <- old_weight_max_difference(effects, old_weights, zero_tol)

    validation[[length(validation) + 1L]] <- data.frame(
      file = basename(path),
      stage = stage$stage %||% s,
      start_date = min(dates),
      end_date = max(dates),
      n_time = n_time,
      alignment = alignment,
      n_stocks = length(effects),
      old_weight_max_abs_diff = max_diff
    )

    for (k in seq_len(n_time)) {
      key <- as.character(dates[[k]])
      raw <- extract_raw_weight(effects, k, zero_tol)
      signed <- normalize_signed_columns(raw)

      # 各网络单独归一化后再相加，与旧的大网+子网合并尺度一致。
      signed_by_date[[key]] <- add_matrix(signed_by_date[[key]], signed)
      if (!is.null(raw_by_date)) {
        raw_by_date[[key]] <- add_matrix(raw_by_date[[key]], raw)
      }
    }
    cat(sprintf("  阶段%s: %s~%s，%d天，%d只股票，旧矩阵校验=%s\n",
                stage$stage %||% s, min(dates), max(dates), n_time,
                length(effects),
                ifelse(is.na(max_diff), "无旧矩阵", format(max_diff, digits = 4))))
  }

  list(signed = signed_by_date, raw = raw_by_date,
       validation = if (length(validation)) do.call(rbind, validation) else NULL)
}

effects_self_test <- function() {
  stocks <- c("A", "B", "C")
  # effects[[j]][t,i]；第1日：A->B=-2，C->B=1，B->C=4。
  effects <- lapply(stocks, function(j) {
    x <- matrix(0, 2, 3, dimnames = list(NULL, stocks))
    as.data.frame(x, check.names = FALSE)
  })
  effects[[2]][1, ] <- c(-2, 99, 1)
  effects[[3]][1, ] <- c(0, 4, 99)

  W <- extract_raw_weight(effects, 1L)
  stopifnot(W["A", "B"] == -2, W["C", "B"] == 1,
            W["B", "C"] == 4, all(diag(W) == 0))
  Wn <- normalize_signed_columns(W)
  stopifnot(abs(Wn["A", "B"] + 2 / 3) < 1e-12,
            abs(Wn["C", "B"] - 1 / 3) < 1e-12,
            abs(Wn["B", "C"] - 1) < 1e-12,
            all(colSums(abs(Wn))[colSums(abs(Wn)) > 0] == 1))

  # 验证“分网络归一化、合并、最终再归一化”。
  merged <- add_matrix(Wn, Wn)
  final <- normalize_signed_columns(merged)
  final_scale <- colSums(abs(final))
  stopifnot(all(abs(final_scale[final_scale > 0] - 1) < 1e-12))
  cat("内置测试通过：方向、符号、自效应剔除、分网络归一化和合并后归一化均正确。\n")
}

rebuild_layers <- function(files, days, alignment = 'strict', zero_tol = 0) {
  if (anyDuplicated(basename(files))) stop('Duplicate layer filenames')
  merged <- list(); checks <- list()
  for (p in sort(files)) {
    ans <- process_rds_file(p, days, zero_tol, alignment, merged)
    merged <- ans$signed
    checks[[length(checks) + 1L]] <- ans$validation
  }
  merged <- lapply(merged, normalize_signed_columns)
  merged <- merged[order(nw_date(names(merged)))]
  nw_validate_daily(merged)
  list(matrices = merged, audit = do.call(rbind, checks))
}

main <- function() {
  cfg <- parse_estimate_args(commandArgs(trailingOnly = TRUE))
  if (cfg$help) return(estimate_usage())
  if (cfg$self_test) return(effects_self_test())
  if (is.null(cfg$output)) stop('Supply --output for the final daily signed RDS')
  audit_path <- paste0(cfg$output, '.validation.csv')
  metadata_path <- paste0(cfg$output, '.metadata.rds')
  if (cfg$mode == 'rebuild') {
    if (any(!dir.exists(cfg$input_dirs))) stop('An --input-dir does not exist')
    files <- unique(c(cfg$input_rds, unlist(lapply(cfg$input_dirs, function(d)
      list.files(d, pattern = cfg$pattern, full.names = TRUE)))))
    if (!length(files) || any(!file.exists(files))) stop('Supply existing stage RDS inputs')
    nw_preflight(list(cfg$output, audit_path, metadata_path), c(files, cfg$calendar), cfg$overwrite)
    days <- nw_calendar(cfg$calendar, cfg$encoding)
  } else {
    if (is.null(cfg$prices) || is.null(cfg$returns) || is.null(cfg$stage_output))
      stop('estimate requires --prices, --returns, --stage-output')
    stage_audit_path <- paste0(cfg$stage_output, '.audit.csv')
    nw_preflight(list(cfg$output, cfg$stage_output, stage_audit_path, audit_path, metadata_path),
                 c(cfg$prices, cfg$returns), cfg$overwrite)
    prices <- nw_read_panel(cfg$prices, cfg$encoding)
    returns <- nw_read_panel(cfg$returns, cfg$encoding)
    fitted <- estimate_stages(prices, returns, cfg$M, cfg$basis_type, cfg$seed, cfg$short_stage)
    # Preserve legacy absolute diagnostics; derive the usable network from effects.
    for (s in seq_along(fitted$stages)) {
      eff <- fitted$stages[[s]]$result$effects
      signed <- lapply(seq_len(effect_time_count(eff)), function(k)
        normalize_signed_columns(extract_raw_weight(eff, k, cfg$zero_tol)))
      names(signed) <- fitted$stages[[s]]$dates
      fitted$stages[[s]]$result$signed_weight_matrix <- signed
    }
    nw_save_rds(fitted$stages, cfg$stage_output)
    write.csv(fitted$audit, stage_audit_path, row.names = FALSE, fileEncoding = 'UTF-8')
    files <- cfg$stage_output
    days <- nw_date(rownames(prices))
  }
  ans <- rebuild_layers(files, days, cfg$alignment, cfg$zero_tol)
  nw_save_rds(ans$matrices, cfg$output)
  write.csv(ans$audit, audit_path, row.names = FALSE, fileEncoding = 'UTF-8')
  nw_save_rds(list(mode = cfg$mode, inputs = basename(files),
    input_md5 = unname(tools::md5sum(files)), alignment = cfg$alignment,
    zero_tol = cfg$zero_tol, R = as.character(getRversion()),
    convention = 'W[i,j]=i->j; zero diagonal; signed column L1 per layer and after sum'), metadata_path)
  cat('Saved', length(ans$matrices), 'daily signed matrices:', cfg$output, '\n')
}

if (sys.nframe() == 0L) main()
