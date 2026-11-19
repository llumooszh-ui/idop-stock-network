# 传统特征与特征合并

当前正式流程直接接收用户预先整理的 122 项传统因子表，不要求从 CSMAR 原始下载重新构建。输入为 Date、stock、target_return 加 122 个数值特征（合计 125 列）；正式文件版本已由用户指定并完成全表衔接核对，见 docs/prepared-traditional-input.md。保留原表已采用的时间处理，不再次滞后或重算财务可得日。原财报固定延迟规则属于上游数据处理假设，读取整理表本身不能验证实际公告时点。

整理表可直接传给 prediction 的 --factor-path 或 merge_features 的 --traditional。严格合并仍要求两表样本键及收益标签一致。下述 41 项历史收益构建工具作为可选辅助，不是正式 122 项的替代，也不应重复追加到已包含这些字段的整理表。

本仓库的复现边界为“给定整理后的传统因子表”，不是 CSMAR 原始数据到传统因子的完整复现。实际数据不自动复制或提交到仓库。

## 历史收益特征

```sh
PYTHONPATH=src python3 -m stock_network.features.build_return_features \
  --returns data/processed/daily_returns.csv \
  --start-date 2021-04-01 --end-date 2026-03-30 \
  --output-dir outputs/features/returns
```

输入为日期×股票日收益宽表，小数单位，默认 UTF-8 BOM，可传 --encoding GB18030。须提供开始日期之前的历史数据，先计算完整历史再截取范围。保留原 calculate_return_factors.py 的公式：7 个收益滞后、4 个窗口各 6 指标、4 个 20 日指标、6 个横截面排名，共 41 项。所有特征仅使用前一观察日及以前收益；日期并集应为完整交易日历。

历史窗口允许部分缺失，最少观测数为 max(3, window//2)，20 日高阶指标最少 10 个观测。滚动标准差 ddof=1；下行波动率仅对负收益且 ddof=0。原最大回撤从第一个复合收益开始计算峰值，未加入初始净值 1，此处保留以避免改变历史因子定义，与资产定价模块修正后的绩效回撤不同。

输出 return_features.csv 和 manifest.json。与旧主入口一致，缺失目标行和全部收益特征缺失行排除。无穷输入在读取层转为缺失，不做插值。

## 严格合并

```sh
PYTHONPATH=src python3 -m stock_network.features.merge_features \
  --traditional data/processed/traditional_features.csv \
  --network outputs/features/directed/network_features.csv \
  --output-dir outputs/features/combined
```

该示例使用预先整理的正式传统因子表；路径应替换为实际文件。两表必须有完全相同的 Date+stock 键集合及一致 target_return；只允许共享 Date、stock、target_return 三列。无需相同行序，重复键、单边缺样本、冲突特征名、不同标签直接报错，绝不静默取交集。标签按 rtol=atol=1e-12 比较，两边同时缺失允许。CLI 读取时统一排序；stock 按字符串保留前导零。

输出 combined_features.csv 和 manifest.json，记录输入哈希、实际特征列与样本规则。输出目录必须不存在；失败可能留下部分文件，成功后才写 manifest。不会自动构建共同样本或修改网络表。如两表样本不一致，应先确认正式样本规则，再显式整理。

## 测试

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -p test_traditional_features.py
```

测试检查 41 个字段、未来收益扰动不改变当期特征、乱序键连接，以及重复、样本缺失、标签冲突拒绝。正式 122 项整理表已完成与 89/211 项表的全量键、标签和特征值核对；不重新生成 CSMAR 原始因子。论文版本映射仍待确认。
