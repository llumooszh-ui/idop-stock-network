# 授权数据接入指南

本项目公开代码、合成示例和研究输出，不提供 CSMAR 原始数据下载。正式复现从用户自行取得并整理的数据开始；不假定他人能够访问原作者的磁盘路径。取得和使用数据的权限由使用者自行确认。

## 最小输入清单

| 本地文件建议名 | 必要内容 | 校验要求 |
|---|---|---|
| traditional_features.csv | Date、stock、target_return、122项数值特征 | 125列，键唯一；标签为当日小数收益 |
| network_features.csv | 同三列、89项网络特征 | 92列；字段见 R/features/feature_dictionary.csv |
| combined_features.csv | 同三列、211项特征 | 可由严格合并入口生成；与两输入样本及标签一致 |
| daily_returns.csv | Date、各股票列 | 每日小数收益，0.01=1%；无元数据说明行 |
| calendar.csv | Date | 完整、唯一、升序的交易日历，涵盖完整首尾月份 |
| monthly_factors.csv | year_month、RiskPremium1、SMB1、HML1、RMW1、CMA1 | 月份唯一；风险因子单位明确；仅Alpha分析需要 |

示例日期为 YYYY-MM-DD，year_month 为 YYYY-MM。股票代码/名称体系必须一致，前导零不能丢失。默认输入编码在不同模块中不同，命令中明确指定 UTF-8/GB18030；不要让数字股票代码被表格软件改写。缺失特征留空，不填零；源文件中的无穷值应先核对，预测入口按既有规则转为缺失。

网络特征已由上游滞后，预测入口不再次滞后。传统表同样应保留原作者确认的时间口径。月收益在程序内由每日收益复合，不要把月收益当成 daily_returns 输入。

## 准备路径

将真实文件放在仓库之外，例如 `/your/data/`。复制 `scripts/experiment.example.json` 到被忽略的 `outputs/local-config/daily.json`（先创建目录），然后替换以下字段：

- models 中各模型的 factor_path：指向你的三份特征表；可用绝对路径。
- truth：你的 daily_returns.csv；truth_encoding 与实际编码一致。
- calendar：添加你的 calendar.csv 路径。
- start_date、end_date：明确研究区间，前面保留足够训练历史。
- output_dir：未存在的新目录，如 `../runs/daily_v1`。

所有相对路径以配置文件目录为基准。发布结果 JSON 中 `external/…` 只用于去除原本机路径，不是可下载文件或可直接运行配置。

## 合并和执行

没有合并表时，先执行（替换示例路径）：

```sh
PYTHONPATH=src python3 -m stock_network.features.merge_features \
  --traditional /your/data/traditional_features.csv \
  --network /your/data/network_features.csv \
  --output-dir outputs/local-combined
python3 scripts/run_experiment.py --config outputs/local-config/daily.json --dry-run
python3 scripts/run_experiment.py --config outputs/local-config/daily.json
```

合并器拒绝重复键、样本差异及标签冲突，不会静默取交集。合并输出路径要同步填写到 combined 的 factor_path。dry-run 仅展示执行计划，不能代替数据内容校验。

月频复制另一份配置，设置 frequency=monthly、不同 output_dir，明确 min_train_months 和最后观察月规则。三份月频预测接资产定价的 conventional/network/enhanced 参数；风险因子必须显式指定 factor-units。详见 [资产定价参数](../R/asset_pricing/README.md)。

## 本项目已验证的数据范围

正式三份特征表均607633行、606只股票、1209个特征日期（2021-04-01—2026-03-30）；独立收益日历1210日。不能把1210直接作为最终特征行日期数。原收益文件含6行元数据，正式评估使用清理后的副本并逐键核对全部标签。

这些范围是本项目的核对结果，不是替其他数据硬编码的通用要求。样本、覆盖率、缺失值和可得日期必须根据研究输入核查，不能只凭列数判断文件正确。
