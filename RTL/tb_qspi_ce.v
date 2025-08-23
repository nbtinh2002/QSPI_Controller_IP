`timescale 1ns/1ps

module tb_qspi_ce();

    reg clk;
    reg resetn;

    // CSR inputs
    reg cmd_trigger;
    reg dma_en;

    // Feedback
    reg done;
    reg dma_done;

    // Outputs
    wire start;
    wire dma_start;
    wire ce_clear;
    wire ce_busy;
    wire ce_done;


    // DUT
    qspi_ce uut (
        .clk        (clk),
        .resetn     (resetn),
        .cmd_trigger(cmd_trigger),
        .dma_en     (dma_en),
        .qspi_done       (done),
        .dma_done   (dma_done),
        .ce_start      (start),
        .dma_start  (dma_start),

        .ce_busy    (ce_busy),
        .ce_done    (ce_done)
    );

    // Clock generation
    initial begin
        clk = 1;
        forever #5 clk = ~clk; // 100 MHz
    end
 
    // Stimulus
    initial begin
        // Dump waveform
        $dumpfile("tb_qspi_ce.vcd");
        $dumpvars(0, tb_qspi_ce);

        // Reset
        resetn = 0;
        cmd_trigger = 0;
        dma_en = 0;
        done = 0;
        dma_done = 0;
        #10;
        resetn = 1;
        cmd_trigger = 1; 
        #20; 
        cmd_trigger = 0;     
        #50;

        done = 1; 
        #20;
        cmd_trigger = 1;
        dma_en = 1;

        #20;
        cmd_trigger = 0;
        done = 0;
        #50;

        done = 1;
        dma_done = 1;
        #20;
        dma_en = 0;
        cmd_trigger = 1;
        #10;


        #10;
        cmd_trigger = 0;

        done = 0;
        #50;
        done =1;
        #20;

        $display("Simulation finished.");
        $finish;
    end

endmodule
