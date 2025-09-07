`timescale 1ns/1ps

module tb_qspi_controller_ip;
    localparam integer APB_TIMEOUT_CYCLES = 1000;
    localparam integer CLK_PERIOD_NS = 10;

    // ------------------- APB register offsets -------------------
	localparam [7:0]    ID_ADDR			= 8'h00;// RO
	localparam [7:0]	CTRL_ADDR		= 8'h04;// RW
	localparam [7:0]	STATUS_ADDR 	= 8'h08;// RO
	localparam [7:0]	INT_EN_ADDR 	= 8'h0C;// RW
	localparam [7:0]	INT_STAT_ADDR	= 8'h10;// RW1C
	localparam [7:0]	CLK_DIV_ADDR	= 8'h14;// RW
	localparam [7:0]	CS_CTRL_ADDR	= 8'h18;// RW
	localparam [7:0]	XIP_CFG_ADDR	= 8'h1C;// RW
	localparam [7:0]	XIP_CMD_ADDR	= 8'h20;// RW
	localparam [7:0]	CMD_CFG_ADDR	= 8'h24;// RW
	localparam [7:0]	CMD_OP_ADDR		= 8'h28;// RW
	localparam [7:0]	CMD_ADDR_ADDR	= 8'h2C;// RW
	localparam [7:0]	CMD_LEN_ADDR	= 8'h30;// RW
	localparam [7:0]	CMD_DUMMY_ADDR	= 8'h34;// RW
	localparam [7:0]	DMA_CFG_ADDR	= 8'h38;// RW
	localparam [7:0]	DMA_ADDR_ADDR	= 8'h3C;// RW
	localparam [7:0]	DMA_LEN_ADDR	= 8'h40;// RW
	localparam [7:0]	FIFO_TX_ADDR	= 8'h44;// WO
	localparam [7:0]	FIFO_RX_ADDR	= 8'h48;// RO
	localparam [7:0]	FIFO_STAT_ADDR	= 8'h4C;// RO
	localparam [7:0]	ERR_STAT_ADDR	= 8'h50;// RO

    // ------------------- Signals -------------------
    reg clk, rst_n;
    
    // APB signals
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
    wire sclk, cs_n, hold_n, wp_n;
    wire io0, io1, io2, io3;
    wire irq;

    // AXI4 Master Signals
    wire [31:0] m_awaddr;
    wire        m_awvalid;
    reg         m_awready;
    //wire [3:0]  m_awid; 
    //wire [7:0]  m_awlen;
    //wire [2:0]  m_awsize; 
    //wire [1:0]  m_awburst;
    wire [31:0] m_wdata;
    wire [3:0]  m_wstrb;
    wire        m_wvalid;
    reg         m_wready;
    //wire        m_wlast;
    //wire        m_wuser;
    reg         m_bvalid;
    wire        m_bready;
    //reg [3:0]   m_bid;
    //reg [1:0]   m_bresp;
    //reg         m_buser;
    wire [31:0] m_araddr;
    wire        m_arvalid;
    reg         m_arready;
    //wire [3:0]  m_arid;
    //wire [7:0]  m_arlen;
    //wire [2:0]  m_arsize;
    //wire [1:0]  m_arburst;
    reg [31:0]  m_rdata;
    reg         m_rvalid;
    wire        m_rready;
    //reg [3:0]   m_rid;
    //reg [1:0]   m_rresp;
    //reg         m_rlast;
    //reg         m_ruser;

    // ------------------- DUT Instance -------------------
    apb_master apb_m (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(apb_paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready),
        .start(apb_start), .rw(apb_rw),
        .addr(apb_addr), .wdata(apb_wdata), .rdata(apb_rdata),
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
        .m_awvalid(m_awvalid), .m_awaddr (m_awaddr), .m_awready(m_awready),
        // Write data
        .m_wvalid(m_wvalid), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wready(m_wready),
        // Write response
        .m_bvalid(m_bvalid), .m_bready(m_bready),
        // Read address
        .m_arvalid(m_arvalid), .m_araddr(m_araddr), .m_arready(m_arready),
        // Read data
        .m_rvalid(m_rvalid), .m_rdata(m_rdata), .m_rready(m_rready)
        );

    qspi_device flash_model(
        .qspi_sclk(sclk), .qspi_cs_n(cs_n),
        .qspi_io0(io0), .qspi_io1(io1),
        .qspi_io2(io2), .qspi_io3(io3)
    );

      axi4_ram_slave axi4_ram0(
        .clk(clk),.rst_n(rst_n),
        // Write address
        .awvalid(m_awvalid), .awaddr (m_awaddr), .awready(m_awready),
        // Write data
        .wvalid(m_wvalid), .wdata(m_wdata), .wstrb(m_wstrb), .wready(m_wready),
        // Write response
        .bvalid(m_bvalid), .bready(m_bready),
        // Read address
        .arvalid(m_arvalid), .araddr(m_araddr), .arready(m_arready),
        // Read data
        .rvalid(m_rvalid), .rdata(m_rdata), .rready(m_rready)
    );

    // ------------------- Clock & Reset generation -------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end
    initial begin
        rst_n = 0;#20;rst_n = 1;
    end

    // ------------------- Wait condition -------------------
    task wait_with_timeout(input test_cond);
        integer cnt;
        begin
            cnt = 0;
            while (!test_cond && cnt < 10000) begin
                @(posedge clk);
                cnt = cnt + 1;
            end
        end
    endtask

    // ------------------- APB write task -------------------
    task apb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
        @(posedge clk);
        while (!apb_idle) @(posedge clk);
        apb_addr   <= addr;
        apb_wdata  <= data;
        apb_rw     <= 1;// write
        apb_start  <= 1;
        @(posedge clk);
        apb_start  <= 0;
        while (!apb_idle) @(posedge clk);
        end
    endtask

    // ------------------- APB read task -------------------
    task apb_read;
        input [7:0]   addr;
        input [31:0]  expect_data;
        input         check_enable;
        reg [31:0] rdata;
        begin
            @(posedge clk);
            while (!apb_idle) @(posedge clk);
            apb_addr   <= addr;
            apb_rw     <= 0;// read
            apb_start  <= 1;
            @(posedge clk);
            apb_start  <= 0;
            while (!apb_idle) @(posedge clk);
            rdata = apb_rdata;
            wait(dut.csr_inst.read);
            repeat(2) @(posedge clk);
            if(check_enable) begin
                if(dut.csr_inst.csr_data_i==expect_data) $display("          ✅ DATA READ: 0x%h",dut.csr_inst.csr_data_i);
                else  $display("          ❌ ERROR: DATA READ: 0x%h, EXPECT: 0x%h",dut.csr_inst.csr_data_i, expect_data);   
            end 
        end
    endtask

    // ------------------- Send command -------------------
    task send_cmd;
        input [31:0] cfg;
        input [31:0] op;
        input [31:0] addr;
        input [31:0] len;
        input [31:0] dummy;
        input [31:0] ctrl;
        begin
            apb_write(CMD_CFG_ADDR, cfg);   
            apb_write(CMD_OP_ADDR, op);    
            apb_write(CMD_ADDR_ADDR, addr);  
            apb_write(CMD_LEN_ADDR, len); 
            apb_write(CMD_DUMMY_ADDR, dummy); 
            apb_write(CTRL_ADDR, ctrl);       
            apb_write(CTRL_ADDR, ctrl | 32'h0000_0100); 
            wait_with_timeout(dut.ce_inst.ce_done);
        end
    endtask

    // ------------------- Check data after erase ------------------- 
    task erase_testcase;
        input [31:0] start_addr;
        input [7:0]  cmd;
        integer      start_word, end_word;
        integer      bytes_to_check;
        integer      i, j;
        integer      byte_index;
        reg [31:0]   word_val;
        reg          fail;
        begin
            case(cmd)
                8'h20: bytes_to_check = 4*1024;// 4KB
                8'hD8: bytes_to_check = 64*1024;// 64KB
                8'hC7: bytes_to_check = 1024*1024;// 1MB
                default: begin
                    $display("❌ Unknown erase command: 0x%0h", cmd);
                    bytes_to_check = 0;
                end
            endcase
            start_word = start_addr / 4;
            end_word   = start_word + (bytes_to_check / 4);
            fail = 0;
            byte_index = 0;
            for (i = start_word; i < end_word; i = i + 1) begin
                word_val = {flash_model.memory[i*4 + 3], flash_model.memory[i*4 + 2], 
                            flash_model.memory[i*4 + 1], flash_model.memory[i*4 + 0]};
                for (j = 0; j < 4 && byte_index < bytes_to_check; j = j + 1) begin
                    if (flash_model.memory[i*4 + j] !== 8'hFF) begin
                        $error("         ❌ Not erased  BYTE[%0d], WORD[%0d], addr=0x%0h val=%02h",
                            i*4 + j, i, i*4 + j, flash_model.memory[i*4 + j]);
                        fail = 1;
                    end
                    byte_index = byte_index + 1;
                end
            end
            if (!fail) $display("         ✅ DATA erased ok");
        end
    endtask

    // ------------------- DMA testcase ------------------- 
    task dma_testcase;
        input [31:0] len;
        input [31:0] addr;
        input [31:0] incr;
        input        dir;
        input [3:0]  burst;

        integer      words, i, remain, bytes_here;
        reg [31:0]   exp, got, mask, last_word;
        reg          fail;
        begin
        $display("         . . . Testing %0d byte at 0x%h . . .", len, addr[15:2]);               
        apb_write(CMD_CFG_ADDR  , 32'h0000_2040);
        apb_write(CMD_OP_ADDR   , 32'h0000_0003);
        apb_write(CMD_ADDR_ADDR , 32'h0000_0000);
        apb_write(CMD_LEN_ADDR  , len);
        apb_write(DMA_CFG_ADDR  , {26'd0, incr, dir, burst});// control bits
        apb_write(DMA_ADDR_ADDR , addr<<2); // DMA_ADDR (shift left 2)
        apb_write(DMA_LEN_ADDR  , len); 
        apb_write(CTRL_ADDR     , 32'h0000_0201); // CTRL: ENABLE=1 + sel dma
        apb_write(CTRL_ADDR     , 32'h0000_0301); // Enable + DMA_EN + Trigger
        wait_with_timeout(dut.ce_inst.ce_done);

        words  = (len+3)/4;
        remain = len;
        fail   = 1'b0;

        if(incr)begin
            for (i = 0; i < words; i = i + 1) begin
                exp        = {flash_model.memory[i*4 + 0], flash_model.memory[i*4 + 1],
                              flash_model.memory[i*4 + 2], flash_model.memory[i*4 + 3] };
                got        = axi4_ram0.mem[addr + i];
                bytes_here = (remain >= 4) ? 4 : remain;
                mask       = 32'hFFFFFFFF << ((4 - bytes_here)*8);
                if ((got & mask) !== (exp & mask)) begin
                    $display("         ❌ AXI[%0h] got=%08h exp=%08h mask=%08h", addr+i, got, exp, mask);
                    fail = 1;
                end else if (len <= 16) $display("         ✅ AXI[%0h] = %08h", addr+i, got & mask);
                remain = remain - bytes_here;
            end
        end else begin
            last_word       = {flash_model.memory[(words-1)*4 + 0], flash_model.memory[(words-1)*4 + 1],
                              flash_model.memory[(words-1)*4 + 2], flash_model.memory[(words-1)*4 + 3] };
            if (last_word!= axi4_ram0.mem[addr]) begin
                $error("         ❌ AXI[%0h] = %08h last word = %08h", addr+i, axi4_ram0.mem[addr], last_word);
                fail = 1;
            end else $display("         ✅ Overwrite succcesful. AXI[%0h] = %08h", addr,axi4_ram0.mem[addr]);
        end
        if (!fail && len > 16)  if (!fail && len > 16) $display("         ✅ All %0d words matched", words);
        end
    endtask
    
    // ------------------- Check IRQ ------------------- 
    task check_auto_irq;
        integer    i;
        reg        all_pass;
        reg [63:0] event_name;
        begin
            all_pass = 1;
            for(i=0; i<5; i++) begin
                apb_write(INT_EN_ADDR, 32'h1 << i);
                case(i)
                    0: begin
                        event_name = "CMD_done";
                        send_cmd(32'h0000_0040, 32'h0000_0020, 0, 0, 0, 1);
                       end
                    1: begin
                        event_name = "DMA_done";
                        apb_write(CTRL_ADDR, 32'h0000_0201);    // CTRL: ENABLE=1 + sel dma
                        apb_write(CMD_CFG_ADDR, 32'h0000_2040); // CMD_CFG
                        apb_write(CMD_OP_ADDR, 32'h0000_0003);  // CMD_OP
                        apb_write(CMD_ADDR_ADDR, 32'h0000_0000);// CMD ADDR
                        apb_write(8'h3C, 0 << 2);               // DMA_ADDR (shift left 2)
                        apb_write(CMD_LEN_ADDR, 1);             // CMD_LEN
                        apb_write(8'h40, 1);                    // DMA_LEN
                        apb_write(DMA_CFG_ADDR, 32'h0000_0030); // control bits
                        apb_write(CTRL_ADDR, 32'h0000_0301);    // Enable + DMA_EN + Trigger
                        wait_with_timeout(dut.ce_inst.ce_done);
                       end
                    2: begin
                        event_name = "Error";
                        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0007, 32'h0000_00AA, 32'h0000_0000, 32'h0000_0001);  
                       end
                    3: begin
                        event_name = "TX_empty";
                        apb_write(8'h44, 32'h0); // clear FIFO
                       end
                    4: begin
                        event_name = "RX_full";
                        send_cmd(32'h0000_2040, 32'h0000_0003, 7, 64, 0, 1);
                    end
                endcase
                // Wait IRQ asserted
                wait_with_timeout(irq);
                if (!irq) begin 
                    $display("         ❌ IRQ NOT asserted when %s", event_name);
                    all_pass = 0;
                end
                // Cleanup special cases
                if(i==2) send_cmd(32'h0000_0040, 32'h0000_0020, 0, 0, 0, 32'h0000_0001);// clear error by short CMD
                if(i==4) apb_read(8'h48, 0,0);// read fifo to make space

                // Clear IRQ bit
                apb_write(INT_STAT_ADDR, 32'h1 << i);
                wait_with_timeout(!irq);
                if (irq) begin 
                    $display("         ❌ IRQ still high after clear when %s", event_name);
                    all_pass = 0;
                end 
                // reset between tests to ensure clean state
                rst_n = 0;#20;rst_n = 1; 
            end
            if(all_pass) $display("         ✅ IRQ check pass ");
        end
    endtask

    integer i,j;
    integer CNT_ERROR = 0;

    // ------------------- Test Sequence -------------------
    initial begin
        $dumpfile("tb_qspi_controller_ip.vcd");
        $dumpvars(0, tb_qspi_controller_ip);
        wait(rst_n);
        wait(apb_idle); 

        $display("\n======================================================================================");
        $display("                      GROUP 1: READ INFO DEVICE");
        $display("======================================================================================");
        
        $display("\n   TC01: Read Status Register(0x05) (singal lanes, 1 byte, no addr/dummy)");
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001); 
        apb_read(8'h48, 32'h0000_0000,1); // expect 0x00

        $display("\n   TC02: Read Identification(0x9F) (singal lanes, 1 byte, no addr/dummy)");
        send_cmd(32'h0000_2000, 32'h0000_009F, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001); 
        apb_read(8'h48, 32'hC200_0000,1); // expect 0xC2
        
        $display("\n======================================================================================");
        $display("                      GROUP 2: WRITE ENABLE/DISABLE LATCH");
        $display("======================================================================================");

        $display("\n   TC03: Write Enable(0x06) (singal lanes, no addr/len/dummy)");
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 32'h0200_0000,1); // expect 0x02

        $display("\n   TC04: Write Disable(0x04) (singal lanes, no addr/len/dummy)");
        send_cmd(32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2000, 32'h0000_0005, 32'h0000_0000, 32'h0000_0001, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 32'h0000_0000,1); // expect 0x00
   
        $display("\n======================================================================================");
        $display("                               GROUP 3: READ DATA");
        $display("======================================================================================");
        //Prepare data
        flash_model.memory[7]=8'hDE;
        flash_model.memory[8]=8'hAD;
        flash_model.memory[9]=8'hBE;
        flash_model.memory[10]=8'hEF;
        flash_model.memory[11]=8'hFE;
        flash_model.memory[12]=8'hEB;
        flash_model.memory[13]=8'hDA;
        flash_model.memory[14]=8'hED;
        flash_model.memory[15]=8'h11;
        $display("\n   .....Preparing data.....");
        // If you want to know the data that has been written to memory you can use the code below
        //for (i=1; i<21; i++) begin
        //    $write("[%2d]: %0h - ",i, flash_model.memory[i]);
        //    if( i%4==0&&i!=0) $display("");
        //end

        $display("\n   TC05: Single Read Mode(0x03) (1-1-1)(4 bytes at 0x07, no dummy)");
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   TC06: Single Read Mode(0x03) (1-1-1)(10 bytes at 0x07, no dummy)");
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0007, 32'h0000_000A, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 32'hDEADBEEF,1); // expect 0xDEADBEEF
        apb_read(8'h48, 32'hFEEBDAED,1); // expect 0xFEEBDAED
        apb_read(8'h48, 32'h11FF0000,1); // expect 0x11FF0000

        $display("\n   TC07: 2xIO Read Mode(0xBB) (1-2-2)(4 bytes at 0x07, dummy 8)");
        send_cmd(32'h0000_3054, 32'h0000_00BB, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   TC08: 4xIO Read Mode(0xEB) (1-4-4)(4 bytes at 0x07, dummy 8)");
        send_cmd(32'h0000_3068, 32'h0000_00EB, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        apb_read(8'h48, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n   TC09: Fast Single Read Mode(0x0B) (1-1-1)(4 bytes at 0x07, dummy 8)");
        send_cmd(32'h0000_3040, 32'h0000_000B, 32'h0000_0007, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        apb_read(8'h48, 32'hDEADBEEF,1); // expect 0xDEADBEEF

        $display("\n======================================================================================");
        $display("                          GROUP 4: WRITE DATA");
        $display("======================================================================================");
        send_cmd(32'h0000_0000, 32'h0000_0006, 32'h0000_000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);//WREN

        $display("\n   TC10: Page Program(0x02) (1-1-1)(4 bytes at 0x00, no dummy)");
        apb_write(8'h44, 32'hAABBCCDD); // Load TX FIFO
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 32'hAABBCCDD,1); // expect 0xAABBCCDD

        $display("\n   TC11: 4xIO Page Program(0x38) (1-4-4)(4 bytes at 0x00, no dummy)");
        apb_write(8'h44, 32'h11223344); // Load TX FIFO
        send_cmd(32'h0000_0068, 32'h0000_0038, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0005);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 32'h11223344,1); // expect 0xBBAACCDD

        $display("\n   TC12: Page Program(0x02) (1-1-1)(11 bytes at 0x05, no dummy)");
        apb_write(8'h44, 32'hAABBCCDD); // Load TX FIFO
        apb_write(8'h44, 32'h11223344); // Load TX FIFO
        apb_write(8'h44, 32'h55667788); // Load TX FIFO
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0005, 32'h0000_000B, 32'h0000_0000, 32'h0000_0001);
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0005, 32'h0000_000B, 32'h0000_0000, 32'h0000_0001);//Verify
        apb_read(8'h48, 32'hAABBCCDD,1); // expect 0xAABBCCDD
        apb_read(8'h48, 32'h11223344,1); // expect 0x11223344
        apb_read(8'h48, 32'h55667700,1); // expect 0x55667700

        $display("\n======================================================================================");
        $display("                          GROUP 5: ERASE DATA");
        $display("======================================================================================");     

        $display("\n   .....Preparing data.....");
        j=0;
        for (i=100; i<70000; i=i+500) flash_model.memory[i] = 8'hAA;
        // If you want to know the data that has been written to memory you can use the code below
        //for (i=100; i<70000; i=i+500) begin
        //    $write("[%5d]: %0h - ",i, flash_model.memory[i]);
        //    j=j+1;
        //    if(j==10) begin
        //        $display("");
        //        j=0;
        //    end
        //end
        $display("\n   TC: Sector Erase(0x20) (4KB)");
        send_cmd(32'h0000_0040, 32'h0000_0020, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0001);
        erase_testcase(0, 8'h20);

        $display("\n   TC: Block Erase(0xD8) (64KB)");
        send_cmd(32'h0000_0040, 32'h0000_00D8, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        erase_testcase(0, 8'hD8);
/*        
        $display("\n   TC: Chip Erase(0xC7) (All)");
        send_cmd(32'h0000_0040, 32'h0000_00C7, 32'h0000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0001);
        erase_testcase(0, 8'hC7);
*/
        $display("\n======================================================================================");
        $display("                      GROUP 6: COMMAND MODE WITH DMA");
        $display("======================================================================================");


        $display("\n   TC16: Transfer 1 byte");
        dma_testcase(1, 0, 1, 1, 0);// expect 0xFF000000

        $display("\n   TC17: Transfer 2 bytes");
        dma_testcase(2, 0, 1, 1, 0);// expect 0xFFFF0000

        // $display("\n   TC18: Transfer 3 bytes");
        dma_testcase(3, 0, 1, 1, 0);// expect 0xFFFFFF00

        // $display("\n   TC19: Transfer 4 word (16 bytes)");
        dma_testcase(16, 0, 1, 1, 0);// expect 0xFFFFFFFF

        $display("\n   TC20: Transfer large block to RAM offset address (128 byte)");
        dma_testcase(150, 0, 1, 1, 0);// expect 0xFFFFFFFF

        $display("\n   TC21: Overwrite multiple times");
        //Prepare data
        flash_model.memory[0]=8'hDE;
        flash_model.memory[1]=8'hAD;
        flash_model.memory[2]=8'hBE;
        flash_model.memory[3]=8'hEF;
        flash_model.memory[4]=8'hFE;
        flash_model.memory[5]=8'hEB;
        flash_model.memory[6]=8'hDA;
        flash_model.memory[7]=8'hED;
        flash_model.memory[8]=8'h11;
        dma_testcase(8, 0, 0, 1, 1);

        $display("\n   TC22: DMA Burst (567 byte), 1 burst = 12 byte(3 beat x 4 byte) ");
        dma_testcase(567, 0, 1, 1, 0);// expect 0xFFFFFFFF

        $display("\n   TC22: DMA Burst (1000 byte), 1 burst = 60 byte(15 beat x 4 byte), different addr ");
        dma_testcase(1000, 1000, 1, 1, 15);// expect 0xFFFFFFFF

        $display("\n======================================================================================");
        $display("                      GROUP 7: FLAGS CHECKING");
        $display("======================================================================================");
   
        $display("\n   TC: Underrun flags test");
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0005, 32'h0000_0008, 32'h0000_0000, 32'h0000_0001);
        if (dut.csr_inst.err_stat_reg[2]) $display("         ✅ UNDERRUN flag set");
        else $error("         ❌ UNDERRUN not set (expected)");
        rst_n = 0;#20;rst_n = 1;

        $display("\n   TC: Overrun flags test");
        send_cmd(32'h0000_2040, 32'h0000_0003, 32'h0000_0007, 32'h0000_00AA, 32'h0000_0000, 32'h0000_0001);
        if (dut.csr_inst.err_stat_reg[1]) $display("         ✅ OVERRUN flag set");
        else $error("         ❌ OVERRUN not set (expected)");
        repeat (4) apb_read(8'h48, 32'h0, 0);
        rst_n = 0;#20;rst_n = 1;

        $display("\n   TC: Timeout flag test");
        send_cmd(32'h0000_0040, 32'h0000_0002, 32'h0000_0005, 32'h0000_0008, 32'h0000_0000, 32'h0000_0001);
        if (dut.csr_inst.err_stat_reg[0])  $display("         ✅ TIMEOUT flag set");
        else $error("         ❌ TIMEOUT flag NOT set (expected)");
        rst_n = 0;#20;rst_n = 1;

        $display("\n   TC: IRQ output test");
        check_auto_irq;

        repeat (10) @(posedge clk);
        $finish;
    end
endmodule
//baotinh