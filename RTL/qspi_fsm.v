//===============================================================================================//
// Module: qspi_fsm.v																			 //
// Note:																						 //
//		+ CONFIGURATION & PARAMETERS															 //
//		+ STATE MACHINE																			 //
//		+ CS_DELAY & CS_N																		 //
//		+ CLOCK DIVIDER - DETECT EDGE															 //
//		+ IO PREPARATION + DRIVE LOGIC															 //
//		+ SHIFT DATA (WRITE)																	 //
//		+ SAMPLE DATA (READ)																	 //
//		+ COUNTER																				 //
//		+ DONE & ERROR FLAGS																	 //
//===============================================================================================//
module qspi_fsm #(
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

  	// Start/Done
  	input  wire	start,
	output wire	done,

  	// Input signal from CSR
	input wire [2:0] clk_div,	// CLK_DIV
	input wire 		 enable,	// CTRL.bit0
	input wire		 quad_en,	// CTRL.bit2
	input wire		 cpol,		// CTRL.bit3
	input wire		 cpha,		// CTRL.bit4
	input wire		 lsb_first,	// CTRL.bit5
	input wire		 cs_auto,	// CS_CTRL.bit0
	input wire		 cs_level,	// CS_CTRL.bit1
  	input wire [1:0] cs_delay,	// CS_CTRL.bit2-3
	
	// CMD & XIP field
	input wire [1:0]  cmd_lanes,	// CMD_CFG/XIP_CFG.bit0-1
	input wire [1:0]  addr_lanes,	// CMD_CFG/XIP_CFG.bit2-3
	input wire [1:0]  data_lanes,	// CMD_CFG/XIP_CFG.bit4-5
	input wire [1:0]  addr_bytes,	// CMD_CFG/XIP_CFG.bit6-7
	input wire 		  mode_en,		// CMD_CFG/XIP_CFG.bit8
	input wire [3:0]  dummy_cycles,	// CMD_CFG/XIP_CFG.bit9-12
	input wire 		  cmd_dir,		// CMD_CFG.bit13 (0:wr, 1:rd)	
	input wire [7:0]  cmd_opcode,	// CMD_OP.bit0-7
	input wire [7:0]  mode_bits,	// CMD_OP.bit8-15	
	input wire [31:0] cmd_addr,
	input wire [31:0] cmd_len,
	input wire [7:0]  cmd_extra_dummy,
 	input wire		  xip_cont_read,	// XIP_CFG.bit13
	input wire		  xip_write_en,		// XIP_CFG.bit14
	input wire [7:0]  xip_read_op,		// XIP_CMD.bit0-7
	input wire [7:0]  xip_write_op,		// XIP_CMD.bit8-15

  	// FIFO signals (TX: IP -> flash | RX: flash -> IP)
	input  wire [7:0] tx_data_fifo,
	input  wire		  tx_empty,
	output reg		  tx_ren,
	output reg [7:0]  rx_data_fifo,
	input  wire		  rx_full,
	output wire		  rx_wen,
	
	// ERROR flag signals
	output reg underrun,	// ERR_STAT.bit2
	output reg overrun,		// ERR_STAT.bit1
	output reg timeout		// ERR_STAT.bit0
);
	//==========================================================================================//
	//							CONFIGURATION & PARAMETERS										//
	//==========================================================================================//
	localparam [2:0] IDLE=0, CS=1, CMD=2, ADDR=3, MODE=4, DUMMY=5, DATA=6, STOP_CS=7;
	localparam TIMEOUT_MAX = 32'd100000;
	reg [2:0] state, next_state;

	reg [1:0] 	cs_gap_cnt;
	reg       	gap_active, cs_n_reg;

	reg [7:0] 	div_cnt;
	reg [2:0]	clk_div_lat;
	reg		  	sclk_core;
	reg			cpol_lat, cpha_lat;

	reg [31:0]	addr32_shift_reg;
	reg [23:0]	addr24_shift_reg;
	reg [7:0] 	cmd_shift_reg;
	reg [7:0] 	mode_shift_reg;
	reg [7:0] 	tx_shift_reg;
	reg       	tx_ren_latch;
	reg 	 	tx_shift_valid;

	reg [7:0] 	rx_shift_reg;
	reg [3:0] 	rx_bits_cnt;
	reg			rx_started;
	
	reg	[31:0] byte_cnt;
	reg	[3:0]  bits_cnt;
	reg [5:0]  bits_sent;
    reg [7:0] dummy_cnt; 

	wire [7:0] total_dummy_cycles = {4'd0,dummy_cycles} + cmd_extra_dummy;
	wire [5:0] n_bits_addr = (addr_bytes==2'd1) ? 6'd24 : (addr_bytes==2'd2) ? 6'd32 : 6'd0;

	wire [2:0] n_cmd_lanes  = (cmd_lanes==2'd0)  ? 3'd1 : (cmd_lanes==2'd1)  ? 3'd2 : (cmd_lanes==2'd2)  ? (quad_en ? 3'd4 : 3'd0) : 3'd0;
	wire [2:0] n_addr_lanes = (addr_lanes==2'd0) ? 3'd1 : (addr_lanes==2'd1) ? 3'd2 : (addr_lanes==2'd2) ? (quad_en ? 3'd4 : 3'd0) : 3'd0;
	wire [2:0] n_data_lanes = (data_lanes==2'd0) ? 3'd1 : (data_lanes==2'd1) ? 3'd2 : (data_lanes==2'd2) ? (quad_en ? 3'd4 : 3'd0) : 3'd0;


	// HOLD & WP pin control
	generate
		if (SUPPORT_HOLD_UP) begin : g_hold_wp
			assign hold_n = 1'b1;
			assign wp_n   = 1'b1;
		end else begin
			assign hold_n = 1'b1;
			assign wp_n   = 1'b1;
		end
	endgenerate	

	// LSB first support for 8 bits
	function [7:0] bit_reverse8;
    	input [7:0] din;
    	integer i;
    	begin
        	for (i=0; i<8; i=i+1) bit_reverse8[i] = din[7-i];
    	end
	endfunction

	// LSB first support for 24 bits
	function [23:0] bit_reverse24;
		input [23:0] din;
		integer i;
		begin
			for (i=0; i<24; i=i+1) bit_reverse24[i] = din[23-i];
		end
	endfunction

	// LSB first support for 32 bits
	function [31:0] bit_reverse32;
		input [31:0] din;
		integer i;
		begin
			for (i=0; i<32; i=i+1) bit_reverse32[i] = din[31-i];
		end
	endfunction

   	//==========================================================================================//
	//										STATE MACHINE										//						
	//==========================================================================================//	
	// State register
	always@(posedge qclk or negedge qresetn) begin
		if(!qresetn) state	<= IDLE;
		else 		 state	<= next_state;
	end

	// Next state logic
	always@(*) begin
		next_state = state;
		case(state)
		IDLE: 	begin
				if(start && enable && (cs_auto || !gap_active))	
					next_state = CS;
				else 
					next_state = IDLE;
				end
		CS:		next_state = CMD;
		CMD: 	begin
				if(bits_cnt + {1'b0,n_cmd_lanes} >= 4'd8) begin
					if(n_bits_addr!=0)	next_state = ADDR;
					else if (cmd_len!=0)	next_state = DATA;
					else 					next_state = STOP_CS;		
				end else next_state = CMD;
				end
		ADDR: 	begin
				if(bits_sent  >= n_bits_addr-4'd1|| (bits_sent >= 6'd20 && cmd_opcode == 8'h38)) begin
					if(mode_en) 					next_state = MODE;
					else if(total_dummy_cycles!=0)	next_state = DUMMY;
					else if(cmd_len!=0) 			next_state = DATA;
					else 							next_state = STOP_CS;
				end else next_state = ADDR;
				end		
		MODE: 	begin
				if(bits_cnt + {1'b0,n_addr_lanes} >= 4'd8 && total_dummy_cycles!=0) next_state = DUMMY;
				else next_state = MODE;
				end
		DUMMY: 	begin
				if((dummy_cnt + 8'd1 >=total_dummy_cycles) && (cmd_len!=0)) next_state = DATA;	
				else next_state = DUMMY;
				end
		DATA: 	begin
				if (underrun || overrun || timeout)	next_state = STOP_CS;
				else if(byte_cnt >= cmd_len)		next_state = STOP_CS;
				else next_state = DATA;
				end
		STOP_CS: next_state = IDLE;
		default: next_state = IDLE;
		endcase
	end

	//==========================================================================================//
    //									CS_DELAY & CS_N											//
    //==========================================================================================//
	// CS gap counter
	always @(posedge qclk or negedge qresetn) begin
    	if (!qresetn) begin
        	cs_gap_cnt <= 2'd0;
        	gap_active <= 1'b0;
    	end else if (state==STOP_CS && next_state==IDLE && cs_auto) begin
			cs_gap_cnt <= 2'd0;
			gap_active <= 1'b1;
		end else if (state==IDLE && gap_active) begin
        	if (cs_gap_cnt < cs_delay) cs_gap_cnt <= cs_gap_cnt + 2'd1;
        	else gap_active <= 1'b0; 
    	end else if (state!=IDLE) begin
			cs_gap_cnt <= 2'd0;
			gap_active <= 1'b0;
		end
	end

	// CS_N generation
	always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			cs_n_reg <= 1'b1;  
		end else if (!cs_auto) begin
			cs_n_reg <= cs_level;
		end else begin
			if(state==IDLE && gap_active) begin
				cs_n_reg <=  1'b1;
			end else if(state!=STOP_CS && state!=IDLE) begin
				cs_n_reg <= 1'b0;
			end 
		end
	end
	assign cs_n = cs_n_reg;

 	//==========================================================================================//
	//							CLOCK DIVIDER - DETECT EDGE										//
	//==========================================================================================//
	wire cs_active = (state!=IDLE && state!=STOP_CS);
	
	// CPOL & CPHA latch
	always@(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			cpol_lat <= 1'b0;
			cpha_lat <= 1'b0;
			clk_div_lat <= 3'd0;
		end else if(state==IDLE && next_state==CS) begin
			cpol_lat <= cpol;
			cpha_lat <= cpha;
			clk_div_lat <= clk_div;
		end
	end

	// SCLK generation
	always@(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
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
	assign sclk = cs_active ? ((clk_div_lat!=0) ? (sclk_core ^ cpol_lat) : (qclk ^ cpol_lat)) 
							: cpol_lat;
	// Edge detection
	wire leading_edge  = cpol_lat ? !sclk : sclk;
	wire trailing_edge = cpol_lat ? sclk : !sclk;
	wire edge_sample = cs_active ? (cpha_lat ? trailing_edge : leading_edge)  : 1'b0;
	wire edge_shift  = cs_active ? (cpha_lat ? leading_edge  : trailing_edge) : 1'b0;

	//==========================================================================================//
	// 							IO PREPARATION + DRIVE LOGIC									//
	//==========================================================================================//
	wire [3:0]	io_in = {io3, io2, io1, io0};

	// Lane mask
	wire [3:0] lane_mask = (state==CMD)               ? 4'b0001:
    					   (state==ADDR||state==MODE) ? ((n_addr_lanes==3'd1)? 4'b0001:(n_addr_lanes==3'd2)? 4'b0011 : (quad_en ? 4'b1111 : 4'b0001)):
    					   (state==DATA)              ? ((n_data_lanes==3'd1)? 4'b0001:(n_data_lanes==3'd2)? 4'b0011 : (quad_en ? 4'b1111 : 4'b0001)): 
						   4'b0000;
	// IO drive logic
	wire       io_drive_en = (state==CMD)||(state==ADDR)||(state==MODE)||(state==DATA && cmd_dir==1'b0);					   
	wire [3:0] io_oe  = (io_drive_en) ? lane_mask : 4'b0000;
	// Output data bits
	wire [3:0] 	out_bits_cmd = {3'b000, cmd_shift_reg[7]};

	wire [3:0] out_bits_addr = (n_bits_addr == 24) ? ((n_addr_lanes==3'd1) ? {3'b000, addr24_shift_reg[23]} :
                                 						 (n_addr_lanes==3'd2) ? {2'b00,  addr24_shift_reg[23:22]} : addr24_shift_reg[23:20]) :
													    ((n_addr_lanes==3'd1) ? {3'b000, addr32_shift_reg[31]} :
													     (n_addr_lanes==3'd2) ? {2'b00,  addr32_shift_reg[31:30]} : addr32_shift_reg[31:28]);

	wire [3:0] 	out_bits_mode = (n_addr_lanes==3'd1) ? {3'b000, mode_shift_reg[7]} :
    						    (n_addr_lanes==3'd2) ? {2'b00,  mode_shift_reg[7:6]} : mode_shift_reg[7:4];

	wire [3:0] out_bits_dataw = (n_data_lanes==3'd1) ? {3'b000, tx_shift_reg[7]} :
								(n_data_lanes==3'd2) ? {2'b00,  tx_shift_reg[7:6]} : tx_shift_reg[7:4];
	wire [3:0] io_out = (io_drive_en) ? ((state==CMD)  ? out_bits_cmd  :
										 (state==ADDR) ? out_bits_addr :
										 (state==MODE) ? out_bits_mode :
										 (state==DATA) ? out_bits_dataw: 4'h0 ) : 4'h0;
	
	// IO bidirectional buffer
	assign io0 = io_oe[0] ? io_out[0] : 1'bz;
	assign io1 = io_oe[1] ? io_out[1] : 1'bz;
	assign io2 = io_oe[2] ? io_out[2] : 1'bz;
	assign io3 = io_oe[3] ? io_out[3] : 1'bz;
	
	//==========================================================================================//
	//								SHIFT DATA (WRITE)											//
	//==========================================================================================//
	// Stall condition
	wire stall_tx = (state==DATA) && (cmd_dir==1'b0) && (!tx_shift_valid);
	wire stall_rx = (state==DATA) && (cmd_dir==1'b1) && rx_full && (rx_bits_cnt + {1'b0,n_data_lanes} >= 4'd8);
	// Effective edge (not stalled)
	wire eff_sample = edge_sample && (!(stall_tx || stall_rx));
	wire eff_shift = edge_shift && (!(stall_tx || stall_rx));

	// Shift registers
	always @(posedge qclk or negedge qresetn) begin 
		if(!qresetn) begin
			cmd_shift_reg		<=  8'h0;
        	addr32_shift_reg	<= 32'h0;
			addr24_shift_reg	<= 32'h0;
        	mode_shift_reg		<=  8'h0;
			tx_shift_reg    	<= 	8'h0;
			tx_ren				<=  1'b0;
			tx_ren_latch		<=  1'b0;
			tx_shift_valid 		<=  1'b0;
		end else begin
			// Load shift register at the beginning of each state
			if(state != next_state) begin
				case(next_state)
				CMD: 	cmd_shift_reg <= lsb_first ? bit_reverse8(cmd_opcode) : cmd_opcode;
				ADDR:	if(n_bits_addr == 6'd24) begin
							addr24_shift_reg <= lsb_first ? bit_reverse24(cmd_addr[23:0]) : cmd_addr[23:0];
						end else begin
							addr32_shift_reg <= lsb_first ? bit_reverse32(cmd_addr) : cmd_addr;
						end
				MODE: 	mode_shift_reg <= lsb_first ? bit_reverse8(mode_bits) : mode_bits;
				DATA:	if(!cmd_dir) begin
							tx_shift_reg   <= lsb_first ? bit_reverse8(tx_data_fifo) : tx_data_fifo;
							tx_ren_latch   <= 1'b0;
						end
				default:;
				endcase
			end
			// TX FIFO read enable
			if(state==ADDR && bits_cnt==4'd0 && byte_cnt==32'd0 && !cmd_dir && !tx_empty) begin
				tx_ren			<= 1'b1;
				tx_ren_latch	<= 1'b1;
			end else if(state!=DATA && next_state==DATA && n_data_lanes==3'd4) begin
				tx_ren			<= 1'b1;
			end else if(state==DATA && !tx_empty) begin
					case(n_data_lanes)
					3'd1: tx_ren <= (bits_cnt==4'd5) ? 1'b1 : 1'b0;
					3'd2: tx_ren <= (bits_cnt==4'd4) ? 1'b1 : 1'b0;
					3'd4: tx_ren <= (bits_cnt==4'd4) ? 1'b1 : 1'b0;
					default: tx_ren <= 1'b0;
					endcase
			end else begin
				tx_ren <= 1'b0;
			end
			// TX shift valid flag
			tx_shift_valid <= tx_ren_latch ? 1'b1 : next_state==STOP_CS ? 1'b0 : tx_shift_valid;     
			// Shift data
			if (eff_shift) begin
				case (state)
					CMD: begin
						case(n_cmd_lanes)
							3'd1: cmd_shift_reg  <= {cmd_shift_reg[6:0],1'b0};
							3'd2: cmd_shift_reg  <= {cmd_shift_reg[5:0],2'b00};
							3'd4: cmd_shift_reg  <= {cmd_shift_reg[3:0],4'b0000};
						endcase
					end
					ADDR: begin
						case(n_addr_lanes)
							3'd1: addr24_shift_reg <= (n_bits_addr == 24) ? {addr24_shift_reg[22:0],1'b0}   : {addr32_shift_reg[30:0],1'b0};
							3'd2: addr24_shift_reg <= (n_bits_addr == 24) ? {addr24_shift_reg[21:0],2'b00}  : {addr32_shift_reg[29:0],2'b00};
							3'd4: addr24_shift_reg <= (n_bits_addr == 24) ? {addr24_shift_reg[19:0],4'b0000}: {addr32_shift_reg[27:0],4'b0000};
						endcase
					end
					MODE: begin
						case(n_addr_lanes)
							3'd1: mode_shift_reg <= {mode_shift_reg[6:0],1'b0};
							3'd2: mode_shift_reg <= {mode_shift_reg[5:0],2'b00};
							3'd4: mode_shift_reg <= {mode_shift_reg[3:0],4'b0000};
						endcase
					end
					DATA:begin
						case(n_data_lanes)
							3'd1: tx_shift_reg <= (bits_cnt==4'd7) ? tx_data_fifo: {tx_shift_reg[6:0],1'b0};
							3'd2: tx_shift_reg <= (bits_cnt==4'd0) ? tx_data_fifo: {tx_shift_reg[5:0],2'b00};
							3'd4: begin
								  if(bits_cnt==4'd4) tx_shift_reg <= lsb_first ? bit_reverse8(tx_data_fifo) : tx_data_fifo;
								  else tx_shift_reg <= {tx_shift_reg[3:0],4'b0000};
							end
						endcase
					end
				endcase
			end
		end
	end

	//==========================================================================================//
	//								SAMPLE DATA (READ)											//
	//==========================================================================================//
	// RX bit counter & start flag
	always @(posedge qclk or negedge qresetn) begin //Counter & Flags
		if (!qresetn) begin
			rx_bits_cnt   <= 4'd0;
			rx_started     <= 1'b0;  
		end else begin
			if (state==DATA && cmd_dir==1'b1) begin
				rx_bits_cnt 	<= ((rx_bits_cnt + {1'b0,n_data_lanes}) >= 4'd8 ) ? 4'b0 :  rx_bits_cnt + {1'b0,n_data_lanes};
				case(n_data_lanes)
				3'd1: rx_started <= (!rx_started && (rx_bits_cnt + {1'b0,n_data_lanes}) >= 4'd8 ) ? 1'b1 : 1'b0;
				3'd2: rx_started <= (!rx_started && rx_bits_cnt==4'd4 ) ? 1'b1 : 1'b0;
				3'd4: rx_started <= (!rx_started && (rx_bits_cnt + {1'b0,n_data_lanes}) >= 4'd8 ) ? 1'b1 : 1'b0;
				default:;
				endcase
			end else if (next_state==DATA) begin
				rx_bits_cnt 	<= 4'd0;
			end	
		end
	end

	// Shift data to RX FIFO
	always @(negedge qclk or negedge qresetn) begin
		if (!qresetn) begin
			rx_shift_reg   <= 8'h00;
			rx_data_fifo   <= 8'h00;
		end else begin
			case(n_data_lanes)
			3'd1: 	if ((rx_bits_cnt == 4'd0) && rx_started && !rx_full) begin
						rx_data_fifo <= lsb_first ? bit_reverse8({rx_shift_reg[6:0], io_in[1]})   : {rx_shift_reg[6:0], io_in[1]};
					end
			3'd2: 	if ((rx_bits_cnt + {1'b0,n_data_lanes}) >= 4'd8 && rx_started && !rx_full) begin
						rx_data_fifo <= lsb_first ? bit_reverse8({rx_shift_reg[5:0], io_in[1:0]}) : {rx_shift_reg[5:0], io_in[1:0]};
					end
			3'd4: 	if ((rx_bits_cnt == 4'd0) && rx_started && !rx_full) begin
						rx_data_fifo <= lsb_first ? bit_reverse8({rx_shift_reg[3:0], io_in[3:0]}) : {rx_shift_reg[3:0], io_in[3:0]};
					end
			endcase
			if (next_state==DATA && cmd_dir==1'b1 && eff_sample) begin
				case (n_data_lanes)
				3'd1: rx_shift_reg <= {rx_shift_reg[6:0], io_in[1]};
				3'd2: rx_shift_reg <= {rx_shift_reg[5:0], io_in[1:0]};
				3'd4: rx_shift_reg <= {rx_shift_reg[3:0], io_in[3:0]};
				endcase
			end
		end
	end
	assign rx_wen = (state==DATA && rx_started && !rx_full);

	//==========================================================================================//
	// 										COUNTER												//
	//==========================================================================================//
	// Bit/Byte/Dummy counter
	always@(posedge qclk or negedge qresetn) begin 
		if (!qresetn) begin
			byte_cnt  <= 32'd0;
			bits_sent <= 6'd0;
			bits_cnt  <= 4'd0;
			dummy_cnt <= 8'd0;
		end else if (state != next_state) begin
			byte_cnt  <= 32'd0;
			bits_sent <= 6'd0;
			bits_cnt  <= 4'd0;
			dummy_cnt <= 8'd0;
		end else begin
			if(eff_shift) begin
				bits_sent <= state==ADDR  ? bits_sent + {3'b0,n_addr_lanes} : 6'b0;

				dummy_cnt <= state==DUMMY ? (edge_shift ? dummy_cnt + 8'd1 : dummy_cnt) : 8'd0;

				byte_cnt  <= state==ADDR ? (bits_cnt+n_addr_lanes>=4'd8) ? byte_cnt + 32'd1 : byte_cnt :
							 state==DATA ? (bits_cnt+n_data_lanes>=4'd8) ? byte_cnt + 32'd1 : byte_cnt : 32'd0;
							 
				bits_cnt  <= ((bits_cnt+n_data_lanes>=4'd8)&&(state==DATA||state==ADDR)) ? 4'd0 :
							 state==CMD   ? bits_cnt + n_cmd_lanes :
							 state==ADDR  ? bits_cnt + n_addr_lanes :
							 state==MODE  ? bits_cnt + n_addr_lanes :
							 state==DATA  ? bits_cnt + n_data_lanes : 4'd0;
			end
		end
	end
	    
	//==========================================================================================//
    //								DONE & ERROR FLAGS											//
    //==========================================================================================//
	reg [31:0] timeout_cnt;

	// Done signal generation
	assign done = (state==STOP_CS && next_state==IDLE);	

	// Error flag generation
	always@(posedge qclk or negedge qresetn) begin
    	if(!qresetn) begin
      		underrun <= 1'b0;
        	overrun  <= 1'b0;
        	timeout  <= 1'b0;
        	timeout_cnt  <= 32'd0;
    	end else begin
			// Clear error flags at the beginning of a new transfer
        	if(state == IDLE && start) begin
            	underrun <= 1'b0;
            	overrun  <= 1'b0;
            	timeout  <= 1'b0;
            	timeout_cnt  <= 32'd0;
        	end
			// Set error flags during a transfer
        	if(state==DATA && cmd_dir==1'b0) begin
				if(!tx_shift_valid && tx_empty && (bits_sent[2:0]==3'd0))    		
					underrun <= 1'b1;
			end
			// RX FIFO full and still more data to read in the last byte
        	if(state==DATA && cmd_dir==1'b1) begin
			 if(eff_sample && rx_full && (rx_bits_cnt+{1'b0,n_data_lanes}>=4'd8) )
            	overrun <= 1'b1;
			end
			// Timeout detection
        	if (stall_tx || stall_rx) begin
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