// -----------------------------------------------------------------------------//
// Module: csr.v
// Note:
// 1. INT_STAT_ADDR is RW1C
// 2. cmd_trigger_o is self-clearing
// 3. tx_data_o and tx_wen_o are driven directly from APB writes
// 5. pready is always '1' — APB transaction completes in a single cycle.
// -----------------------------------------------------------------------------//
module qspi_csr
#(
	parameter APB_ADDR_WIDTH = 12
)(
	// APB Interface
	input wire	pclk,	
	input wire	presetn,
	input wire	psel,
	input wire	penable,
	input wire	pwrite,
	input wire [APB_ADDR_WIDTH-1:0]	paddr,
	input wire [31:0] pwdata,	
	output reg [31:0] prdata,
	output wire	pready,
	output wire	pslverr,

	// Interrupt request output
	output wire	irq,
	
	// CTRL outputs
	output wire	enable_o,
	output wire	xip_en_o,
	output wire	quad_en_o,
	output wire	cpol_o,
	output wire	cpha_o,
	output wire	lsb_first_o,
	output wire	cmd_trigger_o,// pulse 
	output wire	dma_en_o,
	output wire	hold_en_o,
	output wire	wp_en_o,

	// STATUS inputs
	input wire	busy_i,			
	input wire	xip_active_i,	
	input wire	cmd_done_i,		
	input wire	dma_done_i,	
	
	// INT_EN outputs
	output wire	cmd_done_en_o,	
	output wire	dma_done_en_o,
	output wire	err_en_o,
	output wire	fifo_tx_empty_en_o,
	output wire	fifo_rx_full_en_o,

	// INT_STAT
	input wire	cmd_done_set_i,
	output wire	cmd_done_o,
	input wire	dma_done_set_i,
	output wire dma_done_o,
	input wire	err_set_i,
	output wire err_done_o, 
	input wire	fifo_tx_empty_set_i,
	output wire	fifo_tx_empty_done_o,
	input wire	fifo_rx_full_set_i,
	output wire	fifo_rx_full_done_o,

	// CLK_DIV outputs
	output wire [2:0]	clk_div_o,

	// CS_CTRL outputs
	output wire			cs_auto_o,
	output wire			cs_level_o,
	output wire [1:0]	cs_delay_o,

	// XIP_CFG outputs
	output wire [1:0]	xip_cmd_lanes_o,
	output wire [1:0]	xip_addr_lanes_o,
	output wire	[1:0]	xip_data_lanes_o,
	output wire	[1:0]	xip_addr_bytes_o,
	output wire			xip_mode_en_o,
	output wire	[3:0]	xip_dummy_cycles_o,
	output wire			xip_cont_read_o,
	output wire			xip_write_o,

	// XIP_CMD outputs
	output wire [7:0]	xip_read_op_o,
	output wire [7:0]	xip_write_op_o,
	output wire	[7:0]	xip_mode_bits_o,	

	// CMD_CFG outputs
	output wire [1:0]	cmd_cmd_lanes_o,
	output wire [1:0]	cmd_addr_lanes_o,
	output wire	[1:0]	cmd_data_lanes_o,
	output wire	[1:0]	cmd_addr_bytes_o,
	output wire			cmd_mode_en_o,
	output wire	[3:0]	cmd_dummy_cycles_o,
	output wire 		cmd_dir_o,	

	// CMD_OP outputs
	output wire	[7:0]	cmd_opcode_o,
	output wire	[7:0]	cmd_mode_bits_o,

	// CMD_ADDR outputs
	output wire	[31:0]	cmd_addr_o,

	// CMD_LEN outputs
	output wire	[31:0]	cmd_len_o,

	// CMD_DUMMY outputs
	output wire	[7:0]	cmd_extra_dummy_o,

	// DMA_CFG outputs
	output wire	[3:0]	dma_burst_size_o,
	output wire 		dma_dir_o,
	output wire			dma_incr_addr_o,

	// DMA_ADDR outputs
	output wire	[31:0]	dma_addr_o,

	// DMA_LEN outputs
	output wire	[31:0]	dma_len_o,

	// FIFO_STAT inputs
	input wire [3:0]	tx_level_i,		
	input wire [3:0]	rx_level_i,		
	input wire			tx_empty_i,		
	input wire			rx_full_i,	

	// ERR_STAT inputs
	input wire	timeout_i,		
	input wire	overrun_i,		
	input wire	underrun_i,		
	input wire	axi_err_i,

	// FIFO Signals
	input  wire 		tx_full_i,
	output wire [31:0]	tx_data_o,	
	output wire			tx_wen_o,

	input  wire 		rx_empty_i,	
	input  wire [31:0]	rx_data_i,
	output wire			rx_ren_o

	);

	// Address constant for paddr APB_ADDR_WIDTH bit
	localparam [APB_ADDR_WIDTH-1:0] ID_ADDR			= 'h000;// RO
	localparam [APB_ADDR_WIDTH-1:0]	CTRL_ADDR		= 'h004;// RW
	localparam [APB_ADDR_WIDTH-1:0]	STATUS_ADDR 	= 'h008;// RO
	localparam [APB_ADDR_WIDTH-1:0]	INT_EN_ADDR 	= 'h00C;// RW
	localparam [APB_ADDR_WIDTH-1:0]	INT_STAT_ADDR	= 'h010;// RW1C
	localparam [APB_ADDR_WIDTH-1:0]	CLK_DIV_ADDR	= 'h014;// RW
	localparam [APB_ADDR_WIDTH-1:0]	CS_CTRL_ADDR	= 'h018;// RW
	localparam [APB_ADDR_WIDTH-1:0]	XIP_CFG_ADDR	= 'h01C;// RW
	localparam [APB_ADDR_WIDTH-1:0]	XIP_CMD_ADDR	= 'h020;// RW
	localparam [APB_ADDR_WIDTH-1:0]	CMD_CFG_ADDR	= 'h024;// RW
	localparam [APB_ADDR_WIDTH-1:0]	CMD_OP_ADDR		= 'h028;// RW
	localparam [APB_ADDR_WIDTH-1:0]	CMD_ADDR_ADDR	= 'h02C;// RW
	localparam [APB_ADDR_WIDTH-1:0]	CMD_LEN_ADDR	= 'h030;// RW
	localparam [APB_ADDR_WIDTH-1:0]	CMD_DUMMY_ADDR	= 'h034;// RW
	localparam [APB_ADDR_WIDTH-1:0]	DMA_CFG_ADDR	= 'h038;// RW
	localparam [APB_ADDR_WIDTH-1:0]	DMA_ADDR_ADDR	= 'h03C;// RW
	localparam [APB_ADDR_WIDTH-1:0]	DMA_LEN_ADDR	= 'h040;// RW
	localparam [APB_ADDR_WIDTH-1:0]	FIFO_TX_ADDR	= 'h044;// WO
	localparam [APB_ADDR_WIDTH-1:0]	FIFO_RX_ADDR	= 'h048;// RO
	localparam [APB_ADDR_WIDTH-1:0]	FIFO_STAT_ADDR	= 'h04C;// RO
	localparam [APB_ADDR_WIDTH-1:0]	ERR_STAT_ADDR	= 'h050;// RO

	// Internal registers 
	reg [31:0] 	ctrl_reg;
	reg [31:0] 	int_en_reg;
	reg [31:0] 	clk_div_reg;
	reg [31:0] 	cs_ctrl_reg;
	reg [31:0] 	xip_cfg_reg;
	reg [31:0] 	xip_cmd_reg;
	reg [31:0] 	cmd_cfg_reg;
	reg [31:0] 	cmd_op_reg;
	reg [31:0] 	cmd_addr_reg;
	reg [31:0] 	cmd_len_reg;
	reg [31:0] 	cmd_dummy_reg;
	reg [31:0] 	dma_cfg_reg;
	reg [31:0] 	dma_addr_reg;
	reg [31:0] 	dma_len_reg;

	// INT_STAT RW1C latches
	reg cmd_done_reg;
	reg dma_done_reg;
	reg err_reg;
	reg fifo_tx_empty_reg;
	reg fifo_rx_full_reg;
	wire [31:0] int_stat_reg = {27'b0, fifo_rx_full_reg, fifo_tx_empty_reg, err_reg, dma_done_reg, cmd_done_reg};
	wire [31:0] id_reg		= {16'h0A10, 8'h01, 8'h01};
	wire [31:0] status_reg 	= {28'b0, dma_done_i, cmd_done_i, xip_active_i, busy_i};
	wire [31:0] fifo_stat_reg	= {22'b0, rx_full_i, tx_empty_i, rx_level_i, tx_level_i};
	wire [31:0] err_stat_reg	= {28'b0, axi_err_i, underrun_i, overrun_i, timeout_i};
	


	// Decode APB transaction signals 
	wire apb_transfer = psel && penable;
	wire write = apb_transfer && pwrite;
	wire read = apb_transfer && !pwrite;

	reg invalid_addr;   
	// Detect invalid address
	always @(*) begin
    	invalid_addr = 1'b0;
    	if (apb_transfer) begin
        	case (paddr)
        	   	ID_ADDR	,CTRL_ADDR, STATUS_ADDR, INT_EN_ADDR, INT_STAT_ADDR,
            	CLK_DIV_ADDR, CS_CTRL_ADDR, XIP_CFG_ADDR, XIP_CMD_ADDR,
				CMD_CFG_ADDR, CMD_OP_ADDR, CMD_ADDR_ADDR, CMD_LEN_ADDR,
            	CMD_DUMMY_ADDR, DMA_CFG_ADDR, DMA_ADDR_ADDR	, DMA_LEN_ADDR,	
            	FIFO_TX_ADDR, FIFO_RX_ADDR, FIFO_STAT_ADDR, ERR_STAT_ADDR:
						invalid_addr = 1'b0;	
            	default: 	
						invalid_addr = 1'b1;
        	endcase
		end
	end

	// WRITE to registers
	always@(posedge pclk or negedge presetn) begin
		if(!presetn) begin
			ctrl_reg		<= 0;
			int_en_reg		<= 0;
			clk_div_reg		<= 0;
			cs_ctrl_reg		<= 0;
			xip_cfg_reg		<= 0;
			xip_cmd_reg		<= 0;
			cmd_cfg_reg		<= 0;
			cmd_op_reg		<= 0;
			cmd_addr_reg	<= 0;
			cmd_len_reg		<= 0;
			cmd_dummy_reg	<= 0;
			dma_cfg_reg		<= 0;
			dma_addr_reg	<= 0;
			dma_len_reg		<= 0;
			cmd_done_reg		<= 0;
			dma_done_reg		<= 0;
			err_reg				<= 0;
			fifo_tx_empty_reg	<= 0;
			fifo_rx_full_reg	<= 0;
		end else begin
			if(write && !invalid_addr) begin
				case(paddr)
					CTRL_ADDR		: ctrl_reg		<= pwdata;
					INT_EN_ADDR 	: int_en_reg	<= pwdata;
					CLK_DIV_ADDR	: clk_div_reg	<= pwdata;
					CS_CTRL_ADDR	: cs_ctrl_reg	<= pwdata;
					XIP_CFG_ADDR	: xip_cfg_reg	<= pwdata;
					XIP_CMD_ADDR	: xip_cmd_reg	<= pwdata;
					CMD_CFG_ADDR	: cmd_cfg_reg	<= pwdata;
					CMD_OP_ADDR		: cmd_op_reg	<= pwdata;
					CMD_ADDR_ADDR	: cmd_addr_reg	<= pwdata;
					CMD_LEN_ADDR	: cmd_len_reg	<= pwdata;
					CMD_DUMMY_ADDR	: cmd_dummy_reg	<= pwdata;
					DMA_CFG_ADDR	: dma_cfg_reg	<= pwdata;
					DMA_ADDR_ADDR	: dma_addr_reg	<= pwdata;
					DMA_LEN_ADDR	: dma_len_reg	<= pwdata;
					INT_STAT_ADDR	:begin 
										if(pwdata[0]) cmd_done_reg	<= 0;
										if(pwdata[1]) dma_done_reg	<= 0;
										if(pwdata[2]) err_reg		<= 0;
										if(pwdata[3]) fifo_tx_empty_reg	<= 0;
										if(pwdata[4]) fifo_rx_full_reg	<= 0;
									 end
					default	:;
				endcase
			end
			if (cmd_done_set_i)       cmd_done_reg      <= 1'b1;
			if (dma_done_set_i)       dma_done_reg      <= 1'b1;
			if (err_set_i)            err_reg           <= 1'b1;
			if (fifo_tx_empty_set_i)  fifo_tx_empty_reg <= 1'b1;
			if (fifo_rx_full_set_i)   fifo_rx_full_reg  <= 1'b1;
		end
	end
	
	// READ from registers
	always@(*) begin
		prdata = 32'b0;
		if(read) begin
			case(paddr)
				ID_ADDR			:prdata	= id_reg;
				CTRL_ADDR		:prdata	= ctrl_reg;
				STATUS_ADDR 	:prdata	= status_reg;
				INT_EN_ADDR 	:prdata	= int_en_reg;
				INT_STAT_ADDR	:prdata = int_stat_reg;
 				CLK_DIV_ADDR	:prdata	= clk_div_reg;
				CS_CTRL_ADDR	:prdata	= cs_ctrl_reg;
				XIP_CFG_ADDR	:prdata	= xip_cfg_reg;
				XIP_CMD_ADDR	:prdata	= xip_cmd_reg;
				CMD_CFG_ADDR	:prdata	= cmd_cfg_reg;
				CMD_OP_ADDR		:prdata	= cmd_op_reg;
				CMD_ADDR_ADDR	:prdata	= cmd_addr_reg;
				CMD_LEN_ADDR	:prdata	= cmd_len_reg;
				CMD_DUMMY_ADDR	:prdata	= cmd_dummy_reg;
				DMA_CFG_ADDR	:prdata	= dma_cfg_reg;
				DMA_ADDR_ADDR	:prdata	= dma_addr_reg; 
				DMA_LEN_ADDR	:prdata	= dma_len_reg;
				FIFO_RX_ADDR	:prdata = rx_data_i;
				FIFO_STAT_ADDR	:prdata	= fifo_stat_reg;
				ERR_STAT_ADDR	:prdata	= err_stat_reg;
				default			:prdata	= 0;
			endcase
		end
	end

	// APB ready end invalid address
	assign pready = 1'b1;
	assign pslverr = invalid_addr;

	// IRQ
	assign irq = (cmd_done_en_o 	& cmd_done_reg) |
             	 (dma_done_en_o 	& dma_done_reg) |
             	 (err_en_o 			& err_reg) |
             	 (fifo_tx_empty_en_o & fifo_tx_empty_reg) |
             	 (fifo_rx_full_en_o  & fifo_rx_full_reg);

	// CTRL
	assign enable_o 	 = ctrl_reg[0];
	assign xip_en_o		 = ctrl_reg[1];
	assign quad_en_o	 = ctrl_reg[2];
	assign cpol_o		 = ctrl_reg[3];
	assign cpha_o		 = ctrl_reg[4];
	assign lsb_first_o	 = ctrl_reg[5];
	assign cmd_trigger_o = write && (paddr==CTRL_ADDR) && pwdata[8];// self clearing
	assign dma_en_o		 = ctrl_reg[9];
	assign hold_en_o	 = ctrl_reg[10];
	assign wp_en_o		 = ctrl_reg[11];

	// INT_EN
	assign cmd_done_en_o		= int_en_reg[0];
	assign dma_done_en_o		= int_en_reg[1];
	assign err_en_o				= int_en_reg[2];
	assign fifo_tx_empty_en_o	= int_en_reg[3];
	assign fifo_rx_full_en_o	= int_en_reg[4];
	
	// INT_STAT
	assign cmd_done_o           = cmd_done_reg;
	assign dma_done_o           = dma_done_reg;
	assign err_done_o           = err_reg;
	assign fifo_tx_empty_done_o = fifo_tx_empty_reg;
	assign fifo_rx_full_done_o  = fifo_rx_full_reg;

	// CLK_DIV
	assign clk_div_o = clk_div_reg[2:0];

	// CS_CTRL
	assign cs_auto_o	= cs_ctrl_reg[0];
	assign cs_level_o	= cs_ctrl_reg[1];
	assign cs_delay_o	= cs_ctrl_reg[3:2];

	// XIP_CFG
	assign xip_cmd_lanes_o		= xip_cfg_reg[1:0];
	assign xip_addr_lanes_o		= xip_cfg_reg[3:2];
	assign xip_data_lanes_o		= xip_cfg_reg[5:4];
	assign xip_addr_bytes_o		= xip_cfg_reg[7:6];
	assign xip_mode_en_o		= xip_cfg_reg[8];
	assign xip_dummy_cycles_o	= xip_cfg_reg[12:9];
	assign xip_cont_read_o		= xip_cfg_reg[13];
	assign xip_write_o		= xip_cfg_reg[14];

	// XIP_CMD
	assign xip_read_op_o	= xip_cmd_reg[7:0];
	assign xip_write_op_o	= xip_cmd_reg[15:8];
	assign xip_mode_bits_o	= xip_cmd_reg[23:16];

	// CMD_CFG
	assign cmd_cmd_lanes_o		= cmd_cfg_reg[1:0];
	assign cmd_addr_lanes_o		= cmd_cfg_reg[3:2];
	assign cmd_data_lanes_o		= cmd_cfg_reg[5:4];
	assign cmd_addr_bytes_o		= cmd_cfg_reg[7:6];
	assign cmd_mode_en_o		= cmd_cfg_reg[8];
	assign cmd_dummy_cycles_o	= cmd_cfg_reg[12:9];
	assign cmd_dir_o			= cmd_cfg_reg[13];

	// CMD_OP
	assign cmd_opcode_o		= cmd_op_reg[7:0];
	assign cmd_mode_bits_o	= cmd_op_reg[15:8];

	// CMD_ADDR
	assign cmd_addr_o	= cmd_addr_reg;

	// CMD_LEN
	assign cmd_len_o	= cmd_len_reg;

	// CMD_DUMMY
	assign cmd_extra_dummy_o	= cmd_dummy_reg[7:0];

	// DMA_CFG
	assign dma_burst_size_o	= dma_cfg_reg[3:0];
	assign dma_dir_o		= dma_cfg_reg[4];
	assign dma_incr_addr_o	= dma_cfg_reg[5];

	// DMA_ADDR
	assign dma_addr_o	= dma_addr_reg;

	// DMA_LEN
	assign dma_len_o	= dma_len_reg;

	// FIFO data signals
	assign tx_data_o	= pwdata;
	assign tx_wen_o   	= !tx_full_i  && write && (paddr == FIFO_TX_ADDR);
	assign rx_ren_o   	= !rx_empty_i && read  && (paddr == FIFO_RX_ADDR);	
endmodule
