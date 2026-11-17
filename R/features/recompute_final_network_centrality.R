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

suppressPackageStartupMessages(library(igraph))
measure <- function(W, target_date) {
  stocks <- rownames(W)
  ans <- data.table(
    Date = as.character(target_date), stock = stocks,
    net_betweenness = NA_real_, net_harmonic_closeness = NA_real_,
    net_eigenvector_centrality = NA_real_, net_pagerank = NA_real_,
    net_local_clustering = NA_real_
  )
  A <- abs(W)
  diag(A) <- 0
  A[!is.finite(A)] <- 0
  active <- rowSums(A != 0) + colSums(A != 0) > 0
  if (sum(active) < 5L) return(ans)
  A <- A[active, active, drop = FALSE]
  g <- graph_from_adjacency_matrix(A, mode = "directed", weighted = TRUE, diag = FALSE)
  n <- vcount(g)
  weight <- E(g)$weight
  safe <- function(expr) tryCatch(suppressWarnings(expr), error = function(e) rep(NA_real_, n))
  bt <- safe(betweenness(g, cutoff = 3, directed = TRUE, weights = 1 / weight))
  hc <- safe(harmonic_centrality(g, mode = "in"))
  gu <- as_undirected(g, mode = "collapse", edge.attr.comb = "sum")
  ev <- safe(eigen_centrality(gu, weights = E(gu)$weight)$vector)
  pr <- safe(page_rank(g, weights = weight)$vector)
  cc <- safe(transitivity(g, type = "local", isolates = "zero"))
  idx <- match(V(g)$name, stocks)
  ans$net_betweenness[idx] <- bt / ((n - 1) * (n - 2))
  ans$net_harmonic_closeness[idx] <- hc / (n - 1)
  ans$net_eigenvector_centrality[idx] <- ev
  ans$net_pagerank[idx] <- pr
  ans$net_local_clustering[idx] <- cc
  ans
}


compute_centrality <- function(matrices) {
  feature_validate_matrices(matrices)
  if (length(matrices)<2L) return(empty_features(CENTRALITY_FEATURES))
  dates <- as.Date(names(matrices))
  rows <- lapply(seq_len(length(matrices)-1L), function(i) measure(matrices[[i]], dates[[i+1L]]))
  result <- rbindlist(rows); result[, Date:=as.IDate(Date)]; check_keys(result)
  result
}
main <- function() {
  cfg <- feature_args(list(input=NULL,output=NULL,overwrite=FALSE),c("input","output"))
  nw_preflight(list(cfg$output),cfg$input,cfg$overwrite)
  feature_write_csv(compute_centrality(readRDS(cfg$input)),cfg$output)
}
if (sys.nframe()==0L) main()
