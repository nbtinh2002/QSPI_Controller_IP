module dma_controller(
	// Clock and reset
    input wire	        clk,
    input wire          rst_n,

	//apb interface
	input wire          dma_sel_i,
    input wire          dma_enable_i,
    input wire          dma_dir_i,
    output reg          pready,
	
    // Interact with apb_interface module
    input wire          dma_start_i, // 1-pulse từ apb
    input wire [31:0]   len_i,
    input wire [31:0]   src_addr_i,
    output reg          dma_done,

    // Interact with read_axi4_interface module
    output reg          start_read,
    output reg  [31:0]  r_size_data,
    output   	[31:0]  raddr_reg,
	input wire          read_done,


    // Interact with write_axi4_interface module
    output reg          start_write,
    output reg  [31:0]  w_size_data,
    output     	[31:0]  waddr_reg,
    input wire          write_done,
	output              dma_ce_done,

	//io for incr_addr
	input wire          incr_addr_i,
	output              incr_addr_o,
    input wire  [3:0]   dma_burst_size_i,
    output      [3:0]   dma_burst_size_o
);

    localparam [1:0] IDLE = 0, WAIT_WRITE_DONE = 1, WAIT_READ_DONE = 2;
    localparam [31:0] RAM_LIMIT = 32'h0001_0000;
    reg [1:0] state;
    reg read_completed;
    reg dma_busy;
    reg [31:0] src_addr_reg;
    reg [31:0] len_reg;
    reg 	   incr_addr_reg;
    reg 	   write_reg;
    reg [3:0]  dma_burst_size_reg;
    
    //define control signal
    assign dma_start = dma_sel_i && dma_enable_i && dma_start_i && !dma_busy;
    assign dma_ce_done = read_done || write_done;
    assign waddr_reg   = src_addr_reg;
    assign raddr_reg   = src_addr_reg;
    assign w_size_data = len_reg;
    assign r_size_data = len_reg;
    assign incr_addr_o = incr_addr_reg;
    assign dma_burst_size_o = dma_burst_size_reg;

    // ADDR/ SIZE logic
	always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            src_addr_reg 	<= 0;
            len_reg			<= 0;
            incr_addr_reg	<= 0;
            write_reg    	<= 0;
            dma_burst_size_reg <=0;
        end else begin
            if(dma_sel_i && !dma_busy)begin
                src_addr_reg 	<= src_addr_i;
                len_reg			<= len_i;
                incr_addr_reg	<= incr_addr_i;
                write_reg		<= dma_dir_i;
                dma_burst_size_reg <= dma_burst_size_i == 0? 1 : dma_burst_size_i;
            end
        end
    end

    // Controller logic for DMA process
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dma_done	<= 0;
            start_read	<= 0; 
            start_write	<= 0;
            state		<= IDLE;
            read_completed	<= 0;
        end else begin
            dma_done	<= 0;
            start_read	<= 0;
            start_write	<= 0;
            case(state)
                IDLE:   begin
                        read_completed	<= 0;
                        if(dma_start&&(src_addr_reg+len_reg<RAM_LIMIT)) begin	
                            if(write_reg)begin
                                start_write	<= 1;
                                state		<= WAIT_WRITE_DONE;
                            end else begin
                                start_read	<= 1;
                                state		<= WAIT_READ_DONE;
                            end
                        end else begin
                            dma_done	<= 1;
                        end
                    end
                WAIT_WRITE_DONE: begin
                        start_write		<= 0;
                        if(write_done) begin
                            dma_done	<= 1;
                            state		<= IDLE;
                        end
                        end
                WAIT_READ_DONE: begin
                        start_read		<= 0;
                        if(read_done) begin
                            dma_done	<= 1;
                            state		<= IDLE;
                        end	
                        end
                default:;
            endcase
        end
    end

    //process for busy and pready
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dma_busy <= 0;
        else begin
            if(dma_done)
            dma_busy <= 0;
            else dma_busy <= 0;
        end
    end

    // PREADY generation (1-cycle pulse)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pready <= 0;
        else
            pready <= dma_start;
    end
endmodule