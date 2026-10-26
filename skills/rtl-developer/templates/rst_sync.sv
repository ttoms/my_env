`default_nettype none
//==============================================================================
// Module : rst_sync
// Description : 异步复位、同步释放
// Features :
//   - 复位异步拉低立即生效
//   - 释放经 STAGES 级同步，避免复位置位/撤销亚稳态
// Parameters :
//   STAGES - 同步级数，默认 2，必须 >= 2
// Limitations :
//   - 复位输入必须来自同一复位源
//==============================================================================
module rst_sync #(
    parameter   int STAGES  =   2
) (
    input   logic   clk         ,
    input   logic   rst_async_n ,
    output  logic   rst_n
);

logic [STAGES-1:0] rst_sync_ff;
logic [STAGES-1:0] nxt_rst_sync_ff;

assign nxt_rst_sync_ff = {rst_sync_ff[STAGES-2:0], 1'b1};

dffr #(
    .W          (STAGES ),
    .RESET_VAL  ('0     )
) U_RST_SYNC_FF (
    .clk    (clk                ),
    .rst_n  (rst_async_n        ),
    .en     (1'b1               ),
    .d      (nxt_rst_sync_ff    ),
    .q      (rst_sync_ff        )
);

assign rst_n = rst_sync_ff[STAGES-1];

`ifdef SVA_ON
`include "rst_sync.sva"
`endif

endmodule

`default_nettype wire
