`timescale 1ns/1ps

module tb_qspi_tx_fifo;
    localparam FIFO_DEPTH  = 16;
    localparam WRITE_WIDTH = 32;
    localparam READ_WIDTH  = 8;

    reg                  clk;
    reg                  resetn;
    reg                  fifo_wen;
    reg  [WRITE_WIDTH-1:0] data_in;
    wire                 fifo_full;
    reg                  fifo_ren;
    wire [READ_WIDTH-1:0] data_out;
    wire                 fifo_empty;
    wire [3:0]           fifo_level;


    qspi_fifo #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .WRITE_WIDTH(WRITE_WIDTH),
        .READ_WIDTH(READ_WIDTH)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .fifo_wen(fifo_wen),
        .data_in(data_in),
        .fifo_full(fifo_full),
        .fifo_ren(fifo_ren),
        .data_out(data_out),
        .fifo_empty(fifo_empty),
        .fifo_level(fifo_level)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // --- Task: Write one 32-bit word ---
    task write32(input [31:0] word);
    begin
        @(posedge clk);
        fifo_wen = 1;
        data_in  = word;
        @(posedge clk);
        fifo_wen = 0;
        data_in  = 32'h0;
        $display("[WRITE] Time=%0t Wrote 0x%08h fifo_level=%0d full=%b empty=%b", 
                  $time, word, fifo_level, fifo_full, fifo_empty);
    end
    endtask

    // --- Task: Read one 8-bit word and check ---
    task read8_check(input [7:0] expected);
    begin
        @(posedge clk);
        fifo_ren = 1;
        @(posedge clk);
        if (data_out !== expected)
            $error("[FAIL] Time=%0t Got=%02h Expected=%02h fifo_level=%0d", $time, data_out, expected, fifo_level);
        else
            $display("[PASS] Time=%0t Got=%02h fifo_level=%0d", $time, data_out, fifo_level);
        fifo_ren = 0;
    end
    endtask
    
    reg [3:0] fifo_level_check;
    integer expected_level;
    // Stimulus
    initial begin
        resetn   = 0;
        fifo_wen = 0;
        fifo_ren = 0;
        data_in  = 32'h0;
        fifo_level_check = 0;
        // Reset
        #20;
        resetn = 1;
        @(posedge clk);

        // --- Testcase 0: fifo_empty after reset ---
        if (fifo_empty !== 1)
            $error("[FAIL] FIFO not empty after reset");
        else
            $display("[PASS] FIFO empty after reset");
 
        // --- Testcase 1: Write 1 word and read 4 bytes ---
        write32(32'hAABBCCDD);
        read8_check(8'hAA);
        read8_check(8'hBB);
        read8_check(8'hCC);
        read8_check(8'hDD);

        // --- Testcase 2: fifo_full detection ---
        // Fill FIFO (16-byte depth, 4 words of 32-bit = 16 bytes)
        write32(32'h11111111);
        write32(32'h22222222);
        write32(32'h33333333);
        write32(32'h44444444);

        if (fifo_full != 1)
            $error("[FAIL] FIFO not full when expected");
        else
            $display("[PASS] FIFO full detected");

        // Try to write when full -> should be ignored
        write32(32'h55555555);
        if (fifo_level != FIFO_DEPTH[3:0])
            $error("[FAIL] FIFO accepted data when full");
        else
            $display("[PASS] FIFO write ignored when full");

        // --- Testcase 3: Write 2 words and read 8 bytes ---
        // First read out everything to empty FIFO
        fifo_ren = 1;
        while (!fifo_empty) begin
            @(posedge clk);
            $display("[READ] Time=%0t Got=%02h fifo_level=%0d", $time, data_out, fifo_level);
        end
        fifo_ren = 0;

        // Now write and check sequence
        write32(32'h11223344);
        write32(32'h55667788);
        read8_check(8'h11);
        read8_check(8'h22);
        read8_check(8'h33);
        read8_check(8'h44);
        read8_check(8'h55);
        read8_check(8'h66);
        read8_check(8'h77);
        read8_check(8'h88);

        // --- Testcase 4: fifo_empty after all reads ---
        if (fifo_empty !== 1)
            $error("[FAIL] FIFO not empty after draining");
        else
            $display("[PASS] FIFO empty after draining");

        // --- Testcase 5: Simultaneous read/write ---
$display("=== Test simultaneous read/write ===");

// Reset FIFO
@(posedge clk);
fifo_wen = 1; data_in = 32'hAA55AA55;
fifo_ren = 1;
@(posedge clk);
fifo_wen = 0; fifo_ren = 0;
$display("After simultaneous R/W: data_out=%02h fifo_level=%0d fifo_empty=%b fifo_full=%b",
         data_out, fifo_level, fifo_empty, fifo_full);

// Lặp 4 lần để cover wrap-around
fifo_level_check = fifo_level; // cập nhật cho chu kỳ tiếp theo
repeat(4) begin
    @(posedge clk);
    fifo_wen = 1; data_in = 32'h11223344;
    fifo_ren = 1;
        expected_level = fifo_level_check; 
    if (fifo_wen && !fifo_full) expected_level = expected_level + 4;
    if (fifo_ren && !fifo_empty) expected_level = expected_level - 1;
    // Clamp
    if (expected_level > FIFO_DEPTH) expected_level = FIFO_DEPTH;
    if (expected_level < 0) expected_level = 0;
    @(posedge clk);
    fifo_wen = 0; fifo_ren = 0;



    if (fifo_level == expected_level) 
        $display("[PASS] R/W cycle: data_out=%02h fifo_level=%0d fifo_empty=%b fifo_full=%b",
                 data_out, fifo_level, fifo_empty, fifo_full);
    else 
        $error("[FAIL] R/W cycle: data_out=%02h fifo_level=%0d fifo_empty=%b fifo_full=%b, expected=%0d",
               data_out, fifo_level, fifo_empty, fifo_full, expected_level);

    fifo_level_check = fifo_level; // cập nhật cho chu kỳ tiếp theo
end
        // Finish sim
        #50;
        $finish;
    end

endmodule
