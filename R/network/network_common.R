# Shared validation and I/O; sourcing this file never trains or writes data.
nw_date <- function(x) {
  suppressWarnings(as.Date(gsub('/', '-', trimws(as.character(x)), fixed = TRUE),
                           format = '%Y-%m-%d'))
}

nw_check_names <- function(x, label) {
  if (!length(x) || anyNA(x) || any(!nzchar(x)) || anyDuplicated(x))
    stop(label, ': names must be nonempty and unique')
  invisible(x)
}

nw_read_panel <- function(path, encoding = 'GB18030') {
  if (!file.exists(path)) stop('Input does not exist: ', path)
  dat <- withCallingHandlers(read.csv(path, check.names = FALSE,
                    fileEncoding = encoding, stringsAsFactors = FALSE),
                    warning = function(w) stop('CSV read failed: ', conditionMessage(w)))
  if (ncol(dat) < 2L || !nrow(dat)) stop('Expected Date and stock columns: ', path)
  dates <- nw_date(dat[[1L]])
  if (anyNA(dates) || anyDuplicated(dates)) stop('Invalid or duplicate dates: ', path)
  nw_check_names(names(dat)[-1L], path)
  vals <- lapply(dat[-1L], function(x) {
    y <- suppressWarnings(as.numeric(as.character(x)))
    if (any(!is.na(x) & nzchar(trimws(as.character(x))) & is.na(y)))
      stop('Non-numeric price/return value: ', path)
    if (any(is.infinite(y))) stop('Infinite price/return value: ', path)
    y
  })
  ans <- do.call(cbind, vals)
  dimnames(ans) <- list(as.character(dates), names(dat)[-1L])
  ans[order(dates), , drop = FALSE]
}

nw_calendar <- function(path, encoding = 'GB18030') {
  if (is.null(path) || !file.exists(path)) stop('Supply an existing --calendar CSV')
  dat <- withCallingHandlers(read.csv(path, check.names = FALSE,
                  fileEncoding = encoding, stringsAsFactors = FALSE),
                  warning = function(w) stop(conditionMessage(w)))
  days <- nw_date(dat[[1L]])
  if (!length(days) || anyNA(days) || anyDuplicated(days))
    stop('Calendar must contain unique valid dates, without metadata rows')
  sort(days)
}

nw_validate_matrix <- function(W) {
  if (!is.matrix(W) || !is.numeric(W) || nrow(W) != ncol(W) || !nrow(W))
    stop('Expected a nonempty square numeric matrix')
  nw_check_names(rownames(W), 'Matrix rows')
  if (!identical(rownames(W), colnames(W))) stop('Row/column names or order differ')
  if (any(!is.finite(W))) stop('Matrix contains non-finite values')
  invisible(W)
}

nw_validate_daily <- function(x) {
  if (!is.list(x) || !length(x)) stop('Expected a nonempty daily matrix list')
  nw_check_names(names(x), 'Daily list')
  dates <- nw_date(names(x))
  if (anyNA(dates) || any(diff(dates) <= 0)) stop('Daily dates must be valid and increasing')
  invisible(lapply(x, nw_validate_matrix))
}

nw_preflight <- function(outputs, inputs = character(), overwrite = FALSE) {
  outputs <- outputs[!vapply(outputs, is.null, logical(1))]
  outputs <- unlist(outputs, use.names = FALSE)
  norm <- function(x) vapply(x, function(p) {
    file.path(normalizePath(dirname(p), mustWork = FALSE), basename(p))
  }, character(1))
  if (anyDuplicated(norm(outputs))) stop('Output paths must differ')
  if (length(intersect(norm(outputs), norm(inputs)))) stop('An output would overwrite an input')
  if (!overwrite && any(file.exists(outputs)))
    stop('Output already exists: ', paste(outputs[file.exists(outputs)], collapse = ', '))
}

nw_save_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(object, tmp, compress = 'xz')
  if (!file.rename(tmp, path)) stop('Cannot save: ', path)
}

nw_align_returns <- function(prices, returns) {
  missing_dates <- setdiff(rownames(prices), rownames(returns))
  missing_stocks <- setdiff(colnames(prices), colnames(returns))
  if (length(missing_dates) || length(missing_stocks))
    stop('Returns lack price dates or stocks; align input files explicitly')
  returns[rownames(prices), colnames(prices), drop = FALSE]
}
