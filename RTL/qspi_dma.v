module qspi_dma(
	input  wire	 clk,
	input  wire  resetn,
	
    // Signals from CSR
	input  wire	        dma_en_i,
	input  wire         dma_enable_i,
    input  wire         dma_dir_i,
	input  wire         dma_incr_addr_i,	
    input  wire [3:0]   dma_burst_size_i,
    input  wire[31:0]   dma_addr_i,
    input  wire [31:0]  dma_len_i,

    // start/done
    input  wire         dma_start_i,// From CE
    output wire         dma_ce_done,

	// FIFO Interact
    input  wire         rx_empty_i, tx_full_i,     
	output wire         dma_rx_ren, dma_tx_wen, 
	input  wire [31:0]  dma_data_i,
    output wire [31:0]  dma_data_o,
	input  wire [6:0]   rx_level_i,

	//DMA AXI4 Interface
	output reg			axi_arvalid,
	output reg 	[31:0]	axi_araddr,
	input  wire 		axi_arready,
	input  wire 		axi_rvalid,
	input  wire [31:0]	axi_rdata,
	output reg			axi_rready,
	output reg			axi_awvalid,
	output reg	[31:0]	axi_awaddr,
	input				axi_awready,
	output reg			axi_wvalid,
	output reg  [3:0]	axi_wstrb,
	output reg	[31:0]	axi_wdata,
	input  wire 		axi_wready,
	input  wire 		axi_bvalid,
	output reg			axi_bready	
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
wire[3:0]   dma_burst_size;

	dma_controller ctrl0(
        .clk(clk), .rst_n(resetn),
        .dma_start_i(dma_start_i),
        .len_i(dma_len_i),
        .src_addr_i(dma_addr_i),
        .dma_sel_i(dma_en_i),
        .dma_enable_i(dma_enable_i),
        .dma_done(dma_done),
        .dma_dir_i(dma_dir_i),
        .dma_ce_done,
        .incr_addr_i(dma_incr_addr_i),
        .incr_addr_o(incr_addr),
        .dma_burst_size_i(dma_burst_size_i),
        .dma_burst_size_o(dma_burst_size),

        .start_read(start_read),
        .r_size_data(r_size_data),
        .raddr_reg(raddr_reg),
        .read_done(read_done),

        .start_write(start_write),
        .w_size_data(w_size_data),
        .waddr_reg(waddr_reg),
        .write_done(write_done)
    );

	//DMA read_axi4_interface module
	dma_read_axi4 rd_axi40(	
        .clk(clk), .rst_n(resetn),
        .start_read(start_read),
        .r_size_data(r_size_data),
        .raddr_reg(raddr_reg),
        .read_done(read_done),
        .fifo_full(tx_full_i),
        .wen(dma_tx_wen),
        .data_in(dma_data_o),
        .axi_arvalid(axi_arvalid),
        .axi_araddr(axi_araddr),
        .axi_arready(axi_arready),
        .axi_rvalid(axi_rvalid),
        .axi_rdata(axi_rdata),
        .axi_rready(axi_rready)
    );

	//DMA write_axi4_interface module
	dma_write_axi4 wr_axi40(
        .clk(clk), .rst_n(resetn),
        .start_write(start_write),
        .w_size_data(w_size_data),
        .waddr_reg(waddr_reg),
        .write_done(write_done),
        .fifo_empty(rx_empty_i),
        .data_out(dma_data_i),
        .ren(dma_rx_ren),
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