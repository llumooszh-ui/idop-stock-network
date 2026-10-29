# 最终脚本清单：已确认职责与待核实版本

核查日期：2026-10-29。依据：源文件的参数、读写、导入与调用关系，以及两个既有实验 README。仅静态核查，未运行实验。

这里的“确认纳入”表示职责和依赖明确、建议迁入发布版；不代表已证明该文件生成了论文最终结果。原文件名暂时保留，迁移时再统一目录，避免先重命名导致依赖断裂。

源路径缩写：

- `E/` = 原项目 `基于idopnetwork的股票数据分析/code/实验代码/`。
- `A/` = 原项目 `基于idopnetwork的股票数据分析/code/资产定价代码/`。
- 原项目根目录 = `/Users/lumos/Desktop/IdopNetwork`。

## 1. 确认纳入：网络重建和特征公共组件

| 编号 | 源文件 | 已确认职责 | 迁移注意事项 |
|---|---|---|---|
| N01 | E/rebuild_signed_weight_matrices_from_effects.R | 阶段 effects → 合并的逐日有向带符号矩阵及验证表 | 保留方向、列 L1 归一化、日期对齐参数；阶段输入来源待锁定 |
| N02 | E/compute_new_network_metrics.R | 从逐日矩阵计算网络指标，输出 RDS/CSV | 两个对照流水线均直接调用 |
| N03 | E/add_lagged_network_return_influence.R | 添加滞后收益影响指标 | 同时依赖矩阵、指标对象、真实收益率 |
| N04 | E/build_leakage_safe_network_factor_file.R | 按股票滞后拓扑指标，再对齐指定基表的样本键 | 只读基表 Date/stock；输出不带 target_return；不能作为最终预测表直接使用 |
| N05 | E/recompute_final_network_centrality.R | 重算最终矩阵的五个中心性特征 | 输出为滞后中心性表；被两个对照流水线调用 |
| N06 | E/finalize_paper_network_features.py | 删除十个旧 net_node_* 列，加入五个中心性，统一字段名 | 输入必须包含十个旧列；不是将 N04 输出直接转换为最终表的通用入口 |
| N07 | E/merge_traditional_network_features.py | 合并传统与网络特征 | 输入必须按行对齐；共享字段严格为 Date、stock、target_return |

## 2. 确认纳入：预测与对照实验

| 编号 | 源文件 | 已确认职责 | 必须保留的依赖或区别 |
|---|---|---|---|
| P01 | E/lightgbm_daily_return_prediction.py | 每月重训、逐日预测当日单交易日收益 | 导入 P02 的六个公共函数；实际默认因子路径为网络因子，不能仅依赖文件头说明 |
| P02 | E/lightgbm_sliding_prediction.py | 默认自然月收益率预测；兼容 fixed_horizon | 同时为 P01 提供工具函数；需区分模式与标签 |
| D01 | E/run_directionality_ablation_pipeline.py | 生成无向 89 特征表及传统+无向特征表 | 只构建特征，不自动训练和评价 |
| D02 | E/symmetrize_signed_weight_matrices.R | 对称化有向矩阵 | mean/sum/max_abs；现有说明采用 mean |
| D03 | E/assemble_directionality_ablation_features.py | 合并 84 特征和 5 中心性，对齐原有向样本和标签 | 名称虽含 directionality，也被相关网络流水线复用 |
| D04 | E/evaluate_directionality_ablation.py | 同一非缺失样本上的有向/无向预测比较 | 日收益率评价；需要两套已有预测与真实收益 |
| C01 | E/run_correlation_network_benchmark.py | 相关网络构建、特征、日频预测和评价编排 | 依赖既有有向特征表和 Idop 预测；features-only 可只生成特征 |
| C02 | E/build_stage_correlation_matrices.R | 按 Idop 阶段和节点集合生成相关矩阵 | 阶段 RDS、价格与名称参考；完整阶段收盘价相关性 |
| C03 | E/evaluate_network_method_comparison.py | 两种网络预测的共同样本评价 | 输出指标、逐日差异、Newey-West 检验及共同样本 |

## 3. 确认纳入：资产定价模块

| 编号 | 源文件 | 职责 |
|---|---|---|
| A00 | A/00_common_4_4.R | 共享路径、预测读取、真实月收益构造、组合和风险因子处理 |
| A01 | A/01_portfolio_sorting_analysis.R | 预测排序与十分组收益 |
| A02 | A/02_long_short_portfolio_performance.R | 多空绩效、增量检验与累计收益 |
| A03 | A/03_capm_ff3_alpha_tests.R | 风险调整收益；实际输出含 CAPM、FF3、FF5，不能只按文件名理解 |
| A04 | A/04_transaction_cost_tests.R | 换手率及交易成本调整 |
| A05 | A/05_market_state_performance.R | 不同市场状态下组合表现 |

A01–A05 均直接 source A00；没有证据表明必须依次读取前一脚本输出。公共模块目前默认读取三套自然月 LightGBM 预测。迁移时须修改绝对 source 路径和数据路径。实际使用的预测目录、风险因子版本以及论文表图编号仍需锁定。

## 4. 候选纳入：功能明确，但最终数据版本未闭合

| 源文件 | 判断 | 待确认内容 |
|---|---|---|
| E/build_traditional_factor_dataset_20210401.py | 传统因子候选主入口 | 输出是否就是最终 122 个传统特征的来源；下载文件版本和样本筛选 |
| E/calculate_return_factors.py | 上述入口直接导入的辅助模块 | 随入口保留，核对收益率单位及历史窗口 |
| E/merge_downloaded_fundamental_factors.py | 上述入口直接导入的辅助模块 | 随入口保留，补充 Downloads/1–6 数据来源映射 |
| E/idop_dynamic_network.R、E/R_idop_stock.R | 网络方法相关候选 | 尚不能认定为最终 22 层阶段 RDS 的唯一生成入口 |
| E/return_calculate.R、E/return_calculate_adsiht.R、E/return_melt.R | 存在阶段结果生成/汇总代码 | 含特定类别、本机或服务器路径；需追溯最终阶段数据来源 |
| E/ridge_sliding_prediction.py、E/elasticnet_sliding_prediction.py、E/historical_mean_sliding_prediction.py | 候选模型比较脚本 | 未在本次核查中逐一验证接口；是否属于最终论文主表待确认 |
| E/train_multi_horizon_models.py、E/multi_horizon_prediction_evaluation.R | 候选多期限实验 | 最终期限、样本和结果版本待确认 |
| E/create_ablation_feature_files.py、E/create_nd_round1_feature_files.py、E/return_vs_nd_round1_common_sample.R、E/return_vs_nd_round2_common_sample.R、E/return_vs_nd_round3_common_sample.R | 多轮特征消融候选 | 不能仅凭 round3 或修改日期判断最终版本 |

## 5. 暂不放入核心复现链

论文 Word 生成、文字改写、附录排版和流程图脚本可单独归入 tools/manuscript；旧网络绘图和探索脚本需按最终图号挑选。缓存、环境目录、大型矩阵及中间结果不属于脚本清单。暂不纳入不等于删除原文件。

## 6. 发布前必须闭合的事项

- [ ] 阶段网络 RDS 的生成脚本、分层定义、阶段边界和参数。
- [ ] 正式有向 89 特征表的完整生成链：样本键、标签、旧列替换和字段映射。
- [ ] 传统 122 特征与正式合并表的实际表头和共同样本。
- [ ] 主预测、日频对照与月频资产定价分别对应哪些论文表图。
- [ ] 固定依赖、随机种子、命令参数、输入版本及运行日志。
- [ ] 统一路径并验证小型示例，随后再认定“最终可复现版本”。
