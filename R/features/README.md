# 89 个网络特征

2026-11-12 整理。保留原有分工和指标公式，用统一入口完成调用、样本对齐和最终合并。输入直接来自 `R/network/` 导出的逐日矩阵；不读取阶段 `weight_matrix`，也不重新训练网络。

## 模块与来源

| 文件 | 职责 | 原实现 |
|---|---|---|
| compute_new_network_metrics.R | 79 个主体指标：SC 26、NP 15、ND 38 | 同名旧脚本，保留指标计算函数 |
| recompute_final_network_centrality.R | 5 个中心性，已对齐到下一矩阵日期 | 同名旧脚本，保留 measure 公式 |
| add_lagged_network_return_influence.R | 5 个 NWR；合并进指标对象形成 84 个特征 | 同名旧脚本，保留 compute_influence 公式 |
| build_leakage_safe_network_factor_file.R | 对完整历史的 79 指标滞后一次，保留已对齐的 NWR，再选样本 | 同名旧脚本 |
| build_network_features.R | 调用上述模块、验证标签、加入中心性、重命名并校验 89 字段 | 新统一入口 |
| feature_schema.R | 正式字段顺序与四类分组 | 从 create_ablation_feature_files.py 的四个列表逐项提取 |
| feature_dictionary.csv | 89 行字段、分组、计算来源、时间口径 | 与 schema 同序 |
| feature_common.R | 参数、键、矩阵、读写校验及模块加载 | 共用 ../network/network_common.R 的 I/O 校验 |

所有入口都可以 `source()` 后调用函数，不会自动读数据或运行 CLI。单独执行各脚本时使用命名参数；旧中心性与旧滞后脚本的位置参数在本目录统一改为命名参数，可执行 `Rscript 文件 --help` 查看。R 包需求仍是 data.table、igraph 及 base R，现有 renv.lock 已包含，无需新增包。

## 字段分组与输出

| 分组 | 数量 | 组成 |
|---|---:|---|
| SC — Signed Connections | 26 | 有符号连接 |
| NP — Network Position | 20 | 主体位置 15 + 中心性 5 |
| ND — Network Dynamics | 38 | 网络动态 |
| NWR — Network-Weighted Returns | 5 | 网络加权收益 |
| 合计 | 89 | 79 + 5 + 5 |

五个中心性为 net_betweenness、net_harmonic_closeness、net_eigenvector_centrality、net_pagerank、net_local_clustering。

最终 CSV 共 **92 列**：Date、stock、target_return，加按 SC/NP/ND/NWR 排列的 89 个特征。清单和顺序以 feature_schema.R 为准，代码检查缺失、额外和重复特征。没有旧 net_node_* 或 net_new_* 字段。

新流程不再需要运行 finalize_paper_network_features.py：该脚本的字段改名规则已保留，但“删除旧十列”属于历史表迁移，不是新数据生成的前置条件。最终 CSV 的列顺序与旧拼接顺序可能不同，下游应按字段名使用。

## 统一入口

从仓库根目录执行，给三类网络传相同的 returns、sample-keys、calendar、seed，仅替换 matrices 与 output-dir：

```sh
Rscript R/features/build_network_features.R \
  --matrices outputs/network/daily_signed_weight_matrices.rds \
  --returns data/example/科创板中心节点网数据_收益率.csv \
  --sample-keys /path/to/sample_keys.csv \
  --calendar data/example/科创板中心节点网数据_收盘价.csv \
  --expected-days 1210 \
  --output-dir outputs/features/directed \
  --encoding GB18030 --seed 20260922 \
  --keep-intermediates
```

示例收益率只有中心节点网的股票，只有矩阵与样本也属于该节点集合时才可直接使用。全市场网络必须提供覆盖全部样本股票及必要来源收益的全市场收益率表，不要用中心网文件替代全市场输入。

- `--matrices`：ISO 日期命名、严格递增的非空矩阵列表；行来源、列接收者，节点名唯一同序、数值有限、对角线为 0。有向、无向、相关性矩阵均可使用同一入口。
- `--returns`：第一列日期，其余列为股票收益，日期唯一；允许数值缺失，不接受日期说明行或非数值说明文本。默认 GB18030，UTF-8 文件用 `--encoding UTF-8`。若原始下载含说明行，先整理成日期宽表。
- `--sample-keys`：UTF-8 CSV，必须有 Date、stock 且键唯一；输出保留输入行顺序。日期可以用斜杠，输出统一 ISO 格式。仅键表即可，不依赖任何旧网络指标。也可以传已有因子 CSV，程序只读键和可选 target_return；若含标签，会与 returns 当日值核对。
- `--calendar`：可选，第一列为交易日期，采用同一编码。程序检查矩阵范围内的全部交易日，不只检查样本日期。未传时使用收益表日期作为日历。
- `--expected-days 1210`：正式补齐版本的完整性检查；合成测试或有意缩短的研究区间可省略。1210 不作为所有数据的隐式默认。
- `--min-coverage`：默认 0，与旧 NWR 计算一致，取值 [0,1]。
- `--keep-intermediates`：保存 79/84 指标对象、滞后表与中心性表，便于核对；默认只写最终结果和报告。
- 默认拒绝覆盖输出；需要时显式传 `--overwrite`。输入输出同路径即使开启覆盖也会拒绝。

样本键格式，例如：

```csv
Date,stock
2021-04-01,某只股票
2021-04-02,某只股票
```

样本日期必须位于矩阵日期内，股票必须在网络历史中出现；每个样本键必须有有限的真实当日收益作为标签，否则报错。指标因历史长度不足等原因缺失时，保留 NA，不删样本、不补零。程序不会自动替你改变正式样本选择。

## 三类时间口径：只滞后一次

| 特征 | 口径 |
|---|---|
| 79 个主体 | 先在完整矩阵历史上计算滚动、差分和横截面排名，再按每只股票的前一个观测滞后一次，最后与样本键匹配 |
| 5 个中心性 | 第 i 个矩阵产生的中心性标记到第 i+1 个矩阵日期；合并时不再 shift |
| 5 个 NWR | 目标日期 t 使用前一矩阵日期的收益 R[t−1] 和前两个矩阵日期的 W[t−2]；合并时不再 shift |

这里“主体前一个观测”保留旧代码语义；股票中途退出再进入时，不自动改成前一个市场交易日。首次出现、滚动窗口不足、中心性条件不满足等缺失都保留并计入质量报告。完整日历检查防止把缺失矩阵日期误当成相邻交易日。

NWR 还保留以下原始定义：

- 用有效来源股票的绝对入边权重之和作分母，缺失来源收益会触发可用权重重归一化。
- 负边分量使用负边权重的绝对值，所以 net = pos_edges − neg_edges。
- net_return_influence_abs 使用 |收益| 与 |权重|，不是 net 的绝对值。
- coverage 是可用绝对入边权重总和；对称网络未逐列归一化时，它可能大于 1，不应强行当作概率裁剪。

中心性保留旧设定：使用 |W| 的结构网络，活跃节点不足 5 时返回 NA；betweenness 的 cutoff=3、逆权重距离及归一化方式不改动；harmonic 使用入方向且未指定权重；PageRank、特征向量和局部聚类沿用原定义。

主体指标的 Leiden 社区检测涉及随机数，统一入口显式设置并记录 seed。与历史结果逐值对比时需同时控制 seed 和 igraph 版本；本次不声称固定 seed 后能自动复原未记录种子的历史运行。原指标中的异常回退逻辑也保持不变，整列缺失可从报告中发现。

**“leakage_safe”只指这些下游时间对齐操作**。阶段网络若用完整阶段数据估计，其前视信息仍然存在，不能因此声称严格实时预测。

## 输出文件

| 文件 | 内容 |
|---|---|
| network_features.csv | Date、stock、target_return + 89 特征 |
| feature_dictionary.csv | 字段分组、来源和时点 |
| feature_quality.csv | 每个特征缺失数、缺失率、有限值数与取值范围 |
| manifest.rds | 输入指纹、seed、R/包版本、矩阵/样本日期范围、四类数量、未匹配指标/中心性键数、全缺失字段 |
| metrics_79.rds | 可选：主体指标对象，尚未 lag |
| metrics_with_nwr_84.rds | 可选：主体 + 已对齐 NWR |
| lagged_features_84.csv | 可选：已滞后的主体 + 不再滞后的 NWR |
| centrality_5.csv | 可选：已按目标日期对齐的五个中心性 |

manifest 中未匹配中心性键不等于中心性所有缺失：活跃节点不足 5 也会产生 NA，应同时看 feature_quality.csv。所有中间指标计算均使用完整输入历史，不按样本起始日提前裁剪。

## 验证与范围

```sh
Rscript tests/test_features.R .
```

测试覆盖 89 字段/四分组、标签与行序、主体仅 lag 一次、NWR 两级时点、中心性不重复 lag、当日矩阵/收益扰动不改变当日特征、1/2 日短历史、阶段节点缺失、覆盖权重和 CLI 输出检查。

整理时还运行了原五个脚本的完整旧链（含 Python finalize）对照：26 日、6 节点，包含缺失来源收益的 155 行样本，全部 89 个字段缺失位置一致，最大数值差异 5.684342e-14。该验证针对相同 seed 的合成输入；没有运行全部正式 1210 日股票数据，也没有更改历史原始脚本或结果文件。
