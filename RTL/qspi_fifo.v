module qspi_fifo #(
    parameter FIFO_DEPTH  = 16,// Words
    parameter WR_BYTES    = 4,// Bytes
    parameter RD_BYTES    = 4// Bytes
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
    // Status
    output wire [3:0]               level,
    output wire [6:0]               ff_bytes_cnt
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

    localparam TOTAL_BYTES = FIFO_DEPTH * 4;
    localparam PTR_WIDTH   = log2(TOTAL_BYTES);

    // ------------------- Internal Signals -------------------
    integer i;
    reg  [31:0]         mem [0:FIFO_DEPTH-1];
    
    reg  [PTR_WIDTH:0]   wr_ptr, rd_ptr, addr_byte, byte_cnt;//byte
    reg  [PTR_WIDTH-2:0] word_idx;
    reg  [1:0]           byte_idx;

    wire [PTR_WIDTH:0]   take_bytes = (byte_cnt >= RD_BYTES) ? RD_BYTES : byte_cnt;
    wire [PTR_WIDTH-2:0] level_words = byte_cnt>>2;

    assign empty        = (byte_cnt==0);
    assign full         = (byte_cnt + WR_BYTES > TOTAL_BYTES);
    assign level        = level_words[3:0];
    assign ff_bytes_cnt = byte_cnt[6:0];
        
    // ------------------- Write Pointer Wrap-around -------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            for (i=0; i < WR_BYTES; i=i+1) begin
                // byte address
                addr_byte = (wr_ptr + i >= TOTAL_BYTES) ? (wr_ptr + i - TOTAL_BYTES) : (wr_ptr + i);
                // word & byte index
                {word_idx, byte_idx} = addr_byte;
                case(byte_idx)
                    2'd0: mem[word_idx][31:24] <= data_in[8*(WR_BYTES-1-i) +: 8];
                    2'd1: mem[word_idx][23:16] <= data_in[8*(WR_BYTES-1-i) +: 8];
                    2'd2: mem[word_idx][15:8 ] <= data_in[8*(WR_BYTES-1-i) +: 8];
                    2'd3: mem[word_idx][7:0  ] <= data_in[8*(WR_BYTES-1-i) +: 8];
                endcase
            end
            // update pointer
            wr_ptr <= (wr_ptr + WR_BYTES >= TOTAL_BYTES) ? (wr_ptr + WR_BYTES - TOTAL_BYTES) 
                                                         : (wr_ptr + WR_BYTES);
        end
    end

   // ------------------- Read Pointer Wrap-around -------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rd_ptr      <= 0;
            data_out    <= {8*RD_BYTES{1'b0}};
        end else if (rd_en && !empty) begin
            for (i=0; i < RD_BYTES; i=i+1) begin
                // byte address
                addr_byte = (rd_ptr + i >= TOTAL_BYTES) ? (rd_ptr + i - TOTAL_BYTES) : (rd_ptr + i);
                // word & byte index
                {word_idx, byte_idx} = addr_byte;
                if (i < take_bytes)
                    case (byte_idx)
                        2'd0: data_out[8*(RD_BYTES-1-i) +: 8] <= mem[word_idx][31:24];
                        2'd1: data_out[8*(RD_BYTES-1-i) +: 8] <= mem[word_idx][23:16];
                        2'd2: data_out[8*(RD_BYTES-1-i) +: 8] <= mem[word_idx][15:8];
                        2'd3: data_out[8*(RD_BYTES-1-i) +: 8] <= mem[word_idx][7:0];
                    endcase
                else data_out[8*(RD_BYTES-i)-1 -:8] <= 8'h00;
            end
            // update pointer
            rd_ptr <= (rd_ptr + take_bytes >= TOTAL_BYTES) ? (rd_ptr + take_bytes - TOTAL_BYTES)
                                                           : (rd_ptr + take_bytes);
        end
    end

    // ------------------- Byte Counter -------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            byte_cnt <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: byte_cnt <= byte_cnt + WR_BYTES;
                2'b01: byte_cnt <= byte_cnt - take_bytes;
                2'b11: byte_cnt <= byte_cnt + WR_BYTES - take_bytes;
                default: byte_cnt <= byte_cnt;
            endcase
        end
    end
endmodule
