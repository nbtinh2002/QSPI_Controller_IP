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

    // AXI4 Master Signals
//    wire [3:0]  m_awid;
    wire [31:0] m_awaddr;
//    wire [7:0]  m_awlen;
//    wire [2:0]  m_awsize; 
//    wire [1:0]  m_awburst;
    wire        m_awvalid;
    reg         m_awready;

    wire [31:0] m_wdata;
    wire [3:0]  m_wstrb;
//    wire        m_wlast;
//    wire        m_wuser;
    wire        m_wvalid;
    reg         m_wready;

//    reg [3:0]   m_bid;
//    reg [1:0]   m_bresp;
//    reg         m_buser;
    reg         m_bvalid;
    wire        m_bready;

//    wire [3:0]  m_arid;
    wire [31:0] m_araddr;
//    wire [7:0]  m_arlen;
//    wire [2:0]  m_arsize;
//    wire [1:0]  m_arburst;
    wire        m_arvalid;
    reg         m_arready;

//    reg [3:0]   m_rid;
    reg [31:0]  m_rdata;
//    reg [1:0]   m_rresp;
//    reg         m_rlast;
//    reg         m_ruser;
    reg         m_rvalid;
    wire        m_rready;

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
        .io0(io0), .io1(io1), .io2(io2), .io3(io3),
        // Write address
        .m_awvalid(m_awvalid),.m_awaddr (m_awaddr),.m_awready(m_awready),
        // Write data
        .m_wvalid(m_wvalid),.m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wready(m_wready),
        // Write response
        .m_bvalid(m_bvalid), .m_bready(m_bready),
        // Read address
        .m_arvalid(m_arvalid),.m_araddr(m_araddr),.m_arready(m_arready),
        // Read data
        .m_rvalid(m_rvalid),.m_rdata(m_rdata),.m_rready(m_rready)
        );

    qspi_device flash_model (
        .qspi_sclk(sclk),
        .qspi_cs_n(cs_n),
        .qspi_io0(io0),
        .qspi_io1(io1),
        .qspi_io2(io2),
        .qspi_io3(io3)
    );

      axi4_ram_slave axi4_ram0 (
        .clk(clk),.rst_n(rst_n),
        // Write address
        .awvalid(m_awvalid),.awaddr (m_awaddr),.awready(m_awready),
        // Write data
        .wvalid(m_wvalid),.wdata(m_wdata),.wstrb(m_wstrb),.wready(m_wready),
        // Write response
        .bvalid(m_bvalid), .bready(m_bready),
        // Read address
        .arvalid(m_arvalid),.araddr(m_araddr),.arready(m_arready),
        // Read data
        .rvalid(m_rvalid),.rdata(m_rdata),.rready(m_rready)
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
                    $display("        ✅ DATA READ: 0x%h",dut.csr_inst.rx_data_i);
                else
                    $display("        ❌ ERROR: DATA READ: 0x%h, EXPECT: 0x%h",dut.csr_inst.rx_data_i, expect_data);   
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
    function automatic [31:0] pack_flash_word(input int word_idx);
        return { flash_model.memory[word_idx*4+3],
                flash_model.memory[word_idx*4+2],
                flash_model.memory[word_idx*4+1],
                flash_model.memory[word_idx*4+0] };
    endfunction
    // Prepare data to test erase command
    task prepare_data(input int start_word, input int end_word, input int step);
        int i;
        begin
        $display("         Prepare DATA...");
        for (i = start_word; i < end_word; i += step) begin
            flash_model.memory[i*4+0] = i[7:0];
            flash_model.memory[i*4+1] = i[7:0];
            flash_model.memory[i*4+2] = i[7:0];
            flash_model.memory[i*4+3] = i[7:0];
            if (i < start_word+4) // chỉ log vài dòng đầu
                $display("         WORD[%0d] @0x%0h = %08h", i, i*4, pack_flash_word(i));
        end
        end
    endtask
    // Check test erase command
    task check_erased(input int start_word, input int end_word, input int step);
        int i; bit fail;
        begin
        fail = 0;
        for (i = start_word; i < end_word; i += step) begin
            if (pack_flash_word(i) !== 32'hFFFF_FFFF) begin
                $error("         ❌ Not erased @WORD[%0d], addr=0x%0h val=%08h",
                        i, i*4, pack_flash_word(i));
                fail = 1;
            end
        end
        if (!fail) $display("         ✅ DATA erased ok");
        end 
    endtask

    // Write data from DEVICE to DMA
    task dma_testcase(input int len, input int addr);
        int words, i, remain, bytes_here;
        reg [31:0] exp, got, mask;
        bit fail;
        begin
        $display("         Testing len = %0d byte addr = 0x%h", len, addr);
        apb_write(8'h04, 32'h0000_0201);  // CTRL: ENABLE=1 + sel dma
        apb_write(8'h24, 32'h0000_2040);  // CMD_CFG
        apb_write(8'h28, 32'h0000_0003);  // CMD_OP
        apb_write(8'h2C, 32'h0000_0000);  // CMD ADDR
        apb_write(8'h3C, addr<<2);        // DMA_ADDR (dịch trái 2)
        apb_write(8'h30, len);            // CMD_LEN
        apb_write(8'h40, len);            // DMA_LEN
        apb_write(8'h38, 32'h0000_0030);  // control bits
        apb_write(8'h04, 32'h0000_0301);  // Enable + DMA_EN + Trigger
        wait(dut.qspi_ce_inst.ce_done);
        words  = (len+3)/4;
        remain = len;
        fail   = 0;
        for (i=0; i<words; i++) begin
            exp        = pack_flash_word(i);
            got        = axi4_ram0.mem[addr + i];
            bytes_here = (remain >= 4) ? 4 : remain;
            mask       = 32'hFFFFFFFF << ((4 - bytes_here)*8);

            if ((got & mask) !== (exp & mask)) begin
                $error("         ❌ AXI[%0h] got=%08h exp=%08h mask=%08h",
                    addr+i, got, exp, mask);
                fail = 1;
            end else if (len <= 16) begin
                $display("         ✅ AXI[%0h] = %08h", addr+i, got & mask);
            end
            remain -= bytes_here;
        end
        if (!fail && len > 16)
            $display("         ✅ All %0d words matched", words);
        end
    endtask
    integer i;
    integer CNT_ERROR = 0;

    // Test Sequence
    initial begin
        $dumpfile("tb_qspi_controller_ip.vcd");
        $dumpvars(0, tb_qspi_controller_ip);

        wait(rst_n);
        wait(apb_idle); 
        // use code to read memory in flash_device
        //    for(i=0;i<10;i=i+1) 
        //      $display("%0d: addr %0h, data %0h",i,flash_model.addr_reg, flash_model.memory[i]);
          
        //cfg - op - addr - len - dummy - ctrl
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
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 1, 32'h0200_0000,1); // expect 0x02

        $display("\n   Write Disable(0x04) (singal lanes, no addr/len/dummy)");
        send_cmd(32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 1, 32'h0000_0000,1); // expect 0x00
        
        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 2: READ DATA");
        $display("======================================================================================");
        //Prepare data
        flash_model.memory[7]=8'hDE;
        flash_model.memory[8]=8'hAD;
        flash_model.memory[9]=8'hBE;
        flash_model.memory[10]=8'hEF;

        $display("\n   Single Read Mode(0x03) (1-1-1)(has addr/len, no dummy)");
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   2xIO Read Mode(0xBB) (1-2-2)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3054, 32'h0000_00BB, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   4xIO Read Mode(0xEB) (1-4-4)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3068, 32'h0000_00EB, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   Fast Single Read Mode(0x0B) (1-1-1)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3040, 32'h0000_000B, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

/*        $display("\n   Dual Read Mode(0x3B) (1-1-2)(has addr/len, dummy 8)");
         send_cmd(32'h0000_3050, 32'h0000_003B, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   Quad Read Mode(0x6B) (1-1-4)(has addr/len, dummy 8)");
        send_cmd(32'h0000_3060, 32'h0000_006B, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 1, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   Fast Read (0x0B) dummy=12 (extra dummy)");
        send_cmd(32'h0000_3040, 32'h0000_000B, 32'h0000_0007, 32'h0000_0004, 32'h0000_000C, 32'h0000_0001);
        apb_read(8'h48, 1, 32'hDEADBEEF, 1);
*/       
        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 3: WRITE DATA");
        $display("======================================================================================");
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);//WREN

        $display("\n   Page Program(0x02) (1-1-1)(has addr/len, no dummy)");
        apb_write(8'h44, 32'hAABBCCDD); // Load TX FIFO
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 1, 32'hAABBCCDD,1); // expect 0xAABBCCDD

        $display("\n   4xIO Page Program(0x38) (1-4-4)(has addr/len, no dummy)");
        apb_write(8'h44, 32'h11223344); // Load TX FIFO
        send_cmd(32'h0000_0068, 32'h0000_0038, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 1, 32'h11223344,1); // expect 0xBBAACCDD

        $display("\n======================================================================================");
        $display("    Non_DMA     TEST CASE 4: ERASE DATA");
        $display("======================================================================================");     

        $display("\n   Sector Erase(0x20) (4KB)");
        prepare_data(100, 160, 10);
        send_cmd(32'h0000_0040, 32'h0000_0020, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        check_erased(100, 160, 10);// expect 0xFFFFFFFF

        $display("\n   Block Erase(0xD8) (64KB)");
        prepare_data(100, 160, 10);
        send_cmd(32'h0000_0040, 32'h0000_00D8, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        check_erased(100, 160, 10);// expect 0xFFFFFFFF
        
        $display("\n   Chip Erase(0xC7) (All)");
        prepare_data(100, 160, 10);
        send_cmd(32'h0000_0040, 32'h0000_00C7, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        check_erased(100, 160, 10);// expect 0xFFFFFFFF

        $display("\n======================================================================================");
        $display("    DMA     TEST CASE 5: COMMAND MODE WITH DMA");
        $display("======================================================================================");

        $display("\n   Transfer 1 word (4byte)");
        dma_testcase(4, 0);// expect 0xFFFFFFFF

        $display("\n   Transfer 1 byte");
        dma_testcase(1, 0);// expect 0xFF000000

        $display("\n   Transfer 2 bytes");
        dma_testcase(2, 0);// expect 0xFFFF0000

        $display("\n   Transfer 3 bytes");
        dma_testcase(3, 0);// expect 0xFFFFFF00

        $display("\n   Transfer 4 word (16 bytes)");
        dma_testcase(16, 0);// expect 0xFFFFFFFF

        $display("\n   Transfer large block (128 bytes)");
        dma_testcase(128, 0);// expect 0xFFFFFFFF

        $display("\n   Transfer to RAM offset address (32 byte)");
        dma_testcase(32, 16'h0200);// expect 0xFFFFFFFF

        $display("\n   Overwrite multiple times");
        dma_testcase(8, 0);// expect 0xFFFFFFFF
        dma_testcase(8, 0);

        $display("\n   Stress test (1024 byte)");
        dma_testcase(1024, 0);// expect 0xFFFFFFFF

        repeat (10) @(posedge clk);
        $finish;
    end
endmodule
//baotinh