# 预测评估

基于原 `evaluate_network_method_comparison.py`，比较两个模型在完全相同的股票—日期样本上的预测。三个模型可分别做两两比较；不同配对的共同样本可能不同，不能把这些结果视为固定三模型共同样本。

## 文件

- `data.py`：严格读取预测/收益宽表，构建自然月实际收益。
- `ic_metrics.py`：Pearson IC、Spearman Rank IC；至少 5 个有效股票且两个序列均非常数。
- `prediction_metrics.py`：MSE、RMSE、MAE。
- `compare_models.py`：沿用原 Newey–West 均值差检验与 Holm 校正。
- `run_evaluation.py`：两模型共同样本评估及输出。

## 输入与执行

预测和实际收益均为 CSV 宽表，首列日期、其余列为股票代码。预测默认 UTF-8 BOM；实际收益默认 GB18030，可用 `--truth-encoding` 修改。股票代码保留列名字符串。重复日期/股票列、非法数值直接报错；无穷值作为缺失排除。收益必须为小数单位，1% 写成 0.01。

在仓库根目录：

```sh
PYTHONPATH=src python3 -m stock_network.evaluation.run_evaluation \
  --model-a outputs/prediction/daily/network/predictions.csv \
  --model-b outputs/prediction/daily/conventional/predictions.csv \
  --label-a Network --label-b Conventional \
  --truth data/processed/daily_returns.csv --truth-encoding utf-8-sig \
  --frequency daily --nw-lag 5 \
  --output-dir outputs/evaluation/network_vs_conventional
```

月频使用两份月频预测，将 frequency 改为 monthly，truth **仍然提供日收益宽表**。月初预测对应同一个自然月的复合收益。默认至少 80% 有效交易日才生成股票月收益标签（`--min-month-coverage`）；最后观察月默认排除，仅确定完整时指定 `--include-last-observed-month`。输入的日期并集作为日历，须自行保证无整日漏数及首月完整。本模块不联网验证交易日历，不接受已复合月收益冒充日收益。

每月最多一个预测日期，且在可评估月份内必须等于收益日历的月首交易日。排除最后月及日历之外的日期不会参加共同样本。日频模式不能自动判断一份稀疏文件是否其实是月频预测，调用者必须明确选择正确模式。

## 指标与统计口径

先按 Date+stock 对齐两个预测与真实收益，再删除任一值缺失的观测。两模型所有误差和相关指标使用相同样本。

- pooled 指标在全部有效股票—日期观测上计算；不是逐期 IC 的均值。
- 逐期 Pearson IC、Rank IC 各自取时间均值；ICIR = 均值 / 样本标准差（ddof=1），**不年化**。零标准差返回缺失。正 IC 比例仅以有效 Rank IC 期数为分母。
- 汇总误差按全部观测加权；逐期误差差异检验每期等权。这两者在股票数变化时不同。
- 差异方向：Rank IC 为 A−B，MSE/MAE 为 B−A，正值均有利于 A。
- Newey–West 使用原 Bartlett 权重和正态双侧 p 值，默认 lag=5，可显式调整；Holm 在本次三个差异检验的有效 p 值中校正，不跨其他配对或实验校正。
- 沿用旧逻辑：检验删除非有限期后按剩余观测顺序计算滞后，不补缺失日/月。因此存在缺口时不代表严格日历间隔的 HAC；请检查逐期输出。小于 3 期或标准误为零时检验统计量缺失。
- 暂不输出样本外 R²：历史基准尚未确认，不能擅自用零收益或测试期均值替代。

为便于沿用原结果，汇总字段 `mean_daily_rank_ic`、`ic_positive_days`、`n_days` 在月频模式下仍保留名称，但其单位是月；以 manifest 中 frequency 为准。

## 输出

| 文件 | 内容 |
|---|---|
| `model_summary.csv` | 两模型的 pooled 相关、误差、平均 IC、ICIR、正 Rank IC 比例 |
| `period_metrics.csv` | 每日期、模型的股票数、两类 IC、MSE、MAE |
| `period_method_differences.csv` | A 相对 B 的三项逐期改善 |
| `newey_west_tests.csv` | 三项均值差异检验和 Holm p 值 |
| `common_sample_panel.csv` | 实际使用的共同样本，预测列为 model_a/model_b |
| `manifest.json` | 参数、输入 SHA256、软件版本、对齐前行数、共同样本数量 |

已有输出默认拒绝覆盖，显式 `--overwrite` 重跑。输出不能覆盖输入。写出失败可能留下部分文件，manifest 仅在成功后写出。读取严格校验与旧脚本静默丢弃非法日期的行为不同，应先清理原始数据中的说明行。

本模块评估统计预测效果，不替代 `R/asset_pricing/` 的组合收益和 Alpha 检验。上游完整阶段网络估计的前视信息也不会被本模块消除。

## 测试

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -p test_evaluation.py
```

合成数据测试覆盖相关方向、常数列、Holm 校正、小样本检验、月收益复合与覆盖率、共同样本筛选、误差和输出覆盖保护。尚未运行正式全样本评估或复核论文指标。
