# Shared feature contracts; no data files are read when sourced.
if (!requireNamespace('data.table', quietly=TRUE)) stop('Missing data.table')
if (!requireNamespace('igraph', quietly=TRUE)) stop('Missing igraph')
suppressPackageStartupMessages(library(data.table))
sys.source(file.path(FEATURES_DIR,'..','network','network_common.R'), envir=environment())
sys.source(file.path(FEATURES_DIR,'feature_schema.R'), envir=environment())

paper_name <- function(x) {
  x <- sub('^net_new_deg_', 'net_degree_', x)
  x <- sub('^net_new_str_', 'net_strength_', x)
  sub('^net_new_', 'net_', x)
}
check_keys <- function(x) {
  if (!all(c('Date','stock') %in% names(x))) stop('Missing Date/stock keys')
  x[, `:=`(Date=as.IDate(nw_date(Date)),stock=as.character(stock))]
  if (anyNA(x$Date) || anyNA(x$stock) || any(!nzchar(trimws(x$stock)))) stop('Invalid Date/stock')
  if (anyDuplicated(x,by=c('Date','stock'))) stop('Duplicate Date+stock')
  invisible(x)
}
empty_features <- function(cols) {
  ans <- data.table(Date=as.IDate(character()),stock=character())
  for (name in cols) ans[, (name):=numeric()]
  ans
}
feature_validate_matrices <- function(x) {
  nw_validate_daily(x)
  if (!identical(names(x),as.character(nw_date(names(x))))) stop('Use ISO YYYY-MM-DD matrix date names')
  if (any(vapply(x,function(W)any(diag(W)!=0),logical(1)))) stop('Network matrices must have zero diagonals')
  invisible(NULL)
}
feature_seed <- function(x) {
  n <- suppressWarnings(as.integer(x))
  if (length(n)!=1L || is.na(n) || n<0L) stop('seed must be a nonnegative integer')
  n
}
feature_write_csv <- function(x,path) {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  tmp <- tempfile(tmpdir=dirname(path)); on.exit(unlink(tmp),add=TRUE)
  fwrite(x,tmp,bom=TRUE,na='')
  if (!file.rename(tmp,path)) stop('Cannot save CSV: ',path)
}
feature_args <- function(defaults,required,args=commandArgs(trailingOnly=TRUE)) {
  if ('--help' %in% args) {
    cat('Options (required: ',paste(required,collapse=', '),'):\n',sep='')
    for (n in names(defaults)) cat('--',gsub('_','-',n), ' ',
      if (is.logical(defaults[[n]])) '(flag)' else paste(defaults[[n]],collapse=','),'\n',sep='')
    quit(save='no',status=0L)
  }
  cfg<-defaults;i<-1L
  while(i<=length(args)) {
    key<-gsub('-','_',sub('^--','',args[[i]]))
    if (!startsWith(args[[i]],'--') || !key %in% names(cfg)) stop('Unknown argument: ',args[[i]])
    if (is.logical(defaults[[key]])) {cfg[[key]]<-TRUE;i<-i+1L;next}
    if(i==length(args)) stop('Missing value: ',args[[i]])
    cfg[[key]]<-args[[i+1L]];i<-i+2L
  }
  if(any(vapply(cfg[required],is.null,logical(1)))) stop('Required arguments: ',paste(required,collapse=', '))
  cfg
}
feature_read_sample <- function(path) {
  header<-names(fread(path,nrows=0L,encoding='UTF-8'))
  if(anyDuplicated(header)) stop('Sample header has duplicate fields')
  keys<-fread(path,select=intersect(c('Date','stock','target_return'),header),
              colClasses=c(Date='character',stock='character'),encoding='UTF-8')
  if(!nrow(keys)) stop('Empty sample')
  check_keys(keys)
  keys
}
feature_module <- function(file) {
  e<-new.env(parent=globalenv())
  source(file.path(FEATURES_DIR,file),local=e)
  e
}
