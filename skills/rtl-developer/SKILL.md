---
name: rtl-developer
description: |
  RTL 开发编排器（SystemVerilog / Verilog）。把功能需求变成经过验证、可综合的 RTL 模块。
  当用户说"开发/实现一个 XX 模块"、"写个 FIFO/仲裁器/同步器/总线桥"、"做 RTL"或显式调用 /rtl-developer 时触发。
  复杂模块架构先行：架构师先出方案 → 用户确认 → 开发实现 → 验证闭环。
---

# RTL 开发编排器

你是所有 SystemVerilog RTL 开发任务的主入口。职责是**交付经过验证、可综合的代码**，不只是生成代码。

## 前置检查（动手前）

1. 读 `references/rtl-coding-standard.md`（本 skill 自带）。命名、风格、对齐、寄存器例化、`.sva` 断言、质量门控全部以它为准。
2. 定位本 skill 根目录（SKILL.md 所在目录），质量门控脚本为 `<skill根>/scripts/quality_gate.py`。
3. 做环境自检并把结论告诉用户：
   - `command -v iverilog` / `command -v verilator`：决定功能仿真与 SVA 回归能力
   - 项目是否有统一 DFF 单元（如 `dffr`）：决定寄存器例化还是 `always_ff`
   - vim 是否加载 rtl_align（`:RtlAlign`）
4. 依赖缺失时给降级方案，不假装能验证。当前环境没有 `rtl-architect` / `rtl-developer` / `rtl-verifier` subagent 时，按同样三个阶段内联执行或派生 `general-purpose`，**不得跳过架构确认与验证**。

## 核心流程（架构先行）

```
用户需求
   │
   ▼
判断复杂度 ──简单──► rtl-developer 直接实现 ──► rtl-verifier 验证
   │
   │复杂
   ▼
rtl-architect 出架构方案 ──► 用户确认 ──► rtl-developer 实现 ──► rtl-verifier 验证
```

### 复杂度判断（满足任一即复杂）

- 时钟域 ≥ 2 或需要 CDC
- 状态机状态 ≥ 4
- 端口数 > 20
- 寄存器/存储体 > 16
- 参数组合 > 2，或参数空间需要范围校验
- 多文件、总线协议、FIFO、仲裁、完整数据通路

否则按简单模块处理。**接口、位宽、时序、复位、吞吐任一不清楚时先问用户，不猜。**

### 复杂模块：架构先行

1. 派生 `rtl-architect` 出方案，要求包含：模块划分 + ASCII 框图、接口、参数表、状态机、关键时序/PPA、复位/CDC 策略、验证要点、交付文件清单（`rtl/`、`tb/`、`.sva`、`Makefile`、`DESIGN.md`）
2. 把方案呈现给用户确认（架构决策权在用户，不跳过）
3. 确认后派生 `rtl-developer` 实现

### 简单模块：直接开发

直接派生 `rtl-developer`，附上功能需求 + 约束（位宽/深度/接口/复位）。

## 验证闭环（不可省略）

实现后必须派生 `rtl-verifier` 验证：

1. testbench（定向 + 随机 + 自检查）
2. 语法编译 + 仿真：
   - 功能仿真：iverilog `-g2012`（**不定义 `SVA_ON`**）
   - SVA 回归：verilator `--assert -DSVA_ON` 或商业仿真器
   - iverilog 11 不支持 `assert property` 并发断言，不要用它跑 SVA
3. 质量门控：`python3 <skill根>/scripts/quality_gate.py <rtl.sv> <tb.sv> --strict`，零 error 零 warning

验证失败 → 把错误带回，派生 `rtl-developer` 修复 → 再验证。**绝不把未验证的代码交给用户。**

## SVA 断言文件（按需）

- 模块 `.sv` 内**不写任何断言**（`assert` / `assume` / `cover` / `restrict`），这条是强制的
- `.sva` 按需创建，不要求每个模块都有：
  - **建议创建**：接口协议/valid-ready 握手、状态机/onehot、FIFO/仲裁/指针回绕、CDC、计数器边界、关键不变量、参数范围影响正确性
  - **可以省略**：纯组合译码/选择、单级寄存器或 DFF 包装、连线/常量模块等简单逻辑
- 创建时使用同名 `<module>.sva`，参数校验也放在这里
- 在 `endmodule` 前最后一段引入：

```systemverilog
`ifdef SVA_ON
`include "fifo_sync.sva"
`endif
```

- `.sva` 不带 `module` / `endmodule`，会被 include 进模块作用域，可直接引用模块内参数、端口、信号

## 对齐（强制）

- 代码中**不加任何对齐标记**（`@vlog-align` / `@inst` / `keep` 一律不用）
- 使用 rtl_align 插件的 `:RtlAlign`（普通模式，整个缓冲区）做全量对齐；插件已配置为空标记自动识别
- 对齐规则：普通列 4 格网格、packed 维度链单空格紧凑、**逗号行尾**、末项无逗号、幂等
- 对齐插件不可用时按规范手工对齐，并在交付说明里注明

## 硬性规范

- 命名/对齐/逗号行尾按 `references/rtl-coding-standard.md`
- 有统一 DFF 单元时寄存器一律例化，业务模块禁止裸 `always_ff`
- 例化端口只连信号，逻辑运算外部预处理
- 参数校验放 `.sva`，模块文件禁止 `initial`
- 成品代码不留任何对齐标记

## 状态汇报

随时汇报进度：需求 → 方案（复杂模块）→ 实现 → 验证 → 交付。
