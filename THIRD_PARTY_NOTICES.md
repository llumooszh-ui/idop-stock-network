# 代码来源与第三方说明

## idopNetwork

本地上游包 DESCRIPTION 记录：

- Package：idopNetwork；Version：0.1.2。
- Author：Ang Dong。
- License 字段：GPL (>= 3)。
- 上游地址（来自 DESCRIPTION）：https://github.com/cxzdsa2332/idopNetwork
- 标题：A Network Tool to Dissect Spatial Community Ecology。

本仓库的股票研究脚本沿用 idopNetwork 方法，并对股票收益、阶段网络和下游分析进行改写。网络估计入口包含本地股票研究 MTODEs 实现；不是单纯加载上游包。现有文件尚不足以逐段证明所有复制/改写代码的原始作者和权利链，因此本说明不替代正式许可清理，也不将上游作者列为本仓库全部代码的作者。

## 研究脚本迁移

网络重建、89项指标、预测、对照评价、资产定价等由原本地研究脚本迁入并拆分。可追溯的旧文件名与职责见 docs/final-script-inventory.md 及 docs/archive/。新增工程组织包括公共入口、校验、合成测试、配置编排和文档。

Python/R 运行依赖及版本见 requirements.txt 和 renv.lock；依赖的授权由各自项目声明。本仓库不重新授权第三方依赖，也不将依赖的作者视作论文作者。

## 当前状态

仓库所有者已决定暂不设置覆盖整个仓库的 LICENSE，只补充来源与署名。此决定不替代或更改上游已有的许可声明；现有说明也不代表已经完成逐段代码来源核查。数据与代码授权不同：本项目未分发 CSMAR 原始数据，发布的研究输出不代表授予原始数据访问或再分发权限。
