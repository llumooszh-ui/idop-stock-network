# GitHub 自动检查与协作模板

`workflows/tests.yml` 在 push、pull_request 和手动 workflow_dispatch 时运行两个独立任务：

- Python：使用 3.9 系列与 requirements.txt 的固定包版本，执行所有 test_*.py，再跑通合成日频/月频三模型实验。
- R：使用 R 4.5.1、安装系统库并按 renv.lock 恢复环境，执行网络重建/小样本估计、89 项特征、资产定价测试。

两者只使用测试生成的合成数据，不读取 outputs/prepared_inputs 中的正式本地配置。任务分别限时 25/60 分钟，避免挂起；同一分支新运行取消旧运行。权限为 contents: read，不发布、不提交、不推送结果。Python 编排失败时将步骤日志尾部打印到 Actions 日志，不上传正式数据或模型产物。

Python CI 使用 3.9 系列可用补丁版本，不保证等于原本机 3.9.6；R 与包版本按现有记录。首次 R 依赖恢复可能较慢，需要网络与 CRAN/包归档可用。GitHub Actions 的实际云端执行尚待推送后验证，本地测试通过不等于云端环境已通过。

配置依据 [checkout](https://github.com/actions/checkout)、[setup-python](https://github.com/actions/setup-python)、[setup-r](https://github.com/r-lib/actions/tree/v2/setup-r) 和 [setup-renv](https://github.com/r-lib/actions/tree/v2/setup-renv) 官方说明。使用 major 标签；它们会随维护者发布更新，不是不可变提交锁定。

PR 模板记录改动、验证和研究口径；Issue 模板分别用于运行问题和功能建议。模板不配置自动标签、负责人或对外通知。

推送后在仓库 Actions 页面查看 Synthetic tests。尚未设置分支保护或 required checks；需要在首次云端成功后再决定是否将这两个任务作为合并门槛。
