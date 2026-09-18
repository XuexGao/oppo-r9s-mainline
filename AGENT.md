# AGENT.md

给接手的 agent / 开发者看的仓库说明。**先读这个文件，再动手。**

## 这个仓库是什么

OPPO R9s（msm8953 / Snapdragon 625，机型号 16017/16027）的**主线内核 bring-up**
覆盖层（overlay）。我们不是 fork 一份内核，而是维护一个**薄覆盖层**，放在
`msm8953-mainline/linux`（上游主线衍生树，默认 tag `v7.1.3-r0`）之上。

硬件参考数据来自 OPPO 的 4.9 CAF 内核：
[`XuexGao/android_kernel_oppo_msm8937`](https://github.com/XuexGao/android_kernel_oppo_msm8937)。

一句话定位：**这是个 bring-up 工程，目前没有任何东西上过真机。** 所有结论都要标明
出处（见下文“证据标注”），不要假装点亮过屏幕。

## 目录结构

```
configs/r9s.fragment             # 在 ARCH=arm64 defconfig 之上 merge 的配置片段
overlay/
  arch/arm64/boot/dts/qcom/msm8953-oppo-r9s.dts    # 板级设备树
  drivers/gpu/drm/panel/panel-oppo-ea8064.c        # Samsung EA8064 AMOLED panel 驱动
scripts/apply-overlay.sh        # 把 overlay 拷进内核树 + 挂钩 Kconfig/Makefile
.github/workflows/build.yml     # 手动触发的 CI：拉上游→套覆盖层→编译→打包→校验
README.md                        # 面向人的说明（Blockers / Milestones / 布局）
```

### 为什么是 overlay 而不是 patch / 分支

`apply-overlay.sh` 每次把 OPPO 相关文件**覆盖**进上游树，把新的 `.dtb` 和 panel
驱动用**追加**的方式挂进上游 Kconfig/Makefile（去重后追加，不是替换）。这样上游提
价/rebase 时不会跟我们冲突——不维护 diff，就没有合并冲突。改动上游已有文件时要小心。

## 修复过的坑（别回退）

- `msm8953-oppo-r9s.dts` **必须** `#include "msm8953.dtsi"` 等，否则 dts 编译不过。
- USB 标签是 `&usb3`，不是 `&usb3_dwc3`（后者不存在），`dr_mode` 直接设在 `usb3` 上。
- panel 驱动要补 `<drm/drm_*.h>` 头文件（connector / mipi_dsi / modes / panel）。
- 显示供电来自 PMI8950 的 **LAB/IBB**。旧主线 `qcom-labibb-regulator.c` 只认
  `qcom,pmi8998-lab-ibb`；从 tag **v7.1.3-r0** 起 `pmi8950.dtsi` 自带 `labibb` 节点
  （兼容串 `"qcom,pmi8950-lab-ibb", "qcom,pmi8998-lab-ibb"`），所以 panel 才能接
  `&lab` / `&ibb`。
- **尚未实机确认**：`panel-oppo-ea8064.c` 目前只驱动 avdd+vci，**没把 VNEG(ibb)
  作为独立轨**导出来。所以“能探测”≠“能点亮”。

## 在本地复现一次带上改动的构建

先做前置：克隆 `msm8953-mainline/linux`（切到默认 ref），然后：

```sh
scripts/apply-overlay.sh <内核树路径> overlay
cd <内核树路径>
make ARCH=arm64 defconfig
./scripts/kconfig/merge_config.sh -m .config ../configs/r9s.fragment
make ARCH=arm64 olddefconfig
make -j"$(nproc)" ARCH=arm64 Image.gz dtbs modules
```

交叉编译器：`gcc-aarch64-linux-gnu` / `binutils-aarch64-linux-gnu`（Ubuntu 源）。

## CI 怎么跑

`.github/workflows/build.yml`：只在 **Actions 页手动触发**（`workflow_dispatch`），
三个输入：上游仓库、tag/分支、是否发 Release。流程：

1. 装依赖（apt 带超时/重试加固）
2. `actions/checkout` 取本仓库 → 套覆盖层
3. **ccache**（`hendrikmuhs/ccache-action@v1.2`）对象级缓存，key 绑在上游 ref 上，
   同一 ref 重跑复用；只给 `CC="ccache aarch64-linux-gnu-gcc"` 包一层，binutils 不用
   ccache，避免 objcopy/ld 被误拦
4. `defconfig` + merge 片段 + `olddefconfig`，并**逐条核对片段是否落地**
5. 编 `Image.gz dtbs` + `modules`
6. **DTB 静态检查**：`dtc` 反编译后确认关键节点（panel / touch / ramoops /
   labibb / vci/avdd-supply）都进了 dtb
7. 用 `XuexGao/android_kernel_oppo_msm8937` 的 `AnyKernel3` 打 `Image.gz+dtb` 包
8. 上传 Artifact，可选发 Release

改完 `build.yml` 后建议在本地做一次 YAML 解析校验（`ruby -e 'require "yaml"; YAML.load_file(...)'`），
并实际跑一次 CI 验证全绿，再谈“完成”。

## 证据标注约定（README 也用了）

| 标记 | 含义 |
|---|---|
| `[vendor]` | 来自下游 4.9 树 `arch/arm64/boot/dts/qcom/oppo-msm8953/**`，对这块板子是权威 |
| `[upstream]` | 已用 `torvalds/linux` 或 msm8953-mainline 源码/绑定核实 |
| `FIXME(unverified)` | 合理猜测，必须在真机或原理图上确认 |

写结论时**必须带标注**。分不清 `[vendor]` 和 `FIXME` 时，宁可按 FIXME 写，不要当事实
陈述。README 里的 Blockers 是当前真实状态，改了硬件行为要先同步它。

## 给 agent 的三个提醒

1. 这是给**真机 bring-up** 的仓库：任何“已支持”“正常”的说法，都要有“在真机上确认
   过”这一前提，否则就是 FIXME。
2. 改动覆盖面尽量小：能改 overlay 现有文件就不新建文件；能复用现有 checks 就不加
   新流程。
3. 大改动（新增驱动、改成 out-of-tree 构建、换工具链）**先跟人类确认**，别闷头改——
   尤其涉及默认上游 ref、AnyKernel3 依赖或 Release 行为时。