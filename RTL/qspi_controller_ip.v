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
);
endmodule
