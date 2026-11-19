# 当前脚本清单与迁移映射

更新：2026-11-16。下列路径相对于仓库根目录。“已迁入”指有实现和相应验证，不表示已生成正式论文最终结果。原始调查及候选脚本详见[归档清单](archive/final-script-inventory.md)。

| 模块 | 当前主入口 | 原来源 / 当前边界 |
|---|---|---|
| 网络构建 | `R/network/estimate_stage_networks.R` | 默认复用 effects；重建以 rebuild_signed_weight_matrices_from_effects.R 为准，显式 estimate 模式才训练 |
| 无向网络 | `R/network/symmetrize_weights.R` | 原 symmetrize_signed_weight_matrices.R 的职责 |
| 相关网络 | `R/network/build_correlation_network.R` | 原 build_stage_correlation_matrices.R 的职责；完整阶段价格水平相关 |
| 89 项网络特征 | `R/features/build_network_features.R` | 统一主体 79、中心性 5、收益影响 5；不依赖旧十个 net_node 列替换链 |
| 日频预测 | `src/stock_network/prediction/daily_prediction.py` | 原 lightgbm_daily_return_prediction.py；每月重训、每日预测 |
| 自然月预测 | `src/stock_network/prediction/monthly_prediction.py` | 原 lightgbm_sliding_prediction.py 的自然月分支；未迁入 fixed_horizon |
| 两模型评估 | `src/stock_network/evaluation/run_evaluation.py` | 原 evaluate_network_method_comparison.py；共同样本、误差和 IC 差异检验 |
| 月频资产定价 | `R/asset_pricing/run_asset_pricing.R` | 原资产定价 00—05 系列；五项分析统一入口 |
| 实验编排 | `scripts/run_experiment.py` | 新增 JSON 配置入口：多个预测模型与指定配对评估；不执行 R 模块 |
| 合成示例 | `examples/generate_demo.py` | 新增可公开的合成特征、收益、日历与两种频率配置 |

## 公共组件与子模块

- `R/network/network_common.R`：矩阵、日期与参数辅助。
- `R/features/feature_common.R`、`feature_schema.R`、`feature_dictionary.csv`：公共逻辑和正式 89 字段契约；原 compute_new_network_metrics、recompute_final_network_centrality、add_lagged_network_return_influence、build_leakage_safe_network_factor_file 的 R 脚本保留在该目录。
- `prediction/data.py`、`preprocessing.py`、`lightgbm_model.py`、`importance.py`、`cli.py`：拆分原预测脚本的共享功能。
- `evaluation/data.py`、`ic_metrics.py`、`prediction_metrics.py`、`compare_models.py`：数据、相关和误差指标、Newey–West/Holm。
- `R/asset_pricing/common.R`：共享上下文；portfolio_sorting、long_short_performance、factor_alpha_tests、transaction_cost_tests、market_state_performance 为五项分析。
- `tests/`：network、features、asset_pricing 的 R 测试；prediction、evaluation、experiment_runner、demo 的 Python 测试。

## 尚未迁入或未闭合

正式 122 项传统整理表已接入，已有 211 项合并表逐值核对通过；另有 features/merge_features.py 严格键合并入口及可选的 41 项历史收益构建工具。按用户确定的边界，不要求迁入 CSMAR 原始构建。固定 horizon、多算法比较、多轮特征消融调度尚未完整纳入。方向/相关网络已有组件可组合使用，但原对照实验的一键全流程尚未整体迁移。论文 Word、排版、历史探索脚本不属于当前核心流程。

原 N04→N06 的旧中间表依赖不可直接套用新入口；新 features 输出已含 target_return 和统一 89 字段。原 P01 导入 P02 的依赖已拆为包内公共模块。不要将原脚本命令的 --output 路径直接替换为新版要求的 --output-dir。
