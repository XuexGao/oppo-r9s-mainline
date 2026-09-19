# AGENT.md — 仓库详细手册

给接手的 agent / 开发者。**动手前先读本文件。** README 只做项目简介，这里是全部
细节：硬件事实、每个文件的功能实现、CI 流程、本地复现、boot 诊断、已知坑与 FIXME、
维护约定。

## 0. 这是什么仓库，为什么用 overlay

OPPO R9s（msm8953，机型号 **16017 / 16027**）的主线内核 **bring-up 覆盖层**。不
fork 内核，而是在 [`msm8953-mainline/linux`](https://github.com/msm8953-mainline/linux)
（默认 tag `v7.1.3-r0`）之上维护一层薄 overlay。

- 形式：**覆盖 + 追加**，不做 `.patch`。`apply-overlay.sh` 每次把 OPPO 相关文件
  覆盖进内核树，并把新 `.dtb` / panel 驱动**尾部追加**进上游 Kconfig/Makefile
  （去重后追加，不替换）。→ 上游 rebase 不会跟我们有合并冲突。
- 定位：**bring-up 工程，尚未在真机上点亮/进入用户态。** 首刷停在 OPPO logo。
- 硬件来源：下游 4.9 CAF 树
  [`XuexGao/android_kernel_oppo_msm8937`](https://github.com/XuexGao/android_kernel_oppo_msm8937)，
  `arch/arm64/boot/dts/qcom/oppo-msm8953/**`。

## 1. 硬件事实（先确认实机型号）

OPPO R9s 两个机型号**面板不同**，这是排查显示问题的第一要素：

| 机型 | 面板 | vendor dtsi 文件名 | mainline 现状 |
|---|---|---|---|
| **16017** | Samsung **EA8064** AMOLED | `dsi-panel-oppo16017samsung_ea8064_1080p_cmd.dtsi` | `panel-oppo-ea8064.c` |
| **16027** | JDI **R63452** (cmd TFT/LCD) | `dsi-panel-oppo16027jdi_r63452_1080p_cmd.dtsi` | `panel-oppo-jdi-r63452.c`（**实机，默认**） |

> **重要（本会话确认）**：实机是 **16027 / JDI r63452**（运行日志
> `qcom,mdss_dsi_oppo16027jdi_r63452_1080p_cmd`），不是 16017 的 EA8064 AMOLED。
> 当前 board dts 已切到 `oppo,r63452-cmd`。JDI r63452 是 command-mode TFT/LCD，
> 供电走 pmi8950 **labibb 的 `"lcd"` 模式**（不是 AMOLED）。16027 显示栈关键走线
> `[vendor]`：
> - GPIO：reset=**131**、enable=**38**、bklight-en=34、TE=24
> - panel 供电：**lab/ibb → `&lab`/`&ibb`**（pmi8950）；**vdd(2.85V)/vddio(1.8V)
>   实际 PMIC rail FIXME(unverified)**
> - 背光：独立 **LM3697** @ `i2c_2` 0x36（enable GPIO 46），**尚未接入 mainline**

其余关键硬件 `[vendor]`：

- SoC `msm8953`（Snapdragon 625），PMIC `pm8953` + `pmi8950`。**供应按 LAB/IBB**
  （AMOLED 的 AVDD/VNEG 来自 pmi8950 的 lab/ibb boosters）。
- GPIO：panel reset **41**；touch attn **17** / reset **16**（`i2c_3`，S3508，地址
  `0x20`）；音量上 **34** / 下 **39**；microSD CD **131**。
- eMMC：vmmc `pm8953_l8`=2.9V，vqmmc `pm8953_l5`=1.8V；microSD vmmc=`sdio_en`
  (gpio 64)，vqmmc=`pm8953_l11`=2.95V。
- LED `ktd,ktd2026` @0x30；音频放大 `nxp,tfa98xx` @0x36（i2c_8）。

## 2. 目录与每个文件的功能实现

```
configs/r9s.fragment
scripts/apply-overlay.sh
overlay/arch/arm64/boot/dts/qcom/msm8953-oppo-r9s.dts
overlay/drivers/gpu/drm/panel/panel-oppo-ea8064.c       # 16017 EA8064 AMOLED
overlay/drivers/gpu/drm/panel/panel-oppo-jdi-r63452.c   # 16027 JDI R63452（实机，默认）
.github/workflows/build.yml
```

### 2.1 `overlay/.../msm8953-oppo-r9s.dts`（板级设备树）

- `#include` `msm8953.dtsi`/`pm8953.dtsi`/`pmi8950.dtsi`（**必须**，缺了 dts 编不过）。
- 根：`compatible = "oppo,r9s", "qcom,msm8953"`；aliases：mmc0=`sdhc_1`、mmc1=`sdhc_2`、
  serial0=`uart_0`。
- `chosen/stdout-path` 指向 `serial@78b3000`（blsp1_uart0）。**注意**：板子是否有可
  用的调试 UART 未实机确认；若没有，日志只能走 ramoops（见 §5）。
- `gpio-keys`：volume 上/下（GPIO 34/39，`KEY_VOLUMEUP/DOWN`）。
- `reserved-memory/ramoops@9ff00000`：`0x100000`、record `0x1000`、console `0x80000`、
  pmsg `0x8000`。**（见 §5 的地址匹配问题 —— 与 Lineage 运行内核的 ramoops 地址不同）**
- 稳压源：`vph_pwr`（fixed）、`sdio_en`（fixed，gpio 64）。
- `&sdhc_1/2`、`&i2c_3`（touch，rmi4 + x0@7）、`&mdp`/`&mdss`/`&mdss_dsi0`/
  `&mdss_dsi0_phy`（显示）、`&rpm_requests/regulators`（s3/s4/l3/l5/l6/l8/l11）、
  `&hsusb_phy`、`&usb3`（`dr_mode="peripheral"`，注意是 `&usb3` 不是 `&usb3_dwc3`）。
- 显示供电：`vci-supply=<&pm8953_l6>`、`avdd-supply=<&lab>`；**`vneg-supply=<&ibb>`
  默认注释掉**（VNEG 负压轨未真机确认，opt-in，见 §2.2 与 §6）。

### 2.2 `overlay/drivers/gpu/drm/panel/panel-oppo-ea8064.c`（EA8064 驱动）

**compatible**：`oppo,ea8064-cmd`。**mode**：1080x1920 CMD 60Hz；4 lanes、RGB888、
`MIPI_DSI_MODE_NO_EOT_PACKET | MIPI_DSI_CLOCK_NON_CONTINUOUS | MIPI_DSI_MODE_LPM`。

**初始化序列（核心）**：从 vendor dtsi 逐字节转录，保持原值——
- vendor 的 DCS 包格式：`[0] type`（`0x05`=短写无参 / `0x15`=短写 1 参 / `0x39`=长写）、
  `[1] flag [2] vc [3] stream`、`[4-5] delay_ms LE`、`[6] len` + payload。
- 用 `ea8064_seq{ pkt, delay_ms, len, data[] }` 表达；`PKT_DCS0/DCS1/GEN` 对应
  `mipi_dsi_dcs_write`/`mipi_dsi_dcs_write(1 参)`/`mipi_dsi_generic_write`。
- **不要"清理" 0xF0/0xC3/0xB0 页切换那套**，控制器就认这个。
- 亮度：`0x51/0x53` 值直接在 init stream 里写死（bring-up 捷径，暂不做 backlight 设备）。

**供电/时序**：
- `ea8064_power_on`：先 `avdd`、再 `vci`；若 `ctx->vneg` 存在再 `vneg`；然后走
  vendor reset `<1 5><0 2><1 12>`。失败沿 err_vci/err_avdd 回滚。
- `ea8064_power_off`：先 reset 拉高，再关 vneg→vci→avdd（逆序）。
- **VNEG 是 optional rail**：`devm_regulator_get_optional(dev, "vneg")`，`-ENODEV`
  → 置 NULL 跳过（这样 dts 没接 vneg-supply 时行为与 old 完全一致，不回退/不伤屏）。
- **别忘了 DRM 头文件**（历史上漏过导致编译失败）：`drm_connector.h`、`drm_mipi_dsi.h`、
  `drm_modes.h`、`drm_panel.h`。
- **FIXME(硬件)**：本驱动对应的是 **16017/Samsung**。若实机是 16027/JDI，需要新驱动。

### 2.2b `overlay/drivers/gpu/drm/panel/panel-oppo-jdi-r63452.c`（JDI 驱动，实机 16027）

**compatible**：`oppo,r63452-cmd`。**mode**：1080x1920 CMD 60Hz；像素时钟 ≈ **149.45MHz**
（h_total 1276=1080+100+2+94，v_total 1952=1920+8+4+20）；4 lanes、RGB888、
`MIPI_DSI_CLOCK_NON_CONTINUOUS | MIPI_DSI_MODE_LPM`（vendor 开了 `tx-eot-append`，
所以**不要**加 `MIPI_DSI_MODE_NO_EOT_PACKET`）。

**on/off 序列**：逐字节转录自 vendor dtsi（`0x39` 长写为主；on 末 `11 00`(sleep out, 120ms)
→ `29 00`(display on, 20ms)；off 为 `0x05` 短写 `28`(20ms) → `10`(120ms)）。DCS 数值照抄，
不要"清理"。**reset 序列 `<1 15> <0 2> <1 15>`**（reset 为高有效）。

**供电/GPIO**：
- reset-gpio = **tlmm 131**（高有效），enable-gpio = **tlmm 38**（高有效）。
- supplies：`lab`/`ibb` → `&lab`/`&ibb`（pmi8950，LCD bias 模式）。`vdd`(2.85V)/`vddio`(1.8V)
  是 optional（`devm_regulator_get_optional`），**真实 rail FIXME(unverified)**，dts 暂未绑定。
- **背光未接入**：16027 的背光是独立 **LM3697** @ `i2c_2` 0x36（enable 46），本驱动不含。
- TE(24)/bklight-en(34) 未在驱动中处理，留给后续。

### 2.3 `configs/r9s.fragment`（配置片段，merge 到 ARCH=arm64 defconfig）

分组：SoC/power（LABIBB/SPMI/RPM/RPMH/interconnect）、display（DRM/MSM/MDP5/DSIO、
`DRM_PANEL_OPPO_EA8064` + `DRM_PANEL_JDI_R63452`、DSI PHY、fb console + boot logo ——
这是我们判断"屏活没活"的唯一可见信号）、input（RMI4 S3508 + gpio-keys）、leds（ktd2026）、storage/usb
（MMC_SDHCI_MSM、DWC3、gadget+configfs/adb serial）、log（PSTORE_RAM、EARLY_PRINTK、
`LOCALVERSION=-r9s-mainline`）。显式关闭暂时不做的：snd soc qcom、panel-simple、
touchscreen dsx、camera。

### 2.4 `scripts/apply-overlay.sh`

把 overlay 拷进一个 msm8953-mainline 内核树，并把新 dtb/panel 挂进构建：
- 复制 board dts；在 `qcom/Makefile` 去重追加 `dtb-$(CONFIG_ARCH_QCOM) += msm8953-oppo-r9s.dtb`。
- 复制 panel .c；在 `panel/Kconfig` 的 `endmenu` 前插 `config DRM_PANEL_OPPO_EA8064`；
  在 `panel/Makefile` 去重追加 `obj-$(CONFIG_DRM_PANEL_OPPO_EA8064) += panel-oppo-ea8064.o`。

### 2.5 `.github/workflows/build.yml`（CI）

手动触发（`workflow_dispatch`），输入：`kernel_repo`、`kernel_ref`、
`publish_release`、`include_modules`。流程与要点：

1. 装依赖 — apt 带超时/重试加固；**装了 `zip`（打包要用）和 `ccache`**。
2. checkout 本项目 → 套 overlay → 拉上游 `git clone --depth 1 --branch kernel_ref`。
3. **ccache**（`hendrikmuhs/ccache-action@v1.2`，key 绑上游 ref，`max-size=4G`）：
   只给 `CC="ccache aarch64-linux-gnu-gcc"` 包 gcc 编译；**binutils 不走 ccache**
   （避免 objcopy/ld 被 ccache 拦截）。`KBUILD_BUILD_USER/HOST` 固定中性值。
4. `defconfig` + `merge_config.sh` 片段 + `olddefconfig`；**逐条核对 fragment 是否落地**。
5. 编 `Image.gz dtbs`、`modules`。
6. **DTB 静态检查**：`dtc` 反编译确认关键节点（panel/touch/ramoops/labibb/vci/avdd）
   都进了 dtb，并锁死 panel `status="okay"` 防止回退成 disabled。
7. 打包 AnyKernel3：`cat Image.gz + dtb > Image.gz-dtb`；**默认不收集 `.ko`**
   （`include_modules=false`）——`anykernel.sh` 是 `do.modules=0`，模块刷机不装，
   塞进去只会把包从 ~16MB 撑到 ~100MB（已实测修过一次）。需要模块时开开关。
8. 上传 Artifact，可选发 Release。

**并发**：`concurrency.group = workflow + ref + kernel_ref`，同一 ref 重复触发会
取消在途构建，不同 ref 互不干扰。

## 3. 修复过的坑（别回退）

- dts 必须 `#include` 全套 dtsi（`msm8953.dtsi` 等）。
- USB 标签是 `&usb3`，不是 `&usb3_dwc3`；`dr_mode` 设在 `usb3` 上。
- panel 驱动要补 `<drm/drm_*.h>`。
- 显示供电靠 PMI8950 **LAB/IBB**：旧主线 labibb 驱动只认 `qcom,pmi8998-lab-ibb`；
  **v7.1.3-r0 起 `pmi8950.dtsi` 自带 `labibb`**（`&lab`/`&ibb` 两个 label）可用。
- VNEG 做成 opt-in，默认 dts 不接（防无证据接负压轨伤屏）。
- 刷机包瘦身：默认不打 `.ko`（do.modules=0 下纯撑体积）。
- CI 的 `find *.ko | head` 在 pipefail 下会 SIGPIPE 误报 → 加 `|| true`。

## 4. 本地复现一次带改动的构建

前置：克隆 `msm8953-mainline/linux` 切默认 ref；交叉编译用 `gcc-aarch64-linux-gnu` /
`binutils-aarch64-linux-gnu`。

```sh
scripts/apply-overlay.sh <内核树路径> overlay
cd <内核树路径>
make ARCH=arm64 defconfig
./scripts/kconfig/merge_config.sh -m .config <本仓库>/configs/r9s.fragment
make ARCH=arm64 olddefconfig
make -j"$(nproc)" ARCH=arm64 Image.gz dtbs modules
```

## 5. Boot 诊断（无调试 UART 的板子）

靠 **pstore/ramoops**。步骤：

1. 刷 mainline boot → 停 OPPO logo → **长按电源 ~10s 强制断电**（留下 ramoops）。
2. 正常开机（回原内核即可）。
3. 读 `adb shell cat /sys/fs/pstore/*`（或 TWRP 文件管理器从挂载后的分区拉）。
4. 把 `console-ramoops-*` 末尾发回分析。

决策表：

| 现象 | 含义 | 下一步 |
|---|---|---|
| 有内核日志/panic | 内核起来了，在某驱动崩 | 看最后调用栈，显示/panel 优先 |
| 空/无文件 | 内核早期没起来 | 查 bootloader 是否拒载、`Image.gz-dtb` 是否被识别、dtb 附加是否正确 |
| 日志正常但屏黑/停 logo | 内核活着但显示链路没点亮 | 排 VNEG/LAB-IBB 与 **面板型号**（见 §1） |

**踩坑（新发现）**：Lineage 运行内核的 ramoops 在 `0xb0000000`
（`dmesg` 里 `ramoops attached 0x800000@0xb0000000`），而我们 board dts 用的是
`0x9ff00000`。**两内核 ramoops 地址不一致 → 重启回 Lineage 后读不到 mainline 那次
的 pstore。** 要能采到 mainline 的日志，需让两个内核用同一保留地址（对齐到
`0xb0000000` 需先确认该区间可用），或用其它手段（如 kernel cmdline
`ramoops.mem_address`）——列为 FIXME。

## 6. 已知 FIXME / Blockers

1. **16027 显示已切到 JDI r63452**（§1/§2.2b），但仍有未落地项：
   - **背光**：LM3697 @ `i2c_2` 0x36（enable 46）未接入 → 即使面板起来也看不到亮图。
   - **vdd(2.85V)/vddio(1.8V) 具体 PMIC rail** 未定，panel 节点暂未绑定。
   - TE(24)/bklight-en(34) 未在驱动处理。
   - 首次真机上次是否真的点亮、有没有进用户态，仍在等一条可读的 mainline pstore。
2. **ramoops 地址与 Lineage 运行内核不一致**（§5）：mainline `0x9ff00000` vs Lineage
   `0xb0000000`，互读还需 record-size/压缩一致 → 影响能否采到 mainline 的 boot 日志。
3. 16017 侧（EA8064）先搁置：其 VNEG(ibb) 负压轨仍是 opt-in/未启用（若将来要支持 16017）。
4. mainline 内核起来后**能否进入用户态**未证实（Android 超出范围 → 目标是
   postmarketOS/Debian 风格 Linux）。
5. 无可用调试 UART。

## 7. 证据标注约定

| 标记 | 含义 |
|---|---|
| `[vendor]` | 来自下游 4.9 树 `oppo-msm8953/**`，对该板权威 |
| `[upstream]` | 已用主线源码/绑定核实 |
| `FIXME(unverified)` | 合理推测，须真机/原理图确认 |

写结论必须带标注；分不清就按 FIXME 写。

## 8. 提交 / 推送 / 验证约定

- 只动必要文件；能改现有就**不新建**文件。
- **提交前确认在 `main` 分支**：本环境常默认落在临时分支（如 `trae/agent-*`）。
  `git checkout main` 再提交；push 用主分支/对应 remote。
- 改 `build.yml` 后本地做 YAML 校验（`ruby -e 'require "yaml"; YAML.load_file(...)'`）
  并跑一次 CI 全绿再收尾。
- 大改动（新驱动、换工具链、改 AnyKernel3/Release 行为）先跟人类确认，别闷头推。

## 9. 给 agent 的三条提醒

1. 这是真机 bring-up：任何"已支持/点亮"都必须有真机证据，否则是 FIXME。
2. 改动尽量小、可回退；涉及负压/电源轨的操作尤其要可回退。
3. 别想当然 —— 实机面板型号（16017 vs 16027）都没定，先把"它在真机上到底长啥样"
   这条证据链补齐，再谈点亮。