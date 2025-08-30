`timescale 1ns/1ps

module tb_qspi_controller_ip;

    // Clock & Reset
    reg clk, rst_n;
    
    //APB signals
    wire [7:0]  apb_paddr;
    wire        psel, penable, pwrite;
    wire [11:0] paddr = {4'b0000, apb_paddr}; 
    wire [31:0] pwdata, prdata;
    wire        pready, pslverr;
    reg         apb_start, apb_rw;
    reg  [7:0]  apb_addr;
    reg  [31:0] apb_wdata;
    wire [31:0] apb_rdata;
    wire        apb_idle, apb_busy;


    // QSPI bus & IRQ
    wire        sclk, cs_n, hold_n, wp_n;
    wire        io0, io1, io2, io3;
    wire        irq;

    // DUT Instance
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
    task apb_write;
        input [7:0] addr;
        input [31:0] data;
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
    task apb_read;
        input  [7:0]  addr;
        input integer nwords;
        input  [31:0]  expect_data;
        input         check_enable;
        integer i;
        reg [31:0] rdata;
        begin
            for (i=0; i<nwords; i=i+1) begin
                @(posedge clk);
                while (!apb_idle) @(posedge clk);
                apb_addr   <= addr;
                apb_rw     <= 0;       // read
                apb_start  <= 1;
                @(posedge clk);
                apb_start  <= 0;
                while (!apb_idle) @(posedge clk);
                rdata = apb_rdata;
                wait(dut.csr_inst.read);
                #20;
                if(check_enable) begin
                    if(dut.csr_inst.rx_data_i==expect_data)
                        $display("   ✅ DATA READ: 0x%h",dut.csr_inst.rx_data_i);
                    else
                        $display("   ❌ ERROR: DATA READ: 0x%h, EXPECT: 0x%h",dut.csr_inst.rx_data_i, expect_data);   
                end else begin
                    $display(" 0x%h", dut.csr_inst.rx_data_i);
                end
            end
        end
    endtask

    // Send command 
    task send_cmd;
        input [31:0] cfg;
        input [31:0] op;
        input [31:0] addr;
        input [31:0] len;
        input [31:0] dummy;
        input [31:0] ctrl;
        begin
            apb_write(8'h24, cfg);   
            apb_write(8'h28, op);    
            apb_write(8'h2C, addr);  
            apb_write(8'h30, len); 
            apb_write(8'h34, dummy); 
            apb_write(8'h04, ctrl);       
            apb_write(8'h04, ctrl | 32'h0000_0100); 
            wait(dut.qspi_ce_inst.ce_done);
        end
    endtask
    integer i;
    // Test Sequence
    initial begin
        $dumpfile("tb_qspi_controller_ip.vcd");
        $dumpvars(0, tb_qspi_controller_ip);

        wait(rst_n);
        wait(apb_idle); 

        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 0: READ DEVICE INFO");
        $display("======================================================================================");
        
        $display("\n   Read Status Register(0x05) (singal lanes, 1 byte, no addr/dummy)");
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001); 
        apb_read(8'h48, 1, 32'h0000_0000,1); // expect 0x00

        $display("\n   Read Identification(0x9F) (singal lanes, 1 byte, no addr/dummy)");
        send_cmd(32'h0000_2000, 32'h0000_009F, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001); 
        apb_read(8'h48, 1, 32'hC200_0000,1); // expect 0xC2
        

        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 1: WRITE ENABLE/DISABLE LATCH");
        $display("======================================================================================");

        $display("\n   Write Enable(0x06) (singal lanes, no addr/len/dummy)");
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);// Verify by readback
        apb_read(8'h48, 1, 32'h0200_0000,1); // expect 0x02

        $display("\n   Write Disable(0x04) (singal lanes, no addr/len/dummy)");
        send_cmd(32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);// Verify by readback
        apb_read(8'h48, 1, 32'h0000_0000,1); // expect 0x00
        
        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 2: READ DATA");
        $display("======================================================================================");
        // Prepare data to test read: load new data -> write -> readback
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);// Write Enable before write data
        apb_write(8'h44, 32'hDEADBEEF);// Write data to TX FIFO (FSM will push to device)
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0001, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        for(i=0;i<10;i=i+1) 

            $display("%0d: addr %0h, data %0h",i,flash_model.addr_reg, flash_model.memory[i]);

        $display("\n   Single Read Mode(0x03) (1-1-1)(has addr/len, no dummy)");
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0001, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF
        $display("%0d: addr %0h, data %0h",i,flash_model.addr_reg, flash_model.memory[i]);
        $display("\n   2xIO Read Mode(0xBB) (1-2-2)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3054, 32'h0000_00BB, 32'h0000_0001, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   4xIO Read Mode(0xEB) (1-4-4)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3068, 32'h0000_00EB, 32'h0000_0001, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   Fast Single Read Mode(0x0B) (1-1-1)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3040, 32'h0000_000B, 32'h0000_0001, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

/*      $display("\n   Dual Read Mode(0x3B) (1-1-2)(has addr/len, dummy 8)");
         send_cmd(32'h0000_3050, 32'h0000_003B, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   Quad Read Mode(0x6B) (1-1-4)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3060, 32'h0000_006B, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF
*/

        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 3: WRITE DATA");
        $display("======================================================================================");

        $display("\n   Page Program(0x02) (1-1-1)(has addr/len, no dummy)");
        apb_write(8'h44, 32'hAABBCCDD); // Load TX FIFO
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);// Verify by readback
        apb_read(8'h48, 1, 32'hAABBCCDD,1); // expect 0xAABBCCDD*/

        $display("\n   4xIO Page Program(0x38) (1-4-4)(has addr/len, no dummy)");
        apb_write(8'h44, 32'h11223344); // Load TX FIFO
        send_cmd(32'h0000_0068, 32'h0000_0038, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);// Verify by readback
        apb_read(8'h48, 1, 32'h11223344,1); // expect 0xBBAACCDD


        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 4: ERASE DATA");
        $display("======================================================================================");

        $display("\n   Sector Erase(0x20) (4KB)");
        // Prepare data to test erase: load new data -> write -> readback
        apb_write(8'h44, 32'hAAAABBBB);
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        $write("       OLD DATA:"); apb_read(8'h48, 1, 0,0); 
        send_cmd(32'h0000_0040, 32'h0000_0020, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);// Verify by readback
        apb_read(8'h48, 1, 32'hFFFF_FFFF,1); // expect 0xFFFFFFFF

        $display("\n   Block Erase(0xD8) (64KB)");
        // Prepare data to test erase: load new data -> write -> readback
        apb_write(8'h44, 32'hCCCCDDDD);
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        $write("       OLD DATA:"); apb_read(8'h48, 1, 0,0); 
        send_cmd(32'h0000_0040, 32'h0000_00D8, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);// Verify by readback
        apb_read(8'h48, 1, 32'hFFFF_FFFF,1); // expect 0xFFFFFFFF
        
        $display("\n   Chip Erase(0xC7) (All)");
        // Prepare data to test erase: load new data -> write -> readback
        apb_write(8'h44, 32'hAADDCC);
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        $write("       OLD DATA:"); apb_read(8'h48, 1, 0,0); 
        send_cmd(32'h0000_0040, 32'h0000_00C7, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);// Verify by readback
        apb_read(8'h48, 1, 32'hFFFF_FFFF,1); // expect 0xFFFFFFFF

        repeat (10) @(posedge clk);
        $finish;
    end
endmodule
//baotinh