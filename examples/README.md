# 无需原始数据的合成示例

本目录演示 Python 的“特征表 → 三模型预测 → 两两评估”流程。数据完全合成，不含真实股票或商业数据，也不代表论文结果。网络特征仅两项演示变量，**不是正式 89 项网络特征**，没有执行 idopNetwork 估计或 R 网络特征构建。

## 快速运行

先按仓库根 README 安装 requirements.txt，然后在仓库根目录执行：

```sh
python3 examples/generate_demo.py --output-dir outputs/demo
python3 scripts/run_experiment.py --config outputs/demo/configs/daily.json
python3 scripts/run_experiment.py --config outputs/demo/configs/monthly.json
```

配置中的数据路径相对于配置文件目录。可以从其他位置执行脚本，但需正确指定脚本和配置路径。想先检查命令，可在后两个命令末尾添加 `--dry-run`。

默认生成 2020 年 1 月至 2021 年 4 月的工作日数据、12 个虚拟股票代码。预测区间为 2021 年 1—3 月。月频至少用前 12 月训练，4 月作为默认排除的最后观察月。日历只有周末过滤，**不模拟交易所节假日**。

三种模型共享目标与样本键：

- conventional：前一日收益与截至前一日的 5 日滚动波动率。
- network：固定随机有向矩阵加权的前一日收益、绝对收益影响。
- combined：上述四项特征。

矩阵无自环、列 L1 归一化；收益生成依赖过去收益和独立噪声。特征计算不引用目标日或未来收益。固定种子为 42，可使用 `--seed` 修改。同一依赖环境下应可重现生成文件；不保证跨依赖版本逐位相同。

## 结果位置

- `outputs/demo/data/`：三份特征长表、日收益宽表、合成日历。
- `outputs/demo/configs/`：可直接运行的日频和月频 JSON。
- `outputs/demo/runs/daily/` 与 `monthly/`：三模型预测、两组比较、日志及运行记录。
- `outputs/demo/demo_manifest.json`：合成标识、种子、规模、依赖版本和生成文件 SHA256。

每条流程运行完成后，run_manifest.json 的 status 应为 complete；各 evaluation 子目录有 model_summary.csv。月频输出仅 3 个评估月，显著性检验不适合作实证推断。此示例不要求合并模型一定优于其他模型。

生成器及实验入口均拒绝覆盖已有目录。重跑请指定新的 output-dir；生成配置会自动使用新目录。生成失败可能留下部分数据，只有最后完成才写 demo_manifest.json。

本示例不包含 R 资产定价、风险因子模拟、正式网络估计或论文图表。R 模块的小样本验证见 tests 下对应测试。公开仓库只需提交生成器和说明，不必提交 outputs 中的文件。
