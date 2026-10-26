`timescale 1ns/1ps

module fifo_sync_tb;

localparam int DATA_W = 8;
localparam int DEPTH  = 4;

logic               clk     ;
logic               rst_n   ;
logic               wr_vld  ;
logic               wr_rdy  ;
logic [DATA_W -1:0] wr_data ;
logic               rd_vld  ;
logic               rd_rdy  ;
logic [DATA_W -1:0] rd_data ;
logic               empty   ;
logic               full    ;

fifo_sync #(
    .DATA_W (DATA_W ),
    .DEPTH  (DEPTH  )
) U_DUT (
    .clk        (clk        ),
    .rst_n      (rst_n      ),
    .wr_vld     (wr_vld     ),
    .wr_rdy     (wr_rdy     ),
    .wr_data    (wr_data    ),
    .rd_vld     (rd_vld     ),
    .rd_rdy     (rd_rdy     ),
    .rd_data    (rd_data    ),
    .empty      (empty      ),
    .full       (full       )
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

initial begin
    rst_n   = 1'b0;
    wr_vld  = 1'b0;
    wr_data = '0;
    rd_rdy  = 1'b0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    for (int i = 0; i < DEPTH; i++) begin
        @(negedge clk);
        wr_vld  = 1'b1;
        wr_data = i[DATA_W-1:0];
        @(posedge clk);
        if (!wr_rdy) begin
            $fatal(1, "[%m] unexpected write stall at %0d", i);
        end
    end

    @(negedge clk);
    wr_vld = 1'b0;
    if (!full) begin
        $fatal(1, "[%m] FIFO should be full");
    end
    if (empty) begin
        $fatal(1, "[%m] FIFO should not be empty");
    end

    for (int i = 0; i < DEPTH; i++) begin
        @(negedge clk);
        rd_rdy = 1'b1;
        #1;
        if (!rd_vld) begin
            $fatal(1, "[%m] missing rd_vld at %0d", i);
        end
        if (rd_data !== i[DATA_W-1:0]) begin
            $fatal(1, "[%m] data mismatch: got %0d, exp %0d", rd_data, i);
        end
        @(posedge clk);
    end

    @(negedge clk);
    rd_rdy = 1'b0;
    #1;
    if (!empty) begin
        $fatal(1, "[%m] FIFO should be empty");
    end
    if (rd_vld) begin
        $fatal(1, "[%m] rd_vld should be low when empty");
    end

    repeat (2) @(posedge clk);
    $display("[%m] PASS");
    $finish;
end

endmodule
