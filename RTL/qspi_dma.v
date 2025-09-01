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
//	input [3:0] dma_brust_size_i,
	input dma_incr_addr_i,
	//connect to fifo
	//read fifo is write to axi
	output dma_fifo_wen, dma_fifo_ren,
	input dma_fifo_full, dma_fifo_empty,
	input [31:0]dma_fifo_rdata, 
	output[31:0]dma_fifo_wdata,
	input [3:0] rx_level_i,
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
                        .incr_addr_o(incr_addr)
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
                            .incr_addr_i(incr_addr)						
	);
endmodule
/*module qspi_dma
#(
    parameter integer DATA_WIDTH     = 32,
    parameter integer AXI_ADDR_WIDTH = 32,
    parameter integer MAX_BURST_LEN  = 16
)(
	// Clock and reset
	input wire          m_aclk,
	input wire          m_aresetn,

	// Start from CE
    input wire          dma_start,

    // CSR inputs
//	input wire			enbale,			// CTRL.bit0
//  input wire          dma_en,			// CTRL.bit9
	input wire [3:0] 	dma_burst_size,	// DMA_CFG.bit 0-3
	input wire			dma_dir,		// DMA_CFG.bit4
	input wire 			dma_incr_addr,	// DMA_CFG.bit5
	input wire [31:0]   dma_addr,
	input wire [31:0]   dma_len,
	output wire			dma_done, 

	// FIFO interface
	input wire 			rx_empty,
	input wire [31:0]   rx_data,
	output wire			rx_ren,

	input wire			tx_full,
	output reg [31:0]	tx_data,
	output wire			tx_wen,

	input wire [3:0] 	rx_level, 

	// DMA APB interfacae
	input				dma_sel_i,
	output reg			pready,	
	//=======================================================
    // AXI4-Lite Master Interface
    // Write Address Channel
    output wire [3:0]                m_awid,
    output wire [AXI_ADDR_WIDTH-1:0] m_awaddr,
    output wire [7:0]                m_awlen,
    output wire [2:0]                m_awsize, 
    output wire [1:0]                m_awburst,
    output wire                      m_awvalid,
    input  wire                      m_awready,
    // Write Data Channel
    output wire [DATA_WIDTH-1:0]     m_wdata,
    output wire [DATA_WIDTH/8-1:0]   m_wstrb,
    output wire                      m_wlast,
    output wire                      m_wuser,
    output wire                      m_wvalid,
    input  wire                      m_wready,
    // Write Response Channel
    input  wire [3:0]                m_bid,
    input  wire [1:0]                m_bresp,
    input  wire                      m_buser,
    input  wire                      m_bvalid,
    output wire                      m_bready,
    // Read Address Channel
    output wire [3:0]                m_arid,
    output wire [AXI_ADDR_WIDTH-1:0] m_araddr,
    output wire [7:0]                m_arlen,
    output wire [2:0]                m_arsize,
    output wire [1:0]                m_arburst,
    output wire                      m_arvalid,
    input  wire                      m_arready,
    // Read Data Channel
    input  wire [3:0]                m_rid,
    input  wire [DATA_WIDTH-1:0]     m_rdata,
    input  wire [1:0]                m_rresp,
    input  wire                      m_rlast,
    input  wire                      m_ruser,
    input  wire                      m_rvalid,
    output wire                      m_rready
);

	// Internal wires
	wire 		start_read, start_write;
	wire		read_done, write_done;
	wire [31:0]	r_size_data, raddr_reg;
	wire [31:0]	w_size_data, waddr_reg;
	wire 		incr_addr;

	// Controller
	dma_controller  
		ctrl0 #( .DATA_WIDTH(DATA_WIDTH),.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH))(

		);

	//DMA read_axi4_interface 
	dma_read_axi4 rd_a0(

	);
	
	//DMA write_axi4_interface
	dma_write_axi4 wr_a0(
		                                                    
	);
endmodule*/