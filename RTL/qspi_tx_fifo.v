module qspi_tx_fifo #(
    parameter FIFO_DEPTH = 16 
)(
    input  wire        clk,
    input  wire        resetn,

    // Write side (CPU -> FIFO)
    input  wire        fifo_wen,
    input  wire [31:0] data_in,
    output wire        fifo_full,

    // Read side (FIFO -> QSPI)
    input  wire        fifo_ren,
    output reg  [7:0]  data_out,
    output wire        fifo_empty,

    output reg  [3:0]  fifo_level
);

    function integer log2;
        input integer value;
        integer i;
        begin
            log2 = 0;
            for (i = value-1; i > 0; i = i >> 1)
                log2 = log2 + 1;
        end
    endfunction

    reg [7:0] mem [0:FIFO_DEPTH-1];
    reg [log2(FIFO_DEPTH)-1:0] wr_ptr, rd_ptr;

    assign fifo_empty = (fifo_level == 0);
    assign fifo_full  = (fifo_level > (FIFO_DEPTH - 4));

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr     <= 0;
            fifo_level <= 0;
        end else if (fifo_wen && !fifo_full) begin
            mem[wr_ptr]                        <= data_in[31:24];
            mem[(wr_ptr + 1) & (FIFO_DEPTH-1)] <= data_in[23:16];
            mem[(wr_ptr + 2) & (FIFO_DEPTH-1)] <= data_in[15:8];
            mem[(wr_ptr + 3) & (FIFO_DEPTH-1)] <= data_in[7:0];
            wr_ptr     <= (wr_ptr + 4) & (FIFO_DEPTH-1);
            fifo_level <= fifo_level + 4;
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ptr   <= 0;
            data_out <= 8'h00;
        end else if (fifo_ren && !fifo_empty) begin
            data_out <= mem[rd_ptr];
            rd_ptr   <= (rd_ptr + 1) & (FIFO_DEPTH-1);
            fifo_level <= fifo_level - 1;
        end
    end

endmodule