`timescale 1ns/1ps

module mask_controller (
    input  wire [7:0] scan_out_raw,   // from scan chain scan_out ports
    input  wire [7:0] mask_code,      // from ATE (1=block this chain)
    output wire [7:0] scan_out_mask   // to XOR compactor
);

    // ── AND gate per chain: mask_code=1 blocks chain, mask_code=0 passes ──
    // From article: "masking logic at scan chain output"
    assign scan_out_mask = scan_out_raw & ~mask_code;

endmodule
