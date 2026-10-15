# RTL 编码规范（SystemVerilog）

> 通用数字 IC 设计编码规范，适用于 SoC 总线、IP 模块等 RTL 开发。
> 目标：统一风格、提高可读性与可维护性、减少综合与仿真风险。
> 规范分三级：**必须**（违反需改）、**应该**（违反需说明）、**建议**（不强制）。

## 1. 命名规范

### 1.1 模块与文件

| 项 | 规则 | 示例 |
|---|---|---|
| 模块名 | 小写蛇形（snake_case） | `fifo_sync`、`rr_arbiter` |
| 文件名 | 与模块名一致，`.sv` 后缀 | `fifo_sync.sv` |
| 实例名 | **全大写** | `U_FIFO_SYNC` |
| package | `_pkg.sv` 后缀 | `axi_pkg.sv` |
| interface | `_if.sv` 后缀 | `axi_if.sv` |
| testbench | `_tb.sv` 后缀 | `fifo_sync_tb.sv` |

- 一个文件一个模块
- 子模块顶层用 `_top` 后缀；层级过深（>4 级）时保留两头缩写控制命名长度

### 1.2 端口信号

- ANSI-C 风格，一次声明方向/类型/位宽
- **无方向后缀**（`input`/`output` 关键字已体现方向）
- 功能相关信号用角色前缀分组：`wr_*`/`rd_*`（读写）、`s_*`/`m_*`（从/主）、`arb_*`（仲裁）

### 1.3 内部信号

| 类型 | 规则 | 示例 |
|---|---|---|
| 时钟 | `clk_*` | `clk_sys` |
| 复位 | `rst_*_n`（低有效） | `rst_n` |
| 计数器 | `*_cnt`，次态 `nxt_*_cnt` | `timeout_cnt` / `nxt_timeout_cnt` |
| 状态机 | `a_*_st`，次态 `nxt_a_*_st` | `a_fifo_st` / `nxt_a_fifo_st` |
| 低有效 | `*_n` | `ready_n` |
| 多级寄存 | `*_d1`/`_d2` | `data_d1` |
| 悬空 | `*_nc` | `unused_nc` |
| 三态 | `*_z` | `sda_z` |

### 1.4 类型后缀

| 类型 | 后缀 | 示例 |
|---|---|---|
| typedef logic | `_t` | `addr_t` |
| enum | `_e` | `fsm_state_e` |
| union | `_u` | `policy_u` |
| struct | `_s` | `tag_info_s` |
| function | `_f` | `get_tag_f` |
| package | `_pkg` | `comm_pkg` |

枚举项全大写；localparam 全大写。

### 1.5 单词缩写

| 单词 | 缩写 | | 单词 | 缩写 |
|---|---|---|---|---|
| valid | vld | | slave/master | slv/_s / mst/_m |
| ready | rdy | | current/next | cur/nxt |
| address | addr | | counter | cnt |
| command | cmd | | request | req |
| acknowledge | ack | | response | rsp |
| credit | crdt | | priority | pri |
| state | st | | status | sts |

禁止用关键字缩写；禁止只靠大小写区分命名。

## 2. 端口声明

### 2.1 格式

ANSI 风格，每行一个信号，方向/类型/位宽/名称列对齐（见 §13 对齐规范）：

```systemverilog
module fifo_sync #(
    parameter  DATA_W = 32
    ,parameter  DEPTH  = 16
) (
    input  logic               clk
    ,input  logic               rst_n
    ,input  logic               wr_en
    ,input  logic [DATA_W-1:0]  wr_data
    ,output logic [DATA_W-1:0]  rd_data
    ,output logic               empty
    ,output logic               full
);
```

### 2.2 端口顺序

按功能分段，相关信号放一起：
1. clk 与 rst_n
2. 配置/参数输入
3. 数据输入（valid-ready 对：valid → data → ready）
4. 数据输出
5. 状态/中断输出
6. 调试观测输出

### 2.3 valid-ready 握手

- 发送方 `valid` 寄存器输出，`data` 与 `valid` 同周期有效
- 接收方 `ready` 可为组合输出
- 握手成立 `valid && ready`
- 禁止 `valid` 依赖 `ready`（不能因 ready 拉低而撤销 valid）

## 3. 参数与 localparam

- 可配置项用 `parameter` 放端口列表；内部派生/固定值用 `localparam`
- 位宽用 `_W`、深度用 `_DEPTH`、数量用 `_NUM`
- 派生位宽用 `$clog2`/`$bits`，不手算

## 4. 模块组织

### 4.1 内部分区顺序

```
// 模块头注释
module xxx #(...) ( ... );

// --- Local Parameters ---
// --- Internal Signals ---
// --- Main Code（组合逻辑 + 寄存器例化）---
// --- DFX / Debug ---
// --- Assertion ---

endmodule
```

信号声明顺序与逻辑赋值顺序一致。

### 4.2 模块头注释（每个文件顶部必须有）

```systemverilog
//==============================================================================
// Module : fifo_sync
// Description : 同步 FIFO，写 1 读 0 时序
// Features :
//   - 参数化位宽/深度
//   - empty/full 寄存器输出
// Parameters :
//   DATA_W - 数据位宽，默认 32
//   DEPTH  - 深度，默认 16
// Limitations :
//   - 单时钟域
//==============================================================================
```

## 5. 编码风格

### 5.1 always 块

- 时序：`always_ff` + 非阻塞赋值 `<=`
- 组合：`always_comb` + 阻塞赋值 `=`
- 禁止 `always @(*)`，必须用 `always_comb`
- 禁止在同一块混用阻塞/非阻塞

### 5.2 case / if-else

- `case` 必须有 `default`；`if` 组合逻辑必须覆盖全分支或先赋默认值
- 互斥用 `unique case`，有优先级用 `priority case`
- 禁止 `casex`，慎用 `casez`

### 5.3 复位

- 默认异步复位、同步释放，低有效 `rst_n`

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位
    end else begin
        // 时序逻辑
    end
end
```

## 6. 状态机

- 两段式（次态组合 + 状态寄存器）或三段式（复杂/出口时序紧张时）
- 独热码（onehot）编码
- 命名 `a_*_st` / `nxt_a_*_st`，enum 类型 `*_e`

```systemverilog
typedef enum logic [2:0] {
    ST_IDLE = 3'b001,
    ST_RUN  = 3'b010,
    ST_DONE = 3'b100
} fsm_state_e;

fsm_state_e a_fifo_st, nxt_a_fifo_st;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) a_fifo_st <= ST_IDLE;
    else        a_fifo_st <= nxt_a_fifo_st;
end

always_comb begin
    nxt_a_fifo_st = a_fifo_st;
    unique case (a_fifo_st)
        ST_IDLE: if (start) nxt_a_fifo_st = ST_RUN;
        ST_RUN:  if (done)  nxt_a_fifo_st = ST_DONE;
        ST_DONE: nxt_a_fifo_st = ST_IDLE;
        default: nxt_a_fifo_st = ST_IDLE;
    endcase
end
```

## 7. 寄存器实现

### 7.1 推荐：统一 DFF 单元例化

项目提供带显式 `en` 使能的 DFF 单元时，寄存器一律通过它例化，禁止在业务模块直接写 `always_ff`。理由：显式 `en` 让综合工具精准插入时钟门控（ICG），并保证寄存器风格统一。

```systemverilog
// @vlog-align
logic   [W-1:0]     cnt     ;
logic   [W-1:0]     nxt_cnt ;
logic               cnt_en  ;

// @inst
dffr #(
    .W        (W      )
    ,.RESET_VAL ('0    )
) U_CNT (
    .clk    (clk    )
    ,.rst_n (rst_n  )
    ,.en    (cnt_en )
    ,.d     (nxt_cnt)
    ,.q     (cnt    )
);
```

（无 DFF 单元时直接 `always_ff`，但显式 en 的思想仍适用。）

### 7.2 en 使能条件

- `en` 必须连明确条件，禁止悬空
- 条件更新寄存器（指针/计数器）：`en` = 精确更新条件
- 状态寄存器：`en = (nxt != cur)`，状态不变关时钟
- 每拍加载：`en = 1'b1`，加注释说明
- 多 bit 合并例化（如 `entry_vld` 用宽 DFF），利于整体插 ICG

### 7.3 next 值

- next 用 `always_comb` 计算，命名 `nxt_*`，默认保持（`nxt = cur`）防锁存

### 7.4 存储体

- 用 DFF 数组例化（generate 循环），不用 `always_ff` 写 RAM
- 大深度建议专用 SRAM

## 8. 例化连接规则

端口连接只能写**信号名、参数名、字面常量**，禁止直接写逻辑运算式。运算必须在例化块外 `assign`/`always_comb` 预处理。

```systemverilog
// 正确
logic cnt_en;
assign cnt_en = wr_allow ^ rd_allow;
dffr #(.W(W), .RESET_VAL('0)) U_CNT (.clk(clk), .rst_n(rst_n), .en(cnt_en), .d(nxt_cnt), .q(cnt));

// 禁止：.en(wr_allow ^ rd_allow)
```

例外：参数值（`#(...)` 内）可写常量表达式。

## 9. 参数校验

**禁止 `initial begin/end` 过程块**。参数合法性检查用 SVA `initial` 序列断言（时间 0 检查一次）：

```systemverilog
`ifndef SYNTHESIS
    a_param_w: assert property (
        initial (DATA_W > 0 && DATA_W <= 1024)
    ) else $fatal(1, "[%m] DATA_W out of range, got %0d", DATA_W);
`endif
```

> SVA 中的 `initial` 是序列操作符，非过程块。testbench 可用 `initial`。

## 10. 可综合性

禁止：`initial` 块、`force/release`、`#delay`、`fork-join`、动态/关联数组、`class`、`$random`（RTL 中）、`casex`。

仿真专用代码用 `` `ifndef SYNTHESIS `` 隔离。

## 11. 低功耗

- 统一 DFF 例化 + 显式 `en` → 精准插 ICG
- 状态寄存器 `en = (nxt != cur)` 空闲关时钟
- 时钟门控用标准门控单元，禁止手工 latch+AND
- 未使用数据通路加使能隔离（操作数隔离）

## 12. DFT

- 寄存器可扫描，复位寄存器用可扫描 DFF
- 关键状态（指针/计数器）引出观测端口（可选参数控制）

## 13. 对齐规范

代码按统一列对齐，**幂等**。用 `@vlog-align` / `@inst` / `keep` 标记 + 对齐插件自动对齐。

### 13.1 标记

| 标记 | 用途 |
|---|---|
| `// @vlog-align` | 信号声明块对齐 |
| `// @inst` | 例化块对齐 |
| `// keep` | 跳过该行 |

### 13.2 规则

- 所有列左对齐；列起始 = 上一列结束 + 1 空格，向上取整到 4 的倍数
- packed 维度 `[MSB:LSB]` 拆 prefix（`[MSB` 左）/ suffix（`:LSB]` 右）
- 逗号行首：块内首项无逗号，其余项行首逗号
- 纯注释行不参与对齐
- module 声明（parameter + port）自动对齐

## 14. 断言

在关键位置加 SVA 断言：接口协议、内部不变量、corner 场景、onehot/stable 检查。从源头消除风险。

## 15. 质量门控

发布前必须通过 `quality_gate.py`（零 error 零 warning），检查：命名、模块头注释、端口/参数规范、参数校验、SVA、寄存器例化、例化连接、禁止 initial、复位风格、testbench/Makefile。
