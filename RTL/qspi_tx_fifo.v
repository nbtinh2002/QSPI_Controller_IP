module tx_fifo #(
    parameter FIFO_DEPTH      = 16
)(
    input  wire  clk,	
    input  wire  resetn,	

    // Write from CSR
    input  wire        tx_wen,
    input  wire [31:0] tx_data,		
    output wire        tx_full, 
    output wire [3:0]  tx_level,

    // Read to FSM
    input  wire        tx_ren, 
    output reg  [7:0]  tx_data,
    output wire        tx_empty
);
    reg [7:0] fifo_mem[0:FIFO_DEPTH-1];// FIFO_DEPTH(=16) bytes
    reg [5:0] wr_ptr; 
    reg [5:0] rd_ptr; 
    reg [5:0] level_cnt;

    assign fifo_empty = (level == 0);
    assign fifo_full  = (level == FIFO_DEPTH);
    assign level = level_cnt;

    // Write
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr <= 5'd0;
        end else if (wen && !fifo_full) begin
            fifo_mem[wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= data_in;
            wr_ptr <= wr_ptr + 5'd4;                     
        end
    end

    // Read
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ptr   <= 5'd0;
            data_out <= 5'd0;
        end else if (ren && !fifo_empty) begin
            data_out <= fifo_mem[rd_ptr[FIFO_ADDR_WIDTH-1:0]];
            rd_ptr   <= rd_ptr + 5'd1;
        end
    end

    // Level counter
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            level_cnt <= 5'd0;
        end else if(wen && !fifo_full) begin
            level_cnt <= level_cnt + 5'd4;
        end else if(ren && !fifo_empty) begin
            level_cnt <= level_cnt -5'd1;
        end else begin
            level_cnt <= level_cnt;
        end 
    end

endmodule