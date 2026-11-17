# 输入输出依赖表

核查日期：2026-10-29。脚本编号对应[最终脚本清单](final-script-inventory.md)。本表区分代码中直接存在的调用关系与尚未闭合的数据来源；没有重新运行实验。

## 路径约定与核查范围

下列路径相对原研究项目 `基于idopnetwork的股票数据分析/`，不是本仓库当前已有文件。

| 别名 | 原项目相对路径 / 含义 |
|---|---|
| CODE | code/ |
| EXP | code/实验代码/ |
| RES | results/国泰安数据——创业板/ |
| RAW | data/国泰安数据集/科创板数据/ |
| FEATURES | RES/lightgbm预测收益率/特征数据（加入网络中心性特征）/ |
| DAILY_PRED | RES/lightgbm预测收益率/LightGBM预测收益率——每天(加入网络中心性特征)/ |
| STAGES | RES/网络构建/收盘价_权重矩阵无方向_流通市值/ |

这些是当前脚本的默认值或现有说明中的路径，并非逐文件存在性或内容验证结果。历史目录名中的“无方向”不能替代矩阵方向约定。

## 1. 主流程及未闭合部分

| 步骤 / 脚本 | 主要输入 | 主要输出 | 下游 / 当前确认程度 |
|---|---|---|---|
| 原始数据预处理与阶段网络估计（入口待定） | 价格、市值、分层和阶段定义等，具体文件待确认 | 含 effects 的 results_*.rds 阶段对象 | N01、C02；这是完整复现的首要缺口 |
| N01 重建有向矩阵 | --input-dir（可重复）的阶段 RDS；--calendar 可选 | 默认 CODE/重建权重矩阵/daily_signed_weight_matrices.rds；同名 .validation.csv；可选原始矩阵 | N02、N03、N05、D01；输入接口已确认，正式运行参数待补 |
| N02 网络指标 | --input 逐日矩阵 | --output 指标 RDS，--csv 可选指标表 | N03；对照流水线已确认调用 |
| N03 收益影响 | --matrices 矩阵、--metrics 指标 RDS、--returns 收益宽表 | --output 扩展指标 RDS、--csv CSV | N04；收益影响按 R[t-1] 与 W[t-2] 对齐 |
| N04 滞后和样本对齐 | 位置参数 base_csv、metrics_rds、output_csv | Date、stock 与滞后网络指标，现有对照中为 84 个特征 | D03；输出不含 target_return，也不含旧十个 net_node_* |
| N05 五个中心性 | 位置参数 matrices.rds、output.csv | Date/stock 对齐的五个最终网络中心性 | N06 或 D03 |
| N06 正式列替换 | --base 含十个旧 net_node_* 的表、--centrality 五中心性表 | --output 更新表、--mapping 列名映射 CSV | 正式有向因子候选；base 表来源仍待确认，不能直接接 N04 |
| 传统因子候选入口 | --return-file 收益宽表、--mapping-file 名称映射参考、--downloads-dir 下载数据 | --output 因子 CSV、--dictionary-output 字段说明、--quality-output 质量报告 | N07、P01/P02；最终版本及 122 特征需核实 |
| N07 传统+网络合并 | --traditional、--network；两表同序且包含 Date/stock/target_return | --output 合并特征 CSV | P01/P02；不能视为任意顺序的键连接 |
| P01 日频预测 | --factor-path 因子表，含 target_return | --output 预测宽表；全局/月度重要性及图 | D04、C03；默认预测区间 2022-07-01 至 2026-03-30 |
| P02 自然月预测 | --factor-path；必要时 --target-source 补标签；--target-mode | --output 月初形成日预测宽表及重要性产物（默认模式） | A00–A05；fixed_horizon 是另一模式，应单独配置 |

P01 直接从 P02 导入 cross_sectional_standardize、load_factor_data、make_model、normalize_optional_path、plot_feature_importance、summarize_importance_records。移动或拆分文件时须维护导入关系。

传统因子入口直接导入 calculate_return_factors.py 和 merge_downloaded_fundamental_factors.py。其 Downloads/1、2、3、6 中为财务/分析师 XLSX，4、5 中为融资融券/交易估值 CSV；这些外部下载目录需要配置化并补数据清单。

## 2. 方向性消融：已确认调用链

D01 输入：

| 参数 | 当前默认输入 |
|---|---|
| --directed-matrices | CODE/重建权重矩阵/daily_signed_weight_matrices.rds |
| --returns | RAW/科创板收益率.csv |
| --directed-network | FEATURES/科创板网络因子.csv |
| --directed-combined | FEATURES/科创板传统因子+网络因子.csv |
| --output-dir | CODE/outputs/directionality_ablation/ |
| --method | mean；支持 sum、max_abs |

以下输出均位于 --output-dir：

| 顺序 | 调用 | 输出 |
|---|---|---|
| 1 | D02 | undirected_signed_weight_matrices_mean.rds（后缀随 method 变化） |
| 2 | N02 | undirected_network_metrics.rds / .csv |
| 3 | N03 | undirected_metrics_with_return_influence.rds / .csv |
| 4 | N04 | undirected_network_features_safe_84.csv |
| 5 | N05 | undirected_centrality_5.csv |
| 6 | D03 | 科创板无向网络因子_89.csv；科创板传统因子+无向网络因子.csv |

D03 还读取原有向特征表，以保持样本、标签及传统特征一致。因此这一流程不是从原始数据独立生成所有输入。

D01 在第 6 步结束。随后需要分别用 P01 生成无向网络与传统+无向网络的日收益率预测，再运行 D04。已有有向预测也必须使用一致口径。

D04 参数为 --directed、--undirected、--truth、--output-dir，默认 --nw-lag=5。输出 model_summary.csv、daily_metrics.csv、daily_directed_minus_undirected.csv、newey_west_tests.csv。完整实验命令与配置尚需从正式运行记录补齐。

## 3. 相关网络基准：已确认调用链

C01 额外输入为 STAGES 阶段目录、RAW 价格目录、科创板收盘价_平均流通市值最大股票.csv、科创板收盘价.csv、收益率名称参考，以及原有向两套特征表。默认方法 pearson，稀疏化 density_match。

代码默认 stage-dir 只有 STAGES 一个目录，虽然参数帮助文字提及 main plus supplement；发布时以正式运行配置为准，不应根据帮助文字额外假设目录。

| 顺序 | 调用 | 默认输出目录 CODE/outputs/correlation_network_benchmark/ 下的文件 |
|---|---|---|
| 1 | C02 | stage_static_close_correlation_matrices.rds |
| 2 | N02 | correlation_network_metrics.rds / .csv |
| 3 | N03 | correlation_metrics_with_return_influence.rds / .csv |
| 4 | N04 | correlation_network_features_safe_84.csv |
| 5 | N05 | correlation_centrality_5.csv |
| 6 | D03 | 科创板相关性网络因子_89.csv；科创板传统因子+相关性网络因子.csv |
| 7 | P01，各运行一次 | predictions/相关性网络因子_日收益率预测.csv；predictions/传统因子+相关性网络因子_日收益率预测.csv，及重要性文件 |
| 8 | C03，各运行一次 | evaluation_network_only/ 与 evaluation_traditional_plus_network/ |

第 8 步还依赖已有 DAILY_PRED/科创板_网络因子_日收益率预测.csv 和 DAILY_PRED/科创板_传统因子+网络因子_日收益率预测.csv；C01 不会生成这两份 Idop 基准预测。

每个评价目录输出 model_summary.csv、daily_metrics.csv、daily_method_differences.csv、newey_west_tests.csv、common_sample_panel.csv。传 --features-only 会在第 6 步结束。

两个对照特征流水线均检查已有输出并拒绝覆盖；重跑需指定新的输出目录。不要把拒绝覆盖误认为计算失败。

## 4. 月频资产定价：共享输入与独立分析

A00 默认预测目录为 CODE/4.4实验，可由环境变量 EXPERIMENT_4_4_PREDICTION_DIR 覆盖。读取：

- 科创板下一自然月收益率预测_LightGBM_传统因子.csv
- 科创板下一自然月收益率预测_LightGBM_网络因子.csv
- 科创板下一自然月收益率预测_LightGBM_传统因子+网络因子.csv

共享真实收益输入是 RAW/科创板收益率.csv；风险因子输入为 RES/模型评价/factors_filtered.csv。默认输出目录为 CODE/4.4实验/结果_自然月_修正真实收益率，可由 EXPERIMENT_4_4_OUT_DIR 覆盖。这些默认目录的有效性及正式运行时的环境变量值待核实。

| 脚本 | 主要直接输入 | 主要输出（相对 OUT_DIR） |
|---|---|---|
| A01 | 三套月频预测、真实日收益 | 4_4_1_Table_Returns_of_Portfolios_Sorted_by_Predicted_Returns.csv；十分组收益及图 |
| A02 | 同上，通过 A00 构建组合 | 4_4_2_Table_Long_Short_Portfolio_Performance.csv；增量检验、累计收益及图 |
| A03 | 同上，另需风险因子 | 4_4_3_Table_Risk_Adjusted_Performance.csv；4_4_3_Table_Incremental_Risk_Adjusted_Performance.csv；CAPM/FF3/FF5 明细 |
| A04 | 月频预测、真实收益及公共组合逻辑 | 4_4_4_Table_Transaction_Cost_Test.csv；换手率与净收益明细 |
| A05 | 月频预测、真实收益及公共状态划分逻辑 | 4_4_5_Table_Market_State_Performance.csv；状态样本 |

01–05 是分析编号，不表示这些脚本必须依次消费前一步生成的 CSV。日频对照的预测文件不能直接替换这里的自然月预测文件。

## 5. 数据契约与复现核验

| 对象 | 当前可确认约定 | 尚需验证 |
|---|---|---|
| 权重矩阵 | 日期命名的矩阵列表；行来源、列接收者；有向带符号 | 日期覆盖、节点名称、分层合并及阶段生成来源 |
| 特征表 | Date + stock 键；最终预测表含 target_return | 键唯一性、实际特征数、股票名映射、目标收益单位 |
| N04 中间表 | 仅样本键及特征；拓扑按股票前一观测滞后 | 缺失交易日下前一观测与前一市场交易日的差异 |
| 预测/真实收益宽表 | 日期和股票列 | 频率、日期含义、列名映射、收益率单位、缺失值 |
| 字符编码 | 部分原始收益读取 GBK/GB18030；许多生成 CSV 使用 UTF-8 BOM | 发布版明确每类文件编码，避免全局替换 |

阶段内使用完整数据的前视限制详见根 README；“safe”脚本名仅描述特征对齐处理，不构成整个估计链无泄漏的保证。

## 6. 建议的执行边界

第一版可先验证“给定阶段 RDS + 已有基表”的网络重建与对照流程；必须明确这是条件复现。原始数据到阶段 RDS、有向最终特征的完整来源、传统因子版本及月频正式配置闭合后，才能宣称原始数据到论文结果的端到端复现。
