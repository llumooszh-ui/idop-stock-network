# 实验运行脚本

`run_experiment.py` 顺序执行已迁入的预测模块，再执行指定的两两共同样本评估。不改变模型公式、不自动合并特征、不运行网络拟合或 R 资产定价。

复制 `experiment.example.json` 修改输入位置、日期、输出目录后，在仓库根目录执行：

```sh
python3 scripts/run_experiment.py --config scripts/experiment.example.json --dry-run
python3 scripts/run_experiment.py --config scripts/experiment.example.json
```

示例路径为占位符，未附正式数据。所有配置相对路径均相对于 **配置文件所在目录**，与启动目录无关。使用当前 Python 解释器，自动设置仓库 src 的模块搜索路径，无需手动设置 PYTHONPATH。

- `models` 可命名传统、网络、合并或消融模型，每项提供 factor_path，可选 target_source。输入须满足 prediction 模块契约。
- `prediction` 是共享的模型参数，允许的键见脚本 OPTIONS；三个模型使用相同参数。输出编码固定沿用 UTF-8 BOM，供评估直接读取。
- `comparisons` 是有方向的 [A,B] 配对，改善为正表示有利于 A。每对使用其自身共同样本，不保证不同配对的股票样本完全相同。
- `frequency` 可为 daily 或 monthly。月频仍用日收益 truth，并将覆盖率和最后月选项同步传给评估；日期及标签规则见 prediction/evaluation 文档。
- 可选 calendar 传给预测模块；收益文件日期与因子日历仍需一致。
- nw_lag 默认为 5，研究者应按频率和实验口径明确设定。

输出目录必须不存在；不提供自动覆盖或自动续跑，避免旧预测与新配置混合。失败后查看日志并选择新的输出目录重跑。dry-run 仅校验配置结构、展示命令，不检查输入数据存在性和全部模型参数。

输出包含 `prediction/<model>/`、`evaluation/<A>__vs__<B>/`、每一步的 `logs/`、配置快照以及 `run_manifest.json`。manifest 记录 running/failed/complete 状态，步骤失败即停止；子进程的输入哈希、软件版本、样本信息见各模块 manifest。运行日志写入文件，终端打印计划。中断或进程强制终止可能留下 running 状态，不能当作成功。

先使用合成数据验证流程，再接正式数据。本入口不代表已完成论文全流程复现。R/asset_pricing 仍单独运行，可使用此入口产出的三份月频预测。
