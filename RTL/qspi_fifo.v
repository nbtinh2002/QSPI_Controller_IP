module qspi_fifo #(
    parameter FIFO_DEPTH  = 16, // số word
    parameter WR_BYTES    = 4,
    parameter RD_BYTES    = 4
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

    output wire [3:0]               level,
    output wire [6:0]               byte_level
);

    //==== function log2 ==== 
    function integer log2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i=0; value>0; i=i+1)
                value = value >> 1;
            log2 = i;
        end
    endfunction

    localparam WORD_BYTES  = 4;
    localparam TOTAL_BYTES = FIFO_DEPTH*WORD_BYTES;
    localparam PTR_WIDTH   = log2(TOTAL_BYTES);

    // con trỏ byte
    reg [PTR_WIDTH:0] wr_byte_ptr, rd_byte_ptr;
    reg [PTR_WIDTH:0] level_bytes, level_words;

    reg [31:0] mem [0:FIFO_DEPTH-1];

    // level theo word = byte_level/WORD_BYTES
    assign level_words = level_bytes / WORD_BYTES;
    assign level = level_words[3:0];
    assign byte_level = level_bytes;

    assign empty = (level_bytes==0);
    assign full  = (level_bytes + WR_BYTES > TOTAL_BYTES);

    wire [PTR_WIDTH:0] take_bytes = 
        (level_bytes >= RD_BYTES) ? RD_BYTES : level_bytes;

    integer i;
    integer addr_byte;
    integer word_idx;
    integer byte_off;

    //==== Write Pointer Wrap-around ====
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        wr_byte_ptr <= 0;
    end else if (wr_en && !full) begin
        for (i=0; i<WR_BYTES; i=i+1) begin
            addr_byte = wr_byte_ptr + i;
            if (addr_byte >= TOTAL_BYTES) addr_byte = addr_byte - TOTAL_BYTES;
            word_idx = addr_byte >> 2;          // addr / WORD_BYTES
            byte_off = addr_byte[1:0];          // addr % WORD_BYTES

            mem[word_idx][8*(WORD_BYTES-1-byte_off) +: 8]
                <= data_in[8*(WR_BYTES-i)-1 -: 8];
            mem[word_idx][8*(WORD_BYTES-1-byte_off) +:8] 
                <= data_in[8*(WR_BYTES-i)-1 -:8];
        end
        if (wr_byte_ptr + WR_BYTES >= TOTAL_BYTES)
            wr_byte_ptr <= wr_byte_ptr + WR_BYTES - TOTAL_BYTES;
        else
            wr_byte_ptr <= wr_byte_ptr + WR_BYTES;
    end
end


   //==== Read Pointer Wrap-around ====
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        rd_byte_ptr <= 0;
        data_out    <= {8*RD_BYTES{1'b0}};
    end else if (rd_en && !empty) begin
        for (i=0; i<RD_BYTES; i=i+1) begin
            addr_byte = rd_byte_ptr + i;
            if (addr_byte >= TOTAL_BYTES) addr_byte = addr_byte - TOTAL_BYTES;
            word_idx = addr_byte >> 2;          // addr / WORD_BYTES
            byte_off = addr_byte[1:0];          // addr % WORD_BYTES

            if (i < take_bytes)
                data_out[8*(RD_BYTES-i)-1 -:8] 
                    <= mem[word_idx][8*(WORD_BYTES-1-byte_off) +:8];
            else
                data_out[8*(RD_BYTES-i)-1 -:8] <= 8'h00;
        end
        if (rd_byte_ptr + take_bytes >= TOTAL_BYTES)
            rd_byte_ptr <= rd_byte_ptr + take_bytes - TOTAL_BYTES;
        else
            rd_byte_ptr <= rd_byte_ptr + take_bytes;
    end
end
    //==== Level (byte counter) ====
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            level_bytes <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: level_bytes <= level_bytes + WR_BYTES;
                2'b01: level_bytes <= level_bytes - take_bytes;
                2'b11: level_bytes <= level_bytes + WR_BYTES - take_bytes;
                default: level_bytes <= level_bytes;
            endcase
        end
    end

endmodule
