#!/usr/bin/env Rscript
local({
  sources <- Filter(Negate(is.null), lapply(sys.frames(), function(f)
    get0("ofile", envir=f, inherits=FALSE)))
  ofile <- if(length(sources)) sources[[length(sources)]] else NULL
  if(is.null(ofile)) {
    arg<-grep("^--file=", commandArgs(), value=TRUE)
    if(!length(arg)) stop("Cannot resolve script path")
    ofile<-sub("^--file=", "", arg[[1L]])
  }
  assign("AP_DIR", dirname(normalizePath(ofile)), envir=parent.env(environment()))
})

source(file.path(AP_DIR,"common.R"),local=TRUE)

parse_args <- function(args=commandArgs(trailingOnly=TRUE),default_analysis='all') {
  cfg<-list(conventional=NULL,network=NULL,enhanced=NULL,returns=NULL,factors=NULL,
    output_dir=NULL,analysis=default_analysis,prediction_encoding='UTF-8',return_encoding='GB18030',
    factor_encoding='GB18030',return_units='decimal',factor_units=NULL,
    start_month='2022-04',end_month='9999-12',n_groups='10',min_stocks='10',nw_lag='4',
    min_month_coverage='0.8',cost_bps='5,10,20',vol_window='6',sample_mode='per_model',
    calendar=NULL,no_plots=FALSE,overwrite=FALSE)
  if('--help' %in% args) {
    cat('Monthly portfolio analysis; specify three prediction CSVs and daily realized returns.\n')
    for(n in names(cfg)) cat('--',gsub('_','-',n),' ',if(is.logical(cfg[[n]]))'(flag)'else paste(cfg[[n]],collapse=','),'\n',sep='')
    cat('Analyses:',paste(names(ANALYSIS_OUTPUTS),collapse=','),'or all\n')
    return(NULL)
  }
  i<-1L
  while(i<=length(args)) {
    key<-gsub('-','_',sub('^--','',args[[i]]))
    if(!startsWith(args[[i]],'--')||!key %in% names(cfg))stop('Unknown option: ',args[[i]])
    if(is.logical(cfg[[key]])){cfg[[key]]<-TRUE;i<-i+1L;next}
    if(i==length(args))stop('Missing option value: ',args[[i]])
    cfg[[key]]<-args[[i+1L]];i<-i+2L
  }
  required<-c('conventional','network','enhanced','returns','output_dir')
  if(any(vapply(cfg[required],is.null,logical(1))))stop('Required: ',paste(required,collapse=', '))
  cfg$analyses<-if(cfg$analysis=='all')names(ANALYSIS_OUTPUTS)else strsplit(cfg$analysis,',',fixed=TRUE)[[1L]]
  if(!length(cfg$analyses)||anyDuplicated(cfg$analyses)||!all(cfg$analyses %in% names(ANALYSIS_OUTPUTS)))stop('Invalid analysis')
  if('factor_alpha_tests' %in% cfg$analyses &&
     (is.null(cfg$factors)||is.null(cfg$factor_units)))stop('Alpha tests require --factors and explicit --factor-units decimal|percent')
  for(n in c('n_groups','min_stocks','nw_lag','vol_window')) {
    v<-suppressWarnings(as.numeric(cfg[[n]]))
    if(length(v)!=1L||!is.finite(v)||v!=as.integer(v))stop('Invalid integer: ',n)
    cfg[[n]]<-as.integer(v)
  }
  cfg$min_month_coverage<-as.numeric(cfg$min_month_coverage)
  cfg$cost_bps<-as.numeric(strsplit(cfg$cost_bps,',',fixed=TRUE)[[1L]])
  if(cfg$n_groups<2L||cfg$min_stocks<cfg$n_groups||cfg$nw_lag<0L||cfg$vol_window<2L||
     !is.finite(cfg$min_month_coverage)||cfg$min_month_coverage<=0||cfg$min_month_coverage>1||
     !length(cfg$cost_bps)||any(!is.finite(cfg$cost_bps))||any(cfg$cost_bps<0)||anyDuplicated(cfg$cost_bps))stop('Invalid numeric configuration')
  if(!cfg$sample_mode %in% c('per_model','common'))stop('sample-mode must be per_model or common')
  if(!cfg$return_units %in% c('decimal','percent'))stop('Invalid return units')
  if(!is.null(cfg$factor_units)&&!cfg$factor_units %in% c('decimal','percent'))stop('Invalid factor units')
  if(!grepl('^[0-9]{4}-(0[1-9]|1[0-2])$',cfg$start_month)||
     !grepl('^[0-9]{4}-(0[1-9]|1[0-2])$',cfg$end_month)||cfg$start_month>cfg$end_month)stop('Invalid month range')
  cfg
}

run_asset_pricing <- function(cfg) {
  inputs<-unlist(Filter(Negate(is.null),cfg[c('conventional','network','enhanced','returns','factors','calendar')]))
  if(any(!file.exists(inputs)))stop('Missing input: ',paste(inputs[!file.exists(inputs)],collapse=', '))
  extra<-c('sample_counts.csv','assigned_portfolios.csv','group_returns.csv','long_short_returns.csv','manifest.rds')
  if('factor_alpha_tests' %in% cfg$analyses)extra<-c(extra,'monthly_factors.csv')
  planned<-unique(c(unlist(ANALYSIS_OUTPUTS[cfg$analyses]),extra))
  if(cfg$no_plots)planned<-planned[!grepl('\\.png$',planned)]
  output_paths<-file.path(cfg$output_dir,planned)
  canonical<-function(p)file.path(normalizePath(dirname(p),mustWork=FALSE),basename(p))
  if(length(intersect(vapply(output_paths,canonical,''),vapply(inputs,canonical,''))))stop('Output would overwrite input')
  if(!cfg$overwrite&&any(file.exists(output_paths)))stop('Output already exists; choose a new output directory or --overwrite')
  context<-create_context(cfg)
  dir.create(cfg$output_dir,recursive=TRUE,showWarnings=FALSE)
  # All five analyses share this validated panel and the same grouping configuration.
  results<-list()
  for(name in cfg$analyses) {
    module<-new.env(parent=context)
    source(file.path(AP_DIR,paste0(name,'.R')),local=module)
    results[[name]]<-get(paste0('run_',name),envir=module)(context)
  }
  write.csv(context$sample_counts,file.path(cfg$output_dir,'sample_counts.csv'),row.names=FALSE,fileEncoding='UTF-8')
  write.csv(context$assigned_panel,file.path(cfg$output_dir,'assigned_portfolios.csv'),row.names=FALSE,fileEncoding='UTF-8')
  write.csv(context$group_returns,file.path(cfg$output_dir,'group_returns.csv'),row.names=FALSE,fileEncoding='UTF-8')
  write.csv(context$long_short_returns,file.path(cfg$output_dir,'long_short_returns.csv'),row.names=FALSE,fileEncoding='UTF-8')
  if('factor_alpha_tests' %in% cfg$analyses)
    write.csv(context$factor_data_checked,file.path(cfg$output_dir,'monthly_factors.csv'),row.names=FALSE,fileEncoding='UTF-8')
  manifest<-list(config=cfg,input_alignment=context$input_alignment,inputs=basename(inputs),input_md5=unname(tools::md5sum(inputs)),
    sample_months=context$assigned_panel %>% distinct(model,year_month),
    alpha_sample_counts=if('factor_alpha_tests' %in% names(results))
      results$factor_alpha_tests$reg_data %>% count(model,name='regression_months') else NULL,
    packages=vapply(c('dplyr','tidyr','purrr','ggplot2','lubridate','sandwich','lmtest'),function(p)as.character(packageVersion(p)),''),
    R=as.character(getRversion()),outputs=planned,
    conventions=list(sample_mode=cfg$sample_mode,weights='equal-weight each side; long gross 1, short gross 1',
      turnover='sum(abs(target weights - previous target weights)); initial positions zero; no drift',
      volatility_threshold='full-sample median of lagged volatility; retrospective grouping',
      sharpe='mean monthly raw strategy return / sd * sqrt(12); no cash-rate subtraction',
      drawdown='includes initial wealth 1 (corrected from original implementation)',
      calendar_check=if(is.null(cfg$calendar))'first date in returns; external month completeness not verified'else'supplied calendar'))
  saveRDS(manifest,file.path(cfg$output_dir,'manifest.rds'))
  cat('Asset pricing complete:',cfg$output_dir,'; sample mode=',cfg$sample_mode,'\n')
  invisible(list(context=context,results=results,manifest=manifest))
}
main <- function(default_analysis='all') {
  cfg<-parse_args(default_analysis=default_analysis)
  if(is.null(cfg))return(invisible(NULL))
  run_asset_pricing(cfg)
}
if(sys.nframe()==0L)main()
