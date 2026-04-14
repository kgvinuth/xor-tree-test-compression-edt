
`timescale 1ns/1ps

module xor_phase_shifter (
    input  wire [3:0] q,    // from ring LFSR
    output wire [7:0] s     // to scan chain scan_in ports
);

    // ── XOR Tree — 8 unique linear combinations of 4 LFSR outputs ──
    // 2-input combinations (C(4,2) = 6):
    assign s[0] = q[0] ^ q[1];          // S1 = Q0 XOR Q1
    assign s[1] = q[0] ^ q[2];          // S2 = Q0 XOR Q2
    assign s[2] = q[0] ^ q[3];          // S3 = Q0 XOR Q3
    assign s[3] = q[1] ^ q[2];          // S4 = Q1 XOR Q2
    assign s[4] = q[1] ^ q[3];          // S5 = Q1 XOR Q3
    assign s[5] = q[2] ^ q[3];          // S6 = Q2 XOR Q3
    // 3-input combinations (adds 2 more unique outputs):
    assign s[6] = q[0] ^ q[1] ^ q[2];  // S7 = Q0 XOR Q1 XOR Q2
    assign s[7] = q[0] ^ q[1] ^ q[3];  // S8 = Q0 XOR Q1 XOR Q3

endmodule
