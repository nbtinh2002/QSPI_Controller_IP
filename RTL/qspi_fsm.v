//----------------------------------------------------------------------------------------------//
// Module: qspi_fsm.v
// Note:
//		- 1.Configuration
//		- 2.State Machine
//		- 3.CS Delay (Inter-transaction delay)
//		- 4.Clock Divider + CPOL/CPHA + Edge detect
//		- 5.Drive_IO outputs
//		- 6.Shifters & DATA-phase backpressure 
//		- 7.Counters
//		- 8.IO handling
//		- 9.OUTPUT handling
// Supports: lanes 1/2/4, opcode/address/mode/dummy/data phases, CPOL/CPHA, CS auto/manual, TX/RX FIFOs
//----------------------------------------------------------------------------------------------//
module qspi_fsm #(
	parameter	ADDR_WIDTH 		= 32,
	parameter	SUPPORT_HOLD_UP = 1
)(
	// QPSI Interface
	input  wire	qclk,
	input  wire	qresetn,
	output wire	sclk,
	output wire	cs_n,
	output wire	hold_n,
	output wire	wp_n,
	inout  wire	io0,
	inout  wire	io1,
	inout  wire	io2,
	inout  wire	io3,

  	// Input signal from CSR

	input wire [2:0] clk_div,	// CLK_DIV
	input wire		 quad_en,	// CTRL.bit2
	input wire		 cpol,		// CTRL.bit3
	input wire		 cpha,		// CTRL.bit4
	input wire		 lsb_first,	// CTRL.bit5
	input wire		 cs_auto,	// CS_CTRL.cs_auto
	input wire		 cs_level,	// CS_CTRL.cs_level
  	input wire [1:0] cs_delay,	// CS_CTRL.cs_delay

  	// Start/Done
  	input  wire	start,
	output wire	done,	
	
	// CMD & XIP field
	input wire [1:0] cmd_lanes,
	input wire [1:0] addr_lanes,
	input wire [1:0] data_lanes,
	input wire [1:0] addr_bytes,
	input wire 		 mode_en,
	input wire [3:0] dummy_cycles,
	input wire [7:0] mode_bits,	
	
	// XIP field
 	input wire		 xip_cont_read,
	input wire		 xip_write_en,
	input wire [7:0] xip_read_op,
	input wire [7:0] xip_write_op,

	// CMD field
	input wire 		  cmd_dir,	
	input wire [7:0]  cmd_opcode,
	input wire [31:0] cmd_addr,
	input wire [31:0] cmd_len,
	input wire [7:0]  cmd_extra_dummy,

  	// TX FIFO signals (IP -> flash)
	input  wire		  tx_empty,
	input  wire [7:0] tx_data_fifo,
	output reg		  tx_ren,
  
  	// RX FIFO signals (flash -> IP)
	input  wire		  rx_full,
	output reg [7:0]  rx_data_fifo,
	output reg		  rx_wen,
	
	// ERROR flag signals
	output reg underrun,// ERR_STAT.bit2
	output reg overrun,	// ERR_STAT.bit1
	output reg timeout	// ERR_STAT.bit0
);

	generate
		if (SUPPORT_HOLD_UP) begin : g_hold_wp
			assign hold_n = 1'b1;
			assign wp_n   = 1'b1;
		end else begin
			assign hold_n = 1'b1;
			assign wp_n   = 1'b1;
		end
	endgenerate	

	//==========================================================================================//
	// 1.Configuaration
	//==========================================================================================//
	localparam [2:0] IDLE=0, CS=1, CMD=2, ADDR=3, MODE=4, DUMMY=5, DATA=6, STOP_CS=7;
	localparam TIMEOUT_MAX = 32'd100000;

	reg [5:0] bits_sent;
    reg [31:0] byte_cnt; 
    reg [7:0] dummy_cnt; 

	wire [7:0] total_dummy_cycles = {4'd0,dummy_cycles} + cmd_extra_dummy;
	wire [5:0] addr_bits_need = (addr_bytes==2'd1) ? 6'd24 : 
								(addr_bytes==2'd2) ? 6'd32 : 6'd0;

  	wire [2:0] n_cmd_lanes  = quad_en ? 3'd4 :
										(cmd_lanes==2'd0) ? 3'd1 : 
										(cmd_lanes==2'd1) ? 3'd2 : 3'd4;
    wire [2:0] n_addr_lanes = quad_en ? 3'd4 :
										(addr_lanes==2'd0) ? 3'd1 : 
										(addr_lanes==2'd1) ? 3'd2 : 3'd4;
    wire [2:0] n_data_lanes = quad_en ? 3'd4 :
										(data_lanes==2'd0) ? 3'd1 : 
										(data_lanes==2'd1) ? 3'd2 : 3'd4;
   	reg [1:0] cs_gap_cnt;
	reg	gap_active;
	wire itd_done = (cs_gap_cnt >= cs_delay);
    wire start_ready = (!cs_auto) ? start : (start && (itd_done || !gap_active));
	
   	//===========================================================================================//
	// 2.State Machine
	//===========================================================================================//
	reg [2:0] state, next_state;

	always@(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			state	<= IDLE;
		end else begin
			state	<= next_state;
		end
	end

	always@(*) begin
		next_state = state;
		case(state)
			IDLE:
				next_state = (start_ready) ? CS : IDLE;
			CS:		
				next_state = CMD;
			CMD:begin
				if(bits_sent>= 6'd8) begin
					if(addr_bits_need!=0) 			next_state = ADDR;
					else if (cmd_len!=0) 			next_state = DATA;
					else 							next_state = STOP_CS;		
				end else begin
					next_state = CMD;
				end
				end
			ADDR:begin
				if(bits_sent >= addr_bits_need) begin
					if(mode_en) 					next_state = MODE;
					else if(total_dummy_cycles!=0) 	next_state = DUMMY;
					else if(cmd_len!=0) 			next_state = DATA;
					else 							next_state = STOP_CS;
				end else begin
					next_state = ADDR;
				end
				end			
			MODE:begin
				if(bits_sent >= 6'd8) begin
					if(total_dummy_cycles!=0) 	next_state = DUMMY;
				end else begin
					next_state = MODE;
				end
				end
			DUMMY: begin
				if(dummy_cnt >= total_dummy_cycles) begin 
					if(cmd_len!=0) 		next_state = DATA;
				end else begin
					next_state = DUMMY;
				end
				end
			DATA:begin
				if (underrun || overrun || timeout)	next_state = STOP_CS;
            	else if(byte_cnt >= cmd_len)		next_state = STOP_CS;
            	else                    			next_state = DATA;
				end
			STOP_CS:
				next_state = IDLE;
			default:
				next_state = IDLE;
		endcase
	end

	//==========================================================================================//
    // 3.CS_DELAY: Inter-transaction delay
    //==========================================================================================//
	always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			cs_gap_cnt	<= 2'd0;
			gap_active	<= 1'b0;
		end else if(state==STOP_CS && next_state==IDLE && cs_auto)begin
			cs_gap_cnt	<= 2'd0;
			gap_active	<= 1'b1;
		end else if(state==IDLE && gap_active) begin
			if(cs_gap_cnt < cs_delay) begin
				cs_gap_cnt	<= cs_gap_cnt + 2'd1;
			end else begin
				gap_active	<= 1'b0;
			end
		end else begin
			cs_gap_cnt	<= 2'd0;
		end
	end

 	//==========================================================================================//
	// 4.Clock divider + CPOL/CPHA + Edge detect
	//==========================================================================================//
	reg [7:0] div_cnt;
	reg		  sclk_core;
    wire 	  cs_active = (cs_auto ? (state!=IDLE && state!=STOP_CS) : (~cs_level));

	always@(posedge qclk or negedge qresetn) begin
		if(!qresetn||!cs_active) begin
			div_cnt		<= 8'd0;
			sclk_core	<= cpol;
		end else if(clk_div != 0) begin
			 if(div_cnt == ((8'd1<<(clk_div-1))-1)) begin
				div_cnt		<= 8'd0;
				sclk_core 	<= ~sclk_core;				
			end else begin
				div_cnt <= div_cnt + 8'd1;
			end
		end
	end

	assign sclk = (cs_active) ? ((clk_div!=0) ? (sclk_core^cpol) : (qclk^cpol)) : cpol;

    reg sclk_q;

    always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			sclk_q <= 1'b0;
		end else begin
			sclk_q <= sclk;
		end
    end

    wire sclk_rise =  sclk & ~sclk_q; 
    wire sclk_fall = ~sclk &  sclk_q;
	wire edge_sample = (cpha==1'b0) ? sclk_rise : sclk_fall;
    wire edge_shift  = (cpha==1'b0) ? sclk_fall : sclk_rise;

	//==========================================================================================//
	// 5.Drive IO outputs
	//==========================================================================================//
	reg [3:0] io_out, io_oe;
	wire [3:0] io_in;

	assign io0 = io_oe[0] ? io_out[0] : 1'bz;
	assign io1 = io_oe[1] ? io_out[1] : 1'bz;
	assign io2 = io_oe[2] ? io_out[2] : 1'bz;
	assign io3 = io_oe[3] ? io_out[3] : 1'bz;
	assign io_in = {io3, io2, io1, io0};

	//==========================================================================================//
	// 6.Shifters & DATA-phase backpressure
	//==========================================================================================//
	function [7:0] bit_reverse8;
    	input [7:0] din;
    	integer i;
    	begin
        	for (i=0; i<8; i=i+1)
        	    bit_reverse8[i] = din[7-i];
    	end
	endfunction

	reg [7:0] cmd_sh;
	reg [31:0]addr_sh;
	reg [7:0] mode_sh;
	reg [7:0] data_tx_sh;
	reg       data_tx_valid;
	reg [7:0] data_rx_sh;
	reg [2:0] data_rx_bitacc;
	reg [3:0] newbits;
	reg 	  tx_fetch_pending;

	// Stall logic
	wire stall_tx = (state==DATA) && (cmd_dir==1'b0) && (!data_tx_valid);
	wire stall_rx = (state==DATA) && (cmd_dir==1'b1) && (rx_full) && ((bits_sent+n_data_lanes)>=6'd8);
	wire stall_data = stall_tx || stall_rx;
	wire want_tx_byte = stall_tx && (bits_sent[2:0]==3'd0);
	
	wire eff_sample = edge_sample && (!stall_data);
	wire eff_shift = edge_shift && (!stall_data);

	// TX load and shift
	always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			cmd_sh		<=  8'h0;
        	addr_sh		<= 32'h0;
        	mode_sh		<=  8'h0;
        	data_tx_sh    	<= 	8'h0;
        	data_tx_valid 	<= 	1'b0;
			tx_ren			<=  1'b0;
			tx_fetch_pending<=  1'b0;
		end else begin
			tx_ren	<= 1'b0;
			// Load shifter
			if (state != next_state) begin
            	case (next_state)
                	CMD:cmd_sh <= (lsb_first) ? bit_reverse8(cmd_opcode) : cmd_opcode;
                	ADDR:begin
						if(addr_bits_need==6'd24) begin
							addr_sh <= (lsb_first) ? {bit_reverse8(cmd_addr[23:16]),
															bit_reverse8(cmd_addr[15:8]),
															bit_reverse8(cmd_addr[7:0]),8'h00} :
														{cmd_addr[23:0],8'h00};
						end else begin
							addr_sh <= (lsb_first) ? {bit_reverse8(cmd_addr[31:24]),
															bit_reverse8(cmd_addr[23:16]),
															bit_reverse8(cmd_addr[15:8]),
															bit_reverse8(cmd_addr[7:0])} :
														cmd_addr;
						end
					end
                	MODE:mode_sh <= lsb_first ? bit_reverse8(mode_bits) : mode_bits;
                	DATA:begin
						data_tx_valid <= 1'b0;
						tx_fetch_pending <= 1'b0;
					end
                	default:;
            	endcase
        	end
			// DATA write
        	if (want_tx_byte && !tx_fetch_pending) begin
            	if (!tx_empty) begin
                	tx_ren <= 1'b1;     
                	tx_fetch_pending <= 1'b1;
            	end
        	end else if (tx_fetch_pending) begin
            	tx_fetch_pending <= 1'b0;
            	data_tx_sh       <= (lsb_first) ? bit_reverse8(tx_data_fifo) : tx_data_fifo;
            	data_tx_valid    <= 1'b1;
        	end			
			// Shift out on eff_shift
			if(eff_shift) begin
				case(state)
					CMD: begin
						case (n_cmd_lanes)
                    		3'd1: cmd_sh  <= {cmd_sh[6:0],1'b0};
                    		3'd2: cmd_sh  <= {cmd_sh[5:0],2'b00};
                    		default: cmd_sh <= {cmd_sh[3:0],4'b0000};
                		endcase
					end
					ADDR: begin
						case (n_addr_lanes)
                    		3'd1: addr_sh <= {addr_sh[30:0],1'b0};
                    		3'd2: addr_sh <= {addr_sh[29:0],2'b00};
                    		default: addr_sh<= {addr_sh[27:0],4'b0000};
                		endcase
					end
					MODE: begin
						case (n_addr_lanes)
                    		3'd1: mode_sh <= {mode_sh[6:0],1'b0};
                    		3'd2: mode_sh <= {mode_sh[5:0],2'b00};
                    		default: mode_sh<= {mode_sh[3:0],4'b0000};
                		endcase
					end
					DATA: begin
						if(cmd_dir==1'b0) begin
							case (n_data_lanes)
                    			3'd1: data_tx_sh <= {data_tx_sh[6:0],1'b0};
                    			3'd2: data_tx_sh <= {data_tx_sh[5:0],2'b00};
                    			default: data_tx_sh<= {data_tx_sh[3:0],4'b0000};
                			endcase
							if (bits_sent + n_data_lanes >= 6'd8) data_tx_valid <= 1'b0;
						end
					end
				endcase
			end
		end
	end
	// RX path
	always @(posedge qclk or negedge qresetn) begin
	    if (!qresetn) begin
	        data_rx_sh     <= 8'h0;
	        data_rx_bitacc <= 3'd0;
	        rx_wen         <= 1'b0;
	        rx_data_fifo   <= 8'h0;
	    end else begin
			rx_wen	<= 1'b0;
			if(state==DATA && cmd_dir == 1'b1 && eff_sample) begin
				case (n_data_lanes)
	                3'd1: begin // Single IO
							newbits = {3'b000, io_in[1]};          							
							data_rx_sh     <= (data_rx_sh << 1) | newbits[0];
					end
	                3'd2: begin // Dual IO
							newbits = {2'b00, io_in[1], io_in[0]};
							data_rx_sh     <= (data_rx_sh << 2) | newbits[1:0];
					end
	                3'd4: begin // Quad IO
							newbits = io_in[3:0];
							data_rx_sh     <= (data_rx_sh << 4) | newbits[3:0];
					end
					default:;
	            endcase 
	            data_rx_bitacc <= data_rx_bitacc + n_data_lanes[2:0];
				if (data_rx_bitacc + n_data_lanes >= 4'd8) begin
	                rx_wen       <= !rx_full;
	                rx_data_fifo <= lsb_first ? bit_reverse8(data_rx_sh) : data_rx_sh;
	                data_rx_bitacc <= 3'd0;
	            end
			end else begin
				data_rx_bitacc <= 3'd0;
			end
		end
	end

	//==========================================================================================//
	// 7.Counters
	//==========================================================================================//
	// bit_sent
	always@(posedge qclk or negedge qresetn) begin 
		if(!qresetn) begin
			bits_sent	<= 6'd0;
		end else if(state!=next_state) begin
			bits_sent	<= 6'd0;
		end else begin
			case(state)
        		CMD :  if (eff_shift) bits_sent <= bits_sent + n_cmd_lanes;
        		ADDR:  if (eff_shift) bits_sent <= bits_sent + n_addr_lanes;
        		MODE:  if (eff_shift) bits_sent <= bits_sent + n_addr_lanes;
        		DATA:  if (eff_shift) bits_sent <= bits_sent + n_data_lanes;
				default:;
			endcase
		end	
	end
	
	// byte_cnt
    always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			byte_cnt <= 32'd0;
        end else if(state!=DATA) begin
			byte_cnt <= 32'd0;
        end else if(state==DATA&&eff_shift&&(bits_sent+n_data_lanes>=6'd8)) begin
            byte_cnt <= byte_cnt + 1;
		end 
	end
    
	// dummy_cnt
    always @(posedge qclk or negedge qresetn) begin
        if(!qresetn) begin
			dummy_cnt <= 8'd0;
        end else if (state!=DUMMY) begin
			dummy_cnt <= 8'd0;
		end else if (edge_shift) begin
			dummy_cnt <= dummy_cnt + 1;
		end 
	end

	//==========================================================================================//
	// 8.IO handling
	//==========================================================================================//
	wire [3:0] out_bits_cmd = (n_cmd_lanes==3'd1) ? {3'b000, cmd_sh[7]} :
 							  (n_cmd_lanes==3'd2) ? {2'b00,  cmd_sh[7:6]} : cmd_sh[7:4];

	wire [3:0] out_bits_addr = (n_addr_lanes==3'd1) ? {3'b000, addr_sh[31]} :
							   (n_addr_lanes==3'd2) ? {2'b00,  addr_sh[31:30]} : addr_sh[31:28];

	wire [3:0] out_bits_mode = (n_addr_lanes==3'd1) ? {3'b000, mode_sh[7]} :
    						   (n_addr_lanes==3'd2) ? {2'b00,  mode_sh[7:6]} : mode_sh[7:4];

	wire [3:0] out_bits_dataw = (n_data_lanes==3'd1) ? {3'b000, data_tx_sh[7]} :
    							(n_data_lanes==3'd2) ? {2'b00,  data_tx_sh[7:6]} : data_tx_sh[7:4];

	wire is_tx_phase = (state==CMD)||(state==ADDR)||(state==MODE)||(state==DATA&&cmd_dir==1'b0);

	wire [3:0] lane_mask = (state==CMD)  ? 
						   ((n_cmd_lanes==3'd1) ? 4'b0001:(n_cmd_lanes==3'd2) ? 4'b0011 : 4'b1111):
    					   (state==ADDR) ? 
						   ((n_addr_lanes==3'd1)? 4'b0001:(n_addr_lanes==3'd2)? 4'b0011 : 4'b1111):
    					   (state==MODE) ? 
						   ((n_addr_lanes==3'd1)? 4'b0001:(n_addr_lanes==3'd2)? 4'b0011 : 4'b1111):
    					   (state==DATA && cmd_dir==1'b0) ? 
						   ((n_data_lanes==3'd1)? 4'b0001:(n_data_lanes==3'd2)? 4'b0011 : 4'b1111):
    					   4'b0000;

	always @(posedge qclk or negedge qresetn) begin
    	if(!qresetn) begin
        	io_out <= 4'h0;
        	io_oe  <= 4'h0;
    	end else begin
			io_oe <= lane_mask;
        	if(is_tx_phase) begin
            	case (state)
                	CMD:  io_out <= out_bits_cmd;
                	ADDR: io_out <= out_bits_addr;
                	MODE: io_out <= out_bits_mode;
                	DATA: io_out <= out_bits_dataw;
                	default: io_out <= 4'h0;
            	endcase
			end else begin
           		io_out <= 4'h0;
            	io_oe  <= 4'h0;
        	end
    	end
	end

	//==========================================================================================//
    // 9.OUTPUT handling: CS_OUTPUT + DON PULSE + ERROR flag
    //==========================================================================================//
   	reg cs_n_reg;
	always@(*) begin
		if(!cs_auto) begin
			cs_n_reg = cs_level;
		end else begin
			case(state)
				CS, CMD, ADDR, MODE, DUMMY, DATA: 
                	cs_n_reg = 1'b0;
            	default:
                	cs_n_reg = 1'b1;
			endcase
		end
	end
	assign cs_n = cs_n_reg;

	reg done_r;
	always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			done_r <= 1'b0;
		end else begin
			done_r <= (state==STOP_CS && next_state==IDLE);
		end
	end
	assign done = done_r;

	reg [31:0] timeout_cnt;
	always@(posedge qclk or negedge qresetn) begin
    	if(!qresetn) begin
      		underrun <= 1'b0;
        	overrun  <= 1'b0;
        	timeout  <= 1'b0;
        	timeout_cnt  <= 32'd0;
    	end else begin
        	if(state == IDLE && start_ready) begin
            	underrun <= 1'b0;
            	overrun  <= 1'b0;
            	timeout  <= 1'b0;
            	timeout_cnt  <= 32'd0;
        	end
        	if(state==DATA && cmd_dir==1'b0 && !data_tx_valid && (bits_sent[2:0]==3'd0)&& tx_empty)    		
				underrun <= 1'b1;
        	if(state==DATA && cmd_dir==1'b1 && eff_sample && (data_rx_bitacc+n_data_lanes>=4'd8) && rx_full)
            	overrun <= 1'b1;
        	if (stall_data) begin
            	if (timeout_cnt >= TIMEOUT_MAX)
                	timeout <= 1'b1;
            	else
                	timeout_cnt <= timeout_cnt + 1;
        	end else begin
            	timeout_cnt <= 32'd0;
        	end
    	end
	end
endmodule
