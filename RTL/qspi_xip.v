module qspi_xip #(
    parameter int DATA_WIDTH      = 32,     // 32 or 64
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_ID_WIDTH    = 4,
    parameter bit SUPPORT_XIP_WRITE = 1'b0  // base cut: read-only path
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // ------------------------------
    // AXI4 Slave (Read channel only)
    // ------------------------------
    input  logic [AXI_ID_WIDTH-1:0]   s_arid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_araddr,
    input  logic [7:0]                s_arlen,    // burst length (ignored in base)
    input  logic [2:0]                s_arsize,   // bytes/beat (should match DATA_WIDTH)
    input  logic [1:0]                s_arburst,  // INCR/… (ignored in base)
    input  logic                      s_arvalid,
    output logic                      s_arready,

    output logic [AXI_ID_WIDTH-1:0]   s_rid,
    output logic [DATA_WIDTH-1:0]     s_rdata,
    output logic [1:0]                s_rresp,
    output logic                      s_rlast,
    output logic                      s_rvalid,
    input  logic                      s_rready,

    // ------------------------------
    // CSR-exposed XIP configuration (latched from XIP_CFG/XIP_CMD registers)
    // ------------------------------
    input  logic [1:0]                xip_cmd_lanes,   // 0:1, 1:2, 2:4
    input  logic [1:0]                xip_addr_lanes,  // 0:1, 1:2, 2:4
    input  logic [1:0]                xip_data_lanes,  // 0:1, 1:2, 2:4
    input  logic [1:0]                xip_addr_bytes,  // 0:0, 1:3, 2:4
    input  logic                      xip_mode_en,
    input  logic [3:0]                xip_dummy_cycles,
    input  logic                      xip_cont_read,
    input  logic                      xip_write_en,    // not used in base
    input  logic [7:0]                xip_read_op,
    input  logic [7:0]                xip_write_op,    // not used in base
    input  logic [7:0]                xip_mode_bits,

    // ------------------------------
    // Interface toward QSPI FSM (read flow)
    // ------------------------------
    output logic                      qspi_start,      // 1-cycle pulse to start a transaction
    input  logic                      qspi_busy,
    input  logic                      qspi_done,       // asserted when transaction completes

    // static/transaction parameters driven to FSM on start
    output logic [7:0]                qspi_opcode,
    output logic [1:0]                qspi_cmd_lanes,
    output logic [1:0]                qspi_addr_lanes,
    output logic [1:0]                qspi_data_lanes,
    output logic [1:0]                qspi_addr_bytes_sel,
    output logic                      qspi_mode_en,
    output logic [7:0]                qspi_mode_bits,
    output logic [7:0]                qspi_dummy_cycles,
    output logic [31:0]               qspi_addr,       // flash address (lower 32b)
    output logic [15:0]               qspi_len_bytes,  // number of data bytes to read

    // byte stream coming back from FSM
    input  logic                      qspi_rvalid,
    input  logic [7:0]                qspi_rdata,
    output logic                      qspi_rready
);

    // ------------------------------------------------------------------
    // Local parameters / helpers
    // ------------------------------------------------------------------
    localparam int BYTES_PER_BEAT = (DATA_WIDTH/8);

    // ------------------------------------------------------------------
    // Registers / state
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_ACCEPT,
        ST_ISSUE,
        ST_RECV,
        ST_RESP
    } state_e;

    state_e                 state, state_n;

    logic [AXI_ID_WIDTH-1:0] rid_q, rid_n;
    logic [AXI_ADDR_WIDTH-1:0] addr_q, addr_n;

    // Output packing
    logic [$clog2(BYTES_PER_BEAT+1)-1:0] byte_cnt_q, byte_cnt_n; // 0..BYTES_PER_BEAT
    logic [DATA_WIDTH-1:0]                pack_q, pack_n;

    // Control strobes
    logic start_pulse;

    // Simple one-beat policy in base cut
    wire [15:0] need_bytes_w = BYTES_PER_BEAT[15:0];

    // AXI side defaults
    assign s_rresp = 2'b00; // OKAY

    // Drive static QSPI config from CSRs
    always_comb begin
        qspi_opcode           = xip_read_op;
        qspi_cmd_lanes        = xip_cmd_lanes;
        qspi_addr_lanes       = xip_addr_lanes;
        qspi_data_lanes       = xip_data_lanes;
        qspi_addr_bytes_sel   = xip_addr_bytes;
        qspi_mode_en          = xip_mode_en;
        qspi_mode_bits        = xip_mode_bits;
        qspi_dummy_cycles     = {4'b0, xip_dummy_cycles};
    end

    // FSM next-state and outputs
    always_comb begin
        // Defaults
        state_n      = state;
        rid_n        = rid_q;
        addr_n       = addr_q;
        byte_cnt_n   = byte_cnt_q;
        pack_n       = pack_q;

        // AXI defaults
        s_arready    = 1'b0;
        s_rvalid     = 1'b0;
        s_rlast      = 1'b0;
        s_rid        = rid_q;
        s_rdata      = pack_q;

        // QSPI defaults
        qspi_start   = 1'b0;
        qspi_addr    = addr_q;
        qspi_len_bytes = need_bytes_w;
        qspi_rready  = 1'b0;

        case (state)
        // --------------------------------------------------------------
        ST_IDLE: begin
            // Ready to accept a new AR
            s_arready  = 1'b1;
            if (s_arvalid) begin
                rid_n      = s_arid;
                addr_n     = s_araddr; // direct mapping: AXI addr == flash addr (system maps)
                state_n    = ST_ACCEPT;
            end
        end

        // --------------------------------------------------------------
        ST_ACCEPT: begin
            // Issue a QSPI read for one beat worth of bytes
            if (!qspi_busy) begin
                qspi_start  = 1'b1;  // 1-cycle pulse
                // parameters already driven via CSR fields and addr/len wires
                state_n     = ST_ISSUE;
                // clear packing
                byte_cnt_n  = '0;
                pack_n      = '0;
            end
        end

        // --------------------------------------------------------------
        ST_ISSUE: begin
            // Wait for data stream; some FSMs may also assert qspi_done only at end
            // so we rely on byte counting for R channel timing.
            if (qspi_rvalid) begin
                // Consume first byte immediately
                qspi_rready   = 1'b1;
                // Insert into pack (MSB-first packing by default)
                pack_n        = {pack_q[DATA_WIDTH-9:0], qspi_rdata};
                byte_cnt_n    = byte_cnt_q + 1'b1;
                state_n       = ST_RECV;
            end
        end

        // --------------------------------------------------------------
        ST_RECV: begin
            qspi_rready = (byte_cnt_q < BYTES_PER_BEAT);

            if (qspi_rvalid && qspi_rready) begin
                pack_n      = {pack_q[DATA_WIDTH-9:0], qspi_rdata};
                byte_cnt_n  = byte_cnt_q + 1'b1;
            end

            if (byte_cnt_q == BYTES_PER_BEAT) begin
                // Have a full beat ready to present on AXI R
                state_n   = ST_RESP;
            end
        end

        // --------------------------------------------------------------
        ST_RESP: begin
            s_rvalid = 1'b1;
            s_rid    = rid_q;
            s_rdata  = pack_q;
            s_rlast  = 1'b1; // single-beat response in base cut
            if (s_rvalid && s_rready) begin
                // Return to IDLE. In future, if burst/prefetch supported,
                // compute next address and continue.
                state_n = ST_IDLE;
            end
        end

        default: state_n = ST_IDLE;
        endcase
    end

    // State / regs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            rid_q     <= '0;
            addr_q    <= '0;
            byte_cnt_q<= '0;
            pack_q    <= '0;
        end else begin
            state     <= state_n;
            rid_q     <= rid_n;
            addr_q    <= addr_n;
            byte_cnt_q<= byte_cnt_n;
            pack_q    <= pack_n;
        end
    end

endmodule
