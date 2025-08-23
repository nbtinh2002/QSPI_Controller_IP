module qspi_fifo #(
    parameter FIFO_DEPTH   = 16,
    parameter WRITE_WIDTH  = 32,   
    parameter READ_WIDTH   = 32    
    )(
    input  wire                 clk,
    input  wire                 resetn,

    // Write side
    input  wire                 fifo_wen,
    input  wire [WRITE_WIDTH-1:0] data_in,
    output wire                 fifo_full,

    // Read side
    input  wire                 fifo_ren,
    output reg  [READ_WIDTH-1:0] data_out,
    output wire                 fifo_empty,
    output wire [3:0]           fifo_level
);
    // Memory for FIFO
    reg [7:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [4:0] wr_ptr, rd_ptr;

    // FIFO level calculation
    wire [5:0] level_diff = (wr_ptr[4] != rd_ptr[4]) ?
                            (wr_ptr[3:0] + FIFO_DEPTH - rd_ptr[3:0]) :
                            (wr_ptr[3:0] - rd_ptr[3:0]);
    assign fifo_level = level_diff[3:0];

    // FIFO status signals
    assign fifo_empty = (level_diff < READ_WIDTH/8);
    assign fifo_full = (level_diff > FIFO_DEPTH - WRITE_WIDTH/8);

    // WRITE logic
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin 
            wr_ptr <= 5'd0;
        end else if (fifo_wen && !fifo_full) begin
            if (WRITE_WIDTH == 32) begin
                fifo_mem[wr_ptr[3:0]]     <= data_in[31:24];
                fifo_mem[wr_ptr[3:0] + 1] <= data_in[23:16];
                fifo_mem[wr_ptr[3:0] + 2] <= data_in[15:8];
                fifo_mem[wr_ptr[3:0] + 3] <= data_in[7:0];
                wr_ptr <= wr_ptr + 5'd4;
            end else if (WRITE_WIDTH == 8) begin
                fifo_mem[wr_ptr[3:0]] <= data_in[7:0];
                wr_ptr <= wr_ptr + 5'd1;
            end
        end
    end

    // READ logic
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ptr   <= 5'd0;
            data_out <= {READ_WIDTH{1'b0}};
        end else if (fifo_ren && !fifo_empty) begin
            if (READ_WIDTH == 8) begin
                data_out <= fifo_mem[rd_ptr[3:0]];
                rd_ptr   <= rd_ptr + 5'd1;
            end else if (READ_WIDTH == 32) begin
                data_out[31:24] <= fifo_mem[rd_ptr[3:0]];
                data_out[23:16] <= fifo_mem[rd_ptr[3:0] + 1];
                data_out[15:8]  <= fifo_mem[rd_ptr[3:0] + 2];
                data_out[7:0]   <= fifo_mem[rd_ptr[3:0] + 3];
                rd_ptr <= rd_ptr + 5'd4;
            end
        end
    end
endmodule
