`default_nettype none
//==============================================================================
// Module : cdc_2ff
// Description : 单 bit 电平跨时钟域同步器
// Features :
//   - STAGES 级同步，默认 2 级
//   - 目标时钟域异步复位
// Parameters :
//   STAGES - 同步级数，默认 2，必须 >= 2
// Limitations :
//   - 仅用于单 bit 电平信号
//   - 多 bit 数据必须用格雷码、握手或异步 FIFO
//==============================================================================
module cdc_2ff #(
    parameter   int STAGES  =   2
) (
    input   logic   clk         ,
    input   logic   rst_n       ,
    input   logic   async_in    ,
    output  logic   sync_out
);

logic [STAGES-1:0] sync_ff;
logic [STAGES-1:0] nxt_sync_ff;

assign nxt_sync_ff = {sync_ff[STAGES-2:0], async_in};

dffr #(
    .W          (STAGES ),
    .RESET_VAL  ('0     )
) U_SYNC_FF (
    .clk    (clk            ),
    .rst_n  (rst_n          ),
    .en     (1'b1           ),
    .d      (nxt_sync_ff    ),
    .q      (sync_ff        )
);

assign sync_out = sync_ff[STAGES-1];

`ifdef SVA_ON
`include "cdc_2ff.sva"
`endif

endmodule

`default_nettype wire
