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

assemble_features <- function(sample, safe_features, centrality, returns) {
  sample<-copy(as.data.table(sample));check_keys(sample)
  safe<-copy(as.data.table(safe_features));check_keys(safe)
  cent<-copy(as.data.table(centrality));check_keys(cent)
  if(!identical(sample[,.(Date,stock)],safe[,.(Date,stock)])) stop('Sample order or keys changed')
  if(length(setdiff(names(cent),c('Date','stock')))!=5L ||
     !setequal(setdiff(names(cent),c('Date','stock')),CENTRALITY_FEATURES)) stop('Expected five centralities')
  renamed<-paper_name(names(safe));if(anyDuplicated(renamed)) stop('Renaming collides')
  setnames(safe,renamed)
  di<-match(as.character(sample$Date),rownames(returns)); si<-match(sample$stock,colnames(returns))
  if(anyNA(di)||anyNA(si)) stop('Sample contains dates/stocks absent from returns')
  truth<-returns[cbind(di,si)]
  if(any(!is.finite(truth))) stop('Sample contains missing/non-finite target returns; select sample explicitly')
  if('target_return' %in% names(sample)) {
    old<-suppressWarnings(as.numeric(sample$target_return))
    if(any(!is.finite(old)) || any(abs(old-truth)>1e-12+1e-12*abs(truth)))
      stop('Sample target_return disagrees with supplied returns')
  }
  safe[,row_id:=.I]
  result<-merge(safe,cent,by=c('Date','stock'),all.x=TRUE,sort=FALSE)
  setorder(result,row_id);result[,row_id:=NULL]
  if(nrow(result)!=nrow(sample)) stop('Join changed sample size')
  result[,target_return:=truth]
  actual<-setdiff(names(result),c('Date','stock','target_return'))
  if(length(actual)!=89L || !setequal(actual,FINAL_FEATURES)) stop('Final schema is not exactly 89 features')
  setcolorder(result,c('Date','stock','target_return',FINAL_FEATURES));check_keys(result)
  if(any(vapply(result[,..FINAL_FEATURES],function(x)any(is.infinite(x)),logical(1)))) stop('Infinite feature value')
  result
}

build_features <- function(matrices, returns, sample, seed=20260922L, min_coverage=0) {
  feature_validate_matrices(matrices);check_keys(sample)
  if(!all(as.character(sample$Date) %in% names(matrices))) stop('Sample dates outside matrix calendar')
  if(!all(sample$stock %in% unique(unlist(lapply(matrices,rownames))))) stop('Sample contains unknown network stocks')
  metric_module<-feature_module('compute_new_network_metrics.R')
  nwr_module<-feature_module('add_lagged_network_return_influence.R')
  centrality_module<-feature_module('recompute_final_network_centrality.R')
  lag_module<-feature_module('build_leakage_safe_network_factor_file.R')
  body<-metric_module$compute_network_metrics(matrices,seed)
  with_nwr<-nwr_module$add_return_influence(matrices,body,returns,min_coverage)
  cent<-centrality_module$compute_centrality(matrices)
  safe<-lag_module$build_lagged_features(sample,with_nwr)
  result<-assemble_features(sample,safe,cent,returns)
  list(data=result,metrics=body,with_nwr=with_nwr,centrality=cent,safe=safe)
}

main <- function() {
  cfg<-feature_args(list(matrices=NULL,returns=NULL,sample_keys=NULL,output_dir=NULL,
    calendar=NULL,encoding='GB18030',seed='20260922',min_coverage='0',expected_days=NULL,
    keep_intermediates=FALSE,overwrite=FALSE),c('matrices','returns','sample_keys','output_dir'))
  seed<-feature_seed(cfg$seed)
  filenames<-c('network_features.csv','feature_dictionary.csv','feature_quality.csv','manifest.rds')
  if(cfg$keep_intermediates) filenames<-c(filenames,'metrics_79.rds','metrics_with_nwr_84.rds',
                                       'centrality_5.csv','lagged_features_84.csv')
  paths<-file.path(cfg$output_dir,filenames);names(paths)<-filenames
  inputs<-unlist(Filter(Negate(is.null),list(cfg$matrices,cfg$returns,cfg$sample_keys,cfg$calendar)))
  if(any(!file.exists(inputs))) stop('An input file does not exist')
  nw_preflight(as.list(paths),inputs,cfg$overwrite)
  matrices<-readRDS(cfg$matrices);feature_validate_matrices(matrices)
  if(!is.null(cfg$expected_days)) {
    n<-suppressWarnings(as.integer(cfg$expected_days))
    if(is.na(n)||n<1L||length(matrices)!=n) stop('Matrix count does not match --expected-days')
  }
  returns<-nw_read_panel(cfg$returns,cfg$encoding)
  # Validate the entire matrix history, not just dates selected into the sample.
  md<-as.Date(names(matrices))
  calendar<-if(is.null(cfg$calendar)) as.Date(rownames(returns)) else nw_calendar(cfg$calendar,cfg$encoding)
  calendar<-calendar[calendar>=min(md)&calendar<=max(md)]
  if(!identical(md,calendar)) stop('Matrix dates differ from the trading calendar within matrix range')
  sample<-feature_read_sample(cfg$sample_keys)
  built<-build_features(matrices,returns,sample,seed,as.numeric(cfg$min_coverage))
  result<-built$data
  dictionary<-fread(file.path(FEATURES_DIR,'feature_dictionary.csv'))
  stopifnot(identical(dictionary$feature,FINAL_FEATURES))
  quality<-rbindlist(lapply(FINAL_FEATURES,function(n) {
    x<-result[[n]];ok<-is.finite(x)
    data.table(feature=n,rows=length(x),missing=sum(is.na(x)),missing_fraction=mean(is.na(x)),
      finite=sum(ok),minimum=if(any(ok))min(x[ok])else NA_real_,
      maximum=if(any(ok))max(x[ok])else NA_real_)
  }))
  metric_keys<-built$metrics$data[,.(Date,stock)]
  central_keys<-built$centrality[,.(Date,stock)]
  manifest<-list(seed=seed,min_coverage=as.numeric(cfg$min_coverage),
    matrix_days=length(matrices),matrix_range=as.character(range(md)),
    sample_rows=nrow(result),sample_range=as.character(range(result$Date)),
    category_counts=lengths(FEATURE_GROUPS),feature_count=89L,
    rows_without_metric_key=nrow(sample[!metric_keys,on=.(Date,stock)]),
    rows_without_centrality_key=nrow(sample[!central_keys,on=.(Date,stock)]),
    all_missing_features=quality[finite==0L,feature],
    inputs=basename(inputs),input_md5=unname(tools::md5sum(inputs)),
    R=as.character(getRversion()),packages=c(data.table=as.character(packageVersion('data.table')),
      igraph=as.character(packageVersion('igraph'))),
    timing=list(body='previous observation within each stock, after full-history computation',
      centrality='previous matrix date; already lagged',NWR='R[t-1] and W[t-2]; already lagged'),
    limitations='Stage estimation may include future observations; downstream lag does not remove this.')
  feature_write_csv(result,paths[['network_features.csv']])
  feature_write_csv(dictionary,paths[['feature_dictionary.csv']])
  feature_write_csv(quality,paths[['feature_quality.csv']])
  nw_save_rds(manifest,paths[['manifest.rds']])
  if(cfg$keep_intermediates) {
    nw_save_rds(built$metrics,paths[['metrics_79.rds']])
    nw_save_rds(built$with_nwr,paths[['metrics_with_nwr_84.rds']])
    feature_write_csv(built$centrality,paths[['centrality_5.csv']])
    feature_write_csv(built$safe,paths[['lagged_features_84.csv']])
  }
  cat('Saved',nrow(result),'rows, 89 features (SC26/NP20/ND38/NWR5):',paths[['network_features.csv']],'\n')
}
if(sys.nframe()==0L) main()
