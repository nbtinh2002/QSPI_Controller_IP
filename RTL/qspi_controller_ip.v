module qspi_controller_ip
#(
	parameter integer DATA_WIDTH 		= 32,// AXI data bus width
	parameter integer AXI_ADDR_WIDTH 	= 32,// AXI address width
	parameter integer FIFO_DEPTH		= 16,// Depth of TX/RX FIFO
	parameter		  SUPPORT_XIP_WRITE	= 0, //	Enable write support in XIP mode
	parameter		  SUPPORT_HOLD_UP	= 0, //	Enable optional HOLD, WP pins for flash devices
	parameter integer MAX_BURST_LEN		= 16,// Maximum AXI burst length for DMA
	parameter integer APB_ADDR_WIDTH	= 12 //	APB address width
)(
	input  wire	 clk,
	input  wire  resetn,
	output wire  irq,

	// APB interface
	input  wire                      psel,
	input  wire                      penable,
	input  wire                      pwrite,
	input  wire [APB_ADDR_WIDTH-1:0] paddr,
	input  wire [DATA_WIDTH-1:0]     pwdata,
	output wire [DATA_WIDTH-1:0]     prdata,
	output wire                      pready,
	output wire                      pslverr,

	// QSPI interface
	output wire                      sclk,
	output wire                      cs_n,
	inout  wire                      io0,
	inout  wire                      io1,
	inout  wire                      io2,
	inout  wire                      io3,
	output wire                      hold_n,
	output wire                      wp_n,

	// AXI4 Master Interface
//	output wire [3:0]                m_awid,
    output wire [AXI_ADDR_WIDTH-1:0] m_awaddr,
//    output wire [7:0]                m_awlen,
//    output wire [2:0]                m_awsize, 
//    output wire [1:0]                m_awburst,
    output wire                      m_awvalid,
    input  wire                      m_awready,
    // Write Data Channel
    output wire [DATA_WIDTH-1:0]     m_wdata,
    output wire [DATA_WIDTH/8-1:0]   m_wstrb,
//    output wire                      m_wlast,
//    output wire                      m_wuser,
    output wire                      m_wvalid,
    input  wire                      m_wready,
    // Write Response Channel
//    input  wire [3:0]                m_bid,
//    input  wire [1:0]                m_bresp,
//    input  wire                      m_buser,
    input  wire                      m_bvalid,
    output wire                      m_bready,
    // Read Address Channel
//    output wire [3:0]                m_arid,
    output wire [AXI_ADDR_WIDTH-1:0] m_araddr,
//    output wire [7:0]                m_arlen,
//    output wire [2:0]                m_arsize,
//    output wire [1:0]                m_arburst,
    output wire                      m_arvalid,
    input  wire                      m_arready,
    // Read Data Channel
//    input  wire [3:0]                m_rid,
    input  wire [DATA_WIDTH-1:0]     m_rdata,
//    input  wire [1:0]                m_rresp,
//    input  wire                      m_rlast,
//    input  wire                      m_ruser,
    input  wire                      m_rvalid,
    output wire                      m_rready
);
	// Internal signals
	wire 		enable, quad_en, cpol, cpha, lsb_first, cmd_trigger;
	wire 		ce_busy,  ce_done;
	wire 		timeout, overrun, underrun;
	wire 		err_set = timeout | overrun | underrun;
	wire [2:0]	clk_div;
	wire 		cs_auto, cs_level;
	wire [1:0]	cs_delay;
	wire [1:0]	cmd_lanes, addr_lanes, data_lanes, addr_bytes;
	wire		mode_en, cmd_dir;
	wire [3:0]	dummy_cycles;
	wire [7:0]	cmd_opcode, mode_bits;
	wire [31:0]	cmd_addr, cmd_len;
	wire [7:0]	cmd_extra_dummy;
	wire [3:0]	tx_level, rx_level;
	wire 		tx_empty, rx_full, tx_full, rx_empty;
	wire		tx_wen, tx_ren, rx_ren, rx_wen;
	wire [31:0]	tx_data, rx_data;

	wire		qspi_done, ce_start;
	wire [7:0]	tx_data_fifo, rx_data_fifo;

	wire 		dma_fifo_ren, dma_fifo_wen, dma_fifo_full, dma_fifo_empty;
    wire [31:0] dma_fifo_rdata, dma_fifo_wdata;
	wire 		incr_addr;

    //signal for mux control
    wire 		fifo_rx_sel_ren, fifo_rx_sel_empty, fifo_tx_sel_wen, fifo_tx_sel_full;
    wire[31:0] fifo_rx_sel_rdata, fifo_tx_sel_wdata;

	//csr source addr and len, dam_dir is csr dma_cfg[4]
	wire 		dma_dir; // 0 read from fifo, 1 write to fifo
    wire [31:0] dma_addr; // souce addr dma
    wire [31:0] dma_len; //len for dma

	//dma with ce: dma done and start signal
	wire dma_ce_done, dma_start;

	//CSR
	qspi_csr #(.APB_ADDR_WIDTH(APB_ADDR_WIDTH)) csr_inst(
		.pclk(clk), .presetn(resetn), 
		.psel(psel), .penable(penable), .pwrite(pwrite),
		.paddr(paddr), .pwdata(pwdata), .prdata(prdata),
		.pready(pready), .pslverr(pslverr),
		.irq(irq), 
		.hold_en_o(), .wp_en_o(),
		// CTRL							// STATUS					// INT_STAT							// CLK_DIV, CS_CTRL
		.enable_o(enable),				.busy_i(ce_busy),			.cmd_done_set_i(ce_done),			.clk_div_o(clk_div), 
		.xip_en_o(), 					.xip_active_i(),			.dma_done_set_i(dma_ce_done),		.cs_auto_o(cs_auto), 
		.quad_en_o(quad_en), 			.cmd_done_i(ce_done),		.err_set_i(err_set),				.cs_level_o(cs_level), 
		.cpol_o(cpol), 					.dma_done_i(dma_ce_done),	.fifo_tx_empty_set_i(tx_empty),		.cs_delay_o(cs_delay),
		.cpha_o(cpha), 												.fifo_rx_full_set_i(rx_full), 
		.lsb_first_o(lsb_first), 
		.cmd_trigger_o(cmd_trigger), 
		.dma_en_o(dma_en),
		// XIP_CFG						//XIP_CMD
		.xip_cmd_lanes_o(), 			.xip_read_op_o(),
		.xip_addr_lanes_o(), 			.xip_write_op_o(),
		.xip_data_lanes_o(), 			.xip_mode_bits_o(),
		.xip_addr_bytes_o(),
		.xip_mode_en_o(),
		.xip_dummy_cycles_o(), 
		.xip_cont_read_o(), 
		.xip_write_o(), 
		//CMD_CFG							//CMD_OP						//CMD_ADDR, CMD_LEN, CMD_EXTRA_DUMMY
		.cmd_cmd_lanes_o(cmd_lanes), 		.cmd_opcode_o(cmd_opcode),		.cmd_addr_o(cmd_addr),
		.cmd_addr_lanes_o(addr_lanes),		.cmd_mode_bits_o(mode_bits), 	.cmd_len_o(cmd_len),
		.cmd_data_lanes_o(data_lanes), 										.cmd_extra_dummy_o(cmd_extra_dummy),
		.cmd_addr_bytes_o(addr_bytes), 
		.cmd_mode_en_o(mode_en), 
		.cmd_dummy_cycles_o(dummy_cycles),
		.cmd_dir_o(cmd_dir), 
		// DMA_CFG						// DMA_ADDR, DMA_LEN
		.dma_burst_size_o(), 			.dma_addr_o(dma_addr),
		.dma_dir_o(dma_dir), 			.dma_len_o(dma_len),
		.dma_incr_addr_o(incr_addr),
		// FIFO_STAT
		.tx_level_i(tx_level), 		.rx_level_i(rx_level),  
		.tx_empty_i(tx_empty),		.rx_full_i(rx_full),
		// ERR_STAT
		.timeout_i(timeout), 
		.overrun_i(overrun), 
		.underrun_i(underrun), 
		.axi_err_i(),

		// FIFO signals
		.tx_full_i(tx_full), 		.rx_empty_i(rx_empty),
		.tx_data_o(tx_data), 		.rx_data_i(rx_data),
		.tx_wen_o(tx_wen), 			.rx_ren_o(rx_ren)	
	);
	
	// CE
	qspi_ce qspi_ce_inst(
		.clk(clk), .resetn(resetn), 
		.enable(enable), 
		.cmd_trigger(cmd_trigger), 
		.dma_en(dma_en),
		.qspi_done(qspi_done), 
		.dma_done(dma_ce_done),
		.ce_start(ce_start), 
		.dma_start(dma_start),
		.ce_busy(ce_busy), 
		.ce_done(ce_done)
	);

	// TX/RX FIFO
	qspi_fifo #(.FIFO_DEPTH(FIFO_DEPTH),.WR_BYTES(4),.RD_BYTES(1)) tx_fifo_inst (
		.clk(clk), .resetn(resetn), 
		.data_in(fifo_tx_sel_wdata),	
		.data_out(tx_data_fifo), 
		.wr_en(fifo_tx_sel_wen),			
		.rd_en(tx_ren),
		.full(fifo_tx_sel_full),			
		.empty(tx_empty), 
		.level(tx_level)
	);

	qspi_fifo #(.FIFO_DEPTH(FIFO_DEPTH),.WR_BYTES(1),.RD_BYTES(4)) rx_fifo_inst (
		.clk(clk), .resetn(resetn), 
		.data_in(rx_data_fifo), 		
		.data_out(fifo_rx_sel_rdata), 
		.wr_en(rx_wen),				
		.rd_en(fifo_rx_sel_ren),
		.full(rx_full),				
		.empty(fifo_rx_sel_empty), 
		.level(rx_level)
	);

	// QSPI FSM
	qspi_fsm #(.SUPPORT_HOLD_UP(SUPPORT_HOLD_UP)) fsm_inst(
		.qclk(clk), .qresetn(resetn),
		.sclk(sclk), .cs_n(cs_n), .hold_n(hold_n), .wp_n(wp_n),
		.io0(io0), .io1(io1), .io2(io2), .io3(io3),	
		// Input signal from CSR
		.clk_div(clk_div), 
		.enable(enable), .quad_en(quad_en), 
		.cpol(1'b0), .cpha(1'b0), 
		.lsb_first(lsb_first), 
		.cs_auto(1'b1), .cs_level(cs_level), .cs_delay(cs_delay),
		// Start/Done
		.start(ce_start), .done(qspi_done),
		// CMD & XIP field				// XIP field					// CMD field
		.cmd_lanes(cmd_lanes), 			.xip_cont_read(),				.cmd_dir(cmd_dir),
		.addr_lanes(addr_lanes), 		.xip_write_en(),				.cmd_opcode(cmd_opcode),
		.data_lanes(data_lanes), 		.xip_read_op(),					.cmd_addr(cmd_addr),
		.addr_bytes(addr_bytes),		.xip_write_op(),				.cmd_len(cmd_len),
		.mode_en(mode_en), 												.cmd_extra_dummy(cmd_extra_dummy),
		.dummy_cycles(dummy_cycles), 
		.mode_bits(mode_bits),
		// TX FIFO signals (IP -> flash),// RX FIFO signals (flash -> IP)
		.tx_empty(tx_empty), 				.rx_full(rx_full),
		.tx_data_fifo(tx_data_fifo), 		.rx_data_fifo(rx_data_fifo),
		.tx_ren(tx_ren),					.rx_wen(rx_wen),
		// ERROR flag signals
		.underrun(underrun), 
		.overrun(overrun), 
		.timeout(timeout)
	);

	//TX, and RX sel
	fifo_rx_sel rx_s0(
		.sel(dma_en), 
		.ren(fifo_rx_sel_ren),
		.empty(fifo_rx_sel_empty),
		.data(fifo_rx_sel_rdata),

		.dma_fifo_ren_i(dma_fifo_ren),   		
		.dma_fifo_empty_o(dma_fifo_empty),
		.dma_fifo_data_o(dma_fifo_rdata),

		.cmd_fifo_ren_i(rx_ren), 
		.cmd_fifo_empty_o(rx_empty),
		.cmd_fifo_data_o(rx_data)
    );

    fifo_tx_sel tx_fifo_sel(
        .sel(dma_en), 
        .wen(fifo_tx_sel_wen),
        .full(fifo_tx_sel_full),
        .data(fifo_tx_sel_wdata),

        .dma_wen_i(dma_fifo_wen),   
        .dma_full_o(dma_fifo_full),
        .dma_data_i(dma_fifo_wdata),

        .cmd_wen_i(tx_wen), 
        .cmd_full_i(tx_full),
        .cmd_data_i(tx_data)
    );

	qspi_dma dma_inst(	
		.clk(clk),.rst_n(resetn),
        //fifo signal
        .dma_fifo_ren(dma_fifo_ren),   		.dma_fifo_wen(dma_fifo_wen),
        .dma_fifo_empty(dma_fifo_empty),	.dma_fifo_full(dma_fifo_full),
        .dma_fifo_rdata(dma_fifo_rdata),	.dma_fifo_wdata(dma_fifo_wdata),
		.rx_level_i(rx_level),
        //data input from csr
        .src_addr_i(dma_addr), .len_i(dma_len), .dma_start_i(dma_start),
        .dma_sel_i(dma_en), .dma_enable_i(enable), .dma_dir_i(dma_dir), 
        .dma_incr_addr_i(incr_addr), .dma_ce_done(dma_ce_done),
        // AXI master interface
        .axi_awvalid(m_awvalid), .axi_awaddr(m_awaddr), .axi_awready(m_awready),
        .axi_wvalid(m_wvalid), .axi_wdata(m_wdata), .axi_wstrb(m_wstrb), .axi_wready(m_wready),
        .axi_bvalid(m_bvalid), .axi_bready(m_bready),
        .axi_arvalid(m_arvalid), .axi_araddr(m_araddr), .axi_arready(m_arready),
        .axi_rvalid(m_rvalid), .axi_rdata(m_rdata), .axi_rready(m_rready)
    );

	assign m_awid    = 4'd0;
	assign m_awlen   = 8'd0;
	assign m_awsize  = 3'd2;   // 4-byte beat
	assign m_awburst = 2'b01;  // INCR
	assign m_wlast   = 1'b1;
	assign m_wuser   = 1'b0;
	assign m_arid    = 4'd0;
	assign m_arlen   = 8'd0;
	assign m_arsize  = 3'd2;
	assign m_arburst = 2'b01;
endmodule