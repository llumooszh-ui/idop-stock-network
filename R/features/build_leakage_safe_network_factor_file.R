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

build_lagged_features <- function(sample_keys, metric_object) {
  base<-copy(as.data.table(sample_keys))[,c('Date','stock'),with=FALSE];check_keys(base)
  base[,row_id:=.I]
  metrics<-copy(as.data.table(metric_object$data));check_keys(metrics)
  topology_cols<-grep('^net_new_',names(metrics),value=TRUE)
  influence_cols<-grep('^net_return_influence',names(metrics),value=TRUE)
  if(length(topology_cols)!=79L || !setequal(paper_name(topology_cols),BODY_FEATURES) ||
     !setequal(influence_cols,FEATURE_GROUPS$NWR)) stop('Expected 79 body + 5 NWR fields')
  # Historical convention: shift on the full per-stock observation history,
  # BEFORE selecting the requested sample; do not shift NWR a second time.
  setorder(metrics,stock,Date)
  metrics[, (topology_cols):=shift(.SD,1L),by=stock,.SDcols=topology_cols]
  selected<-metrics[,c('Date','stock',topology_cols,influence_cols),with=FALSE]
  result<-merge(base,selected,by=c('Date','stock'),all.x=TRUE,sort=FALSE)
  setorder(result,row_id);result[,row_id:=NULL]
  setcolorder(result,c('Date','stock',topology_cols,influence_cols))
  stopifnot(nrow(result)==nrow(base));check_keys(result)
  result
}
main <- function() {
  cfg<-feature_args(list(sample_keys=NULL,metrics=NULL,output=NULL,overwrite=FALSE),
                    c('sample_keys','metrics','output'))
  nw_preflight(list(cfg$output),c(cfg$sample_keys,cfg$metrics),cfg$overwrite)
  result<-build_lagged_features(feature_read_sample(cfg$sample_keys),readRDS(cfg$metrics))
  feature_write_csv(result,cfg$output)
}
if(sys.nframe()==0L) main()
