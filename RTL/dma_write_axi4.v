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
	input [3:0]		rx_level_i,

	//Interact with AXI4 slave
	output reg		 axi_awvalid,
	output reg[31:0] axi_awaddr,
	input			 axi_awready,
	output reg		 axi_wvalid,
	output reg [3:0] axi_wstrb,
	output reg[31:0] axi_wdata,
	input			 axi_wready,
	input			 axi_bvalid,
	output reg		 axi_bready
);

reg [2:0] w_state;
reg[15:0] write_cnt;
localparam W_IDLE = 0, W_ADDR = 1,W_DATA = 2, W_RESP = 3;
reg wait_data;
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
					if(start_write) begin
						w_state	<= W_ADDR;
					end	
				end
			W_ADDR: begin
					axi_awvalid		<= 1;
					//process incr_addr
					if(incr_addr_i)
						axi_awaddr		<= waddr_reg + write_cnt;
					else 
						axi_awaddr 	<= waddr_reg;

					if(axi_awready&&!fifo_empty) begin
						if(w_size_data - write_cnt >=4 && rx_level_i>=4)begin
							axi_awvalid	<= 0;
							ren			<= 1;
							wait_data	<= 1;
							w_state		<= W_DATA;
							axi_wstrb <= 4'b1111;
						end else if(rx_level_i == (w_size_data - write_cnt))begin
							axi_awvalid	<= 0;
							ren			<= 1;
							wait_data	<= 1;
							w_state		<= W_DATA;

							case(w_size_data - write_cnt)
								2'b00: axi_wstrb <= 4'b1111;
								2'b01: axi_wstrb <= 4'b1000;
								2'b10: axi_wstrb <= 4'b1100;
								2'b11: axi_wstrb <= 4'b1110;
								default:;
							endcase

						end
					end
				end
			W_DATA: begin
					axi_wdata  <= data_out;
					if(wait_data) begin
						wait_data    <= 0;
					end else if(!axi_wvalid) begin
						axi_wvalid	<= 1;
					end
					if(axi_wvalid&&axi_wready) begin
						axi_wvalid	<= 0;
						w_state		<= W_RESP;
					end
				end

			W_RESP: begin
					
					if(axi_bvalid&&!axi_bready) begin
						axi_bready	<= 1;
						write_cnt	<= write_cnt + 4; 
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