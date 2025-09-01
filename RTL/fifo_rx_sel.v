module fifo_rx_sel(
    input           sel, //dma_anble
    output          ren,
    input           empty,
    input  [31:0]   data,

    input           dma_fifo_ren_i,   
    output          dma_fifo_empty_o,
    output   [31:0]  dma_fifo_data_o,

    input           cmd_fifo_ren_i, 
    output          cmd_fifo_empty_o,
    output   [31:0] cmd_fifo_data_o
);
    assign ren                 = sel ? dma_fifo_ren_i : cmd_fifo_ren_i;
    assign dma_fifo_empty_o    = sel ? empty : 1'b1;
    assign cmd_fifo_empty_o    = sel ? 1'b1  : empty;

    assign dma_fifo_data_o  = sel ? data : 32'd0;
    assign cmd_fifo_data_o   = sel ? 32'd0 : data;

endmodule