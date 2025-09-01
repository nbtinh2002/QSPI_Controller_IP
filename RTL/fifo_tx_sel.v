module fifo_tx_sel(
    input           sel, //dma_anble
    output          wen,
    input           full,
    output  [31:0]  data,

    input           dma_wen_i,   
    output          dma_full_o,
    input   [31:0]  dma_data_i,

    input           cmd_wen_i, 
    output          cmd_full_i,
    input   [31:0]  cmd_data_i
);
    assign wen          = sel ? dma_wen_i:cmd_wen_i;
    assign dma_full_o   = sel ? full : 1'b1;
    assign cmd_full_i    = sel ? 1'b1 : full;
    assign data         = sel ? dma_data_i: cmd_data_i;

endmodule