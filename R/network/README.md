# 网络构建与 effects 重建

更新：2026-11-12。这个模块提供三类网络的构建入口，并保留历史训练结果的重用路径。默认不重新训练。

## 文件与运行边界

| 文件 | 职责 |
|---|---|
| estimate_stage_networks.R | `rebuild` 模式从已有阶段 effects 重建逐日矩阵；`estimate` 模式显式执行训练，再用同一重建逻辑导出矩阵 |
| symmetrize_weights.R | 对已有逐日有向矩阵执行 mean / sum / max_abs 对称化 |
| build_correlation_network.R | 按已有阶段边界、节点和价格构建相关性网络并按日合并 |
| network_common.R | 日期、节点、数据对齐、输入输出及矩阵校验；不是运行入口 |

三个入口均可被 `source()` 安全加载，不会清空工作区或自动运行正式实验。命令从仓库根目录执行。恢复依赖见根 README；已有 effects 重建与两个对照入口只需要 base R，重新估计才加载 deSolve、Matrix、orthopolynom、ADSIHT、SGL、grpreg、glmnet 和 R 自带的 splines。

## 1. 重用历史训练结果：无需重新训练

```sh
Rscript R/network/estimate_stage_networks.R \
  --mode rebuild \
  --input-dir /path/to/existing/stages \
  --calendar data/example/科创板中心节点网数据_收盘价.csv \
  --output outputs/network/daily_signed_weight_matrices.rds
```

将 `/path/to/existing/stages` 替换为自己的阶段 RDS 目录。默认读取 `results_*.rds`；`--input-dir` 可以重复指定。也可重复使用 `--input-rds /path/to/results_layer.rds` 指定文件。重复层文件名会报错，避免重复计权或静默替换。输入阶段文件不会被修改。

历史脚本 `tradition_evl.R` 现在直接读取最终矩阵；实际 effects 重建规则来自原 `rebuild_signed_weight_matrices_from_effects.R`。本模块按用户确认保留其数值口径：

1. `effects[[j]][t,i]` 是 i 对接收者 j 的效应，导出 `W[t][i,j]`，行来源、列接收者。
2. 去掉对角线，保留非对角效应的正负号。
3. 每层按列绝对值之和归一化。
4. 按股票名称合并各层，同方向效应相加。
5. 合并后再次进行列 L1 归一化，非空列绝对值之和为 1。

默认 `--zero-tol 0`，与旧重建脚本一致，不截断极小原始 effects。非有限 effect 沿用旧逻辑置零。下游拓扑分析使用的阈值、绝对值图权重不是这里的矩阵定义，不迁入基础重建步骤。

### 日期对齐

默认 `--alignment strict`：阶段交易日数必须与 effects 行数一致。新训练的阶段同时保存逐行 `dates`。不按自然日补齐，不通过删掉收益率前若干行来对齐。

旧重建脚本默认 tail；为避免新数据悄悄错位，本模块改成严格模式。**只有确认某历史阶段按尾部对齐后**，才显式追加 `--alignment tail`；也支持 head。该选择写入报告并在不匹配时发出警告。head/tail 会改变所覆盖的日期，不能据此直接宣称与全阶段相关性基准日期一致。

输出：日期命名的矩阵列表，以及同路径追加 `.validation.csv` 的阶段校验报告、`.metadata.rds` 的配置与输入 MD5 记录。默认拒绝覆盖已有文件；需要时显式传 `--overwrite`，即使如此也禁止输出覆盖输入。

## 2. 仅在需要时估计新的阶段网络

```sh
Rscript R/network/estimate_stage_networks.R \
  --mode estimate \
  --prices data/example/科创板中心节点网数据_收盘价.csv \
  --returns data/example/科创板中心节点网数据_收益率.csv \
  --encoding GB18030 \
  --stage-output outputs/stages/results_center.rds \
  --output outputs/network/center_daily_signed.rds \
  --seed 20260922 --M 3 --basis-type poly
```

这条命令会重新估计输入数据；现有示例文件有 1,210 个交易日、23 个节点，并非小型烟雾测试，请勿为验证安装而运行正式样本。

输入第一列为日期，其余列为唯一股票名的数值列；可以缺失价格以表达股票尚不可用，但不接受说明行、非法日期、重复日期、无限值或非数值文本。默认编码 GB18030（当前示例编码）；UTF-8 文件传 `--encoding UTF-8`。日期及股票名会显式匹配，收益率可以有额外日期/股票，但不能缺少价格表所需的键；被估计阶段内的收益率必须有限。

按价格节点可用集合变化划分阶段，保留原模型 ADSIHT → SGL → Group Lasso → Ridge 的选择顺序、系数与 effects 计算方式。没有为了修复工程问题重写模型或调整正则化策略。随机种子、最终方法、lambda、基函数配置记录在每阶段 `result$estimation` 中。

少于 2 个节点，或少于 `max(4, M+1)` 行的阶段默认报错，不自动合并阶段。确需跳过时显式传 `--short-stage skip`，所有遗漏会写入 `--stage-output` 后缀 `.audit.csv`。恒定价格或非有限阶段输入会报错。改变阶段筛选或兜底算法的统计口径需要另行确定。

阶段 RDS 是列表，每个阶段至少含 `stage/start_date/end_date/stocks/result$effects`；新估计还保存 `dates` 和参数。为避免混淆：

- `result$weight_matrix` 与 `calculated_returns` 保留历史 abs 诊断含义，包括旧自效应归一化方式；它们不是正式有向带符号输出，也不是样本外预测。
- `result$signed_weight_matrix` 为从 effects 导出的阶段带符号矩阵。
- `--output` 文件是下游应使用的最终逐日矩阵。不要把整个阶段 RDS 直接传给无向化入口。

## 3. 无向消融

```sh
Rscript R/network/symmetrize_weights.R \
  --input outputs/network/daily_signed_weight_matrices.rds \
  --output outputs/network/undirected_mean.rds --method mean
```

默认 `U=(W+t(W))/2`，反号效应可能抵消。不做破坏对称性的逐列重新归一化。还支持 sum、max_abs；max_abs 绝对值相等时沿用节点顺序中上三角方向的符号。节点名/顺序、日期唯一且递增、方阵及有限值均会校验。

## 4. 相关性网络

```sh
Rscript R/network/build_correlation_network.R \
  --input-dir /path/to/existing/stages \
  --prices /path/to/prices_with_all_stage_stocks.csv \
  --calendar data/example/科创板中心节点网数据_收盘价.csv \
  --output outputs/network/correlation.rds \
  --method pearson --sparsify density_match
```

`--prices` 应覆盖所有阶段节点及阶段交易日；缺节点、缺日期、重复层、同层阶段重叠都会报错。沿用旧脚本的多编码读取方式，读取警告导致的截断数据不再被接受。缺值按 pairwise correlation 处理，默认每个节点至少 3 个有限观测；某些节点对观测不足或方差为零仍可能形成零边，应查看审计表。

也可沿用行业文件模式，用 `--price-dir` 与 `--big-prices` 替换 `--prices`；该模式保留旧文件名约定 `results_数字类...rds`、`科创板数字类数据_收盘价.csv`，大网 RDS 文件名需包含“大网”。代码表补充价格仍通过配对的 `--all-prices` 和 `--name-reference` 提供。

默认按原邻接矩阵有向边数的一半（取整）匹配无向边预算；审计报告同时记录原始有向边数、目标与实际相关边数。有效相关边不足时实际数量可以低于预算，不能省略审计。每层及合并后按平均非零节点强度统一缩放，保持对称性。

**统计限制仍保留**：使用完整阶段价格估计相关性，并在阶段内复用，属于阶段解释性比较；本次没有改成实时滚动估计，也不声称消除网络估计本身的前视信息。

## 验证

```sh
# 仅 base R：接口、符号、日期、节点、归一化、防覆盖及三条 CLI
Rscript tests/test_network.R .
# 额外用 12 行 × 2 节点验证训练及重新读取 effects 的一致性
Rscript tests/test_network.R . --with-estimation
```