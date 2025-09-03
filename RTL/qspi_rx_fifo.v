module qspi_rx_fifo #(
    parameter FIFO_DEPTH = 16
)(
    input  wire        clk,
    input  wire        resetn,

    // Write side (QSPI -> FIFO)
    input  wire        rx_wen,
    input  wire [7:0]  data_in,
    output wire        rx_full,

    // Read side (FIFO -> CPU)
    input  wire        rx_ren,
    output reg  [31:0] data_out,
    output wire        rx_empty,

    output reg  [3:0]  rx_level
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

    wire [2:0] take_bytes = (rx_level >= 4) ? 3'd4 : rx_level[2:0];
    reg [7:0] mem [0:FIFO_DEPTH-1];
    reg [log2(FIFO_DEPTH)-1:0] wr_ptr, rd_ptr;

    assign rx_empty = (rx_level == 0);
    assign rx_full  = (rx_level == FIFO_DEPTH);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr     <= 0;
            rx_level <= 0;
        end else if (rx_wen && !rx_full) begin
            mem[wr_ptr] <= data_in;
            wr_ptr      <= (wr_ptr + 1) & (FIFO_DEPTH-1);
            rx_level  <= rx_level + 1;
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ptr     <= 0;
            data_out   <= 32'h0;
        end else if (rx_ren && !rx_empty) begin
            data_out[31:24] <= (take_bytes >= 1) ? mem[rd_ptr] : 8'h00;
            data_out[23:16] <= (take_bytes >= 2) ? mem[(rd_ptr + 1) & (FIFO_DEPTH-1)] : 8'h00;
            data_out[15:8]  <= (take_bytes >= 3) ? mem[(rd_ptr + 2) & (FIFO_DEPTH-1)] : 8'h00;
            data_out[7:0]   <= (take_bytes >= 4) ? mem[(rd_ptr + 3) & (FIFO_DEPTH-1)] : 8'h00;

            rd_ptr     <= (rd_ptr + take_bytes) & (FIFO_DEPTH-1);
            rx_level <= rx_level - take_bytes;
        end
    end

endmodule