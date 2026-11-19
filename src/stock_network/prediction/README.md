# LightGBM 收益率预测

本模块从原 `lightgbm_daily_return_prediction.py` 和 `lightgbm_sliding_prediction.py` 拆分，保留日频和自然月两条流程的拟合、标准化及重要性计算口径。第一版仅迁入 LightGBM；旧脚本的固定交易日 horizon 分支不在此模块中。

## 文件职责

| 文件 | 职责 |
|---|---|
| `data.py` | 因子/标签读取、主键与数值校验、自然月标签和月初面板、可选交易日历校验 |
| `preprocessing.py` | 按 Date 做横截面 z-score，样本标准差 ddof=1，默认截尾 ±5 |
| `lightgbm_model.py` | 两条流程共用的 LightGBM 参数 |
| `daily_prediction.py` | 按月扩展训练窗口，逐日预测当日收益 |
| `monthly_prediction.py` | 按月扩展训练窗口，月初预测当月复合收益 |
| `importance.py` | 每月 gain/split、按训练样本数加权汇总、可选图表 |
| `cli.py` | 公共参数、输出保护、输入与输出哈希、运行记录 |
| `__init__.py` | 包标识；导入不训练、不写文件 |

## 输入与时间约定

输入为长表 CSV：`Date, stock, target_return, 特征列...`。

- `Date` 为交易日期；`stock` 按字符串读取，保留前导零。Date+stock 必须唯一。额外列全部视为特征，因此应先移除行业名称、样本标记等非特征元数据。
- `target_return` 为 **Date 当日、小数单位**的实际收益率（0.01 表示 1%），允许缺失，禁止无穷值或小于 -1。没有此列时，可用 `--target-source` 提供包含 Date、stock、target_return 的长表，按主键左连接；未匹配标签保留缺失。因子表已有标签时，不允许另行覆盖。
- 特征必须为数值；±inf 转缺失；不填零或全样本插补。截面常数列标准化后为缺失。训练时删除缺失标签行和全空特征行；预测时仅删除全空特征行，不根据预测期实际收益筛选。
- **上游负责特征可得时间与滞后**：Date=t 的特征应仅使用 t−1 及以前信息。此模块不再次滞后。它不能消除使用完整阶段数据估计网络带来的前视信息。
- 默认以因子表所有日期的并集作交易日历；不能从稀疏样本自动判断市场是否开市。可用 `--calendar` 指定 Date 列的交易日 CSV，发现范围内整日遗漏和月频边界不完整。日历本身应覆盖完整首尾月份；本模块不会联网验证交易日历。
- 月频的覆盖率分母也来自因子表日期并集。若股票收益不完整，标签可能和资产定价模块的独立收益文件不同；正式实验应使用同一收益来源、日历和 80% 覆盖率规则。`--target-source` 只补已有因子行，不能补缺失交易日或股票行。

### 日频

每个自然月首个**实际预测日**重新拟合，训练 Date 严格早于该日；每个预测日使用当天已滞后的特征预测当天收益。默认至少 60 个历史观察交易日。若 start-date 在月中，首次模型使用该日期之前的数据，后续月份仍在月首拟合。开始/结束日期精确到日且包含边界。

### 自然月

每月首个观察交易日的特征 → **同一个自然月**的复合收益 `prod(1+r)-1`，不是形成月之后的下一个月。只使用此前月份的月初特征和已实现月收益训练；默认至少 12 个历史观察月。股票当月有效收益天数不足月交易日数的 80% 时，该月训练标签置空。

start-date/end-date 按所属自然月筛选，例：start-date=2022-04-15 仍包含 4 月月初预测。默认排除数据最后观察月（包括其预测），避免将截断月份误当完整月；仅确认该月完整时使用 `--include-last-observed-month`。首月也应完整，可使用 calendar 检查。

历史期数沿用旧脚本：按数据中观察到的日期/月计数，随后才去除标签或特征不可用的行；不是有效训练样本所覆盖的期数。训练不足或没有可用样本的月份跳过；无任何预测则报错。资产定价要求连续月份，不能将跳过月份当作零收益补齐。

## 使用

在仓库根目录安装 `requirements.txt` 后运行。无需修改代码或配置机器绝对路径。

```sh
# 月频网络因子模型；输出可以接 R/asset_pricing
PYTHONPATH=src python3 -m stock_network.prediction.monthly_prediction \
  --factor-path outputs/features/network_features.csv \
  --output-dir outputs/prediction/monthly/network \
  --start-date 2022-04-01 --end-date 2026-03-31 \
  --min-train-months 12 --min-month-coverage 0.8 --n-jobs 4

# 日频网络因子模型
PYTHONPATH=src python3 -m stock_network.prediction.daily_prediction \
  --factor-path outputs/features/network_features.csv \
  --output-dir outputs/prediction/daily/network \
  --start-date 2022-07-01 --end-date 2026-03-30 --n-jobs 4

# 查看全部参数
PYTHONPATH=src python3 -m stock_network.prediction.monthly_prediction --help
```

示例日期沿用历史实验区间，实际输出取决于输入范围、完整月排除规则和历史窗口。数据截至 2026-03-30 时，默认不会输出 2026 年 3 月月频预测。

传统、网络、传统+网络模型分别传入对应因子表，使用不同输出目录；固定其他模型参数和预测区间。此模块不构建传统因子、不自动合并因子表、不强制各模型共同股票样本。资产定价默认保留各模型独立样本，另有 common 选项。

**旧口径差异**：默认 `--global-features legacy`，日频排除 `net_global_*`，月频保留。可显式设为 include 或 exclude；运行记录保存实际特征清单与被排除列。当前 89 项网络特征不应通过硬编码数量选择，实际列名以输入和运行记录为准。

默认模型参数：80 棵树、learning_rate=0.05、num_leaves=15、min_child_samples=200、subsample=0.8、subsample_freq=1、colsample_bytree=0.8、reg_alpha=0、reg_lambda=1、random_state=42、force_col_wise=True。n_jobs 默认 −1。没有调参、早停或用预测期选择参数；跨平台/线程数不承诺逐位相同。

## 输出与下游依赖

| 输出 | 内容 / 下游 |
|---|---|
| `predictions.csv` | 宽表：Date 加股票列，小数单位的预测收益。日频每日一行；月频每月首交易日一行 |
| `importance.csv` | gain/split 均值及按训练样本数加权均值、比例、排名 |
| `importance_monthly.csv` | 每个拟合月×特征的重要性、训练和预测样本数 |
| `manifest.json` | 模式、参数、实际特征、输入/输出 SHA256、日期范围、拟合月份和软件版本 |
| `importance.png` | 指定 `--plot` 时生成的分组重要性与 Top N 月度热力图，最多 15 项 |

CSV 默认 UTF-8 BOM，可分别设置 `--input-encoding` 和 `--encoding`。输入的标签文件和日历沿用 input-encoding。已有输出默认拒绝覆盖；显式 `--overwrite` 可重跑。失败可能留下部分 CSV，只有成功完成才写 manifest；覆盖时会先移除旧 manifest。

三种**月频**模型输出分别传入 `R/asset_pricing/run_asset_pricing.R` 的 `--conventional`、`--network`、`--enhanced`；另提供原始收益文件及因子文件。日频预测不能传入该月频资产定价入口。预测日期须与资产定价收益日历的月首交易日一致。

重要性保持旧口径，属于模型内指标，不是因果解释。图中 net_* 统一归入 Network，未按 SC/NP/ND/NWR 细分。

## 验证与范围

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -p test_prediction.py
```

测试覆盖输入主键/代码、标签补入、标准化、月复合标签、日历完整性、训练时点、未来标签扰动、两条 CLI 输出及覆盖保护。另在 16 个月×8 只股票的合成样本上，与原两份脚本比较：两种预测值、重要性汇总和月度明细逐值完全一致，并验证绘图执行成功。

已完成正式整理表的日频 907 日、月频 47 月预测。日频三模型与旧文件最大差约 1e-16；月频也已逐值核对旧预测，最大差约1e-16。见 [验证状态](../../../docs/validation-status.md)。这不代表已重新运行上游 1210 日矩阵/特征生成。IC 评估位于 evaluation，消融调度及固定 horizon 不在本模块。原始研究脚本未改动。
