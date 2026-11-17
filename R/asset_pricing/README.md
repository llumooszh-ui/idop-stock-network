# 月频资产定价与组合检验

2026-11-12 整理。基于原 `资产定价代码/00–05` 六个脚本构建，默认保留每个模型分别筛选有效样本的旧口径；可显式切换到三个模型的共同股票—月份样本。这里消费预测文件，不训练预测模型，也不直接消费 89 个网络特征。

## 文件

| 文件 | 原脚本 | 功能 |
|---|---|---|
| common.R | 00_common_4_4.R | 输入与配置、月复合收益、分组、组合、Newey–West 和回归公共函数 |
| portfolio_sorting.R | 01_portfolio_sorting_analysis.R | 等权分组、组收益及排序图 |
| long_short_performance.R | 02_long_short_portfolio_performance.R | 多空绩效、增量收益、累计收益图 |
| factor_alpha_tests.R | 03_capm_ff3_alpha_tests.R | CAPM/FF3/FF5 及网络增强相对传统策略的增量 alpha |
| transaction_cost_tests.R | 04_transaction_cost_tests.R | 目标权重换手率与 5/10/20 bps 成本检验 |
| market_state_performance.R | 05_market_state_performance.R | 当月市场方向、历史波动状态的分组结果 |
| run_asset_pricing.R | 新增 | 建立统一上下文、调用分析、生成审计与运行记录 |

所有文件可以安全 source：只定义函数，不清空工作区、不读取正式数据、不生成输出。五个分析入口也可以独立通过命令行运行。所需 R 包已在现有 renv.lock 中，不新增依赖。

## 输入及时间口径

三份预测宽表均为 `Date,股票1,股票2,...`，分别对应传统因子、网络因子、传统+网络因子。**每个自然月只有一个形成日，必须是收益表或显式日历中该月的首个交易日；预测目标是形成日所在自然月的复合收益。** 不接受日频逐日预测，也不把形成日所在月与下一个月混合。

真实收益也是日期宽表，输入简单日收益率。覆盖率达到阈值后，按该股当月非缺失日收益计算 `prod(1+r)-1`；不足阈值则该股当月不进入组合。默认阈值 80%，月份交易日总数来自收益表日期。说明行应先清理；重复日期、非数值文本、无限值及全天没有任何有效收益会报错。CSV 默认首列视为 Date。

- `--return-units decimal`（默认）：0.01 表示 1%；百分数输入须传 `--return-units percent`。
- `--calendar` 可提供完整交易日历，第一列日期；检查预测月份是否完整覆盖、形成日是否一致。不提供时，只能检查收益表内部的首日，不能证明月末数据没有截断。
- 预测股票与真实收益股票取交集，沿用旧口径；未匹配股票记录在 manifest 中。
- 筛选真实月收益覆盖率使用持有期内信息，属于现有事后评价样本口径，不应直接称为完全可交易的实时回测。

Alpha 使用已经整理为月频的风险因子表：

```csv
year_month,RiskPremium1,SMB1,HML1,RMW1,CMA1
2022-07,-0.00001,0.103812,-0.027377,-0.007685,-0.019409
```

日期列也支持原文件的 `TradingMonth`，值为 `2022年7月`。每月必须唯一。`RiskPremium1` 应是市场风险溢价；这里回归零投资多空收益，不另减一次无风险利率，因此无需额外 RF 列。CAPM、FF3、FF5 沿用五个因子均完整的共同回归样本，不分别改变每个模型规格的月份集合。因子缺失会影响回归样本，实际月份数量记录在 manifest 和回归样本 CSV 中。不能识别或观测不足/共线的回归会明确报错。

**必须显式指定 `--factor-units decimal|percent`，程序不会根据数值大小猜单位。** 日度因子不能直接传入本模块，需先确定其月度构造方法。

## 运行全部分析

在仓库根目录执行，将输入路径替换为已生成的自然月预测与对应数据：

```sh
Rscript R/asset_pricing/run_asset_pricing.R \
  --conventional outputs/predictions/conventional_monthly.csv \
  --network outputs/predictions/network_monthly.csv \
  --enhanced outputs/predictions/enhanced_monthly.csv \
  --returns /path/to/daily_returns.csv \
  --factors /path/to/monthly_factors.csv \
  --factor-units decimal \
  --start-month 2022-04 \
  --sample-mode per_model \
  --output-dir outputs/asset_pricing
```

`--factor-units decimal` 仅在已确认因子为小数时使用。默认预测编码 UTF-8，真实收益和因子编码 GB18030，可分别用 `--prediction-encoding`、`--return-encoding`、`--factor-encoding` 修改。默认输出 CSV 使用 UTF-8。

## 样本规则与配置

用户已确认默认保留旧样本规则：

- `--sample-mode per_model`：各模型按自己的非缺失预测、可匹配股票和合格月收益筛选，再分组；增量收益在共同月份对齐，但两策略持有的股票样本可以不同。
- `--sample-mode common`：在分组前，取三模型共同有效的 Date+stock 键。用于需要控制样本差异的对照，结果可能不同于旧论文。

同一模型形成的组合月份必须连续；缺失月份不会被压缩成相邻月份用于年化、换手或 Newey–West。遇到此情况请选择连续区间或补齐输入。

| 参数 | 默认值 | 含义 |
|---|---|---|
| --start-month / --end-month | 2022-04 / 不限制末月 | YYYY-MM，按形成月份筛选 |
| --n-groups | 10 | 按预测从低到高分组 |
| --min-stocks | 10 | 每模型、每形成日至少的股票数，不能小于组数 |
| --min-month-coverage | 0.8 | 股票月内有效真实收益覆盖率 |
| --nw-lag | 4 | 月频 Newey–West 滞后阶数，prewhite=FALSE |
| --cost-bps | 5,10,20 | 每单位绝对交易权重的成本，基点 |
| --vol-window | 6 | 过去完整月份市场收益的滚动标准差窗口 |
| --no-plots | 默认生成图 | 跳过 PNG 输出 |
| --overwrite | 默认禁止覆盖 | 显式允许覆盖既有同名产物；不允许覆盖输入 |

相同预测值使用 dplyr::ntile；相同分值的组分配沿用输入股票列顺序，不另按股票名打乱或随机打破并列。每组等权，最高组多头权重合计 +1、最低组空头权重合计 −1，多空收益为两组收益之差。

## 单独运行

```sh
Rscript R/asset_pricing/run_asset_pricing.R --help
```

`--analysis` 支持 `all` 或逗号分隔的模块名：portfolio_sorting、long_short_performance、factor_alpha_tests、transaction_cost_tests、market_state_performance。例如只运行组合和成本分析：

```sh
Rscript R/asset_pricing/run_asset_pricing.R \
  --analysis long_short_performance,transaction_cost_tests \
  --conventional outputs/predictions/conventional_monthly.csv \
  --network outputs/predictions/network_monthly.csv \
  --enhanced outputs/predictions/enhanced_monthly.csv \
  --returns /path/to/daily_returns.csv \
  --output-dir outputs/asset_pricing_costs --no-plots
```

不运行 factor_alpha_tests 时无需提供因子文件。直接执行 `Rscript R/asset_pricing/portfolio_sorting.R ...` 也使用相同参数和公共上下文，默认仅运行该分析。

## 保留的统计定义和明确修复

- 分组表的年化收益沿用 `(1+平均月收益)^12-1`；多空绩效表沿用实际月收益连乘后的几何年化。这两个量不完全相同。
- Sharpe 列沿用平均策略月收益 / 月收益标准差 × sqrt(12)，不另减现金利率。
- 交易成本沿用目标权重差：`sum(abs(w_t-w_(t-1)))`，初次建仓以前一期权重 0 计算，初始多空总换手为 2；扣费为 cost_rate × turnover。未计权重价格漂移、融券费、冲击成本或末期强制平仓。
- 换手网格按每个模型自己的形成日期补零，避免某模型没有形成组合的月份被其他模型的日期误当成强制清仓日。
- 当月等权市场收益的正负划分为事后方向状态。波动值用过去完整月份，但高/低阈值沿用全样本波动中位数，仍是事后描述性分组，不能称为实时可知的状态分类。
- **最大回撤修复**：把初始净值 1 纳入峰值序列。旧版首月亏损可能被漏计，修复后的回撤因此可能与旧表不同。
- 因子单位、月频形成日期、重复键、样本连续性和回归可识别性增加了检查；不会用自动猜测或填充方式让不合法输入继续运行。

## 输出与审计

保留原 4_4_1 至 4_4_5 表图文件名，便于对应论文；历史文件名中的“十分组”在非默认分组数下仍保留，但列名和计算采用实际组数。完整回归结果包括 CAPM/FF3/FF5，展示表仍沿用原来的 CAPM/FF3 选择，增量 alpha 表包含三种规格。

此外输出：

- sample_counts.csv：每模型每月筛选后可用股票数与最终进入组合的股票数；被剔除月份记为 0。
- assigned_portfolios.csv：逐股票预测、真实月收益、覆盖率和组号。
- group_returns.csv、long_short_returns.csv：统一上下文的组合收益。
- monthly_factors.csv：Alpha 分析使用的已换算为小数的因子输入。
- manifest.rds：配置、输入 MD5、股票匹配情况、实际组合月份、回归月份数量、R/包版本与统计口径。

输出文件开始运行前检查覆盖风险；若某项分析报错，目录中可能保留此前已完成项目的产物，最终 manifest 只在全部指定分析成功后写出。重新运行建议换一个输出目录，或确认后显式覆盖。

## 验证

```sh
Rscript tests/test_asset_pricing.R .
```

已用 36 个月、20 只股票的合成数据验证五项分析、月收益复合、80% 覆盖率、两种样本模式、多空与成本、单位换算、非法输入和单项 CLI。首月亏损回撤另有精确数值测试；五组配置和 PNG 输出也通过烟雾测试。

与原六脚本对照时，分组统计、多空统计（除明确修正的最大回撤）、增量收益、CAPM/FF3/FF5、增量 alpha、换手和成本、市场状态汇总均在 1e-12 容差内一致。这是相同合成输入下的兼容性验证；未执行正式股票样本，也未验证全新环境恢复。上游网络估计或预测若含前视信息，本模块不会自动消除它。
