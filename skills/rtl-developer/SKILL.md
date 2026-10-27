---
name: rtl-developer
description: |
  RTL 开发助手（SystemVerilog / Verilog），以开发期正向约束为主：写代码前先落命名、复位、
  结构、接口规则，写完后跑秒级文本自检。不做商用 IP 级 EDA flow，不强制回归/覆盖率/形式化。
  当用户说"开发/实现一个 XX 模块"、"写个 FIFO/仲裁器/同步器/总线桥"、"做 RTL"或显式调用
  /rtl-developer 时触发。复杂模块架构先行：出方案 → 用户确认 → 实现。
---

# RTL 开发（轻量、正向约束）

定位：内网日常模块开发，不是商用 IP 交付。目标是 **80% 写前约束 + 20% 秒级检查**，
不引入重型 EDA flow、不强制功能向流程产物。

## 写前 checklist（动手前逐条过）

1. 模块名小写蛇形，文件名与模块名一致；一个文件一个 module
2. `module` 之前的首个非注释内容为 `` `default_nettype none ``，文件末尾为 `` `default_nettype wire ``
3. 模块头注释齐全：Module / Description / Features / Parameters / Limitations
4. 端口 ANSI 风格，无 `_i`/`_o` 方向后缀；按 clk/rst → 配置 → 输入 → 输出 → 状态排序
5. valid-ready：`data` 与 `vld` 同周期，`vld` 不依赖 `rdy`
6. 控制类寄存器（状态机/计数器/指针/vld/rdy/配置/错误）必须复位 → `dffr`
7. 数据通路寄存器（流水线数据/FIFO 存储体/宽总线）不复位 → `dff`
8. 每个寄存器都有显式 `en`：状态 `en=(nxt!=cur)`，指针/计数器用精确更新条件
9. 例化端口只连信号名/参数/字面量，运算在外面 `assign` 预处理
10. 实例名全大写（`U_*`）；有统一 DFF 单元时业务模块禁止裸 `always_ff`
11. 组合逻辑 `always_comb` + 默认值；`case` 必须有 `default`
12. 模块 `.sv` 内不写断言；需要时建同名 `.sva`，`SVA_ON` 包住并放 `endmodule` 前
13. `.sva` 不写 `module/endmodule`；参数校验可选
14. 代码里不加对齐标记；交付前跑 `scripts/align.sh`
15. 禁止 `initial` / `force` / `#delay` / `casex` / `always @(...)` / `always_latch`

## 前置（30 秒）

1. 读 `references/rtl-coding-standard.md`（命名、对齐、复位、例化、`.sva` 以此为准）
2. 判断复杂度（见下），再决定要不要架构方案
3. 环境：`command -v iverilog`（有则做定向仿真）、`command -v verilator`（可选，只做 lint 参考）；
   对齐用 `scripts/align.sh`，不依赖交互式 vim

## 复杂度分级

**简单模块**（单时钟、端口 ≤ 20、状态 < 4、无 FIFO/仲裁/协议/CDC）：
直接实现 + 秒级自检；需要时自己写一个定向 TB 用 iverilog 跑一遍，不派生 `rtl-verifier`。

**复杂模块**（时钟域 ≥ 2 / CDC、状态 ≥ 4、端口 > 20、FIFO/仲裁/总线协议/完整数据通路）：
先出架构方案（模块划分 + 框图、接口、参数表、状态机、复位/CDC、验证要点），
用户确认后再实现。接口、位宽、时序、复位任一不清楚时先问，不猜。

## 实现约定

- 优先复用 `templates/` 的基础件，而不是从零写
- 控制/数据通路的复位策略按 checklist 第 6、7 条，这是 PPA 的核心约束
- 状态机两段式（次态组合 + 状态寄存器），onehot，命名 `a_*_st` / `nxt_a_*_st`
- 参数化位宽用 `$clog2` / `$bits` 派生，不手算

## 自检（秒级，不阻塞）

```bash
python3 <skill根>/scripts/quality_gate.py <module>.sv
```

- 纯文本检查，零依赖，约 0.03 s
- **默认只有 error 判失败**；warning 是建议，不阻塞
- `--lint`（可选）：有 verilator 就顺带跑，结果只作 INFO，不影响 PASS/FAIL；没装就跳过
- 不检查 TB / Makefile 是否存在
- 检查 10 项：文件/模块名、头注释、断言不在 `.sv`、可综合性禁用项、`case default`、
  实例名大写、端口连接无运算、无对齐标记、`default_nettype`、`.sva` 是否被 include

## 仿真（按需，不搞仪式）

- 简单模块：一个定向 TB 即可
  `iverilog -g2012 -o simv *.sv && vvp simv`
- 有状态模块（FIFO/仲裁/FSM/CDC）：加随机激励和 scoreboard，才有必要建 `.sva`
- 纯组合/单级寄存器/连线模块：可省略 `.sva`
- iverilog 不支持 `assert property`；要跑并发断言用 verilator `--assert -DSVA_ON`
- 没有 iverilog 时如实说明"未仿真"，不要声称已验证

## 对齐（强制）

- 代码中不加任何对齐标记（`@vlog-align` / `@inst` / `keep` 一律不用）
- 交付前执行 `scripts/align.sh <module>.sv`（内部 `vim -es` 调 rtl_align，全量对齐）
- 插件不可用时按规范手工对齐，并在交付说明里注明

## 模板（templates/）

| 文件 | 用途 |
|---|---|
| `dffr.sv` | 控制类寄存器，异步复位 + 显式 en |
| `dff.sv` | 数据通路寄存器，无复位 + 显式 en |
| `rst_sync.sv` + `.sva` | 异步复位、同步释放 |
| `cdc_2ff.sv` + `.sva` | 单 bit 2FF 同步器（多 bit 必须格雷码/握手/异步 FIFO） |
| `fifo_sync.sv` + `.sva` + `_tb.sv` | 同步 FIFO 参考实现与定向 TB |

复制后改名、按需求调参。仿真一行命令：`iverilog -g2012 -o simv *.sv && vvp simv`。

## 交付

源码（`.sv`）+ 必需的 `.sva` / TB + 一句说明：做了什么、跑了什么检查、哪些没跑。
不附带 Makefile、覆盖率报告等非模块功能向产物，除非用户明确要求。
