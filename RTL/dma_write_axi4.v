module dma_write_axi4(
	// Clock and reset	
	input	clk,
	input	rst_n,

	//control signal from Controller
	input			start_write,
	input [31:0]	w_size_data,
	input [31:0]	waddr_reg,
	input incr_addr_i, //bit 5 of cfg dma, accept count addr, else addr cant increase
	output reg		write_done,


	//FIFO interface
	input 			fifo_empty,
	input [31:0]	data_out,
	output reg		ren,
	input [6:0]		rx_level_i,

	//Interact with AXI4 slave
	output reg		 axi_awvalid,
	output reg[31:0] axi_awaddr,
	input			 axi_awready,
	output reg		 axi_wvalid,
	output reg [3:0] axi_wstrb,
	output reg[31:0] axi_wdata,
	input			 axi_wready,
	input			 axi_bvalid,
	output reg		 axi_bready,
	input wire [3:0] dma_burst_size_i
);

reg [2:0] w_state;
reg[15:0] write_cnt;
localparam W_IDLE = 0, W_ADDR = 1,W_DATA = 2, W_RESP = 3;
reg wait_data;

//process burst
reg s_wlast; // signal fishish 1 burst
reg [15:0] burst_cnt;//cnt how many beat have been sent in burst(limit 15 for input)
reg [15:0] current_burst_size;
reg start_burst;
//DMA write FSM lodic
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
		write_done	<= 0;
		ren			<= 0;
		axi_awvalid	<= 0;
		axi_awaddr	<= 0;
		axi_wvalid	<= 0;
		axi_wstrb	<= 0;
		axi_wdata	<= 0;
		axi_bready	<= 0;
		write_cnt	<= 0;
		wait_data	<= 0;
		start_burst	<= 0;
		burst_cnt 	<= 0;
		s_wlast		<= 0;
		current_burst_size <= 0;
		w_state		<= W_IDLE;
	end else begin
		ren			<= 0;
		write_done	<= 0;
		case(w_state) 
			W_IDLE:	begin
					write_cnt		<= 0;
					axi_awvalid		<= 0;
					axi_awaddr		<= 0;
					axi_wvalid		<= 0;
					axi_wstrb		<= 0;
					axi_wdata		<= 0;
					axi_bready		<= 0;
					start_burst		<= 0;
					burst_cnt 		<= 0;
					current_burst_size <= 0;
					if(start_write) begin
						w_state	<= W_ADDR;
						s_wlast			<= 1;
						axi_awvalid		<= 1;	
					end	
				end
			W_ADDR: begin
				//burst size default is 4 byte because output is 32 bit
				//and burst len is say, with 4 byte/1 time, how much len I need to write all data
				//process burst
			
				//s_wlast is signal indicates the end of a burst, if match, need new data for new burst
				if(s_wlast)begin
					if(w_size_data - write_cnt >= dma_burst_size_i * 4) begin// 4 byte / 1 time
							current_burst_size <= w_size_data < 4 ? w_size_data : dma_burst_size_i * 4;
							s_wlast <= 0;
					end else begin
						current_burst_size <= w_size_data - write_cnt;
							s_wlast <= 0;
					end
				end
				
				//if burst finish process for new burst
				if(!start_burst && !s_wlast) begin
					//wait until have enough data for 1 burst 
					if(rx_level_i >= current_burst_size) start_burst <= 1; 
				end
				//process incr_addr
				axi_awaddr		<= incr_addr_i? waddr_reg + write_cnt : waddr_reg;

				//if match case then process else is default
				case(w_size_data - write_cnt)
						2'b01:  axi_wstrb <= 4'b1000;
						2'b10:  axi_wstrb <= 4'b1100;
						2'b11:  axi_wstrb <= 4'b1110;
						default:axi_wstrb <= 4'b1111;
				endcase
					

				//read if address and fifo data is ready and go next step for process data
    			ren <= !fifo_empty && axi_awready && start_burst;	
				if(ren) w_state <= W_DATA;
			end
			W_DATA: begin	
					axi_wvalid <= (write_cnt < w_size_data) && !ren; //wait 1 pulse for ren can creat data
					if(!axi_wvalid) begin
						axi_wdata  <= data_out;
						axi_wvalid	<= 1;
					end

					//if data write done increase cnt and go b_resp for check
					if(axi_wvalid&&axi_wready) begin
						axi_wvalid	<= 0;
						write_cnt	<= write_cnt + 4;
						burst_cnt   <= burst_cnt + 4;
						w_state		<= W_RESP;
					end	
						 
				end

			W_RESP: begin
					//if get limit burst, reset signal for prepare new data	
					if(burst_cnt >= current_burst_size) begin 
						s_wlast <= 1; 		
						start_burst <= 0;
						burst_cnt <= 0;
					end	

					
					if(axi_bvalid&&!axi_bready) begin
						axi_bready	<= 1;
					end

					if(axi_bvalid&&axi_bready) begin
						axi_bready	<= 0;
						if(write_cnt<w_size_data) begin
							w_state		<= W_ADDR;
						end else begin
							w_state		<= W_IDLE;
							write_done	<= 1;
						end
					end
				end
			default:begin
					w_state	<= W_IDLE;	
				end
		endcase
	end
end
endmodule