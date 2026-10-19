# rtl_align — SystemVerilog / Verilog RTL 代码对齐插件

按统一列对齐规则格式化 RTL 代码，幂等（重复执行结果不变）。

## 效果

把下面这种参差不齐的声明：

```systemverilog
module m #(
parameter int W = 8,
parameter logic [7:0] RESET = 8'h00,
parameter N = 4
)(
input logic clk,
input logic [N-1:0][W-1:0] data,
output logic [7:0] result,
output logic valid
);
endmodule
```

对齐成：

```systemverilog
module m #(
parameter   int         W       =   8       ,
parameter   logic [7:0] RESET   =   8'h00   ,
parameter               N       =   4
)(
input   logic                   clk     ,
input   logic [N -1:0] [W -1:0] data    ,
output  logic [7   :0]          result  ,
output  logic                   valid
);
endmodule
```

信号声明块（用标记圈起来）：

```systemverilog
// @vlog-align
wire         [W -1:0]           a       ;
logic signed [7   :0]           longer  ;
logic        [3   :0] [15 :0]   matrix  ;
logic                           ready   ;
```

## 用法

- `:RtlAlign` — 对齐整个缓冲区
- `,aa`（普通/可视模式）— 对齐选中块（自动判断信号块 / 例化块）

## 标记

| 标记 | 作用 |
|---|---|
| `// @vlog-align` | 圈定信号声明块，从标记下一行到空行结束 |
| `// @inst` | 圈定模块例化块 |
| `// keep` | 行尾注释里带它，该行不参与对齐 |

module 声明（参数列表 + 端口列表）自动对齐，无需标记。

## 对齐规则

- 普通列 4 格网格对齐；packed 维度链（类型 → 各维前缀/后缀）内部单空格紧凑
- packed 维度逐维拆成前缀（左对齐）+ 后缀（右对齐），`[3:0][15:0]` 排成 `[3 :0] [15 :0]`
- 逗号行尾，末项无逗号、无行尾空格
- 幂等

## 可配置项

在 `.vimrc` 里覆盖（须放在插件加载前）：

```vim
" 信号声明块标记（默认 @vlog-align）
let g:rtl_align_signal_marker = '@vlog-align'
" 例化块标记（默认 @inst）
let g:rtl_align_inst_marker = '@inst'
" 跳过该行标记（默认 keep，写在行尾注释里，如 "logic a; // keep"）
let g:rtl_align_keep_marker = 'keep'
" 信号声明块 ≤ 此行数不处理（默认 3）
let g:rtl_align_min_signal_lines = 3
```

## 已知限制

暂不支持：行内注释作为对齐列、带初始化的信号声明（`= 8'h00`）、unpacked 数组尾部（`[0:3]`）。这几类行会被跳过不参与对齐。
