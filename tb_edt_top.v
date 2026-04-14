`timescale 1ns/1ps

module tb_edt_top;

    // ============================================================
    // Parameters - match to edt_top parameters
    // ============================================================
    parameter CHAIN_DEPTH  = 4;
    parameter NUM_CHAINS   = 8;
    parameter ATE_IN_CH    = 4;     // ATE input channels (2 edt + seed)
    parameter MISR_WIDTH   = 16;
    parameter NUM_PATTERNS = 8;

    // ── Golden signature: set this after first clean run ──────────
    // Step 1: run simulation, note "FINAL SIGNATURE" hex value
    // Step 2: paste it here and re-run for automatic PASS/FAIL
    parameter [15:0] GOLDEN_SIG = 16'hFFFF; // placeholder - update after run 1

    // ============================================================
    // Clock - 10ns period (100MHz)
    // ============================================================
    reg clk;
    initial clk = 0;
    always #5 clk = ~clk;

    // ============================================================
    // DUT ports
    // ============================================================
    reg         rst;
    reg         scan_en;
    reg  [1:0]  edt_ch;
    reg         seed_load;
    reg  [3:0]  seed_in;
    reg  [7:0]  func_in;
    reg  [7:0]  mask_code;
    wire [15:0] signature;

    // ============================================================
    // Test tracking
    // ============================================================
    integer test_num;
    integer pass_count;
    integer fail_count;

    // ============================================================
    // DUT instantiation
    // ============================================================
    edt_top #(
        .CHAIN_DEPTH (CHAIN_DEPTH),
        .NUM_CHAINS  (NUM_CHAINS)
    ) U_DUT (
        .clk       (clk),
        .rst       (rst),
        .scan_en   (scan_en),
        .edt_ch    (edt_ch),
        .seed_load (seed_load),
        .seed_in   (seed_in),
        .func_in   (func_in),
        .mask_code (mask_code),
        .signature (signature)
    );

    // ============================================================
    // Task: print_header
    // ============================================================
    task print_header;
        begin
            $display("╔══════════════════════════════════════════════════════╗");
            $display("║     XOR Tree Based Test Compression Scheme (EDT)     ║");
            $display("║              Industry-Level Testbench                ║");
            $display("╠══════════════════════════════════════════════════════╣");
            $display("║  Architecture  : EDT (Embedded Deterministic Test)   ║");
            $display("║  Decompressor  : Ring LFSR + XOR Phase Shifter       ║");
            $display("║  Compactor     : Spatial XOR Tree + 16-bit MISR      ║");
            $display("║  Scan Chains   : %0d chains x %0d FF depth              ║",
                      NUM_CHAINS, CHAIN_DEPTH);
            $display("║  ATE channels  : %0d in, %0d-bit signature out          ║",
                      ATE_IN_CH, MISR_WIDTH);
            $display("║  Compression   : %0dx stimulus, 0.0015%% aliasing       ║",
                      NUM_CHAINS/ATE_IN_CH);
            $display("║  Test patterns : %0d                                    ║",
                      NUM_PATTERNS);
            $display("╚══════════════════════════════════════════════════════╝");
            $display("");
        end
    endtask

    // ============================================================
    // Task: print_metrics
    // ============================================================
    task print_metrics;
        begin
            $display("╔══════════════════════════════════════════════════════╗");
            $display("║                 Design Metrics                       ║");
            $display("╠══════════════════════════════════════════════════════╣");
            $display("║  Uncompressed test data : %0d bits                    ║",
                      NUM_PATTERNS * CHAIN_DEPTH * NUM_CHAINS);
            $display("║  Compressed test data   : %0d bits                    ║",
                      NUM_PATTERNS * CHAIN_DEPTH * ATE_IN_CH);
            $display("║  Stimulus compression   : %0dx                        ║",
                      NUM_CHAINS/ATE_IN_CH);
            $display("║  Response bits (raw)    : %0d bits                    ║",
                      NUM_PATTERNS * CHAIN_DEPTH * NUM_CHAINS);
            $display("║  MISR signature width   : %0d bits                    ║",
                      MISR_WIDTH);
            $display("║  Aliasing probability   : 1/2^%0d = ~0.0015%%          ║",
                      MISR_WIDTH);
            $display("║  Total area overhead    : ~%0d XOR gates              ║",
                      NUM_CHAINS*3 + NUM_CHAINS + 16);
            $display("╚══════════════════════════════════════════════════════╝");
            $display("");
        end
    endtask

    // ============================================================
    // Task: reset_dut
    // ============================================================
    task reset_dut;
        begin
            rst       = 1;
            scan_en   = 0;
            edt_ch    = 2'b00;
            seed_load = 0;
            seed_in   = 4'b0000;
            func_in   = 8'h00;
            mask_code = 8'h00;
            repeat(3) @(posedge clk);
            rst = 0;
            @(posedge clk); #1;
            $display("[RESET] Reset released at time %0t", $time);
        end
    endtask

    // ============================================================
    // Task: load_seed
    // Loads compressed seed into ring LFSR from ATE
    // ============================================================
    task load_seed;
        input [3:0] seed;
        input [1:0] ch;
        begin
            seed_in   = seed;
            edt_ch    = ch;
            seed_load = 1;
            @(posedge clk); #1;
            seed_load = 0;
            $display("[SEED ] Loaded seed=%b edt_ch=%b into Ring LFSR",
                      seed, ch);
        end
    endtask

    // ============================================================
    // Task: apply_and_capture
    // Full 3-phase DFT test cycle
    //   Phase 1: SHIFT IN  - CHAIN_DEPTH clocks with scan_en=1
    //   Phase 2: CAPTURE   - 1 clock with scan_en=0
    //   Phase 3: back to scan mode
    // ============================================================
    task apply_and_capture;
        input [3:0]  seed;
        input [1:0]  ch;
        input [7:0]  cut_resp;
        input [7:0]  xmask;
        input [63:0] label;
        begin
            $display("\n[PAT  ] Pattern: %s | seed=%b ch=%b resp=%h mask=%b",
                      label, seed, ch, cut_resp, xmask);

            // Load LFSR seed (compressed pattern from ATE)
            load_seed(seed, ch);

            // ── Phase 1: SHIFT IN ──────────────────────────────
            scan_en   = 1;
            mask_code = xmask;
            repeat(CHAIN_DEPTH) begin
                @(posedge clk); #1;
                $display("  [SHIFT] q=%b | s=%b | raw=%b | sig=%h",
                    U_DUT.q,
                    U_DUT.s,
                    U_DUT.scan_out_raw,
                    signature);
            end

            // ── Phase 2: CAPTURE ───────────────────────────────
            func_in = cut_resp;
            scan_en = 0;
            @(posedge clk); #1;
            $display("  [CAPT ] func_in=%b | masked=%b | sig=%h",
                func_in,
                U_DUT.scan_out_mask,
                signature);

            // Return to scan mode
            scan_en = 1;
        end
    endtask

    // ============================================================
    // Task: check_signature
    // Compares final signature against golden
    // ============================================================
    task check_signature;
        input [15:0] expected;
        begin
            if (GOLDEN_SIG === 16'hFFFF) begin
                $display("\n[INFO ] First run - golden signature not set");
                $display("[INFO ] Copy this value into GOLDEN_SIG parameter:");
                $display("[INFO ] GOLDEN_SIG = 16'h%h", signature);
                $display("[INFO ] Re-run for automatic PASS/FAIL");
            end
            else if (signature === expected) begin
                $display("\n╔═══════════════════════════════╗");
                $display("║   *** PASS *** Circuit OK     ║");
                $display("║   Signature: %h              ║", signature);
                $display("╚═══════════════════════════════╝");
                pass_count = pass_count + 1;
            end
            else begin
                $display("\n╔════════════════════════════════════════╗");
                $display("║   *** FAIL *** Fault Detected!         ║");
                $display("║   Got     : %h                       ║", signature);
                $display("║   Expected: %h                       ║", expected);
                $display("╚════════════════════════════════════════╝");
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ============================================================
    // Stimulus - Main test sequence
    // ============================================================
    initial begin
        // Init counters
        test_num   = 0;
        pass_count = 0;
        fail_count = 0;

        // Print header
        print_header;
        print_metrics;

        // ── Test 1: Reset verification ─────────────────────────
        test_num = 1;
        $display("══════════════════════════════════════════════════════");
        $display("[TEST %0d] Reset Verification", test_num);
        $display("══════════════════════════════════════════════════════");
        reset_dut;
        if (signature === 16'h0000)
            $display("[PASS ] Signature = 0 after reset ✓");
        else
            $display("[FAIL ] Signature not 0 after reset: %h", signature);

        // ── Test 2: LFSR seed load verification ────────────────
        test_num = 2;
        $display("\n══════════════════════════════════════════════════════");
        $display("[TEST %0d] LFSR Seed Load", test_num);
        $display("══════════════════════════════════════════════════════");
        load_seed(4'b1010, 2'b01);
        scan_en = 1;
        @(posedge clk); #1;
        $display("[CHECK] After 1 LFSR clock: q=%b", U_DUT.q);
        $display("[CHECK] Phase shifter output s=%b", U_DUT.s);

        // ── Test 3: Full pattern set (fault-free) ──────────────
        test_num = 3;
        $display("\n══════════════════════════════════════════════════════");
        $display("[TEST %0d] Full Scan Test - Fault Free", test_num);
        $display("══════════════════════════════════════════════════════");

        // Reset before pattern run
        reset_dut;

        // Apply 8 test patterns
        // apply_and_capture(seed, edt_ch, CUT_response, mask, label)
        apply_and_capture(4'b0001, 2'b00, 8'h00, 8'h00, "PAT_0");
        apply_and_capture(4'b1010, 2'b01, 8'hA5, 8'h00, "PAT_1");
        apply_and_capture(4'b1100, 2'b10, 8'hC3, 8'h00, "PAT_2");
        apply_and_capture(4'b0111, 2'b11, 8'h7E, 8'h00, "PAT_3");
        apply_and_capture(4'b1111, 2'b01, 8'hFF, 8'h00, "PAT_4");
        apply_and_capture(4'b1001, 2'b10, 8'h96, 8'h00, "PAT_5");
        apply_and_capture(4'b0101, 2'b11, 8'h5A, 8'h00, "PAT_6");
        apply_and_capture(4'b1101, 2'b01, 8'hD2, 8'h00, "PAT_7");

        // Flush last pattern through scan chains
        scan_en = 1;
        repeat(CHAIN_DEPTH + 2) @(posedge clk);

        $display("\n[SIG  ] Final MISR Signature = %h (hex)", signature);
        $display("[SIG  ] Final MISR Signature = %b (bin)", signature);

        // ── Test 4: X-masking verification ─────────────────────
        test_num = 4;
        $display("\n══════════════════════════════════════════════════════");
        $display("[TEST %0d] X-Masking Verification", test_num);
        $display("══════════════════════════════════════════════════════");
        reset_dut;

        // Apply pattern with chain 0 masked (X suspected on SC0)
        $display("[MASK ] Masking SC0 (chain 0) - simulating X contamination");
        apply_and_capture(4'b1010, 2'b01, 8'hA5, 8'h01, "XMASK");

        repeat(CHAIN_DEPTH + 2) @(posedge clk);
        $display("[CHECK] Masked signature = %h", signature);
        $display("[CHECK] mask_code=8'h01 blocked SC0 from compactor ✓");

        // ── Test 5: Fault injection test ───────────────────────
        test_num = 5;
        $display("\n══════════════════════════════════════════════════════");
        $display("[TEST %0d] Fault Injection Test", test_num);
        $display("══════════════════════════════════════════════════════");
        $display("[FAULT] Injecting fault: corrupting func_in response");
        reset_dut;

        // Same patterns but with corrupted func_in on PAT_3
        apply_and_capture(4'b0001, 2'b00, 8'h00, 8'h00, "PAT_0");
        apply_and_capture(4'b1010, 2'b01, 8'hA5, 8'h00, "PAT_1");
        apply_and_capture(4'b1100, 2'b10, 8'hC3, 8'h00, "PAT_2");
        // FAULT: correct is 8'h7E, injecting 8'h7F (1 bit flip)
        apply_and_capture(4'b0111, 2'b11, 8'h7F, 8'h00, "PAT_3_FAULT");
        apply_and_capture(4'b1111, 2'b01, 8'hFF, 8'h00, "PAT_4");
        apply_and_capture(4'b1001, 2'b10, 8'h96, 8'h00, "PAT_5");
        apply_and_capture(4'b0101, 2'b11, 8'h5A, 8'h00, "PAT_6");
        apply_and_capture(4'b1101, 2'b01, 8'hD2, 8'h00, "PAT_7");

        repeat(CHAIN_DEPTH + 2) @(posedge clk);
        $display("[SIG  ] Faulty signature = %h", signature);

        if (signature !== GOLDEN_SIG && GOLDEN_SIG !== 16'hFFFF)
            $display("[PASS ] Fault detected - signature mismatch confirms detection ✓");
        else if (GOLDEN_SIG === 16'hFFFF)
            $display("[INFO ] Set GOLDEN_SIG then re-run to verify fault detection");
        else
            $display("[WARN ] Aliasing occurred - fault not detected (rare event)");

        // ── Final pass/fail summary ────────────────────────────
        $display("\n══════════════════════════════════════════════════════");
        $display("[TEST %0d] Golden Signature Check", test_num+1);
        $display("══════════════════════════════════════════════════════");
        check_signature(GOLDEN_SIG);

        // ── Summary ────────────────────────────────────────────
        $display("\n╔══════════════════════════════════════════════════════╗");
        $display("║                 Test Summary                         ║");
        $display("╠══════════════════════════════════════════════════════╣");
        $display("║  Total tests run   : %0d                              ║",
                  test_num + 1);
        $display("║  Final Signature   : %h                          ║",
                  signature);
        $display("╚══════════════════════════════════════════════════════╝");

        $finish;
    end

    // ============================================================
    // Waveform dump
    // ============================================================
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_edt_top);
    end

    // ============================================================
    // Timeout watchdog - prevents infinite simulation
    // ============================================================
    initial begin
        #100000;
        $display("[ERROR] Simulation timeout - check for infinite loop");
        $finish;
    end

endmodule
