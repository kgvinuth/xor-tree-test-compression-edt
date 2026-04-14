`timescale 1ns/1ps

module edt_top #(
    parameter CHAIN_DEPTH = 4,       // scan chain depth (FFs per chain)
    parameter NUM_CHAINS  = 8        // number of internal scan chains
)(
    // ── Global signals ─────────────────────────────────────────
    input  wire        clk,
    input  wire        rst,
    input  wire        scan_en,      // 1=scan/shift, 0=capture

    // ── ATE inputs (decompressor side) ────────────────────────
    input  wire [1:0]  edt_ch,       // EDT channel injectors from ATE
    input  wire        seed_load,    // 1=load LFSR seed from ATE
    input  wire [3:0]  seed_in,      // compressed seed from ATE

    // ── CUT functional response ────────────────────────────────
    input  wire [7:0]  func_in,      // circuit under test response

    // ── ATE mask (compactor side) ──────────────────────────────
    input  wire [7:0]  mask_code,    // 1=block chain (X suspected)

    // ── ATE output (signature) ─────────────────────────────────
    output wire [15:0] signature     // final MISR signature to ATE
);

    // ── Internal wires ─────────────────────────────────────────
    wire [3:0] q;                    // LFSR → phase shifter
    wire [7:0] s;                    // phase shifter → scan chains
    wire [7:0] scan_out_raw;         // scan chains → mask controller
    wire [7:0] scan_out_mask;        // mask controller → compactor

    // ── Instance 1: Ring LFSR (Ring Generator) ─────────────────
    ring_lfsr U_LFSR (
        .clk       (clk),
        .rst       (rst),
        .scan_en   (scan_en),
        .edt_ch    (edt_ch),
        .seed_load (seed_load),
        .seed_in   (seed_in),
        .q         (q)
    );

    // ── Instance 2: XOR Phase Shifter ──────────────────────────
    xor_phase_shifter U_PHASE (
        .q (q),
        .s (s)
    );

    // ── Instance 3: Scan Chains (8 chains) ─────────────────────
    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC0 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[0]), .func_in(func_in[0]), .scan_out(scan_out_raw[0]));

    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC1 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[1]), .func_in(func_in[1]), .scan_out(scan_out_raw[1]));

    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC2 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[2]), .func_in(func_in[2]), .scan_out(scan_out_raw[2]));

    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC3 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[3]), .func_in(func_in[3]), .scan_out(scan_out_raw[3]));

    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC4 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[4]), .func_in(func_in[4]), .scan_out(scan_out_raw[4]));

    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC5 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[5]), .func_in(func_in[5]), .scan_out(scan_out_raw[5]));

    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC6 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[6]), .func_in(func_in[6]), .scan_out(scan_out_raw[6]));

    scan_chain #(.DEPTH(CHAIN_DEPTH)) SC7 (
        .clk(clk), .rst(rst), .scan_en(scan_en),
        .scan_in(s[7]), .func_in(func_in[7]), .scan_out(scan_out_raw[7]));

    // ── Instance 4: Mask Controller ────────────────────────────
    mask_controller U_MASK (
        .scan_out_raw  (scan_out_raw),
        .mask_code     (mask_code),
        .scan_out_mask (scan_out_mask)
    );

    // ── Instance 5: XOR Spatial Compactor + MISR ───────────────
    xor_compactor U_COMP (
        .clk          (clk),
        .rst          (rst),
        .scan_en      (scan_en),
        .scan_in_mask (scan_out_mask),
        .signature    (signature)
    );

endmodule
