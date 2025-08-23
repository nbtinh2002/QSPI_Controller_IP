// Simple APB Master Driver with wait cycle handling and idle/busy handshake
module apb_master (
    input wire clk,
    input wire rst_n,

    // APB signals
    output reg psel,
    output reg penable,
    output reg pwrite,
    output reg [7:0] paddr,
    output reg [31:0] pwdata,
    input wire [31:0] prdata,
    input wire pready,
 
    // Control
    input wire start,
    input wire rw,    // 0 = read, 1 = write
    input wire [7:0] addr,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output wire idle,
    output wire busy
);

    localparam IDLE = 0, SETUP = 1, ACCESS = 2;
    reg [1:0] state;

    assign idle = (state == IDLE);
    assign busy = !idle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psel <= 0;
            penable <= 0;
            pwrite <= 0;
            paddr <= 0;
            pwdata <= 0;
            rdata <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        psel <= 1;
                        penable <= 0;
                        pwrite <= rw;
                        paddr <= addr;
                        pwdata <= wdata;
                        state <= SETUP;
                    end
                end
                SETUP: begin
                    penable <= 1;
                    state <= ACCESS;
                end
                ACCESS: begin
                    if (pready) begin
                        if (!rw)
                            rdata <= prdata;
                        psel <= 0;
                        penable <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
