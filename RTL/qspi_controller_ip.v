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
	output wire                      wp_n
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


	//CSR
	qspi_csr #(.APB_ADDR_WIDTH(APB_ADDR_WIDTH)) csr_inst(
		.pclk(clk), .presetn(resetn), 
		.psel(psel), .penable(penable), .pwrite(pwrite),
		.paddr(paddr), .pwdata(pwdata), .prdata(prdata),
		.pready(pready), .pslverr(pslverr),
		.irq(irq), 
		.hold_en_o(), .wp_en_o(),
		// CTRL
		.enable_o(enable), .xip_en_o(), .quad_en_o(quad_en), .cpol_o(cpol), .cpha_o(cpha), .lsb_first_o(lsb_first), .cmd_trigger_o(cmd_trigger), .dma_en_o(dma_en),
		// STATUS
		.busy_i(ce_busy), .xip_active_i(), .cmd_done_i(ce_done), .dma_done_i(),
		// INT_STAT	
		.cmd_done_set_i(ce_done), .dma_done_set_i(),  .err_set_i(err_set),	.fifo_tx_empty_set_i(tx_empty),  .fifo_rx_full_set_i(rx_full), 
		// CLK_DIV, CS_CTRL
		.clk_div_o(clk_div), .cs_auto_o(cs_auto), .cs_level_o(cs_level), .cs_delay_o(cs_delay),
		// XIP_CFG
		.xip_cmd_lanes_o(), .xip_addr_lanes_o(), .xip_data_lanes_o(), .xip_addr_bytes_o(),
		.xip_mode_en_o(),.xip_dummy_cycles_o(), .xip_cont_read_o(), .xip_write_o(), 
		//XIP_CMD
		.xip_read_op_o(), .xip_write_op_o(), .xip_mode_bits_o(),
		//CMD_CFG
		.cmd_cmd_lanes_o(cmd_lanes), .cmd_addr_lanes_o(addr_lanes),.cmd_data_lanes_o(data_lanes), .cmd_addr_bytes_o(addr_bytes), 
		.cmd_mode_en_o(mode_en), .cmd_dummy_cycles_o(dummy_cycles),.cmd_dir_o(cmd_dir), 
		//CMD_OP
		.cmd_opcode_o(cmd_opcode), .cmd_mode_bits_o(mode_bits), 
		//CMD_ADDR, CMD_LEN, CMD_EXTRA_DUMMY
		.cmd_addr_o(cmd_addr), .cmd_len_o(cmd_len), .cmd_extra_dummy_o(cmd_extra_dummy),
		// DMA_CFG
		.dma_burst_size_o(), .dma_dir_o(), .dma_incr_addr_o(),
		// DMA_ADDR, DMA_LEN
		.dma_addr_o(), .dma_len_o(), 
		// FIFO_STAT
		.tx_level_i(tx_level), .rx_level_i(rx_level), .tx_empty_i(tx_empty), .rx_full_i(rx_full),
		// ERR_STAT
		.timeout_i(timeout), .overrun_i(overrun), .underrun_i(underrun), .axi_err_i(),
		// FIFO signals
		.tx_full_i(tx_full), .tx_data_o(tx_data), .tx_wen_o(tx_wen), 
		.rx_empty_i(rx_empty), .rx_data_i(rx_data), .rx_ren_o(rx_ren)	
	);
	// CE
	qspi_ce qspi_ce_inst(
		.clk(clk), .resetn(resetn), 
		.enable(enable), .cmd_trigger(cmd_trigger), .dma_en(dma_en),
		.qspi_done(qspi_done), .dma_done(),
		.ce_start(ce_start), .dma_start(),
		.ce_busy(ce_busy), .ce_done(ce_done)
	);
	// TX FIFO
	qspi_tx_fifo #(.FIFO_DEPTH(FIFO_DEPTH)) tx_fifo_inst ( 
		.clk(clk), .resetn(resetn), 
		.data_in(tx_data), .data_out(tx_data_fifo), 
		.tx_wen(tx_wen),.tx_ren(tx_ren),
		.tx_full(tx_full),.tx_empty(tx_empty), 
		.tx_level(tx_level)
	);
	// RX FIFO
	qspi_rx_fifo #(.FIFO_DEPTH(FIFO_DEPTH)) rx_fifo_inst (
		.clk(clk), .resetn(resetn), 
		.data_in(rx_data_fifo), .data_out(rx_data), 
		.rx_wen(rx_wen),.rx_ren(rx_ren),
		.rx_full(rx_full),.rx_empty(rx_empty), 
		.rx_level(rx_level)
	);
		// QSPI FSM
	qspi_fsm #(.SUPPORT_HOLD_UP(SUPPORT_HOLD_UP)) fsm_inst(
		.qclk(clk), .qresetn(resetn),
		.sclk(sclk), .cs_n(cs_n), .hold_n(hold_n), .wp_n(wp_n),
		.io0(io0), .io1(io1), .io2(io2), .io3(io3),	
		// Input signal from CSR
		.clk_div(clk_div), .enable(enable), .quad_en(quad_en), .cpol(1'b0), .cpha(1'b0), .lsb_first(lsb_first), .cs_auto(1'b1), .cs_level(cs_level), .cs_delay(cs_delay),
		// Start/Done
		.start(ce_start), .done(qspi_done),
		// CMD & XIP field
		.cmd_lanes(cmd_lanes), .addr_lanes(addr_lanes), .data_lanes(data_lanes), .addr_bytes(addr_bytes),
		.mode_en(mode_en), .dummy_cycles(dummy_cycles), .mode_bits(mode_bits),
		// XIP field
		.xip_cont_read(), .xip_write_en(), .xip_read_op(), .xip_write_op(),
		// CMD field
		.cmd_dir(cmd_dir), .cmd_opcode(cmd_opcode), .cmd_addr(cmd_addr), .cmd_len(cmd_len), .cmd_extra_dummy(cmd_extra_dummy),
		// TX FIFO signals (IP -> flash),// RX FIFO signals (flash -> IP)
		.tx_empty(tx_empty), .tx_data_fifo(tx_data_fifo), .tx_ren(tx_ren),
		.rx_full(rx_full), .rx_data_fifo(rx_data_fifo), .rx_wen(rx_wen),
		// ERROR flag signals
		.underrun(underrun), .overrun(overrun), .timeout(timeout)
	);
endmodule