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

safe_ratio <- function(x, y) {
  ans <- rep(NA_real_, length(x))
  ok <- is.finite(y) & y > 0
  ans[ok] <- x[ok] / y[ok]
  ans
}

distribution_metrics <- function(Wabs, margin) {
  totals <- if (margin == 1L) rowSums(Wabs) else colSums(Wabs)
  P <- if (margin == 1L) {
    sweep(Wabs, 1L, ifelse(totals > 0, totals, 1), "/")
  } else {
    sweep(Wabs, 2L, ifelse(totals > 0, totals, 1), "/")
  }
  hhi <- if (margin == 1L) rowSums(P^2) else colSums(P^2)
  entropy <- if (margin == 1L) {
    rowSums(ifelse(P > 0, -P * log(P), 0))
  } else {
    colSums(ifelse(P > 0, -P * log(P), 0))
  }
  max_share <- if (margin == 1L) apply(P, 1L, max) else apply(P, 2L, max)
  top3_share <- if (margin == 1L) {
    apply(P, 1L, function(x) sum(sort(x, decreasing = TRUE)[seq_len(min(3L, length(x)))]))
  } else {
    apply(P, 2L, function(x) sum(sort(x, decreasing = TRUE)[seq_len(min(3L, length(x)))]))
  }
  hhi[totals == 0] <- entropy[totals == 0] <- NA_real_
  max_share[totals == 0] <- top3_share[totals == 0] <- NA_real_
  data.table(hhi = hhi, effective_n = safe_ratio(rep(1, length(hhi)), hhi),
             entropy = entropy, max_share = max_share, top3_share = top3_share)
}

empty_structural <- function(n) {
  list(kcore = rep(0, n), hub = rep(0, n), authority = rep(0, n),
       constraint = rep(NA_real_, n), community_size = rep(1L, n),
       within_strength = rep(0, n), between_strength = rep(0, n),
       cross_share = rep(NA_real_, n), participation = rep(NA_real_, n))
}

structural_metrics <- function(Wabs) {
  n <- nrow(Wabs)
  if (!any(Wabs > 0)) return(empty_structural(n))

  g <- igraph::graph_from_adjacency_matrix(
    Wabs, mode = "directed", weighted = TRUE, diag = FALSE
  )
  gu <- igraph::as_undirected(g, mode = "collapse",
                              edge.attr.comb = list(weight = "sum", "ignore"))
  kcore <- igraph::coreness(gu)
  hits <- tryCatch(igraph::hits_scores(g, weights = igraph::E(g)$weight),
                   error = function(e) NULL)
  hub <- if (is.null(hits)) rep(NA_real_, n) else hits$hub
  authority <- if (is.null(hits)) rep(NA_real_, n) else hits$authority
  constraint <- tryCatch(
    igraph::constraint(gu, weights = igraph::E(gu)$weight),
    error = function(e) rep(NA_real_, n)
  )

  membership <- tryCatch({
    igraph::membership(igraph::cluster_leiden(
      gu, objective_function = "modularity", weights = igraph::E(gu)$weight
    ))
  }, error = function(e) seq_len(n))

  comm_ids <- sort(unique(membership))
  K <- matrix(0, nrow = n, ncol = length(comm_ids))
  for (z in seq_along(comm_ids)) {
    in_comm <- membership == comm_ids[[z]]
    K[, z] <- rowSums(Wabs[, in_comm, drop = FALSE]) +
      colSums(Wabs[in_comm, , drop = FALSE])
  }
  total <- rowSums(K)
  own_idx <- match(membership, comm_ids)
  within <- K[cbind(seq_len(n), own_idx)]
  between <- total - within
  participation <- 1 - rowSums((K / ifelse(total > 0, total, 1))^2)
  participation[total == 0] <- NA_real_

  list(
    kcore = as.numeric(kcore), hub = as.numeric(hub),
    authority = as.numeric(authority), constraint = as.numeric(constraint),
    community_size = as.integer(table(membership)[as.character(membership)]),
    within_strength = within, between_strength = between,
    cross_share = safe_ratio(between, total), participation = participation
  )
}

compute_one_day <- function(W, date) {
  W <- as.matrix(W)
  if (is.null(rownames(W)) || !identical(rownames(W), colnames(W))) {
    stop("矩阵行列名缺失或顺序不一致: ", date)
  }
  W[!is.finite(W)] <- 0
  diag(W) <- 0
  stocks <- rownames(W)
  Wpos <- pmax(W, 0)
  Wneg <- pmax(-W, 0)
  Wabs <- abs(W)
  Apos <- Wpos > 0
  Aneg <- Wneg > 0

  in_pos <- colSums(Wpos); in_neg <- colSums(Wneg)
  out_pos <- rowSums(Wpos); out_neg <- rowSums(Wneg)
  gross_in <- in_pos + in_neg; gross_out <- out_pos + out_neg
  net_in <- in_pos - in_neg; net_out <- out_pos - out_neg
  in_dist <- distribution_metrics(Wabs, 2L)
  out_dist <- distribution_metrics(Wabs, 1L)
  st <- structural_metrics(Wabs)

  data.table(
    Date = as.IDate(date), stock = stocks,
    net_new_deg_in_pos = colSums(Apos),
    net_new_deg_in_neg = colSums(Aneg),
    net_new_deg_out_pos = rowSums(Apos),
    net_new_deg_out_neg = rowSums(Aneg),
    net_new_str_in_pos = in_pos, net_new_str_in_neg = in_neg,
    net_new_str_out_pos = out_pos, net_new_str_out_neg = out_neg,
    net_new_str_in_gross = gross_in, net_new_str_out_gross = gross_out,
    net_new_str_in_net = net_in, net_new_str_out_net = net_out,
    net_new_sign_ratio_in = safe_ratio(net_in, gross_in),
    net_new_sign_ratio_out = safe_ratio(net_out, gross_out),
    net_new_negative_share_in = safe_ratio(in_neg, gross_in),
    net_new_negative_share_out = safe_ratio(out_neg, gross_out),
    net_new_weight_hhi_in = in_dist$hhi,
    net_new_effective_neighbors_in = in_dist$effective_n,
    net_new_weight_entropy_in = in_dist$entropy,
    net_new_max_weight_share_in = in_dist$max_share,
    net_new_top3_weight_share_in = in_dist$top3_share,
    net_new_weight_hhi_out = out_dist$hhi,
    net_new_effective_neighbors_out = out_dist$effective_n,
    net_new_weight_entropy_out = out_dist$entropy,
    net_new_max_weight_share_out = out_dist$max_share,
    net_new_top3_weight_share_out = out_dist$top3_share,
    net_new_kcore = st$kcore,
    net_new_hits_hub = st$hub,
    net_new_hits_authority = st$authority,
    net_new_constraint = st$constraint,
    net_new_community_size = st$community_size,
    net_new_community_within_strength = st$within_strength,
    net_new_community_between_strength = st$between_strength,
    net_new_community_cross_share = st$cross_share,
    net_new_participation = st$participation
  )
}

edge_dynamics <- function(W, previous, date) {
  stocks <- rownames(W)
  old <- matrix(0, length(stocks), length(stocks), dimnames = list(stocks, stocks))
  if (!is.null(previous)) {
    common <- intersect(stocks, rownames(previous))
    old[common, common] <- previous[common, common, drop = FALSE]
  }
  nowA <- W != 0; oldA <- old != 0
  out_union <- rowSums(nowA | oldA); in_union <- colSums(nowA | oldA)
  data.table(
    Date = as.IDate(date), stock = stocks,
    net_new_neighbor_jaccard_out = safe_ratio(rowSums(nowA & oldA), out_union),
    net_new_edges_added_out = rowSums(nowA & !oldA),
    net_new_edges_removed_out = rowSums(!nowA & oldA),
    net_new_edge_turnover_out = safe_ratio(rowSums(xor(nowA, oldA)), out_union),
    net_new_weight_change_out = rowSums(abs(W - old)),
    net_new_neighbor_jaccard_in = safe_ratio(colSums(nowA & oldA), in_union),
    net_new_edges_added_in = colSums(nowA & !oldA),
    net_new_edges_removed_in = colSums(!nowA & oldA),
    net_new_edge_turnover_in = safe_ratio(colSums(xor(nowA, oldA)), in_union),
    net_new_weight_change_in = colSums(abs(W - old))
  )
}

add_dynamic_features <- function(DT) {
  setorder(DT, stock, Date)
  vars <- c("net_new_str_in_net", "net_new_str_out_net",
            "net_new_sign_ratio_in", "net_new_sign_ratio_out",
            "net_new_hits_hub", "net_new_hits_authority",
            "net_new_community_cross_share")
  for (v in vars) {
    DT[, paste0(v, "_chg1") := get(v) - shift(get(v), 1L), by = stock]
    DT[, paste0(v, "_chg5") := get(v) - shift(get(v), 5L), by = stock]
    DT[, paste0(v, "_mean5") := frollmean(get(v), 5L, na.rm = TRUE), by = stock]
    DT[, paste0(v, "_sd20") := frollapply(
      get(v), 20L, function(x) stats::sd(x, na.rm = TRUE), align = "right"
    ), by = stock]
  }
  rank_vars <- c("net_new_str_in_net", "net_new_str_out_net",
                 "net_new_hits_hub", "net_new_hits_authority",
                 "net_new_kcore", "net_new_community_cross_share")
  for (v in rank_vars) {
    DT[, paste0(v, "_cs_rank") := {
      n_ok <- sum(!is.na(get(v)))
      if (n_ok) frank(get(v), ties.method = "average", na.last = "keep") / n_ok
      else rep(NA_real_, .N)
    }, by = Date]
  }
  setorder(DT, Date, stock)
  DT
}


compute_network_metrics <- function(matrices, seed = 20260922L) {
  feature_validate_matrices(matrices)
  set.seed(seed)
  rows <- vector("list", length(matrices))
  previous <- NULL
  for (i in seq_along(matrices)) {
    date <- names(matrices)[[i]]; W <- matrices[[i]]
    base <- compute_one_day(W, date)
    dyn <- edge_dynamics(W, previous, date)
    rows[[i]] <- merge(base, dyn, by = c("Date", "stock"), all.x = TRUE, sort = FALSE)
    previous <- W
  }
  result <- add_dynamic_features(rbindlist(rows, use.names = TRUE, fill = TRUE))
  check_keys(result)
  actual <- paper_name(setdiff(names(result), c("Date", "stock")))
  if (!setequal(actual, BODY_FEATURES) || length(actual) != 79L) stop("Expected exactly 79 body features")
  list(direction = "row/source -> column/receiver", lagged = FALSE,
       seed = seed, rows = nrow(result), columns = ncol(result), data = result)
}

main <- function() {
  cfg <- feature_args(list(input=NULL, output=NULL, csv=NULL, seed="20260922", overwrite=FALSE),
                      c("input", "output"))
  nw_preflight(list(cfg$output, cfg$csv), cfg$input, cfg$overwrite)
  result <- compute_network_metrics(readRDS(cfg$input), feature_seed(cfg$seed))
  nw_save_rds(result, cfg$output)
  if (!is.null(cfg$csv)) feature_write_csv(result$data, cfg$csv)
}
if (sys.nframe() == 0L) main()
