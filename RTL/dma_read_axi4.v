module dma_read_axi4 #(
	parameter FIFO_DEPTH = 16
)(
	// Clock and reset
	input wire			clk,
	input wire 			rst_n,

	//control signal from Controller
	input wire 		 	start_read,
	input wire [31:0] 	r_size_data,
	input wire [31:0] 	raddr_reg,
	input wire 			incr_addr_i,
	output reg	 		read_done,

	//FIFO interface
	input wire		 	fifo_full,
	output reg			wen,
	output reg [31:0]	data_in,

	//Interact with AXI4 slave
	output reg			axi_arvalid,
	output reg[31:0]	axi_araddr,
	input wire 			axi_arready,
	input wire			axi_rvalid,
	input wire [31:0]	axi_rdata,
	output reg			axi_rready,

	input [6:0] tx_level_i,
	input [3:0] dma_burst_size_i
	);
	localparam [1:0] R_IDLE = 0, R_ADDR = 1, R_DATA = 2, R_RESP = 3;
	reg [1:0] r_state;
	reg [15:0] read_cnt;

	reg s_wlast; // signal fishish 1 burst
	reg [15:0] burst_cnt;//cnt how many beat have been sent in burst(limit 16 for input)
	reg [15:0] current_burst_size;
	reg start_burst;
	//DMA read FSM logic
	always@(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			read_done	<= 0;
			wen			<= 0;
			data_in		<= 0;
			axi_arvalid <= 0;
			axi_araddr  <= 0;
			axi_rready 	<= 0;
			read_cnt	<= 0;
			start_burst	<= 0;
			burst_cnt 	<= 0;
			s_wlast		<= 0;
			current_burst_size <= 0;
			r_state		<= R_IDLE;
		end else begin
			wen			<= 0;
			read_done	<= 0;
			case(r_state)
				R_IDLE: begin
						axi_arvalid <= 0;
						axi_araddr  <= 0;
						read_cnt	<= 0;
						
						start_burst		<= 0;
						burst_cnt 		<= 0;
						current_burst_size <= 0;
						if(start_read) begin
							r_state	<= R_ADDR;
							s_wlast			<= 1;
							axi_arvalid		<= 1;	
						end	
				end
				R_ADDR: begin
					if(s_wlast)begin
						if(r_size_data - read_cnt >= dma_burst_size_i * 4) begin// 4 byte / 1 time
								current_burst_size <= r_size_data < 4 ? r_size_data : dma_burst_size_i * 4;
								s_wlast <= 0;
						end else begin
							current_burst_size <= r_size_data - read_cnt;
								s_wlast <= 0;
						end
					end

					//if burst finish process for new burst
					if(!start_burst && !s_wlast) begin
						//wait until have enough data for 1 burst 
						if(((FIFO_DEPTH*4 - 1) - tx_level_i) >= current_burst_size) start_burst <= 1; 
					end
					//process incr_addr
					axi_araddr		<= incr_addr_i? raddr_reg + read_cnt : raddr_reg;
	
					if(axi_arready && start_burst) r_state <= R_DATA;
				end
				R_DATA: begin
						if(axi_rvalid) begin
							axi_rready	<= 1;
							data_in		<= axi_rdata;
						end 
						if(axi_rready&&(!fifo_full)) begin
							wen			<= 1;
							axi_rready	<= 0;
							read_cnt	<= read_cnt + 4;
							burst_cnt   <= burst_cnt + 4;
							r_state  	<= R_RESP;
						end 
					end
				R_RESP:begin
					if(burst_cnt >= current_burst_size) begin 
						s_wlast <= 1; 		
						start_burst <= 0;
						burst_cnt <= 0;
					end	
					if(read_cnt < r_size_data) begin
						r_state		<= R_ADDR;
					end else begin
						read_done	<= 1;
						r_state		<= R_IDLE;
					end
				end
				default: r_state <= R_IDLE;
			endcase
		end
	end
endmodule