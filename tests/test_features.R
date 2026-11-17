# From repository root: Rscript tests/test_features.R .
args<-commandArgs(trailingOnly=TRUE);root<-if(length(args)) args[[1L]] else '.'
e<-new.env();source(file.path(root,'R/features/build_network_features.R'),local=e)
expect_error<-function(expr) stopifnot(tryCatch({force(expr);FALSE},error=function(err)TRUE))
set.seed(17)
stocks<-LETTERS[1:6];dates<-as.character(as.Date('2024-01-01')+0:25)
matrices<-lapply(seq_along(dates),function(i){
  W<-matrix(sin(seq_len(36)+i/3),6,6,dimnames=list(stocks,stocks));diag(W)<-0
  sweep(W,2,colSums(abs(W)),'/')
});names(matrices)<-dates
returns<-outer(seq_along(dates),seq_along(stocks),function(i,j)(i-j)/1000)
dimnames(returns)<-list(dates,stocks)
sample<-data.table::CJ(Date=dates,stock=stocks)[.N:1]
sample[,Date:=data.table::as.IDate(Date)]
built<-e$build_features(matrices,returns,sample,seed=123L)
result<-built$data
stopifnot(nrow(result)==156L,ncol(result)==92L,
  identical(names(result),c('Date','stock','target_return',e$FINAL_FEATURES)),
  identical(result[,.(Date,stock)],sample[,.(Date,stock)]),
  identical(unname(lengths(e$FEATURE_GROUPS)),c(26L,20L,38L,5L)))
# Sign/degrees and one-time lag: t3's body comes from W2, not W3 or W1.
row<-result[Date==data.table::as.IDate(dates[3]) & stock=='B']
stopifnot(row$net_degree_in_pos==sum(matrices[[2]][,'B']>0),
  abs(row$net_strength_in_net-sum(matrices[[2]][,'B']))<1e-12,
  abs(row$net_return_influence-as.numeric(returns[2,]%*%matrices[[1]][,'B']))<1e-12,
  abs(row$net_return_influence-(row$net_return_influence_pos_edges-row$net_return_influence_neg_edges))<1e-12)
centmod<-e$feature_module('recompute_final_network_centrality.R')
refcent<-centmod$measure(matrices[[2]],dates[3])
central_cols<-e$CENTRALITY_FEATURES
stopifnot(isTRUE(all.equal(as.numeric(row[,..central_cols]),
                         as.numeric(refcent[stock=='B',..central_cols]))))
# Earliest histories stay NA; no fabricated zero imputation.
stopifnot(all(is.na(result[Date==data.table::as.IDate(dates[1]),net_degree_in_pos])),
          all(is.na(result[Date<=data.table::as.IDate(dates[2]),net_return_influence])))
# Changes to matrix t and returns t must not change t's feature values.
changed<-matrices;changed[[10]]<--changed[[10]]
ret2<-returns;ret2[10,]<-ret2[10,]+0.2
b2<-e$build_features(changed,ret2,data.table::copy(sample),seed=123L)$data
cols<-e$FINAL_FEATURES
stopifnot(isTRUE(all.equal(result[Date<=data.table::as.IDate(dates[10]),..cols],
                          b2[Date<=data.table::as.IDate(dates[10]),..cols],tolerance=1e-10)))
# Short histories (1 or 2 days) still produce a valid 89-column schema.
for(n in 1:2){
 keys<-data.table::CJ(Date=dates[seq_len(n)],stock=stocks)
 short<-e$build_features(matrices[seq_len(n)],returns,keys,seed=123L)$data
 stopifnot(ncol(short)==92L,all(is.na(short$net_return_influence)))
}
# Duplicate keys, wrong labels, missing columns and incorrect calendar must fail.
expect_error(e$build_features(matrices,returns,rbind(sample,sample[1]),123L))
bad<-data.table::copy(sample);bad[,target_return:=999]
expect_error(e$assemble_features(bad,built$safe,built$centrality,returns))
expect_error(e$assemble_features(sample,built$safe,built$centrality[,-'net_pagerank'],returns))
# Run public CLI and verify artifacts and non-overwrite behavior.
tmp<-tempfile();dir.create(tmp)
mp<-file.path(tmp,'matrices.rds');rp<-file.path(tmp,'returns.csv');sp<-file.path(tmp,'keys.csv')
saveRDS(matrices,mp)
write.csv(data.frame(Date=dates,returns,check.names=FALSE),rp,row.names=FALSE)
data.table::fwrite(sample,sp)
output<-file.path(tmp,'output')
cli<-c(shQuote(file.path(root,'R/features/build_network_features.R')),
       shQuote(c('--matrices',mp,'--returns',rp,'--sample-keys',sp,'--output-dir',output,
                  '--seed','123','--expected-days','26','--keep-intermediates')))
status<-system2(file.path(R.home('bin'),'Rscript'),cli)
stopifnot(status==0L)
actual<-data.table::fread(file.path(output,'network_features.csv'))
stopifnot(nrow(actual)==156L,ncol(actual)==92L,
          identical(names(actual),names(result)),
          nrow(data.table::fread(file.path(output,'feature_dictionary.csv')))==89L,
          nrow(data.table::fread(file.path(output,'feature_quality.csv')))==89L,
          readRDS(file.path(output,'manifest.rds'))$matrix_days==26L)
expect_error(e$nw_preflight(list(file.path(output,'network_features.csv')),character(),FALSE))
unlink(tmp,recursive=TRUE)
cat('Feature schema, lag timing, labels, short histories, and CLI tests passed.\n')

# NWR missing-source normalization must match the original formula.
ret_missing<-returns;ret_missing[2,'A']<-NA_real_
keys3<-data.table::data.table(Date=dates[3],stock='B')
missing<-e$build_features(matrices,ret_missing,keys3,123L)$data
valid<-setdiff(stocks,'A');denom<-sum(abs(matrices[[1]][valid,'B']))
stopifnot(abs(missing$net_return_influence_coverage-denom)<1e-12,
          abs(missing$net_return_influence-sum(ret_missing[2,valid]*matrices[[1]][valid,'B'])/denom)<1e-12)
# Preserve the historical previous-stock-observation rule on exit/reentry.
evolving<-matrices
for(i in 6:7)evolving[[i]]<-evolving[[i]][LETTERS[1:5],LETTERS[1:5],drop=FALSE]
keys8<-data.table::data.table(Date=dates[8],stock='F')
reentry<-e$build_features(evolving,returns,keys8,123L)$data
stopifnot(reentry$net_degree_in_pos==sum(matrices[[5]][,'F']>0))
expect_error(e$build_features(matrices,returns,data.table::data.table(Date=dates[3],stock='UNKNOWN'),123L))
# Full-history calculation must be independent of how narrowly the sample is selected.
late<-data.table::copy(sample[Date>=data.table::as.IDate(dates[22])])
late_result<-e$build_features(matrices,returns,late,123L)$data
stopifnot(isTRUE(all.equal(result[Date>=data.table::as.IDate(dates[22])],late_result)))
cat('Missing-return coverage, node reentry, and full-history selection tests passed.\n')
