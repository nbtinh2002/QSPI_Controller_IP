module tx_fifo #(
    parameter FIFO_DATA_WIDTH = 32,
    parameter FIFO_DEPTH      = 16
)(
    input  wire  clk,	
    input  wire  resetn,	

    // Write from CSR
    input  wire                       tx_wen,
    input  wire [FIFO_DATA_WIDTH-1:0] tx_data,		
    output wire                       tx_full, 
    output reg  [FIFO_ADDR_WIDTH:0]   tx_level,

    // Read to FSM
    input  wire                       tx_ren, 
    output reg  [FIFO_DATA_WIDTH-1:0] tx_data,
    output wire                       tx_empty
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value-1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction
    localparam FIFO_ADDR_WIDTH = clog2(FIFO_DEPTH);

    reg [7:0] fifo_mem[0:FIFO_DEPTH-1];  
    reg [FIFO_ADDR_WIDTH:0]   wr_ptr; 
    reg [FIFO_ADDR_WIDTH:0]   rd_ptr; 

    // Flags
    assign fifo_empty   = (level == 0);
    assign fifo_full    = (level == FIFO_DEPTH);

    // Write
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr <= 0;
        end else if (wen && !fifo_full) begin
            fifo_mem[wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= data_in;
            wr_ptr <= wr_ptr + 1;                       
        end
    end

    // Read
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ptr   <= 0;
            data_out <= 0;
        end else if (ren && !fifo_empty) begin
            data_out <= fifo_mem[rd_ptr[FIFO_ADDR_WIDTH-1:0]];
            rd_ptr   <= rd_ptr + 1;
        end
    end

    // Level counter
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            level <= 0;
        end else begin
            case ({wen && !fifo_full, ren && !fifo_empty})
                2'b10: level <= level + 1; // write only
                2'b01: level <= level - 1; // read only
                default: level <= level;
            endcase
        end
    end

endmodule