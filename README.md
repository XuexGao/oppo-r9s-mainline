# OPPO R9s (msm8953) 主线内核 bring-up

这是一个**主线内核 bring-up 项目的覆盖层仓库**：在本项目的基础上游
[`msm8953-mainline/linux`](https://github.com/msm8953-mainline/linux)（默认 tag
`v7.1.3-r0`）之上，为 OPPO R9s 维护**薄覆盖层**——board 设备树 + DRM panel 驱动
+ 内核配置片段，而不是 fork 一份完整内核。

> **当前状态：仍在 bring-up，尚未在真机上点亮或进入用户态。** 首刷到 OPPO logo
> 后卡住。所有"已支持/正常"的说法都必须有真机证据，否则按 `FIXME(unverified)`
> 处理。

**详细信息和功能实现**（文件逐项说明、CI 流程、本地构建、boot 诊断步骤、已知
坑与 FIXME、维护约定）都写在 **[AGENT.md](AGENT.md)** 里，接手的 agent/开发者先读它。

## 支持的机型与面板（先确认你的机器）

OPPO R9s 有两个机型号，**面板不一样**（这是排查显示问题的第一要素）：

| 机型 | 面板 | 说明 |
|---|---|---|
| **16017** | Samsung **EA8064** AMOLED | `panel-oppo-ea8064.c` 对应 |
| **16027** | JDI **R63452**（cmd TFT/LCD） | **实机是这个**；`panel-oppo-jdi-r63452.c` 已按此默认启用 |

> 运行日志确认实机是 **16027 / JDI r63452**。board dts 已切到 `oppo,r63452-cmd`
> （reset 131 / enable 38 / lab·ibb 供电）。**背光(LM3697 i2c_2)** 与 **vdd/vddio
> 具体 PMIC rail** 仍未接入，屏可探测但还没背光，属 FIXME。

## 仓库组成

```
overlay/arch/arm64/boot/dts/qcom/msm8953-oppo-r9s.dts    板级设备树
overlay/drivers/gpu/drm/panel/panel-oppo-ea8064.c        EA8064 panel 驱动
configs/r9s.fragment                                     defconfig 之上的配置片段
scripts/apply-overlay.sh                                 把 overlay 拷入内核树并挂钩构建
.github/workflows/build.yml                              CI：拉上游→套覆盖层→编译→打包→校验
```

## 怎么构建 / 刷机 / 排查

- **构建**：GitHub **Actions** 手动触发 `Build R9s mainline kernel`；产物
  `r9s-mainline-<ref>-<date>.zip`（AnyKernel3，约 16 MB，默认不含模块）。
- **刷机**：TWRP 刷 zip（写入 boot 分区）。刷前务必备份原 boot。
- **排查卡屏**：无调试 UART，靠 pstore 抓上次 boot 日志；步骤见 AGENT.md 的
  "Boot 诊断"一节。

## 证据标注

`[vendor]`=读自下游 4.9 树（对该板权威）；`[upstream]`=已用主线源码核实；
`FIXME(unverified)`=合理推测，需真机确认。不标 = 信息不成立，别当事实用。