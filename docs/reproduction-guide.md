# 复现指南

更新：2026-11-16。以下命令在仓库根目录运行。先按根 README 安装 requirements.txt；R 使用 renv.lock 恢复。锁文件不安装解释器或系统编译库，尚未验证全新机器完整恢复。

## 先验证公开合成示例

```sh
python3 examples/generate_demo.py --output-dir outputs/demo
python3 scripts/run_experiment.py --config outputs/demo/configs/daily.json
python3 scripts/run_experiment.py --config outputs/demo/configs/monthly.json
```

输出目录必须不存在；重跑换一个生成目录即可。三步完成后检查两个 runs 子目录的 run_manifest.json 均为 complete。详细说明见 [examples](../examples/README.md)。这些是虚拟数据，不能用于重现论文数值。

## 再接正式研究数据

1. 锁定分层、阶段、补齐后的 1210 日日历与股票标识。已有 effects 优先重建；只有需要重新估计时选择 estimate 模式，见 [network](../R/network/README.md)。
2. 准备日收益宽表和唯一 Date/stock 样本键，运行 [features](../R/features/README.md) 的 build_network_features.R。检查 89 字段、标签与质量报告。
3. 提供经确认的传统因子和合并因子表。当前代码不自动生成正式传统因子，也不保证任意两表可直接拼接；须按键核对样本和收益标签。
4. 复制 scripts/experiment.example.json，修改路径、日期、编码和模型参数。先用 `--dry-run` 查看计划，再执行；详见 [scripts](../scripts/README.md)。dry-run 不检查全部数据内容。
5. 日频和月频使用独立配置及输出目录；检查实际预测月份、遗漏样本、共同样本规模和日志。月频最后观察月规则须与数据完整性一致。
6. 三份正式月频预测接 [asset_pricing](../R/asset_pricing/README.md)，分别传 conventional、network、enhanced；Alpha 另需月度风险因子及明确单位。该步骤不在 Python 实验编排中自动执行。

## 检查命令

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -p 'test_*.py'
Rscript tests/test_network.R .
Rscript tests/test_features.R .
Rscript tests/test_asset_pricing.R .
```

测试通过只说明覆盖的工程行为成立。不能代替正式全量运行、数据授权核实或论文结果核验。参数说明可从各主入口 --help 查看。

## 保存实验记录

为每次实验保留配置、输入哈希、依赖版本、日志、各模块 manifest 和结果。子模块失败可能留下部分 CSV；不能仅凭文件存在判断完成。实验编排失败即停止，未提供自动续跑。输出目录应按实验版本区分，避免不同频率、网络类型或样本口径混用。
