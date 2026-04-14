`timescale 1ns/1ps

module ring_lfsr (
    input  wire       clk,
    input  wire       rst,
    input  wire       scan_en,
    input  wire [1:0] edt_ch,      // external EDT channel injectors from ATE
    input  wire       seed_load,   // load seed from ATE
    input  wire [3:0] seed_in,     // compressed seed from ATE
    output wire [3:0] q            // to XOR phase shifter
);

    reg [3:0] state;

    // ── Ring LFSR with external injectors ──────────────────────
    // Ring connection: Q3 feeds back to Q0
    // Injector E0 at tap Q0, Injector E1 at tap Q2
    // This matches the EDT architecture from the article:
    // "external inputs feeding the ring generator are EDT channels"
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 4'b0001;           // non-zero initial state
        end
        else if (seed_load) begin
            state <= seed_in;           // load compressed seed from ATE
        end
        else if (scan_en) begin
            // Ring shift + XOR injectors at taps 0 and 2
            // state[0] gets ring feedback from state[3] XORed with injector E0
            // state[2] gets normal shift XORed with injector E1
            state[0] <= state[3] ^ edt_ch[0];   // ring feedback + injector
            state[1] <= state[0];                // normal ring shift
            state[2] <= state[1] ^ edt_ch[1];   // shift + injector
            state[3] <= state[2];                // normal ring shift
        end
    end

    assign q = state;

endmodule
