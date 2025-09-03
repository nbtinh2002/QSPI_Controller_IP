module qspi_fifo #(
    parameter FIFO_DEPTH = 16, 
    parameter WR_BYTES   = 4,   
    parameter RD_BYTES   = 4,
    parameter LEVEL_WIDTH = log2(FIFO_DEPTH)
)(
    input  wire clk,
    input  wire resetn,

    // Write side
    input  wire                     wr_en,
    input  wire [8*WR_BYTES-1:0]    data_in,
    output wire                     full,

    // Read side
    input  wire                     rd_en,
    output reg  [8*RD_BYTES-1:0]    data_out,
    output wire                     empty,

    output reg  [LEVEL_WIDTH-1:0]   level  
);

    //==== function log2 ====
    function integer log2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            log2 = i;
        end
    endfunction

    localparam PTR_WIDTH   = log2(FIFO_DEPTH);

    reg [7:0] mem [0:FIFO_DEPTH-1];
    reg [PTR_WIDTH-1:0] wr_ptr, rd_ptr;

    assign empty = (level == 0);
    assign full  = (level > (FIFO_DEPTH - WR_BYTES));

    integer i;
    wire [PTR_WIDTH:0] take_bytes = (level >= RD_BYTES) ? RD_BYTES : level;
    //==== Write logic ====
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr <= 0;
            level  <= 0;
        end else if (wr_en && !full) begin
            for (i=0; i<WR_BYTES; i=i+1) begin
                mem[(wr_ptr + i) & (FIFO_DEPTH-1)] <= data_in[8*(WR_BYTES-i)-1 -:8];
            end
            wr_ptr <= (wr_ptr + WR_BYTES) & (FIFO_DEPTH-1);
            level  <= level + WR_BYTES;
        end
    end

    //==== Read logic ====
always @(posedge clk or negedge resetn) begin
  if (!resetn) begin
    rd_ptr   <= 0;
    data_out <= {8*RD_BYTES{1'b0}};
  end else if (rd_en && !empty) begin
    for (i=0; i<RD_BYTES; i=i+1) begin
      if (i < take_bytes)
        data_out[8*(RD_BYTES-i)-1 -:8] <= mem[(rd_ptr + i) & (FIFO_DEPTH-1)];
      else
        data_out[8*(RD_BYTES-i)-1 -:8] <= 8'h00;
    end
    rd_ptr <= (rd_ptr + take_bytes) & (FIFO_DEPTH-1);
    level  <= level - take_bytes;
  end
end

endmodule
