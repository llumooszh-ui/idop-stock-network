# Run from repository root: Rscript tests/test_network.R
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else '.'
load_script <- function(name) {
  e <- new.env(parent = globalenv())
  source(file.path(root, 'R', 'network', name), local = e)
  e
}
est <- load_script('estimate_stage_networks.R')
sym <- load_script('symmetrize_weights.R')
cor <- load_script('build_correlation_network.R')
expect_error <- function(expr) {
  hit <- tryCatch({force(expr); FALSE}, error = function(e) TRUE)
  stopifnot(hit)
}
est$effects_self_test(); sym$run_self_test(); cor$run_self_test()
stopifnot(exists('MTODEs', est, inherits=FALSE))
# Input returns may be shuffled, but must align by both date and node names.
P <- matrix(1:12, 6L, 2L, dimnames=list(as.character(as.Date('2024-01-01')+0:5), c('A','B')))
R <- P[6:1, 2:1, drop=FALSE] / 100
stopifnot(identical(est$nw_align_returns(P,R), P/100))
expect_error(est$nw_align_returns(P,R[-1,,drop=FALSE]))
# Missing nodes and too-short observations must not silently change correlation sample.
stage <- list(stage=1, start_date='2024-01-01',end_date='2024-01-06',stocks=c('A','B','C'),
              result=list(adj=matrix(1,3,3)))
expect_error(cor$process_stage(stage,P,cor$parse_args(character())))
stage$stocks <- c('A','B'); stage$result$adj <- matrix(c(0,1,1,0),2)
cfg <- cor$parse_args(character()); cfg$trading_days <- as.Date(rownames(P))
expect_error(cor$process_stage(stage,P[-2,,drop=FALSE],cfg))
C <- cor$process_stage(stage,P,cfg)$W
stopifnot(isTRUE(all.equal(C,t(C))))
# Direction, signs, removal of self effects, and multi-layer normalization.
effects <- list(data.frame(A=c(99,99),B=c(-2,-4)), data.frame(A=c(3,6),B=c(99,99)))
S <- list(list(stage=1, start_date='2024-01-01',end_date='2024-01-02',stocks=c('A','B'),
               result=list(effects=effects)))
tmp <- tempfile(); dir.create(tmp)
f1<-file.path(tmp,'results_layer1.rds');f2<-file.path(tmp,'results_layer2.rds')
saveRDS(S,f1);saveRDS(S,f2)
ans<-est$rebuild_layers(c(f1,f2),as.Date(c('2024-01-01','2024-01-02')))
W<-ans$matrices[[1]]
stopifnot(W['A','B']==1,W['B','A']==-1,all(diag(W)==0),all(colSums(abs(W))==1))
U<-sym$symmetrize_one(W);stopifnot(all(U==0))
expect_error(est$stage_dates(S[[1]],as.Date(c('2024-01-01','2024-01-02')),1L,'strict'))
expect_error(est$rebuild_layers(c(f1,f1),as.Date(c('2024-01-01','2024-01-02'))))
saveRDS(c(S,S),f2)
expect_error(est$rebuild_layers(f2,as.Date(c('2024-01-01','2024-01-02'))))
expect_error(sym$nw_validate_daily(setNames(list(W,W),c('2024-01-01','2024-01-01'))))
expect_error(sym$symmetrize_one(matrix(NA_real_,2,2,dimnames=list(c('A','B'),c('A','B')))))
# CLI integration: rebuild existing effects, then symmetrize and correlate.
saveRDS(S,f2)
pricefile<-file.path(tmp,'prices.csv')
write.csv(data.frame(Date=rownames(P),P,check.names=FALSE),pricefile,row.names=FALSE)
run <- function(script,args) {
  status <- system2(file.path(R.home('bin'),'Rscript'), c(shQuote(file.path(root,'R/network',script)),shQuote(args)))
  stopifnot(status==0L)
}
daily<-file.path(tmp,'daily.rds')
run('estimate_stage_networks.R',c('--mode','rebuild','--input-rds',f1,'--calendar',pricefile,'--output',daily))
run('symmetrize_weights.R',c('--input',daily,'--output',file.path(tmp,'undirected.rds')))
# Stage needs >= 3 observations for the default correlation min_obs.
S[[1]]$end_date <- '2024-01-06'; S[[1]]$result$adj <- matrix(c(0,1,1,0),2)
layerdir<-file.path(tmp,'stages');dir.create(layerdir);saveRDS(S,file.path(layerdir,'results_layer.rds'))
run('build_correlation_network.R',c('--input-dir',layerdir,'--prices',pricefile,'--calendar',pricefile,
                                  '--output',file.path(tmp,'correlation.rds')))
# Non-overwrite guard and input/output alias protection.
expect_error(est$nw_preflight(list(daily),character(),FALSE))
expect_error(est$nw_preflight(list(f1),f1,TRUE))
unlink(tmp,recursive=TRUE)
cat('All network regression and CLI tests passed.\n')

# Verify stage boundaries and date alignment without expensive fitting.
probe <- new.env(); source(file.path(root,'R/network/estimate_stage_networks.R'),local=probe)
probe$MTODEs <- function(data,return_data,...) {
  stopifnot(identical(dimnames(data),dimnames(return_data)),all(return_data==data/100))
  list(effects=list(),estimation=list(method='test-stub'))
}
Q <- cbind(A=1:12,B=21:32,C=c(rep(NA_real_,6),41:46))
rownames(Q)<-as.character(as.Date('2024-01-01')+0:11)
seg<-probe$estimate_stages(Q,(Q/100)[12:1,3:1,drop=FALSE])
stopifnot(length(seg$stages)==2L,seg$stages[[1]]$end_date=='2024-01-06',
          seg$stages[[2]]$start_date=='2024-01-07')
expect_error(probe$estimate_stages(Q[1:3,,drop=FALSE],Q[1:3,,drop=FALSE]/100))
cat('Stage boundaries and key alignment tests passed.\n')

if ('--with-estimation' %in% args) {
  tmp <- tempfile(); dir.create(tmp)
  t <- 1:12
  prices <- data.frame(Date=as.character(as.Date('2024-01-01')+t-1),
                       A=10+0.1*t+sin(t),B=20+cos(t)+0.05*t*t)
  returns <- prices; returns[-1L] <- returns[-1L]/1000
  returns <- returns[12:1,c('Date','B','A')]
  pf<-file.path(tmp,'prices.csv');rf<-file.path(tmp,'returns.csv')
  write.csv(prices,pf,row.names=FALSE);write.csv(returns,rf,row.names=FALSE)
  sf<-file.path(tmp,'results_test.rds');df<-file.path(tmp,'daily.rds')
  run('estimate_stage_networks.R',c('--mode','estimate','--prices',pf,'--returns',rf,
      '--stage-output',sf,'--output',df,'--seed','20260922'))
  estimated<-readRDS(sf);daily<-readRDS(df)
  stopifnot(length(estimated)==1L,length(daily)==12L,
    identical(names(daily),prices$Date),
    identical(estimated[[1]]$result$estimation$seed,20260922L))
  est$nw_validate_daily(daily)
  df2<-file.path(tmp,'reloaded.rds')
  run('estimate_stage_networks.R',c('--mode','rebuild','--input-rds',sf,'--calendar',pf,'--output',df2))
  stopifnot(identical(daily,readRDS(df2)))
  unlink(tmp,recursive=TRUE)
  cat('Estimation -> saved effects -> rebuild round-trip passed.\n')
}
