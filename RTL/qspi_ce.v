module qspi_ce (
    input  wire clk,
    input  wire resetn,
    // From CSR
    input  wire cmd_trigger,   // CTRL[8]
    input  wire dma_en,        // CTRL[9]
    // Feedback signals from QSPI FSM / DMA
    input  wire qspi_done,
    input  wire dma_done,
    // Control signals to FSM / DMA
    output reg  ce_start,
    output reg  dma_start,    
    // Back to CSR
    output reg  ce_busy,
    output reg  ce_done
);

    localparam [1:0] IDLE   = 2'b00,
                     START  = 2'b01,
                     WAIT   = 2'b10,
                     FINISH = 2'b11;

    reg [1:0] state, next_state;

    // State register
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cmd_trigger)
                    next_state = START;
            end
            START: begin
                next_state = WAIT;
            end
            WAIT: begin
                if(dma_en) begin
                    if (qspi_done && dma_done)
                        next_state = FINISH;
                end else begin
                    if (qspi_done)
                        next_state = FINISH;
                end
            end
            FINISH: begin
                next_state = IDLE;
            end
        endcase
    end

    // Outputs
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ce_start    <= 0;
            dma_start   <= 0;
            ce_busy     <= 0;
        end else begin
            ce_done     <= (ce_start) ? 0 : (state == FINISH) ? 1 : ce_done;
            ce_busy     <= (state != IDLE);
            dma_start   <= (state == START) ? dma_en : 0;
            ce_start    <= (state == START) ? 1 : 0;
        end
    end

endmodule
