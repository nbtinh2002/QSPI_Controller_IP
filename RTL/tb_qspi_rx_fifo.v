`timescale 1ns/1ps

module tb_qspi_rx_fifo;

    // Params
    localparam FIFO_DEPTH  = 16;
    localparam WRITE_WIDTH = 8;
    localparam READ_WIDTH  = 32;

    // Signals
    reg                  clk;
    reg                  resetn;
    reg                  fifo_wen;
    reg  [WRITE_WIDTH-1:0] data_in;
    wire                 fifo_full;

    reg                  fifo_ren;
    wire [READ_WIDTH-1:0] data_out;
    wire                 fifo_empty;
    wire [3:0]           fifo_level;

    reg [3:0] fifo_level_check;
    integer expected_level;
    integer i;

    // DUT
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

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
 
    // Write 8-bit
    task write8(input [7:0] bytes);
    begin
        @(posedge clk);
        fifo_wen = 1;
        data_in  = bytes;
        @(posedge clk);
        fifo_wen = 0;
        data_in  = 8'h0;
        $display("[WRITE] Time=%0t Wrote %02h fifo_level=%0d full=%b empty=%b", 
                 $time, bytes, fifo_level, fifo_full, fifo_empty);
    end
    endtask

    // Read 32-bit and check
    task read32_check(input [31:0] expected);
    begin
        @(posedge clk);
        fifo_ren = 1;
        @(posedge clk);
        fifo_ren = 0;
        if (data_out !== expected)
            $error("[FAIL] Time=%0t Got=%08h Expected=%08h fifo_level=%0d", 
                   $time, data_out, expected, fifo_level);
        else
            $display("[PASS] Time=%0t Got=%08h fifo_level=%0d", data_out, $time, fifo_level);
    end
    endtask

    initial begin
        // Reset
        resetn = 0;
        fifo_wen = 0; fifo_ren = 0; data_in = 8'h0; fifo_level_check = 0;
        #20 resetn = 1;
        @(posedge clk);

        // --- Simultaneous write8/read32 test ---
        $display("=== Simultaneous write8 / read32 ===");

        // Preload some data
        for (i = 0; i < 4; i=i+1)
            write8(i);

        // Simultaneous R/W 4 cycles to cover wrap-around
        fifo_level_check = fifo_level;
        for (i = 0; i < 4; i=i+1) begin
            @(posedge clk);
            fifo_wen = 1; data_in = i+8; // write 1 byte
            fifo_ren = 1;                 // read 32-bit

            // compute expected_level
            expected_level = fifo_level_check;
            if (fifo_wen && !fifo_full) expected_level = expected_level + 1;
            if (fifo_ren && !fifo_empty) expected_level = expected_level - ((fifo_level_check >= 4) ? 4 : fifo_level_check);
            // clamp
            if (expected_level < 0) expected_level = 0;
            if (expected_level > FIFO_DEPTH) expected_level = FIFO_DEPTH;

            @(posedge clk);
            fifo_wen = 0; fifo_ren = 0;

            if (fifo_level == expected_level)
                $display("[PASS] R/W cycle %0d: data_out=%08h fifo_level=%0d fifo_empty=%b fifo_full=%b",
                         i+1, data_out, fifo_level, fifo_empty, fifo_full);
            else
                $error("[FAIL] R/W cycle %0d: data_out=%08h fifo_level=%0d expected=%0d fifo_empty=%b fifo_full=%b",
                       i+1, data_out, fifo_level, expected_level, fifo_empty, fifo_full);

            fifo_level_check = fifo_level; // update for next cycle
        end

        #50 $finish;
    end

endmodule
