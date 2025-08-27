//----------------------------------------------------------------------------------------------//
// Module: qspi_fsm.v
// Note:
//		+ CONFIGURATION
//		+ STATE MACHINE
//		+ CS_DELAY & CS_N
//		+ CLOCK DIVIDER - CPOL - CPHA - DETECT EDGE
//		+ IO OUTPUT PREPARATION(selector + mask + mux)
//		+ IO DRIVE LOGIC
//----------------------------------------------------------------------------------------------//
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

  	// Input signal from CSR
	input wire [2:0] clk_div,	// CLK_DIV
	input wire 		 enable,	// CTRL.bit0
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
	output wire		  rx_wen,
	
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
	// CONFIGURATION
	//==========================================================================================//
	localparam [2:0] IDLE=0, CS=1, CMD=2, ADDR=3, MODE=4, DUMMY=5, DATA=6, STOP_CS=7;
	localparam TIMEOUT_MAX = 32'd100000;

	reg [2:0] state, next_state;
	
	reg [5:0] bits_sent, bits_cnt;
    reg [31:0] byte_cnt; 
    reg [7:0] dummy_cnt; 

	wire [7:0] total_dummy_cycles = {4'd0,dummy_cycles} + cmd_extra_dummy;
	wire [5:0] addr_bits_need = (addr_bytes==2'd1) ? 6'd24 : 
								(addr_bytes==2'd2) ? 6'd32 : 6'd0;

	// CMD lanes
	wire [2:0] n_cmd_lanes  = (cmd_lanes==2'd0) ? 3'd1 : 
							  (cmd_lanes==2'd1) ? 3'd2 : 
							  (cmd_lanes==2'd2) ? (quad_en ? 3'd4 : 3'd1) : 3'd1;
	// ADDR lanes
	wire [2:0] n_addr_lanes = (addr_lanes==2'd0) ? 3'd1 : 
							  (addr_lanes==2'd1) ? 3'd2 : 
							  (addr_lanes==2'd2) ? (quad_en ? 3'd4 : 3'd1) : 3'd1;
	// DATA lanes
	wire [2:0] n_data_lanes = (data_lanes==2'd0) ? 3'd1 : 
							  (data_lanes==2'd1) ? 3'd2 : 
							  (data_lanes==2'd2) ? (quad_en ? 3'd4 : 3'd1) : 3'd1;
   	//===========================================================================================//
	// STATE MACHINE
	//===========================================================================================//
	always@(posedge qclk or negedge qresetn) begin
		if(!qresetn) state	<= IDLE;
		else state	<= next_state;
	end

	always@(*) begin
		next_state = state;
		case(state)
		IDLE: begin
			if(start && enable && (cs_auto || !gap_active))	next_state = CS;
			else 	next_state = IDLE;
		end
		CS:												next_state = CMD;
		CMD: begin
			if(bits_sent>= 6'd7) begin
				if(addr_bits_need!=0) 					next_state = ADDR;
				else if (cmd_len!=0) 					next_state = DATA;
				else 									next_state = STOP_CS;		
			end 
			else next_state = CMD;
		end
		ADDR: begin
			if(bits_sent >= addr_bits_need-1) begin
				if(mode_en) 							next_state = MODE;
				else if(total_dummy_cycles!=0) 			next_state = DUMMY;
				else if(cmd_len!=0) 					next_state = DATA;
				else next_state = STOP_CS;
			end 
			else next_state = ADDR;
		end		
		MODE: begin
			if(bits_sent>=6'd8 && total_dummy_cycles!=0) next_state = DUMMY;
			else next_state = MODE;
		end
		DUMMY: begin
			if(dummy_cnt + 8'd1 >=total_dummy_cycles && cmd_len!=0) next_state = DATA;	
			else next_state = DUMMY;
		end
		DATA: begin
			if (underrun || overrun || timeout)			next_state = STOP_CS;
			else if(bits_sent >= cmd_len*8)			next_state = STOP_CS;
			else next_state = DATA;
		end
		STOP_CS: 										next_state = IDLE;
		default:	next_state = IDLE;
		endcase
	end

	//==========================================================================================//
    // CS_DELAY & CS_N
    //==========================================================================================//
	reg [1:0] 	cs_gap_cnt;
	reg       	gap_active;
	reg 		cs_n_reg;
	
	assign cs_n = cs_n_reg;

	always @(posedge qclk or negedge qresetn) begin// delay counter
    	if (!qresetn) begin
        	cs_gap_cnt <= 2'd0;
        	gap_active <= 1'b0;
    	end else if (state==STOP_CS && next_state==IDLE && cs_auto) begin // Finish transaction, begin delay
			cs_gap_cnt <= 2'd0;
			gap_active <= 1'b1;
		end else if (state==IDLE && gap_active) begin
        	if (cs_gap_cnt < cs_delay) cs_gap_cnt <= cs_gap_cnt + 2'd1;
        	else gap_active <= 1'b0; 
    	end 
		else if (state!=IDLE) begin
			cs_gap_cnt <= 2'd0;
			gap_active <= 1'b0;
		end
	end

	always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			cs_n_reg <= 1'b1;  
		end else if (!cs_auto) begin
			cs_n_reg <= cs_level;
		end else begin
			if(state==IDLE && gap_active) begin
				cs_n_reg <=  1'b1;
			end else if(state==CS ||state==CMD || state==ADDR || state==MODE || state==DUMMY || state== DATA) begin
				cs_n_reg <= 1'b0;
			end else begin
				cs_n_reg <= cs_n_reg;
			end
		end
	end

 	//==========================================================================================//
	// CLOCK DIVIDER - CPOL - CPHA - DETECT EDGE
	//==========================================================================================//
	reg [7:0] 	div_cnt;
	reg		  	sclk_core;
	wire		cs_active = (state!=IDLE && state!=STOP_CS);
	assign sclk = /*(cs_active) ? (*/(clk_div!=0) ? (sclk_core^cpol) : (qclk^cpol)/*) : cpol*/;

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
	wire leading_edge  = cpol ? !sclk : sclk;
	wire trailing_edge = cpol ? sclk : !sclk;
	wire edge_sample = (state==IDLE || state==STOP_CS) ? 0 : (cpha ? trailing_edge : leading_edge);
	wire edge_shift  = (state==IDLE || state==STOP_CS) ? 0 : (cpha ? leading_edge : trailing_edge);

	//==========================================================================================//
	// SHIFT DATA & SAMPLE DATA (WRITE & READ)
	//==========================================================================================//
	function [7:0] bit_reverse8;
    	input [7:0] din;
    	integer i;
    	begin
        	for (i=0; i<8; i=i+1)
        	    bit_reverse8[i] = din[7-i];
    	end
	endfunction
	function [32:0] bit_reverse32;
		input [31:0] din;
		integer i;
		begin
			for (i = 0; i < 32; i = i + 1)
				bit_reverse32[i] = din[31-i];
		end
	endfunction

	reg [7:0] 	cmd_shift_reg;
	reg [31:0]	addr_shift_reg;
	reg [7:0] 	mode_shift_reg;
	reg [7:0] 	tx_shift_reg;
	reg       	tx_shift_valid, tx_ren_latch;

	reg [7:0] 	rx_shift_reg;
	reg [3:0] 	rx_bit_count;
	reg			rx_started;

	wire stall_tx = (state==DATA) && (cmd_dir==1'b0) && (!tx_shift_valid);
	wire stall_rx = (state==DATA) && (cmd_dir==1'b1) && (rx_full) && ((rx_bit_count+n_data_lanes)>=6'd8);
	wire eff_sample = edge_sample && (!(stall_tx || stall_rx));
	wire eff_shift = edge_shift && (!(stall_tx || stall_rx));

	// Write phase
	always @(posedge sclk or negedge qresetn) begin 
		if(!qresetn) begin
			cmd_shift_reg	<=  8'h0;
        	addr_shift_reg	<= 32'h0;
        	mode_shift_reg	<=  8'h0;
		end else begin
			if(state != next_state) begin // Load data
				case (next_state)
				CMD:   	cmd_shift_reg  <= lsb_first ? bit_reverse8(cmd_opcode) : cmd_opcode;
				ADDR:	addr_shift_reg <= lsb_first ? (addr_bits_need == 24 ? bit_reverse32({8'h00, cmd_addr[23:0]}) : bit_reverse32(cmd_addr)) 
													: (addr_bits_need == 24 ? {cmd_addr[23:0], 8'h00} : cmd_addr );
				MODE: 	mode_shift_reg <= lsb_first ? bit_reverse8(mode_bits) : mode_bits;
				default:;
				endcase
			end
			if (eff_shift) begin // Shift data to DEVICE
				case (state)
				CMD:case(n_cmd_lanes)
					3'd1: cmd_shift_reg  <= {cmd_shift_reg[6:0],1'b0};
					3'd2: cmd_shift_reg  <= {cmd_shift_reg[5:0],2'b00};
					3'd4: cmd_shift_reg  <= {cmd_shift_reg[3:0],4'b0000};
					endcase
				ADDR:case(n_addr_lanes)
					3'd1: addr_shift_reg <= {addr_shift_reg[30:0],1'b0};
					3'd2: addr_shift_reg <= {addr_shift_reg[29:0],2'b00};
					3'd4: addr_shift_reg <= {addr_shift_reg[27:0],4'b0000};
					endcase
				MODE:case(n_addr_lanes)
					3'd1: mode_shift_reg <= {mode_shift_reg[6:0],1'b0};
					3'd2: mode_shift_reg <= {mode_shift_reg[5:0],2'b00};
					3'd4: mode_shift_reg <= {mode_shift_reg[3:0],4'b0000};
					endcase
				endcase
			end
		end
	end

	always @(posedge sclk or negedge qresetn) begin
		if(!qresetn) begin
			tx_shift_reg    <= 	8'h0;
        	tx_shift_valid 	<= 	1'b0;
			tx_ren			<=  1'b0;
			tx_ren_latch	<=  1'b0;
		end else begin
			if(bits_cnt==0&&state==DATA) begin
				tx_shift_reg <= {tx_data_fifo[6:0], 1'b0};
			end
			if((state==CMD && bits_cnt==6)|| (state==DATA && !tx_empty && bits_cnt+n_data_lanes==7)) begin
				tx_ren			<= 1'b1;
				tx_ren_latch	<= 1'b1;
			end else begin
				tx_ren			<= 1'b0;
			end
			if(tx_ren_latch) begin
				tx_shift_valid  <= 1'b1;
			end else if(state==IDLE) begin
				tx_shift_valid <= 1'b0;
			end
			
			if (eff_shift) begin // Shift data to DEVICE
				case (state)
				DATA:if(cmd_dir==1'b0&&bits_cnt!=0) begin
						case(n_data_lanes)
						3'd1: tx_shift_reg <= {tx_shift_reg[6:0],1'b0};
						3'd2: tx_shift_reg <= {tx_shift_reg[5:0],2'b00};
						3'd4: tx_shift_reg <= {tx_shift_reg[3:0],4'b0000};
						endcase
					 end
				endcase
			end
		end
	end

	//=======================READ PHASE=======================================//
	always @(posedge sclk or negedge qresetn) begin //Counter & Flags
		if (!qresetn) begin
			rx_bit_count   <= 3'd0;
			rx_started     <= 1'b0;  
		end else begin
			if (state==DATA && cmd_dir==1'b1) begin
				rx_bit_count 	<= ((rx_bit_count + n_data_lanes) >= 4'd8 ) ? 3'b0 :  rx_bit_count + n_data_lanes;
				case(n_data_lanes)
				3'd1: rx_started <= (!rx_started && (rx_bit_count + n_data_lanes) >= 4'd8 ) ? 1'b1 : 1'b0;
				3'd2: rx_started <= (!rx_started && rx_bit_count==4'd4 ) ? 1'b1 : 1'b0;
				3'd4: rx_started <= (!rx_started && rx_bit_count==4'd0 ) ? 1'b1 : 1'b0;
				default:;
				endcase
			end else if (next_state==DATA) begin
				rx_bit_count 	<= 3'b0;
			end	
		end
	end

	always @(negedge sclk or negedge qresetn) begin //Shift data to FIFO 
		if (!qresetn) begin
			rx_shift_reg   <= 8'h00;
			rx_data_fifo   <= 8'h00;
		end else begin
			case(n_data_lanes)
			3'd1: if ((rx_bit_count == 4'd0) && rx_started && !rx_full) begin
				rx_data_fifo <= lsb_first ? bit_reverse8({rx_shift_reg[6:0], io_in[1]})   : {rx_shift_reg[6:0], io_in[1]};
			end
			3'd2: if ((rx_bit_count + n_data_lanes) >= 4'd8 && rx_started && !rx_full) begin
				rx_data_fifo <= lsb_first ? bit_reverse8({rx_shift_reg[5:0], io_in[1:0]}) : {rx_shift_reg[5:0], io_in[1:0]};
			end
			3'd4: if ((rx_bit_count + n_data_lanes) >= 4'd8 && rx_started && !rx_full) begin
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
	// IO OUTPUT PREPARATION + IO DRIVE LOGIC
	//==========================================================================================//
	wire [3:0]	io_in = {io3, io2, io1, io0};

	// mux between output and high-z
	assign io0 = io_oe[0] ? io_out[0] : 1'bz;
	assign io1 = io_oe[1] ? io_out[1] : 1'bz;
	assign io2 = io_oe[2] ? io_out[2] : 1'bz;
	assign io3 = io_oe[3] ? io_out[3] : 1'bz;

	// output bit selector 
	wire [3:0] 	out_bits_cmd = (n_cmd_lanes==3'd1) ? {3'b000, cmd_shift_reg[7]} :
 							   (n_cmd_lanes==3'd2) ? {2'b00,  cmd_shift_reg[7:6]} : cmd_shift_reg[7:4];

	wire [3:0] 	out_bits_addr = (n_addr_lanes==3'd1) ? {3'b000, addr_shift_reg[30]} :
							    (n_addr_lanes==3'd2) ? {2'b00,  addr_shift_reg[30:29]} : addr_shift_reg[30:27];

	wire [3:0] 	out_bits_mode = (n_addr_lanes==3'd1) ? {3'b000, mode_shift_reg[7]} :
    						    (n_addr_lanes==3'd2) ? {2'b00,  mode_shift_reg[7:6]} : mode_shift_reg[7:4];

	wire [3:0] out_bits_dataw = (n_data_lanes==3'd1) ? ((state==DATA&&bits_cnt==0) ? {3'b000, tx_data_fifo[7]} : {3'b000, tx_shift_reg[7]}) :
    							(n_data_lanes==3'd2) ? ((state==DATA&&bits_cnt==0) ? {2'b00,tx_data_fifo[7:6]} : {2'b00,tx_shift_reg[7:6]}) :
													   ((state==DATA&&bits_cnt==0) ? tx_data_fifo[7:4]         : tx_shift_reg[7:4]);

	// Lane enable mask
	wire [3:0] lane_mask = (state==CMD)  				  ? ((n_cmd_lanes==3'd1) ? 4'b0001:(n_cmd_lanes==3'd2) ? 4'b0011 : (quad_en ? 4'b1111 : 4'b0001)):
    					   (state==ADDR) 				  ? ((n_addr_lanes==3'd1)? 4'b0001:(n_addr_lanes==3'd2)? 4'b0011 : (quad_en ? 4'b1111 : 4'b0001)):
    					   (state==MODE) 				  ? ((n_addr_lanes==3'd1)? 4'b0001:(n_addr_lanes==3'd2)? 4'b0011 : (quad_en ? 4'b1111 : 4'b0001)):
    					   (state==DATA && cmd_dir==1'b0) ? ((n_data_lanes==3'd1)? 4'b0001:(n_data_lanes==3'd2)? 4'b0011 : (quad_en ? 4'b1111 : 4'b0001)): 
						   4'b0000;

	// IO drive logic
	wire io_drive_en = (state==CMD)||(state==ADDR)||(state==MODE)||(state==DATA&&cmd_dir==1'b0);
	wire [3:0] io_oe  = io_drive_en ? lane_mask : 4'b0000;
	wire [3:0] io_out = (io_drive_en) ? ((state==CMD)  ? out_bits_cmd  :
										 (state==ADDR) ? out_bits_addr :
										 (state==MODE) ? out_bits_mode :
										 (state==DATA) ? out_bits_dataw: 4'h0 ) : 4'h0;

	//==========================================================================================//
	// COUNTER
	//==========================================================================================//
	// bit_sent
	always@(posedge qclk or negedge qresetn) begin 
		if (!qresetn) begin
			bits_sent <= 6'd0;
			bits_cnt  <= 6'd0;
		end else if (state != next_state) begin
			// Reset counters on state transition
			bits_sent <= 6'd0;
			bits_cnt  <= 6'd0;
		end else begin
			// Update counters based on current state and eff_shift
			case(state)
			CMD:  if (eff_shift) begin
				bits_sent <= bits_sent + n_cmd_lanes;
				bits_cnt  <= bits_cnt + n_cmd_lanes;
			end
			ADDR: if (eff_shift) begin
				bits_sent <= bits_sent + n_addr_lanes;
				bits_cnt  <= bits_cnt + n_addr_lanes;
			end
			MODE: if (eff_shift) begin
				bits_sent <= bits_sent + n_addr_lanes;
				bits_cnt  <= bits_cnt + n_addr_lanes;
			end
			DATA: if (eff_shift) begin
				bits_sent <= bits_sent + n_data_lanes;
				bits_cnt  <= bits_cnt + n_data_lanes;
			end
			default:;
			endcase
			if( bits_cnt+n_data_lanes>=6'd8) bits_cnt <= 0;
		end
	end
	
	// byte_cnt
    always @(posedge qclk or negedge qresetn) begin
		if(!qresetn) begin
			byte_cnt <= 32'd0;
        end else if(state!=DATA) begin
			byte_cnt <= 32'd0;
        end else if(state==DATA&&eff_shift&&(bits_cnt+n_data_lanes>=6'd8)) begin
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
			dummy_cnt <= dummy_cnt + 8'd1;
		end 
	end
	//==========================================================================================//
    // DONE & ERROR flags
    //==========================================================================================//
	assign done = (state==STOP_CS && next_state==IDLE);

	reg [31:0] timeout_cnt;
	always@(posedge qclk or negedge qresetn) begin
    	if(!qresetn) begin
      		underrun <= 1'b0;
        	overrun  <= 1'b0;
        	timeout  <= 1'b0;
        	timeout_cnt  <= 32'd0;
    	end else begin
        	if(state == IDLE && start) begin
            	underrun <= 1'b0;
            	overrun  <= 1'b0;
            	timeout  <= 1'b0;
            	timeout_cnt  <= 32'd0;
        	end
        	if(state==DATA && cmd_dir==1'b0 && !tx_shift_valid && (bits_sent[2:0]==3'd0)&& tx_empty)    		
				underrun <= 1'b1;
        	if(state==DATA && cmd_dir==1'b1 && eff_sample && (rx_bit_count+n_data_lanes>=4'd8) && rx_full)
            	overrun <= 1'b1;
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