`timescale 1ns/1ps

module xor_compactor (
    input  wire        clk,
    input  wire        rst,
    input  wire        scan_en,
    input  wire [7:0]  scan_in_mask,  // from mask controller
    output wire [15:0] signature      // final MISR signature to ATE
);

    // ── Spatial XOR tree: 8 inputs → 1 bit ────────────────────────────
    // This is the XOR tree from Fig 5 in the article
    wire xor_all = scan_in_mask[0] ^ scan_in_mask[1] ^
                   scan_in_mask[2] ^ scan_in_mask[3] ^
                   scan_in_mask[4] ^ scan_in_mask[5] ^
                   scan_in_mask[6] ^ scan_in_mask[7];

    // ── 16-bit MISR: polynomial x^16 + x^12 + x^3 + x + 1 ───────────
    // Taps at bit positions 0, 1, 3, 12 from MSB feedback
    reg  [15:0] misr;
    wire [15:0] misr_next;

    // Standard MISR feedback equations for x^16 + x^12 + x^3 + x + 1
    assign misr_next[0]  = misr[15] ^ xor_all;
    assign misr_next[1]  = misr[0]  ^ misr[15] ^ xor_all;
    assign misr_next[2]  = misr[1];
    assign misr_next[3]  = misr[2]  ^ misr[15] ^ xor_all;
    assign misr_next[4]  = misr[3];
    assign misr_next[5]  = misr[4];
    assign misr_next[6]  = misr[5];
    assign misr_next[7]  = misr[6];
    assign misr_next[8]  = misr[7];
    assign misr_next[9]  = misr[8];
    assign misr_next[10] = misr[9];
    assign misr_next[11] = misr[10];
    assign misr_next[12] = misr[11] ^ misr[15] ^ xor_all;
    assign misr_next[13] = misr[12];
    assign misr_next[14] = misr[13];
    assign misr_next[15] = misr[14];

    always @(posedge clk or posedge rst) begin
        if (rst)
            misr <= 16'b0;
        else if (scan_en)
            misr <= misr_next;
    end

    assign signature = misr;

endmodule
