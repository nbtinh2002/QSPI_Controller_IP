module dma_read_axi4(
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
	output reg			axi_rready
	);

	localparam R_IDLE = 0, R_ADDR = 1, R_DATA = 2;
	reg [1:0] r_state;
	reg [16:0] read_cnt;

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
			r_state		<= R_IDLE;
		end else begin
			wen			<= 0;
			read_done	<= 0;
			case(r_state)
				R_IDLE: begin
						axi_arvalid <= 0;
						axi_araddr  <= 0;
						read_cnt	<= 0;
						r_state	<= start_read ? R_ADDR : R_IDLE;
						end
				R_ADDR: begin
						axi_araddr	<= incr_addr_i ? raddr_reg + read_cnt : raddr_reg;
						if(!axi_arvalid) begin
							axi_arvalid	<= 1;
						end
						if(axi_arvalid && axi_arready) begin
							axi_arvalid	<= 0;	
							r_state		<= R_DATA;
						end
						end
				R_DATA: begin
						if(axi_rvalid&&!fifo_full) begin
							axi_rready	<= 1;
							data_in		<= axi_rdata;
						end 
						if(axi_rvalid&&axi_rready&&(!fifo_full)) begin
							wen			<= 1;
							axi_rready	<= 0;
							read_cnt	<= read_cnt + 4;
							if(read_cnt+4 < r_size_data) begin
								r_state		<= R_ADDR;
							end else begin
								read_done	<= 1;
								r_state		<= R_IDLE;
							end
						end 
					end
				default: r_state <= R_IDLE;
			endcase
		end
	end
endmodule