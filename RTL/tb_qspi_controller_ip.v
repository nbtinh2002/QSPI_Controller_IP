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

    // APB master instance
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

    // DUT: QSPI Controller
    qspi_controller_ip dut (
        .clk(clk), .resetn(rst_n), .irq(irq),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), 
        .pready(pready), .pslverr(pslverr),
        .sclk(sclk), .cs_n(cs_n),.hold_n(hold_n), .wp_n(wp_n),
        .io0(io0), .io1(io1), .io2(io2), .io3(io3)
        );

    // Flash model
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
                $display("[%0t] APB READ: addr=0x%h data=0x%h", $time, addr, dut.csr_inst.rx_data_i);
            end
        end
    endtask

    // Send command 
    task send_cmd;
        input [31:0] cfg;    // CMD_CFG
        input [31:0] op;     // CMD_OP
        input [31:0] addr;   // CMD_ADDR
        input [31:0] len;    // CMD_LEN
        input [31:0] dummy;  // CMD_DUMMY
        input [31:0] ctrl;   // CTRL (ENABLE, QUAD_EN, v.v.)
        begin
            apb_write(8'h24, cfg);    // CMD_CFG
            apb_write(8'h28, op);     // CMD_OP
            apb_write(8'h2C, addr);   // CMD_ADDR
            apb_write(8'h30, len);    // CMD_LEN
            apb_write(8'h34, dummy);  // CMD_DUMMY
            apb_write(8'h04, ctrl);         // CTRL: ENABLE / QUAD_EN
            apb_write(8'h04, ctrl | 32'h0000_0100); // CTRL: COMMAND_TRIGGER
            wait(dut.qspi_ce_inst.ce_done);
        end
    endtask

    initial begin
        $dumpfile("tb_qspi_controller_ip.vcd");
        $dumpvars(0, tb_qspi_controller_ip);

        wait(rst_n);
        wait(apb_idle); 

        $display("");
        $display("||==================================================================================||");
        $display("||Non_DMA            TEST CASE 0 : Basic device info                                ||");
        $display("||==================================================================================||");
        $display("");$display("========== Testing Status Register Read (0x05) =================");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //Single IO      0x05(RDSR)     no addr        1 byte         0 dummy        ENABLE=1
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001); 
        apb_read(8'h48, 1);

        $display("");$display("========== Testing Identification Read (0x9F) ==================");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //Single IO      0x9F(RDID)     no addr        1 byte         0 dummy        ENABLE=1
        send_cmd(32'h0000_2000, 32'h0000_009F, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001); 
        apb_read(8'h48, 1);

        $display("");
        $display("||==================================================================================||");
        $display("||Non_DMA            TEST CASE 1 : Write enable/disable latch                       ||");
        $display("||==================================================================================||");
        $display("");$display("========== Testing Write Enable (0x06) =========================");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //Single IO      0x06=WREN      no addr        no length      0 dummy        ENABLE=1
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        // Verify by readback
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1);

        $display("");$display("========== Testing Write Disable (0x04) ========================");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //Single IO      0x04=WRDI      no addr        no length      0 dummy        ENABLE=1
        send_cmd(32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        // Verify by readback
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1);

        $display("");
        $display("||==================================================================================||");
        $display("||Non_DMA            TEST CASE 2 : Read data                                        ||");
        $display("||==================================================================================||");
        // Write Enable before write data
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        // Write data to TX FIFO (FSM will push to device)
        apb_write(8'h44, 32'hDEADBEEF); 
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        // Write Disable after write data
        send_cmd(32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);

        $display("");$display("========== Testing Single Read (1-1-1) (0x03, no dummy) ========");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-1-1 IO       0x03=READ      0x00           4 byte         0 dummy        ENABLE=1
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 4);

        $display("");$display("========== Testing 2xIO Read (1-2-2) (0xBB, dummy 8) ===========");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-2-2 IO       0xBB=2READ     0x00           4 byte         0 dummy        ENABLE=1
        send_cmd(32'h0000_3054, 32'h0000_00BB, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 4);

        $display("");$display("========== Testing 4xIO Read (1-4-4) (0xEB, dummy 8) ===========");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-4-4 IO       0xEB=4READ     0x00           4 byte         0 dummy        ENABLE=1, QUAD_EN=1
        send_cmd(32'h0000_3068, 32'h0000_00EB, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 4);

        $display("");$display("========== Testing Fast Single Read (1-1-1) (0x0B, dummy 8) ====");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-1-1 IO       0x0B=FAST_RD   0x00           4 byte         0 dummy        ENABLE=1
        send_cmd(32'h0000_3068, 32'h0000_00EB, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 4);

/*        $display("");$display("========== Testing Dual Read (1-1-2) (0x3B, dummy 8) ===========");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-1-2 IO       0x3B=DREAD     0x00           4 byte         0 dummy        ENABLE=1
        send_cmd(32'h0000_3050, 32'h0000_003B, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 4);    
        
        $display("");$display("========== Testing Quad Read (1-1-4) (0x6B, dummy 8) ===========");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-1-4 IO       0x6B=QREAD     0x00           4 byte         0 dummy        ENABLE=1, QUAD_EN=1
        send_cmd(32'h0000_3060, 32'h0000_006B, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 4);
*/
        $display("");
        $display("||==================================================================================||");
        $display("||Non_DMA            TEST CASE 3 : Write data                                       ||");
        $display("||==================================================================================||");
        // Write Enable before Page Program
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);

        // Load TX FIFO
        apb_write(8'h44, 32'hAABBCCDD); 
        $display("");$display("========== Testing Single Lane (1-1-1) (0x02, 4 bytes) =========");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-1-1 IO       0x02=PP        0x00           4 byte         0 dummy        ENABLE=1
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        // Verify by readback
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 4);  

        // Load TX FIFO
        apb_write(8'h44, 32'hDDCCBBAA);
        $display("");$display("========== Testing Quad Lane (1-4-4) (0x38, 4 bytes) =========");
               //CMD_CFG        CMD_OP         CMD_ADDR       CMD_LEN        CMD_DUMMY      CTRL
               //1-4-4 IO       0x38=4PP       0x00           4 byte         0 dummy        ENABLE=5
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        // Verify by readback
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 4);  
        
        repeat (10) @(posedge clk);
        $finish;
    end
endmodule
//baotinh