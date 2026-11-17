# From repository root: Rscript tests/test_asset_pricing.R .
args<-commandArgs(trailingOnly=TRUE);root<-if(length(args))args[[1L]]else'.'
e<-new.env();source(file.path(root,'R/asset_pricing/run_asset_pricing.R'),local=e)
expect_error<-function(x)stopifnot(tryCatch({force(x);FALSE},error=function(err)TRUE))
tmp<-tempfile();dir.create(tmp)
set.seed(42)
months<-seq(as.Date('2021-01-01'),by='month',length.out=36)
days<-as.Date(sort(c(as.numeric(months),as.numeric(months+1))),origin='1970-01-01')
stocks<-paste0('S',1:20)
ret<-matrix(rnorm(length(days)*20,0.0005,0.01),length(days),20,dimnames=list(NULL,stocks))
ret[3,20]<-NA_real_
returns<-data.frame(Date=days,ret,check.names=FALSE)
rp<-file.path(tmp,'returns.csv');write.csv(returns,rp,row.names=FALSE)
preds<-lapply(1:3,function(j)data.frame(Date=months,matrix(rnorm(36*20),36,20,dimnames=list(NULL,stocks)),check.names=FALSE))
preds[[2]][5,'S1']<-NA_real_;preds[[3]][8,'S2']<-NA_real_
paths<-file.path(tmp,c('conventional.csv','network.csv','enhanced.csv'))
for(i in 1:3)write.csv(preds[[i]],paths[i],row.names=FALSE)
factors<-data.frame(year_month=format(months,'%Y-%m'),matrix(rnorm(36*5,0,0.02),36,5))
names(factors)[-1]<-c('RiskPremium1','SMB1','HML1','RMW1','CMA1')
fp<-file.path(tmp,'factors.csv');write.csv(factors,fp,row.names=FALSE)
cli<-c('--conventional',paths[1],'--network',paths[2],'--enhanced',paths[3],
       '--returns',rp,'--factors',fp,'--factor-units','decimal','--start-month','2021-01',
       '--output-dir',file.path(tmp,'all'),'--no-plots')
cfg<-e$parse_args(cli)
run<-e$run_asset_pricing(cfg);ctx<-run$context
stopifnot(nrow(ctx$long_short_returns)==108L,length(run$results)==5L)
# Month compounding and coverage rejection.
panel<-ctx$panel
known<-panel[panel$model=='Conventional-factor'&panel$stock_id=='S1'&panel$year_month=='2021-01',]
stopifnot(abs(known$true_month_return-((1+ret[1,1])*(1+ret[2,1])-1))<1e-12,
          !any(panel$stock_id=='S20'&panel$year_month=='2021-02'))
# Long minus short is equal to top group return minus bottom group return.
g<-ctx$group_returns;ls<-ctx$long_short_returns
for(i in seq_len(nrow(ls))){
 rows<-g[g$model==ls$model[i]&g$Date==ls$Date[i],]
 stopifnot(abs(ls$R_LS[i]-(rows$group_return[rows$group==10]-rows$group_return[rows$group==1]))<1e-12)
}
stopifnot(abs(ctx$max_drawdown(c(-0.1,0.2))+0.1)<1e-12,
          ctx$max_drawdown(c(0.1,0.1))==0)
# Initial target positions gross 2; costs are charged per absolute traded weight.
cost<-run$results$transaction_cost_tests
first<-cost$turnover[cost$turnover$Date==months[1],]
stopifnot(all(abs(first$turnover-2)<1e-12),
          max(abs(cost$net_returns$net_R_LS-(cost$net_returns$R_LS-cost$net_returns$cost_rate*cost$net_returns$turnover)))<1e-12)
# Historical default sample differs by model; common mode aligns keys before grouping.
stopifnot(length(unique(ctx$sample_counts$portfolio_stocks[ctx$sample_counts$Date==months[5]]))==2L)
cfg2<-cfg;cfg2$sample_mode<-'common';common<-e$create_context(cfg2)
keysets<-lapply(split(common$assigned_panel,common$assigned_panel$model),function(x)sort(paste(x$Date,x$stock_id)))
stopifnot(identical(keysets[[1]],keysets[[2]]),identical(keysets[[2]],keysets[[3]]))
# Factor units are explicit and converted once; duplicate months are rejected.
pct<-factors;pct[-1]<-pct[-1]*100;pp<-file.path(tmp,'factors_pct.csv');write.csv(pct,pp,row.names=FALSE)
cfg3<-cfg;cfg3$factors<-pp;cfg3$factor_units<-'percent';pctctx<-e$create_context(cfg3)
stopifnot(isTRUE(all.equal(as.data.frame(pctctx$factor_data_checked),as.data.frame(ctx$factor_data_checked),tolerance=1e-12)))
write.csv(rbind(factors,factors[1,]),pp,row.names=FALSE)
expect_error(e$create_context(cfg3))
# Daily prediction rows must never be silently interpreted as monthly formations.
bad<-preds[[1]];bad<-rbind(bad,transform(bad[1,],Date=months[1]+1));bp<-file.path(tmp,'bad.csv');write.csv(bad,bp,row.names=FALSE)
cfg4<-cfg;cfg4$conventional<-bp;expect_error(e$create_context(cfg4))
# Do not overwrite an existing output; this check precedes any computation.
expect_error(e$run_asset_pricing(cfg))
# Individual analysis CLI uses the same validated context; no factors needed for sorting.
one<-cli;one[match('--output-dir',one)+1L]<-file.path(tmp,'sorting')
status<-system2(file.path(R.home('bin'),'Rscript'),c(shQuote(file.path(root,'R/asset_pricing/portfolio_sorting.R')),shQuote(one)))
stopifnot(status==0L,file.exists(file.path(tmp,'sorting','manifest.rds')))
# Full alpha results include all three specifications and incremental alpha.
stopifnot(setequal(run$results$factor_alpha_tests$alpha_results$specification,c('CAPM','FF3','FF5')),
          nrow(run$results$factor_alpha_tests$incremental_alpha_table)==3L)
unlink(tmp,recursive=TRUE)
cat('Asset-pricing tests passed: compounding, sample modes, initial drawdown, costs, units, alpha and CLI.\n')
