# 结果与分析内容索引

本表按实际分析内容组织，不声称它就是论文最终表号。论文最终稿及表号待作者提供后填写。

| 分析 | 已发布结果位置（相对 results/） | 范围 |
|---|---|---|
| 日频传统/网络/合并预测 | formal_20261117_daily/prediction/ | 907日，三模型 |
| 日频增量评价 | formal_20261117_daily/evaluation/ | 两配对共同样本；Rank IC、误差及NW/Holm |
| 月频预测 | formal_20261117_monthly/prediction/ | 47个月；形成月收益 |
| 月频预测评价 | formal_20261117_monthly/evaluation/ | 两配对，47个月 |
| 预测排序组合 | formal_20261117_monthly/asset_pricing/4_4_1_Table_Returns_of_Portfolios_Sorted_by_Predicted_Returns.csv | 十分组 |
| 多空绩效 | formal_20261117_monthly/asset_pricing/4_4_2_Table_Long_Short_Portfolio_Performance.csv | 47个月 |
| 风险调整收益 | formal_20261117_monthly/asset_pricing/4_4_3_CAPM_FF3_FF5_完整回归结果.csv | 44个月；三种规格完整结果 |
| 增量Alpha | formal_20261117_monthly/asset_pricing/4_4_3_Table_Incremental_Risk_Adjusted_Performance.csv | 合并减传统 |
| 交易成本 | formal_20261117_monthly/asset_pricing/4_4_4_Table_Transaction_Cost_Test.csv | 5/10/20bps |
| 市场状态 | formal_20261117_monthly/asset_pricing/4_4_5_Table_Market_State_Performance.csv | 回顾性分组 |
| 共同样本稳健性 | formal_20261117_monthly/asset_pricing_common/ROBUSTNESS_REPORT.md | 三模型各25435股票月 |
| 无向、相关网络对照 | network_benchmarks_20261119/REPORT.md | 四模型重训、四配对评价；保存特征输入 |
| 月频旧预测逐值核查 | monthly_legacy_check/comparison.json | 三模型47月、602列，缺失一致，最大差约1e-16 |

4_4_* 是原脚本产物编号，不据此断言论文最终章节号。三份主要报告给出解释与限制；release-files.json 是发布副本的校验清单。完整运行的私有中间样本保留在本机 outputs，未分发。
