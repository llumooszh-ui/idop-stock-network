# 正式网络对照：迁移后预测与评价复现

完成日期：2026-11-19。四个对照模型均重新训练，沿用日频45个月扩展窗口、2022-07-01—2026-03-30、80棵树及原默认超参数；每组与已复现的有向模型按共同股票—日期样本比较。

## 输入与验证边界

- 四张已有特征表均607633行；网络89项、合并211项；主键、标签及122项传统列与有向基准一致。
- 无向保存矩阵1210日，与有向矩阵的带符号均值对称化逐值一致，最大差为0；不再列归一化。
- 相关保存矩阵1210日，节点/日期一致、对称、无自环、有限值。历史审计有22层、411阶段，全部满足边数目标。
- 相关基准为完整阶段收盘价水平Pearson相关、density_match；这次读取历史构建记录及保存矩阵，没有重新由原始价格计算所有相关矩阵。
- 本次复用已保存89/211项特征，不重新生成完整特征。因此完成的是正式保存输入的审计及预测/评价复现，上游完整重建仍为独立待办。

## 排序与误差结果

| 对照 | 模型 | 共同观测 | 日均 Rank IC | ICIR（未年化） | MSE | MAE |
|---|---|---:|---:|---:|---:|---:|
| undirected_network | idop_network | 501823 | 0.066236 | 0.739465 | 0.00118252 | 0.023600 |
| undirected_network | undirected_network | 501823 | 0.024728 | 0.287347 | 0.00120021 | 0.023793 |
| undirected_combined | idop_combined | 501866 | 0.075058 | 0.846961 | 0.00117060 | 0.023472 |
| undirected_combined | undirected_combined | 501866 | 0.029966 | 0.352917 | 0.00119440 | 0.023708 |
| correlation_network | idop_network | 501823 | 0.066236 | 0.739465 | 0.00118252 | 0.023600 |
| correlation_network | correlation_network | 501823 | 0.039627 | 0.360261 | 0.00120064 | 0.023715 |
| correlation_combined | idop_combined | 501866 | 0.075058 | 0.846961 | 0.00117060 | 0.023472 |
| correlation_combined | correlation_combined | 501866 | 0.050777 | 0.495478 | 0.00119155 | 0.023623 |

## 有向相对对照的改善

| 对照 | 指标 | 逐日平均改善 | Holm p |
|---|---|---:|---:|
| undirected_network | rank_ic_gain_a | 0.04150763 | 1.93369e-32 |
| undirected_network | mse_reduction_a | 0.00001715 | 0.0879424 |
| undirected_network | mae_reduction_a | 0.00019184 | 0.0879424 |
| undirected_combined | rank_ic_gain_a | 0.04509208 | 7.67136e-43 |
| undirected_combined | mse_reduction_a | 0.00002331 | 0.00165048 |
| undirected_combined | mae_reduction_a | 0.00023448 | 0.00935036 |
| correlation_network | rank_ic_gain_a | 0.02660939 | 1.26953e-09 |
| correlation_network | mse_reduction_a | 0.00001746 | 0.0386007 |
| correlation_network | mae_reduction_a | 0.00011199 | 0.232993 |
| correlation_combined | rank_ic_gain_a | 0.02428055 | 1.63263e-07 |
| correlation_combined | mse_reduction_a | 0.00002059 | 0.000710645 |
| correlation_combined | mae_reduction_a | 0.00015137 | 0.0513624 |

Rank IC 改善为有向−对照；MSE/MAE 改善为对照−有向。Newey–West lag=5，Holm 在每组3项检验内校正，没有对四组全部12项检验合并校正。误差检验按日等权，汇总误差按全部股票日观测计算。

## 与旧预测比较

| 模型 | 缺失位置一致 | 最大绝对差 |
|---|---|---:|
| undirected_network | True | 0.00651411 |
| undirected_combined | True | 1.62499e-07 |
| correlation_network | True | 4.44358e-09 |
| correlation_combined | True | 0.00211523 |

## 解释与限制

只能在已定义的带符号均值对称化和阶段静态相关基准下解释有向网络的增量。两种阶段估计都使用完整阶段信息，相关基准使用价格水平；因此不能据此宣称严格实时无前视预测。保存特征的缺失和无穷统计见 input_audit.json，无穷按既有预测规则转为缺失。

本次不包含月频对照资产定价、其他对称化规则或上游特征全量重算。原始数据和历史结果未修改。

## 线程数差异核查

本次四个对照模型及已复现的有向基准均使用 n_jobs=4；旧脚本默认 n_jobs=-1。固定随机种子不保证不同线程配置下逐位相同。

无向单独模型最大差异位于2025-10。用原脚本同一输入复测：4线程对本次预测最大差约1e-16，而全部线程对旧预测最大差约1e-16，确认该月份的差异由线程配置触发，并非迁移公式改变。
相关合并模型最大差异月份为 2026-01；同样的原脚本线程探针详见 correlation_thread_probe.json。
- n_jobs=4：相对旧预测最大差 0.0021152257，相对本次预测最大差 9.996344e-17。
- n_jobs=-1：相对旧预测最大差 9.996344e-17，相对本次预测最大差 0.0021152257。

其余微小差异未逐月归因；不宣称四模型与旧文件逐值完全一致。统一4线程后，四组有向 Rank IC 优势仍显著。无向单独模型误差优势校正后不显著；无向合并模型两项误差优势显著。相关基准的MSE优势显著，MAE优势未达到5%校正阈值。
