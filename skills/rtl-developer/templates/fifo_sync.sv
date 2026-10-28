`default_nettype none
//==============================================================================
// Module : fifo_sync
// Description : 同步 FIFO，单时钟域，每拍 1 项吞吐
// Features :
//   - 参数化位宽/深度，DEPTH 必须为 2 的幂且 >= 2
//   - valid-ready 接口
//   - 控制状态用 dffr，存储体用 dff（无复位）
// Parameters :
//   DATA_W - 数据位宽，默认 32
//   DEPTH  - 深度，默认 16（2 的幂）
// Limitations :
//   - 单时钟域；跨时钟域请用异步 FIFO
//   - 组合读数据，rd_data 仅在 rd_vld 有效时可信
//==============================================================================
module fifo_sync #(
    parameter   int DATA_W  =   32  ,
    parameter   int DEPTH   =   16
) (
    input   logic               clk     ,
    input   logic               rst_n   ,
    input   logic               wr_vld  ,
    output  logic               wr_rdy  ,
    input   logic [DATA_W -1:0] wr_data ,
    output  logic               rd_vld  ,
    input   logic               rd_rdy  ,
    output  logic [DATA_W -1:0] rd_data ,
    output  logic               empty   ,
    output  logic               full
);

localparam int PTR_W = $clog2(DEPTH);

logic [DEPTH-1:0][DATA_W-1:0] mem;

logic [DEPTH -1:0]  entry_vld       ;
logic [DEPTH -1:0]  nxt_entry_vld   ;
logic [DEPTH -1:0]  wr_oh           ;
logic [DEPTH -1:0]  rd_oh           ;
logic [PTR_W -1:0]  wr_ptr          ;
logic [PTR_W -1:0]  rd_ptr          ;
logic [PTR_W -1:0]  nxt_wr_ptr      ;
logic [PTR_W -1:0]  nxt_rd_ptr      ;
logic               wr_en           ;
logic               rd_en           ;
logic               entry_vld_en    ;

assign wr_en        = wr_vld && wr_rdy;
assign rd_en        = rd_vld && rd_rdy;
assign wr_rdy       = ~full;
assign rd_vld       = ~empty;
assign empty        = ~|entry_vld;
assign full         = &entry_vld;
assign nxt_wr_ptr   = wr_ptr + 1'b1;
assign nxt_rd_ptr   = rd_ptr + 1'b1;
assign entry_vld_en = wr_en | rd_en;

// 独热掩码：一个解码器代替每项一个比较器；写优先于同拍读同一项
assign wr_oh        = {{(DEPTH-1){1'b0}}, 1'b1} << wr_ptr;
assign rd_oh        = {{(DEPTH-1){1'b0}}, 1'b1} << rd_ptr;
assign nxt_entry_vld = (entry_vld & ~(rd_en ? rd_oh : '0))
                     | (wr_en ? wr_oh : '0);

always_comb begin
    rd_data = mem[rd_ptr];
end

dffr #(
    .W          (PTR_W  ),
    .RESET_VAL  ('0     )
) U_WR_PTR (
    .clk    (clk        ),
    .rst_n  (rst_n      ),
    .en     (wr_en      ),
    .d      (nxt_wr_ptr ),
    .q      (wr_ptr     )
);

dffr #(
    .W          (PTR_W  ),
    .RESET_VAL  ('0     )
) U_RD_PTR (
    .clk    (clk        ),
    .rst_n  (rst_n      ),
    .en     (rd_en      ),
    .d      (nxt_rd_ptr ),
    .q      (rd_ptr     )
);

dffr #(
    .W          (DEPTH  ),
    .RESET_VAL  ('0     )
) U_ENTRY_VLD (
    .clk    (clk            ),
    .rst_n  (rst_n          ),
    .en     (entry_vld_en   ),
    .d      (nxt_entry_vld  ),
    .q      (entry_vld      )
);

generate
    for (genvar i = 0; i < DEPTH; i++) begin : gen_mem
        logic entry_wr_en;

        assign entry_wr_en = wr_en && wr_oh[i];

        dff #(
            .W  (DATA_W )
        ) U_MEM (
            .clk    (clk            ),
            .en     (entry_wr_en    ),
            .d      (wr_data        ),
            .q      (mem[i]         )
        );
    end
endgenerate

`ifdef SVA_ON
`include "fifo_sync.sva"
`endif

endmodule

`default_nettype wire
