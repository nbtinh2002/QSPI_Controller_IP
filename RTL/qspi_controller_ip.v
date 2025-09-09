module qspi_controller_ip#(
	// ------------------- Parameter -------------------
	parameter integer DATA_WIDTH 		= 32,// AXI data bus width
	parameter integer AXI_ADDR_WIDTH 	= 32,// AXI address width
	parameter integer FIFO_DEPTH		= 16,// Depth of TX/RX FIFO
	parameter		  SUPPORT_XIP_WRITE	= 0, //	Enable write support in XIP mode
	parameter		  SUPPORT_HOLD_UP	= 0, //	Enable optional HOLD, WP pins for flash devices
	parameter integer MAX_BURST_LEN		= 16,// Maximum AXI burst length for DMA
	parameter integer APB_ADDR_WIDTH	= 12 //	APB address width
)(
	// ------------------- Signals -------------------
	input  wire	 clk,
	input  wire  resetn,
	output wire  irq,
	// APB (CSR) 
	input  wire                      psel,
	input  wire                      penable,
	input  wire                      pwrite,
	input  wire [APB_ADDR_WIDTH-1:0] paddr,
	input  wire [31:0]     			 pwdata,
	output wire [31:0]     			 prdata,
	output wire                      pready,
	output wire                      pslverr,
	// QSPI IO 
	output wire                      sclk,
	output wire                      cs_n,
	inout  wire                      io0,
	inout  wire                      io1,
	inout  wire                      io2,
	inout  wire                      io3,
	output wire                      hold_n,
	output wire                      wp_n,
	// AXI Master (DMA)
    output wire [AXI_ADDR_WIDTH-1:0] m_awaddr,
    output wire                      m_awvalid,
    input  wire                      m_awready,
    output wire [DATA_WIDTH-1:0]     m_wdata,
    output wire [DATA_WIDTH/8-1:0]   m_wstrb,
    output wire                      m_wvalid,
    input  wire                      m_wready,
    input  wire                      m_bvalid,
    output wire                      m_bready,
    output wire [AXI_ADDR_WIDTH-1:0] m_araddr,
    output wire                      m_arvalid,
    input  wire                      m_arready,
    input  wire [DATA_WIDTH-1:0]     m_rdata,
    input  wire                      m_rvalid,
    output wire                      m_rready,
	// AXI Slave (XIP)
    input  wire [AXI_ADDR_WIDTH-1:0] s_araddr,
    input  wire [7:0]              	 s_arlen,
    input  wire [2:0]              	 s_arsize,
    input  wire [1:0]              	 s_arburst,
    input  wire                    	 s_arvalid,
    output wire                    	 s_arready,
    output wire [DATA_WIDTH-1:0]   	 s_rdata,
    output wire                    	 s_rlast,
    output wire                    	 s_rvalid,
    input  wire                    	 s_rready	
);
	// ------------------- Internal signals -------------------
	wire		enable, xip_en, quad_en, cpol, cpha, lsb_first, cmd_trigger, dma_en, hold_en, wp_en;
	wire 		xip_active, ce_busy, ce_done, dma_done, qspi_done, ce_start, dma_start;
	wire [2:0]	clk_div;
	wire 		cs_auto, cs_level;
	wire [1:0]	cs_delay;

	wire [1:0]	cmd_cmd_lanes, cmd_addr_lanes, cmd_data_lanes, cmd_addr_bytes;
	wire		cmd_mode_en, cmd_dir;
	wire [3:0]	cmd_dummy_cycles;
	wire [7:0]	cmd_opcode, mode_bits, cmd_extra_dummy;
	wire [31:0]	cmd_addr, cmd_len;

	wire		xip_start_o, xip_dir_o, xip_done_o;
	wire [31:0] xip_addr_o, xip_len_o;
	wire [1:0]  xip_cmd_lanes_i, xip_addr_lanes_i, xip_data_lanes_i, xip_addr_bytes_i;
	wire 		xip_mode_en_i, xip_cont_read_i, xip_write_en_i;
	wire [3:0]	xip_dummy_cycles_i;
	wire [7:0]  xip_read_op_i, xip_write_op_i, xip_mode_bits_i;
	wire [1:0]	xip_cmd_lanes_o, xip_addr_lanes_o, xip_data_lanes_o, xip_addr_bytes_o;
	wire 		xip_mode_en_o, xip_cont_read_o;
	wire [3:0]	xip_dummy_cycles_o;
	wire [7:0]  xip_opcode_o, xip_mode_bits_o;

	wire [3:0]  burst_size;
	wire 		dma_dir, incr_addr;
	wire [31:0] dma_addr, dma_len;

	wire 		timeout, overrun, underrun, axi_err;
	wire [6:0]  ff_bytes_cnt, cnt_bytes_ff;

	wire [3:0]	tx_level, rx_level;
	wire [7:0]  tx_data_o, rx_data_i;
	wire [31:0] rx_data_o, csr_data_o, dma_data_o;
	wire		tx_empty, tx_full, rx_empty, rx_full;
	wire		tx_ren, rx_wen, csr_rx_ren, dma_rx_ren, csr_tx_wen, dma_tx_wen;

	// Source & Destination data for TX/RX FIFO
	wire		tx_wen	   =  dma_en ? dma_tx_wen : csr_tx_wen;
	wire		rx_ren 	   =  xip_en ? xip_rx_ren_o : (dma_en ? dma_rx_ren : csr_rx_ren);
	wire [31:0] tx_data_i  =  dma_en ? dma_data_o : csr_data_o;
	wire [31:0] dma_data_i = (!xip_en && dma_en) ? rx_data_o  : dma_data_i;
	wire [31:0] csr_data_i = (!xip_en && !dma_en) ? rx_data_o  : csr_data_i;
	wire [31:0] xip_data_i = xip_en ? rx_data_o : xip_data_i;

	wire start = xip_en ? xip_start_o : ce_start;
	wire [1:0]  cmd_lanes  	= xip_en ? xip_cmd_lanes_o 	: cmd_cmd_lanes;
	wire [1:0]  addr_lanes 	= xip_en ? xip_addr_lanes_o	: cmd_addr_lanes;
	wire [1:0]  data_lanes 	= xip_en ? xip_data_lanes_o	: cmd_data_lanes;
	wire [1:0]  addr_bytes 	= xip_en ? xip_addr_bytes_o	: cmd_addr_bytes;
	wire 	    mode_en	   	= xip_en ? xip_mode_en_o : cmd_mode_en;
	wire [3:0]  dummy_cycles= xip_en ? xip_dummy_cycles_o : cmd_dummy_cycles;
	wire [7:0]  opcode 		= xip_en ? xip_opcode_o : cmd_opcode;
	wire [31:0] addr 		= xip_en ? xip_addr_o : cmd_addr;
	wire [31:0] len 		= xip_en ? xip_len_o : cmd_len;
	wire 		dir 		= xip_en ? xip_dir_o : cmd_dir;

	wire		ce_qspi_done  = !xip_en ? qspi_done : 0;
	wire		xip_qspi_done =  xip_en ? qspi_done : 0;
	wire		done		  = xip_en ? xip_done_o : ce_done;
	// ------------------- Module Instantiation -------------------
	qspi_xip #(.DATA_WIDTH(DATA_WIDTH),.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
	 			.SUPPORT_XIP_WRITE(SUPPORT_XIP_WRITE)) xip_inst(
		.clk(clk), .resetn(resetn),
		//FSM QSPI
		.xip_start_o(xip_start_o), .xip_addr_o(xip_addr_o), 
		.xip_len_o(xip_len_o), .xip_dir_o(xip_dir_o),
		//RX FIFO
		.xip_data_i(xip_data_i), .xip_rx_ren_o(xip_rx_ren_o), .xip_rx_full(rx_full),
		// CSR
		.xip_en_i(xip_en), .xip_qspi_done_i(xip_qspi_done),
		.xip_active_o(xip_active), .xip_done_o(xip_done_o),
		.xip_cmd_lanes_i(xip_cmd_lanes_i),
		.xip_addr_lanes_i(xip_addr_lanes_i),
		.xip_data_lanes_i(xip_data_lanes_i),
		.xip_addr_bytes_i(xip_addr_bytes_i),
		.xip_dummy_cycles_i(xip_dummy_cycles_i),
		.xip_mode_en_i(xip_mode_en_i),
		.xip_cont_read_i(xip_cont_read_i),
		.xip_write_en_i(xip_write_en_i),
		.xip_read_op_i(xip_read_op_i),
		.xip_write_op_i(xip_write_op_i),
		.xip_mode_bits_i(xip_mode_bits_i),

		.xip_cmd_lanes_o(xip_cmd_lanes_o),
		.xip_addr_lanes_o(xip_addr_lanes_o),
		.xip_data_lanes_o(xip_data_lanes_o),
		.xip_addr_bytes_o(xip_addr_bytes_o),
		.xip_dummy_cycles_o(xip_dummy_cycles_o),
		.xip_mode_en_o(xip_mode_en_o),
		.xip_cont_read_o(xip_cont_read_o),
		.xip_opcode_o(xip_opcode_o),
		.xip_mode_bits_o(xip_mode_bits_o),
		//AXI4 Lite
		.s_arvalid(s_arvalid), .s_arready(s_arready), 
		.s_araddr(s_araddr), .s_arlen(s_arlen), 
		.s_arsize(s_arsize), .s_arburst(s_arburst),
		.s_rvalid(s_rvalid), .s_rready(s_rready), 
		.s_rdata(s_rdata), .s_rlast(s_rlast)
	); 

	qspi_csr #(.APB_ADDR_WIDTH(APB_ADDR_WIDTH)) csr_inst(
		//APB signals
		.clk(clk), .resetn(resetn), 
		.psel(psel), .penable(penable), .pwrite(pwrite),
		.paddr(paddr), .pwdata(pwdata), .prdata(prdata),
		.pready(pready), .pslverr(pslverr),
		.irq(irq), 
		// CTRL_REG signals
		.enable_o(enable), .xip_en_o(xip_en), .quad_en_o(quad_en),
		.cpol_o(cpol), .cpha_o(cpha), .lsb_first_o(lsb_first),
		.cmd_trigger_o(cmd_trigger),
		.dma_en_o(dma_en), .hold_en_o(hold_en), .wp_en_o(wp_en),
		// STATUS
		.busy_i(ce_busy), .xip_active_i(xip_active), .cmd_done_i(done), .dma_done_i(dma_done),
		// INT_STAT
		.cmd_done_set_i(done),												
		.dma_done_set_i(dma_done),
		.err_set_i(timeout | overrun | underrun | axi_err),
		.fifo_tx_empty_set_i(tx_empty),
		.fifo_rx_full_set_i(rx_full),
		// CLK_DIV, CS_CTRL												 
		.clk_div_o(clk_div), .cs_auto_o(cs_auto), .cs_level_o(cs_level), .cs_delay_o(cs_delay),
		// XIP_CFG
		.xip_cmd_lanes_o(xip_cmd_lanes_i), .xip_addr_lanes_o(xip_addr_lanes_i), .xip_data_lanes_o(xip_data_lanes_i),
		.xip_addr_bytes_o(xip_addr_bytes_i), .xip_dummy_cycles_o(xip_dummy_cycles_i), 
		.xip_mode_en_o(xip_mode_en_i), .xip_cont_read_o(xip_cont_read_i), .xip_write_en_o(xip_write_en_i), 
		//XIP_CMD
		.xip_read_op_o(xip_read_op_i), .xip_write_op_o(xip_write_op_i), .xip_mode_bits_o(xip_mode_bits_i),
		//CMD_CFG
		.cmd_cmd_lanes_o(cmd_cmd_lanes),
		.cmd_addr_lanes_o(cmd_addr_lanes),
		.cmd_data_lanes_o(cmd_data_lanes),
		.cmd_addr_bytes_o(cmd_addr_bytes),
		.cmd_mode_en_o(cmd_mode_en),
		.cmd_dummy_cycles_o(cmd_dummy_cycles),
		.cmd_dir_o(cmd_dir),
		//CMD_OP
		.cmd_opcode_o(cmd_opcode), .cmd_mode_bits_o(mode_bits), 
		//CMD_ADDR/LEN/EXTRA_DUMMY
		.cmd_addr_o(cmd_addr), .cmd_len_o(cmd_len), .cmd_extra_dummy_o(cmd_extra_dummy),		 
		// DMA_CFG
		.dma_burst_size_o(burst_size), .dma_dir_o(dma_dir), .dma_incr_addr_o(incr_addr),
		// DMA_ADDR, DMA_LEN
 		.dma_addr_o(dma_addr), .dma_len_o(dma_len),
		// ERR_STAT
		.timeout_i(timeout), .overrun_i(overrun), .underrun_i(underrun), .axi_err_i(axi_err),
		// FIFO_STAT
		.tx_level_i(tx_level),			.rx_level_i(rx_level),
		.tx_full_i(tx_full), 			.rx_full_i(rx_full),
		.tx_empty_i(tx_empty),			.rx_empty_i(rx_empty),
		.csr_data_o(csr_data_o),		.csr_data_i(csr_data_i),
		.csr_tx_wen_o(csr_tx_wen),		.csr_rx_ren_o(csr_rx_ren)			
	);
	
	qspi_ce ce_inst(
		.clk(clk), .resetn(resetn), 
		.enable(enable), 
		.cmd_trigger(cmd_trigger), 
		.dma_en(dma_en),
		.qspi_done(ce_qspi_done), 
		.dma_done(dma_done),
		.ce_start(ce_start), 
		.dma_start(dma_start),
		.ce_busy(ce_busy), 
		.ce_done(ce_done)
	);

	qspi_fifo #(.FIFO_DEPTH(FIFO_DEPTH),.WR_BYTES(4),.RD_BYTES(1)) tx_inst (
		.clk(clk), .resetn(resetn), 
		.wr_en(tx_wen),
		.data_in(tx_data_i),
		.full(tx_full),
		.rd_en(tx_ren),
		.data_out(tx_data_o), 
		.empty(tx_empty), 
		.level(tx_level),
		.ff_bytes_cnt(cnt_bytes_ff)
	);
	
	qspi_fifo #(.FIFO_DEPTH(FIFO_DEPTH),.WR_BYTES(1),.RD_BYTES(4)) rx_inst (
		.clk(clk), .resetn(resetn), 
		.wr_en(rx_wen),
		.data_in(rx_data_i), 
		.full(rx_full),	
		.rd_en(rx_ren),
		.data_out(rx_data_o), 
		.empty(rx_empty), 
		.level(rx_level),
		.ff_bytes_cnt(ff_bytes_cnt)
	);

	qspi_fsm #(.SUPPORT_HOLD_UP(SUPPORT_HOLD_UP)) fsm_inst(
		.clk(clk), .resetn(resetn),
		// QSPI Signals
		.sclk(sclk), .cs_n(cs_n), .hold_n(hold_n), .wp_n(wp_n),
		.io0(io0), .io1(io1), .io2(io2), .io3(io3),	
		// Input signal from CSR
		.clk_div(clk_div), 
		.enable(enable), .quad_en(quad_en), .cpol(1'b0), .cpha(1'b0), 
		.lsb_first(lsb_first), .hold_en(hold_en), .wp_en(wp_en),
		.cs_auto(1'b1), .cs_level(cs_level), .cs_delay(cs_delay),
		// CMD & XIP field
		.cmd_lanes(cmd_lanes),
		.addr_lanes(addr_lanes),
		.data_lanes(data_lanes),
		.addr_bytes(addr_bytes),
		.mode_en(mode_en),
		.dummy_cycles(dummy_cycles), 
		.mode_bits(mode_bits),
		// CMD field
		.cmd_dir(dir),
		.cmd_opcode(opcode),
		.cmd_addr(addr),
		.cmd_len(len),
		.cmd_extra_dummy(cmd_extra_dummy),
		//[3]
		// Start/Done
		.start(start), .done(qspi_done),
		// TX signals (IP -> flash),// RX signals (flash -> IP)
		.tx_empty(tx_empty), 			.rx_full(rx_full),
		.qspi_data_i(tx_data_o), 		.qspi_data_o(rx_data_i),
		.tx_ren(tx_ren),				.rx_wen(rx_wen),
		// ERROR flag signals
		.underrun(underrun), 
		.overrun(overrun), 
		.timeout(timeout)
	);

	qspi_dma dma_inst(	
		.clk(clk),.resetn(resetn),
		// From CSR
		.dma_en_i(dma_en), .dma_enable_i(enable), .dma_dir_i(dma_dir), 
		.dma_incr_addr_i(incr_addr), .dma_burst_size_i(burst_size),
		.dma_addr_i(dma_addr), .dma_len_i(dma_len),
		.dma_start_i(dma_start), .dma_ce_done(dma_done),
        // FIFO Signals
		.rx_empty_i(rx_empty),	.tx_full_i(tx_full),
		.dma_rx_ren(dma_rx_ren),   	.dma_tx_wen(dma_tx_wen),
        .dma_data_i(dma_data_i),	.dma_data_o(dma_data_o),
		.rx_level_i(ff_bytes_cnt),	.tx_level_i(cnt_bytes_ff),		
        // AXI master interface
		.axi_arvalid(m_arvalid),	.axi_araddr(m_araddr),	.axi_arready(m_arready),
		.axi_rvalid(m_rvalid), 		.axi_rdata(m_rdata), 	.axi_rready(m_rready),
		.axi_bvalid(m_bvalid), 								.axi_bready(m_bready),
        .axi_awvalid(m_awvalid), 	.axi_awaddr(m_awaddr), 	.axi_awready(m_awready),
        .axi_wvalid(m_wvalid), 		.axi_wdata(m_wdata), 	.axi_wstrb(m_wstrb), .axi_wready(m_wready)
    );
endmodule