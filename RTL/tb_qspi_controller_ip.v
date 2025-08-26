`timescale 1ns/1ps

module tb_qspi_controller_ip;

    // Clock & Reset
    reg clk, rst_n;
    
    //APB signals
    wire        psel, penable, pwrite;
    wire [11:0] paddr = {4'b0000, apb_paddr}; 
    wire [31:0] pwdata, prdata;
    wire        pready, pslverr;
    reg         apb_start, apb_rw;
    reg  [7:0]  apb_addr;
    reg  [31:0] apb_wdata;
    wire [31:0] apb_rdata;
    wire        apb_idle, apb_busy;
    wire [7:0]  apb_paddr;

    // QSPI bus
    wire        sclk, cs_n, hold_n, wp_n;
    wire        io0, io1, io2, io3;

    // IRQ signal
    wire        irq;

    apb_master apb_m (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(apb_paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready),
        .start(apb_start), .rw(apb_rw),
        .addr(apb_addr), .wdata(apb_wdata),
        .rdata(apb_rdata),
        .idle(apb_idle), .busy(apb_busy)
    );
    qspi_controller_ip dut (
        .clk(clk), .resetn(rst_n), .irq(irq),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), 
        .pready(pready), .pslverr(pslverr),
        .sclk(sclk), .cs_n(cs_n),.hold_n(hold_n), .wp_n(wp_n),
        .io0(io0), .io1(io1), .io2(io2), .io3(io3)
        );

    qspi_device flash_model (
        .qspi_sclk(sclk),
        .qspi_cs_n(cs_n),
        .qspi_io0(io0),
        .qspi_io1(io1),
        .qspi_io2(io2),
        .qspi_io3(io3)
    );

    // Clock generation 
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end
    // Reset generation
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
    end

    // APB write task
    task apb_write(input [7:0] addr, input [31:0] data);
    begin
        @(posedge clk);
        while (!apb_idle) @(posedge clk);
        apb_addr   <= addr;
        apb_wdata  <= data;
        apb_rw     <= 1;       // write
        apb_start  <= 1;
        @(posedge clk);
        apb_start  <= 0;
        while (!apb_idle) @(posedge clk);
    end
    endtask

    // APB read task
    task apb_read(input [7:0] addr, output [31:0] data);
    begin
        @(posedge clk);
        while (!apb_idle) @(posedge clk);
        apb_addr   <= addr;
        apb_rw     <= 0;       // read
        apb_start  <= 1;
        @(posedge clk);
        apb_start  <= 0;
        while (!apb_idle) @(posedge clk);
        data = apb_rdata;
       
    end
    endtask
    
    task read_rx_fifo_multi;
        input  [7:0]  addr;
        input integer nwords;
        integer i;
        reg [31:0] rdata;
    begin
        for (i=0; i<nwords; i=i+1) begin
            apb_read(addr, rdata);
            wait(dut.csr_inst.read);
            #20;
            $display("[%0t] APB READ: addr=0x%h data=0x%h", $time, addr, dut.csr_inst.rx_data_i);
        end
    end
    endtask

    initial begin
        $dumpfile("tb_qspi_controller_ip.vcd");
        $dumpvars(0, tb_qspi_controller_ip);

        wait(rst_n);
        wait(apb_idle); 
        
        $display("========== Testing Single Lane Read (0x03, no dummy) ==========");
        apb_write(8'h04, 32'h0000_0001);  // CTRL: ENABLE=1
        apb_write(8'h24, 32'h0000_2040);  // CMD_CFG
        apb_write(8'h28, 32'h0000_0003);  // CMD_OP
        apb_write(8'h2C, 32'h0000_000F);  // ADDR: 0x0F
        apb_write(8'h30, 32'h0000_0004);  // CMD_LEN: 4byte
        apb_write(8'h04, 32'h0000_0101);  // CTRL: COMMAND_TRIGGER=1
        wait(dut.qspi_ce_inst.ce_done);
        
        read_rx_fifo_multi(8'h48, 4); // RX_FIFO_REG

        $display("========== Testing Write Enable (0x06, single lane) ==========");
        apb_write(8'h04, 32'h0000_0001);  // CTRL: ENABLE=1
        apb_write(8'h24, 32'h0000_0000);  // CMD_CFG
        apb_write(8'h28, 32'h0000_0006);  // CMD_OP
        apb_write(8'h2C, 32'h0000_0000);  // ADDR: no address
        apb_write(8'h30, 32'h0000_0000);  // CMD_LEN: no length
        apb_write(8'h04, 32'h0000_0101);  // CTRL: COMMAND_TRIGGER=1
        wait(dut.qspi_ce_inst.ce_done);

        $display("========== Testing Signal Lane Write (0x02, 4 bytes) ==========");
        apb_write(8'h44, 32'hAABBCCDD);   // TX_FIFO_REG 
        apb_write(8'h04, 32'h0000_0001);  // CTRL: ENABLE=1
        apb_write(8'h24, 32'h0000_0040);  // CMD_CFG
        apb_write(8'h28, 32'h0000_0002);  // CMD_OP
        apb_write(8'h2C, 32'h0000_0000);  // ADDR: no address
        apb_write(8'h30, 32'h0000_0004);  // CMD_LEN: 4byte
        apb_write(8'h04, 32'h0000_0101);  // CTRL: COMMAND_TRIGGER=1
        wait(dut.qspi_ce_inst.ce_done);

        $display("========== Testing Single Lane Read (0x03, no dummy) ==========");
        apb_write(8'h04, 32'h0000_0001);  // CTRL: ENABLE=1
        apb_write(8'h24, 32'h0000_2040);  // CMD_CFG
        apb_write(8'h28, 32'h0000_0003);  // CMD_OP
        apb_write(8'h2C, 32'h0000_0000);  // ADDR: 0x0F
        apb_write(8'h30, 32'h0000_0004);  // CMD_LEN: 4byte
        apb_write(8'h04, 32'h0000_0101);  // CTRL: COMMAND_TRIGGER=1
        wait(dut.qspi_ce_inst.ce_done);
        
        read_rx_fifo_multi(8'h48, 4); // RX_FIFO_REG

/*        $display("========== Testing Read Status Register (0x05) ==========");
        apb_write(8'h04, 32'h0000_0001);  // CTRL: ENABLE=1
        apb_write(8'h24, 32'h0000_2000);  // CMD_CFG
        apb_write(8'h28, 32'h0000_0005);  // CMD_OP
        apb_write(8'h30, 32'h0000_0001);  // CMD_LEN: 1 byte
        apb_write(8'h04, 32'h0000_0101);  // CTRL: COMMAND_TRIGGER=1
        wait(dut.qspi_ce_inst.ce_done);

        read_rx_fifo_multi(8'h48, 1); // RX_FIFO_REG*/

        repeat (10) @(posedge clk);
        $finish;
    end
endmodule
//baotinh