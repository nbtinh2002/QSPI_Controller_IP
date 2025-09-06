module qspi_dma(
	// Clock and reset
	input	clk,
	input	rst_n,
	
	// DMA APB interfacae
	input				dma_sel_i,
	input				dma_enable_i,
	input				dma_dir_i,

	//DMA AXI4 Interface
		//Read address: AR channel
	output reg			axi_arvalid,
	output reg 	[31:0]	axi_araddr,
	input				axi_arready,
		//Read data: R channel
	input 				axi_rvalid,
	input		[31:0]	axi_rdata,
	output reg			axi_rready,
		//Write address: AW channel
	output reg			axi_awvalid,
	output reg	[31:0]	axi_awaddr,
	input				axi_awready,
		//Write data : W channel
	output reg			axi_wvalid,
	output reg  [3:0]	axi_wstrb,
	output reg	[31:0]	axi_wdata,
	input				axi_wready,
		//Response: B channel
	input				axi_bvalid,
	output reg			axi_bready,

	//csr input for dma
	input wire[31:0] src_addr_i, len_i,
	input dma_start_i,// start from ce
	input [3:0] dma_burst_size_i,
	input dma_incr_addr_i,
	//connect to fifo
	//read fifo is write to axi
	output dma_fifo_wen, dma_fifo_ren,
	input dma_fifo_full, dma_fifo_empty,
	input [31:0]dma_fifo_rdata, 
	output[31:0]dma_fifo_wdata,
	input [6:0] rx_level_i,
	output dma_ce_done
);

// Connection between apb_interface and controller
wire 	    dma_done;
wire [31:0] src_reg;
wire 		incr_addr;

// Connection between controller and read_axi4_interface
wire 		start_read;
wire [31:0]	r_size_data;
wire [31:0] raddr_reg;
wire		read_done;

// Connection between controller and write_axi4_interface
wire 		start_write;
wire [31:0]	w_size_data;
wire [31:0] waddr_reg;
wire		write_done;
wire[3:0] dma_burst_size;

	dma_controller ctrl0(.clk(clk),
                        .rst_n(rst_n),
                        .dma_start_i(dma_start_i),
                        .len_i(len_i),
                        .src_addr_i(src_addr_i),
                        .dma_sel_i(dma_sel_i),
                        .dma_enable_i(dma_enable_i),

                        .dma_done(dma_done),
                        .start_read(start_read),
                        .r_size_data(r_size_data),
                        .raddr_reg(raddr_reg),
                        .read_done(read_done),
                        .start_write(start_write),
                        .w_size_data(w_size_data),
                        .waddr_reg(waddr_reg),
                        .write_done(write_done),
                        .dma_dir_i(dma_dir_i),
                        .dma_ce_done,
                        .incr_addr_i(dma_incr_addr_i),
                        .incr_addr_o(incr_addr),
                        .dma_burst_size_i(dma_burst_size_i),
                        .dma_burst_size_o(dma_burst_size)
    );
	//DMA read_axi4_interface module
	dma_read_axi4 rd_axi40(	.clk(clk),
                            .rst_n(rst_n),
                            .start_read(start_read),
                            .r_size_data(r_size_data),
                            .raddr_reg(raddr_reg),
                            .read_done(read_done),
                            .fifo_full(dma_fifo_full),
                            .wen(dma_fifo_wen),
                            .data_in(dma_fifo_wdata),
                            .axi_arvalid(axi_arvalid),
                            .axi_araddr(axi_araddr),
                            .axi_arready(axi_arready),
                            .axi_rvalid(axi_rvalid),
                            .axi_rdata(axi_rdata),
                            .axi_rready(axi_rready)
    );

	//DMA write_axi4_interface module
	dma_write_axi4 wr_axi40(.clk(clk),
                            .rst_n(rst_n),
                            .start_write(start_write),
                            .w_size_data(w_size_data),
                            .waddr_reg(waddr_reg),
                            .write_done(write_done),
                            .fifo_empty(dma_fifo_empty),
                            .data_out(dma_fifo_rdata),
                            .ren(dma_fifo_ren),
                            .axi_awvalid(axi_awvalid),
                            .axi_awaddr(axi_awaddr),
                            .axi_awready(axi_awready),
                            .axi_wvalid(axi_wvalid),
                            .axi_wstrb(axi_wstrb),
                            .axi_wdata(axi_wdata),
                            .axi_wready(axi_wready),
                            .axi_bvalid(axi_bvalid),
                            .axi_bready(axi_bready),
                            .rx_level_i(rx_level_i),
                            .incr_addr_i(incr_addr),
                            .dma_burst_size_i(dma_burst_size)					
	);
endmodule