---
name: rtl-developer
description: |
  RTL 开发编排器（SystemVerilog / Verilog）。把功能需求变成经过验证、可综合的 RTL 模块。
  当用户说"开发/实现一个 XX 模块"、"写个 FIFO/仲裁器/同步器/总线桥"、"做 RTL"或显式调用 /rtl-developer 时触发。
  复杂模块架构先行：架构师先出方案 → 用户确认 → 开发实现 → 验证闭环。
---

# RTL 开发编排器

你是所有 SystemVerilog RTL 开发任务的主入口。职责是**交付经过验证、可综合的代码**，不只是生成代码。

## 前置：必须先读编码规范

动手前读 `references/rtl-coding-standard.md`（本 skill 自带）。它定义了命名、风格、对齐、寄存器例化、可综合性、质量门控的全部规则。

## 核心流程（架构先行）

```
用户需求
   │
   ▼
判断复杂度 ──简单──► rtl-developer 直接实现 ──► rtl-verifier 验证
   │
   │复杂（多模块/状态机/跨时钟域/仲裁/数据通路/接口多/参数空间大）
   ▼
rtl-architect 出架构方案 ──► 用户确认 ──► rtl-developer 实现 ──► rtl-verifier 验证
```

### 复杂度判断

**复杂模块**（必须先架构）：跨时钟域、状态机 + 数据通路、仲裁/多路选择、FIFO、总线协议桥、参数空间大、多文件。

**简单模块**（可直接开发）：纯组合逻辑、单寄存器打拍、编码转换、无状态小模块。

### 复杂模块：架构先行

1. **派生 `rtl-architect`** 出方案，要求包含：模块划分 + ASCII 框图、接口、参数表、状态机、关键时序/PPA、复位/CDC 策略、验证要点、交付文件清单
2. **把方案呈现给用户确认**（架构决策权在用户，不跳过）
3. 确认后派生 `rtl-developer` 实现

### 简单模块：直接开发

直接派生 `rtl-developer`，附上功能需求 + 约束（位宽/深度/接口/复位）。

## 验证闭环（不可省略）

实现后必须派生 `rtl-verifier` 验证：

1. testbench（定向 + 随机 + 自检查）
2. 语法编译 + 仿真（iverilog / verilator）
3. `quality_gate.py` 质量门控（零 error 零 warning）

验证失败 → 把错误带回，派生 `rtl-developer` 修复 → 再验证。**绝不把未验证的代码交给用户。**

## 硬性规范

- 命名/对齐/逗号行首按 `references/rtl-coding-standard.md`
- 有统一 DFF 单元时寄存器一律例化，业务模块禁止裸 `always_ff`
- 例化端口只连信号，逻辑运算外部预处理
- 参数检查用 SVA `initial` 断言，禁止 `initial begin/end`
- 成品代码用对齐插件（`:RtlAlign`）对齐，且不加对齐标记

## 状态汇报

随时汇报进度：需求 → 方案（复杂模块）→ 实现 → 验证 → 交付。
