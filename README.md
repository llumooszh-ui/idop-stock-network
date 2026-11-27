# idop-stock-network

基于 **idopNetwork 的股票动态网络分析与收益率预测研究**。项目以科创板股票为主要实证对象，将股票之间带方向、带符号的网络关系转化为特征，研究这些关系能否在传统因子之外提供增量预测信息，并通过投资组合和风险调整收益检验其经济意义。

仓库包含网络构建、特征计算、LightGBM 预测、预测评价和资产定价分析代码，以及合成示例、环境依赖、测试和已发布的实验结果。

## 研究设计

项目围绕三个问题展开：

1. 股票网络关系能否帮助预测股票收益率？
2. 网络特征与传统因子结合，能否改善预测排序和投资组合表现？
3. 网络的方向性及其构建方式是否重要？

预测实验采用相同模型框架比较三类输入，并以无向网络和相关性网络进行对照：

| 模型 | 输入特征 | 数量 |
|---|---|---:|
| 传统因子模型 | 已整理的 CSMAR 传统因子 | 122 |
| 网络因子模型 | 由股票网络提取的网络特征 | 89 |
| 组合模型 | 传统因子与网络特征 | 211 |

## 分析流程

```text
股票价格 / 已有阶段 effects
          │
          ▼
阶段网络估计与逐日有向、带符号权重矩阵
          │
          ├── 无向网络对照：带符号权重均值对称化
          └── 相关网络对照：完整阶段收盘价 Pearson 相关
          │
          ▼
89 项网络特征 ────── 已整理的 122 项传统因子
          │                    │
          └─────────┬──────────┘
                    ▼
           样本对齐与特征合并
                    │
                    ▼
     LightGBM：日收益率 / 自然月收益率预测
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
   预测排序与误差评价      月频组合与资产定价检验
```

**网络构建。** 支持估计阶段网络，也支持直接从已有 effects 重建逐日矩阵。矩阵 `W[t][i,j]` 表示股票 i 对股票 j 的影响，行是来源，列是接收者。有向矩阵去除自环、保留符号，逐层列 L1 归一化后合并，再进行列 L1 归一化。无向对照采用 `(W + Wᵀ) / 2`，相关网络按网络密度匹配构建。

**网络特征。** 89 项指标由主体指标、中心性和网络加权收益共同生成，最终分为四类：

| 类别 | 含义 | 数量 |
|---|---|---:|
| SC | 有符号连接 | 26 |
| NP | 网络位置，含 5 项中心性 | 20 |
| ND | 网络动态 | 38 |
| NWR | 网络加权收益 | 5 |

特征模块统一处理滞后、样本对齐和字段命名；预测模块使用处理后的特征表。具体时间口径见 [网络特征说明](R/features/README.md)。

**收益率预测。** 两条流程使用扩展训练窗口，分别保存预测与评价结果：

| 流程 | 预测目标 | 训练与预测方式 |
|---|---|---|
| 日频 | 当日单交易日收益率 | 每个自然月重新训练，逐日预测；输入特征已在上游滞后 |
| 月频 | 月初形成组合所对应自然月的复合收益率 | 使用此前完整月份训练，月初预测 |

**评价与资产定价。** 预测评价在模型间共同有效样本上计算 IC、Rank IC、MSE、RMSE 和 MAE，并进行差异检验。资产定价模块提供收益率分组、多空组合、FF5 Alpha、交易成本和市场状态分析，默认保留各模型自身有效股票样本，另提供共同样本选项。

## 项目结构

| 目录 | 职责与使用说明 |
|---|---|
| [`R/network/`](R/network/README.md) | 阶段网络估计、effects 重建、无向与相关网络构建 |
| [`R/features/`](R/features/README.md) | 89 项网络特征计算、滞后与统一输出 |
| [`R/asset_pricing/`](R/asset_pricing/README.md) | 月频组合、风险调整收益与稳健性检验 |
| [`src/stock_network/features/`](src/stock_network/features/README.md) | 整理好的传统因子接入与特征合并 |
| [`src/stock_network/prediction/`](src/stock_network/prediction/README.md) | LightGBM 日频与月频预测 |
| [`src/stock_network/evaluation/`](src/stock_network/evaluation/README.md) | 共同样本预测评价与统计检验 |
| [`scripts/`](scripts/README.md) | 配置驱动的预测与评价实验入口 |
| [`examples/`](examples/README.md) | 无需商业数据的合成示例 |
| [`tests/`](tests/) | Python 与 R 模块测试 |
| [`results/`](results/README.md) | 已发布的实验报告和分析产物 |
| [`docs/`](docs/README.md) | 数据接入、复现指南、脚本依赖和验证记录 |

## 快速开始

以下命令在仓库根目录执行。Python 依赖版本记录于 [requirements.txt](requirements.txt)，对应的参考环境为 Python 3.9.6。

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt

python examples/generate_demo.py --output-dir outputs/demo
python scripts/run_experiment.py --config outputs/demo/configs/daily.json
python scripts/run_experiment.py --config outputs/demo/configs/monthly.json
```

结果写入 `outputs/demo/runs/daily/` 和 `outputs/demo/runs/monthly/`，包含预测、特征重要性、模型比较及运行记录。重复运行请使用新的输出目录。

合成示例仅演示 Python 预测与评价流程，使用少量模拟特征，不包含正式 89 项特征计算、网络估计或 R 资产定价。详细说明见 [examples](examples/README.md)。

运行 R 模块时，建议使用 R 4.5.1，在仓库根目录的 R 会话中恢复依赖：

```r
install.packages("renv", repos = "https://cloud.r-project.org")
renv::restore(lockfile = "renv.lock", prompt = FALSE)
```

[renv.lock](renv.lock) 记录 R 包版本，不包含 R 本身及操作系统编译库。各 R 模块的输入和运行命令见对应目录说明。

## 使用正式数据

正式流程直接接收已整理的 **122 项传统因子表**，无需重新生成原始 CSMAR 因子。网络特征可通过 R 模块计算，也可接入已有的 89 项特征表；合并时严格核对 `Date`、`stock` 主键、目标收益率和特征字段。

原始商业数据、大型中间矩阵和本机运行目录不随仓库分发。使用正式数据时，需要自行准备有权使用的数据并配置本地路径；已发布结果中的配置用于记录参数，不能原样作为数据下载或运行入口。

- [数据获取与输入格式](docs/data-access.md)
- [整理好的传统因子接入](docs/prepared-traditional-input.md)
- [复现操作指南](docs/reproduction-guide.md)
- [最终脚本清单](docs/final-script-inventory.md)与[输入输出依赖表](docs/input-output-dependencies.md)

配置入口 `scripts/run_experiment.py` 负责预测和评价；网络构建、特征计算及 R 资产定价按各模块说明独立执行。

## 实验结果

仓库已发布基于整理好特征表的正式日频、月频实验，以及资产定价、共同样本稳健性和网络对照结果：

| 实验 | 报告内容 |
|---|---|
| [日频预测](results/formal_20261117_daily/REPORT.md) | 三类模型的排序能力、预测误差与增量比较 |
| [月频预测与资产定价](results/formal_20261117_monthly/REPORT.md) | 自然月预测、组合收益、Alpha 与交易成本分析 |
| [共同样本稳健性](results/formal_20261117_monthly/asset_pricing_common/ROBUSTNESS_REPORT.md) | 统一股票样本后的资产定价比较 |
| [网络对照](results/network_benchmarks_20261119/REPORT.md) | 有向、无向和相关网络的预测比较 |

例如，在已发布的网络对照实验中，2022-07-01 至 2026-03-30 的平均日 Rank IC 如下。各对照与有向模型按共同股票—日期样本评价。

| 特征组合 | 有向网络 | 无向网络 | 相关网络 |
|---|---:|---:|---:|
| 网络因子 | 0.066236 | 0.024728 | 0.039627 |
| 传统 + 网络 | 0.075058 | 0.029966 | 0.050777 |

详细样本、误差检验和参数见对应报告；文件入口见 [结果索引](docs/result-map.md)。

## 方法边界与验证范围

当前 idop 阶段估计与相关网络使用完整阶段数据，分配到阶段早期日期的矩阵可能包含阶段后续信息。下游特征滞后不能消除这一前视限制，因此现有结果用于同口径研究比较，不能直接解释为严格实时、可交易的样本外收益。相关基准使用的是收盘价水平相关性。

资产定价中的事后样本覆盖率筛选、市场状态划分及简化交易成本也会影响结果解释，具体口径见 [资产定价说明](R/asset_pricing/README.md)。

已验证整理后特征表上的预测、评价和资产定价流程，以及 Python/R 测试和云端依赖恢复。**从正式 effects 重建全部 1210 日矩阵、从原始价格重算全部相关矩阵并重新生成 89 项特征的上游全量复现，尚未全部完成。** 完整记录见 [验证状态](docs/validation-status.md)。

可在仓库根目录运行模块测试：

```sh
PYTHONPATH=src python -m unittest discover -s tests -p 'test_*.py'
Rscript tests/test_network.R . --with-estimation
Rscript tests/test_features.R .
Rscript tests/test_asset_pricing.R .
```

自动检查配置见 [GitHub Actions](.github/workflows/tests.yml)，运行机制与协作模板见 [自动检查说明](.github/AUTOMATION.md)。

## 来源、署名与许可

本项目使用并整理了 idopNetwork 相关实现。上游来源、作者和已有许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。仓库暂不设置整体许可证；上游已有许可声明保留。

论文题目、作者及正式引用信息确认后将在 [CITATION.md](CITATION.md) 补充。
