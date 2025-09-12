module qspi_xip #(
    parameter integer DATA_WIDTH      = 32,
    parameter integer AXI_ADDR_WIDTH  = 32,
    parameter SUPPORT_XIP_WRITE       = 0 
)(
    input   clk,
    input   resetn,
    // QSPI FSM
    output reg                      xip_start_o,
    output reg [AXI_ADDR_WIDTH-1:0] xip_addr_o,
    output reg [31:0]               xip_len_o,
    output reg                      xip_dir_o,

    //RX FIFO
    input [DATA_WIDTH-1:0] xip_data_i,
    input       xip_rx_full,
    output reg  xip_rx_ren_o,

    // CSR Signals
    input       xip_en_i, xip_qspi_done_i,
    output reg  xip_active_o,
    output reg  xip_done_o,

    input      [1:0] xip_cmd_lanes_i,
    input      [1:0] xip_addr_lanes_i,
    input      [1:0] xip_data_lanes_i,
    input      [1:0] xip_addr_bytes_i,
    input      [3:0] xip_dummy_cycles_i,
    input            xip_mode_en_i,
    input            xip_cont_read_i,
    input            xip_write_en_i,
    input      [7:0] xip_read_op_i,
    input      [7:0] xip_mode_bits_i,

    output reg [1:0] xip_cmd_lanes_o,
    output reg [1:0] xip_addr_lanes_o,
    output reg [1:0] xip_data_lanes_o,
    output reg [1:0] xip_addr_bytes_o,
    output reg [3:0] xip_dummy_cycles_o,
    output reg       xip_mode_en_o,
    output reg       xip_cont_read_o,
    output reg [7:0] xip_opcode_o,
    output reg [7:0] xip_mode_bits_o,

    // AXI4 Slave Interface
    input  wire                     s_arvalid,
    output reg                      s_arready,
    input  wire [AXI_ADDR_WIDTH-1:0]s_araddr,
    input  wire [2:0]               s_arsize,// 1 beat = 2^arsize (bytes) default:010
    input  wire [7:0]               s_arlen, // burst length = arlen + 1 (beat)
    input  wire [1:0]               s_arburst,// FIXED:00, INCR:01, WRAP:10

    output reg  [DATA_WIDTH-1:0]    s_rdata,
    output reg                      s_rlast,
    output reg                      s_rvalid,
    input  wire                     s_rready
);

    // ------------------- FSM states -------------------
    localparam [1:0] IDLE = 0, AR_ACCEPT = 1, WAIT_FSM = 2, SEND_DATA = 3;
    reg [1:0] state, next_state;
    
    // ------------------- Registers -------------------
    reg [2:0]   arsize_q;
    reg [1:0]   arburst_q;
    reg [7:0]   arlen_q;
    reg [15:0]  beats_total, beats_sent;
    reg         xip_qspi_done_q;
    reg         rready_latch;
    reg [1:0] byte_offset;
    // ------------------- Sequential FSM -------------------
     always@(posedge clk or negedge resetn) begin
        if(!resetn) state <= IDLE;
        else state <= next_state;
    end

    // ------------------- Next state logic -------------------
    always@(*) begin  
        next_state = state;
        case(state)
            IDLE:      if(xip_en_i && s_arvalid) next_state = AR_ACCEPT;
            AR_ACCEPT: next_state = WAIT_FSM;
            WAIT_FSM:  if(xip_qspi_done_i) next_state = SEND_DATA;
            SEND_DATA: if (beats_sent >= beats_total) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // ------------------- State actions -------------------
    always@(posedge clk or negedge resetn) begin
        if(!resetn) begin
            s_arready       <= 1'b0;
            xip_start_o     <= 1'b0;
            xip_addr_o      <= {AXI_ADDR_WIDTH{1'b0}};
            xip_len_o       <= 32'd0;
            arsize_q        <= 3'd0;
            arburst_q       <= 2'd0;
            arlen_q         <= 8'd0;
            beats_total     <= 16'd0;
            beats_sent      <= 16'd0;
            s_rdata         <= {DATA_WIDTH{1'b0}};
            s_rlast         <= 1'b0;
            s_rvalid        <= 1'b0;
            xip_qspi_done_q <= 1'b0;
            xip_rx_ren_o    <= 1'b0;
            xip_done_o      <= 1'b0;
            rready_latch    <= 0;
        end else begin
            rready_latch    <= 0;
            xip_rx_ren_o    <= 1'b0;
            case(state)
            IDLE: begin
                s_arready   <= xip_en_i ? 1'b1 : 1'b0;
                xip_start_o <= 1'b0;
                s_rvalid    <= 1'b0;
                beats_sent  <= 16'd0;
                xip_start_o <= 1'b0;
                xip_done_o  <= 1'b0;
            end
            AR_ACCEPT: begin
                s_arready   <= 1'b0; // accepted; clear ready
                xip_start_o <= 1;// pulse start
                xip_active_o <= 1;
                arsize_q    <= s_arsize;
                arburst_q   <= s_arburst;
                arlen_q     <= s_arlen;
                beats_total <= s_arlen + 1;
                beats_sent  <= 16'd0;
                xip_addr_o  <= s_araddr;
                xip_len_o   <= ((s_arlen + 8'd1) << s_arsize);
                s_rvalid    <= 1'b0;
                s_rlast     <= 1'b0;
            end
            WAIT_FSM: begin
                xip_start_o <= 1'b0;
                if (xip_qspi_done_i && !xip_rx_full) begin
                    xip_qspi_done_q <= 1'b1;
                    xip_rx_ren_o    <= 1'b1;
                end
                if(xip_qspi_done_q) begin
                    s_rvalid        <= 1'b1;
                    xip_qspi_done_q <= 1'b0;
                    xip_rx_ren_o    <= 1'b0;
                    beats_sent      <= 16'd0;
                end
                
            end
            SEND_DATA: begin
                case (arsize_q)
                    3'd0: begin // 1 byte
                        case (byte_offset)
                            2'd0: s_rdata <= {24'd0, xip_data_i[31:24]};
                            2'd1: s_rdata <= {24'd0, xip_data_i[23:16]};
                            2'd2: s_rdata <= {24'd0, xip_data_i[15:8]};
                            2'd3: s_rdata <= {24'd0, xip_data_i[7:0]};
                            default: s_rdata <= 32'd0;
                        endcase
                    end
                    3'd1: begin // 2 byte
                        case (byte_offset[1]) 
                            1'b0: s_rdata <= {16'd0, xip_data_i[31:16]};
                            1'b1: s_rdata <= {16'd0, xip_data_i[15:0]};
                        endcase
                    end
                    3'd2: begin // 4 byte
                        s_rdata <= xip_data_i;
                    end
                    default: s_rdata <= 32'd0;
                endcase

                if (!s_rvalid && beats_sent < beats_total) begin
                    xip_rx_ren_o <= 1'b1;
                    s_rdata  <= xip_data_i;
                    s_rvalid <= 1'b1;
                    s_rlast  <= (beats_sent == beats_total-1);
                end


                if (s_rvalid && s_rready) begin
                    beats_sent <= beats_sent + 1;
                    s_rvalid   <= 1'b0; // clear valid
                    if (s_rlast) begin
                        xip_done_o <= 1'b1;
                        xip_active_o <= 1'b0;
                    end
                end
            end
            default: begin
                s_arready <= 1'b0;
                xip_start_o <= 1'b0;
            end
            endcase
        end
    end
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            byte_offset <= 2'd0;
        end else if (state == AR_ACCEPT) begin
            byte_offset <= 0; // khởi tạo offset theo địa chỉ base
        end else if (s_rvalid && s_rready) begin
            byte_offset <= byte_offset + (1 << arsize_q); // tăng theo kích thước beat
        end
    end
    // ------------------- Forward CSR config -------------------
    always @(*) begin
        xip_cmd_lanes_o     = xip_en_i ? xip_cmd_lanes_i : 0;
        xip_addr_lanes_o    = xip_en_i ? xip_addr_lanes_i : 0;
        xip_data_lanes_o    = xip_en_i ? xip_data_lanes_i : 0;
        xip_addr_bytes_o    = xip_en_i ? xip_addr_bytes_i : 0;
        xip_dummy_cycles_o  = xip_en_i ? xip_dummy_cycles_i : 0;
        xip_mode_en_o       = xip_en_i ? xip_mode_en_i : 0;
        xip_cont_read_o     = xip_en_i ? xip_cont_read_i : 0;
        xip_mode_bits_o     = xip_en_i ? xip_mode_bits_i : 0;
        if(SUPPORT_XIP_WRITE) begin
            xip_opcode_o    = xip_en_i ? (xip_write_en_i ? 0 : xip_read_op_i) : 0;
            xip_dir_o       = xip_en_i ? (xip_write_en_i ? 1'b0 : 1'b1) : 1'b1;
        end else begin
            xip_opcode_o    = xip_en_i ? xip_read_op_i : 8'd0;
            xip_dir_o       = 1'b1;// read only
        end
    end
endmodule