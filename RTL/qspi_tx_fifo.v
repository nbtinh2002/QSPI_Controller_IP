module qspi_tx_fifo #(
    parameter FIFO_DEPTH = 16
)(
    input wire  clk,	
    input wire  resetn,	

    // Write from CSR
    input  wire        fifo_wen,
    input  wire [31:0] data_in,		
    output wire        fifo_full, 
    output wire [3:0]  fifo_level,

    // Read to FSM
    input  wire        fifo_ren, 
    output reg  [7:0]  data_out,
    output wire        fifo_empty
);
    reg [7:0] fifo_mem[0:FIFO_DEPTH-1];
    reg [4:0] wr_ptr, rd_ptr; 

    assign fifo_empty = (wr_ptr == rd_ptr); 
    assign fifo_full = (fifo_level > FIFO_DEPTH - 4);
    wire [4:0] level_diff = (wr_ptr[4] != rd_ptr[4]) ? (wr_ptr[3:0] + FIFO_DEPTH - rd_ptr[3:0]) : 
                                                       (wr_ptr[3:0] - rd_ptr[3:0]);
    assign fifo_level = level_diff[3:0];

    // Write
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr <= 5'd0;
        end else if (fifo_wen && !fifo_full) begin
            fifo_mem[wr_ptr[3:0]]     <= data_in[31:24];
            fifo_mem[wr_ptr[3:0] + 1] <= data_in[23:16];
            fifo_mem[wr_ptr[3:0] + 2] <= data_in[15:8];
            fifo_mem[wr_ptr[3:0] + 3] <= data_in[7:0];
            wr_ptr <= wr_ptr + 5'd4;                     
        end
    end

    // Read
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ptr   <= 5'd0;
            data_out <= 8'd0;
        end else if (fifo_ren && !fifo_empty) begin
            data_out <= fifo_mem[rd_ptr[3:0]];
            rd_ptr   <= rd_ptr + 5'd1;
        end
    end
endmodule