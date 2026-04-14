# EDT-XOR-Test-Compression
### Embedded Deterministic Test (EDT) Architecture — XOR Tree Based Scan Compression in Verilog HDL

---

## Overview

This repository implements a hardware-level **Embedded Deterministic Test (EDT)** architecture
for scan-based test compression in digital VLSI circuits. The design reduces ATE test data volume
by 2× on the stimulus side using a Ring LFSR decompressor with XOR phase shifting, and compacts
8 scan chain outputs into a 16-bit MISR signature on the response side — achieving an aliasing
probability of 1/2¹⁶ (0.0015%).

The architecture directly mirrors the EDT implementation described in Mentor Tessent TestKompress,
implementing the full decompressor–scan–compactor pipeline in synthesizable Verilog RTL.

---

## Why Test Compression Exists

In a modern SoC with 10M+ scan cells, the ATE test data volume is:

```
Test Data Volume = Scan Cells × Patterns × Shift Cycles
```

At even modest scale — 500K cells, 5K patterns, depth 100 — that is **250 billion bits**
that must be stored on ATE memory and transferred across a bandwidth-limited tester interface.
ATE channel bandwidth is the primary bottleneck. You cannot test faster than the rate at which
you can transfer data between tester and DUT.

Hardware-based EDT compression addresses this by:

1. Storing a **compressed seed** on the ATE instead of the full pattern
2. Expanding the seed **on-chip** using a Ring LFSR + XOR phase shifter
3. Compacting the **output response** into a short MISR signature

The key insight driving EDT: ATPG-generated patterns are **highly sparse** — typically only
1–5% of scan bits carry specified (care) values. The remaining 95–99% are don't-cares that
can be filled with any pseudo-random value without affecting fault coverage. EDT exploits
this sparsity — it encodes only the care bits by solving a system of linear equations over
GF(2), then lets the LFSR fill the don't-cares automatically.

---

## Architecture

```
                        ┌─────────────────────────────────────────────┐
                        │              DECOMPRESSOR                    │
                        │                                              │
   ATE                  │  ┌──────────────┐     ┌──────────────────┐  │
   seed_in[3:0] ───────►│  │  Ring LFSR   │     │  XOR Phase       │  │
   edt_ch[1:0]  ───────►│  │  (Ring Gen)  │─q──►│  Shifter         │  │
   seed_load    ───────►│  │  4-bit       │     │  4-in → 8-out    │  │
                        │  └──────────────┘     └────────┬─────────┘  │
                        │                                │ s[7:0]     │
                        └────────────────────────────────┼────────────┘
                                                         │
                                              ┌──────────▼──────────┐
                                              │   8 × Scan Chains   │
                                              │   DEPTH=4 FFs each  │
                             func_in[7:0] ───►│   shift / capture   │
                                              └──────────┬──────────┘
                                                         │ scan_out_raw[7:0]
                        ┌────────────────────────────────┼────────────┐
                        │              COMPACTOR          │            │
                        │                                │            │
   ATE                  │  ┌──────────────┐     ┌────────▼─────────┐  │
   mask_code[7:0] ─────►│  │  Mask        │─────►  XOR Spatial     │  │
                        │  │  Controller  │     │  Compactor       │  │
                        │  └──────────────┘     │  + 16-bit MISR   │  │
                        │                       └────────┬─────────┘  │
                        │                                │            │
                        └────────────────────────────────┼────────────┘
                                                         │
                                              signature[15:0] → ATE
```

### Signal-Level Data Flow

**Decompressor path (stimulus):**

1. ATE drives `seed_in[3:0]` and `edt_ch[1:0]` — these are the compressed pattern bits
2. `seed_load=1` for one clock loads the seed into Ring LFSR state registers
3. With `scan_en=1`, the Ring LFSR shifts — `state[0]` takes ring feedback from `state[3]`
   XORed with injector `edt_ch[0]`; `state[2]` takes shift from `state[1]` XORed with
   `edt_ch[1]`
4. The 4-bit LFSR state `q[3:0]` feeds the XOR phase shifter combinationally
5. Phase shifter generates 8 linearly independent combinations of `q`:
   - `s[0]=q[0]^q[1]`, `s[1]=q[0]^q[2]`, ..., `s[7]=q[0]^q[1]^q[3]`
6. Each `s[i]` drives the `scan_in` of scan chain `SC[i]`
7. After `DEPTH` shift clocks, the test pattern is fully loaded into all 8 scan chains

**Capture phase:**

8. `scan_en` goes low for **one functional clock**
9. The CUT (Circuit Under Test) response propagates combinationally
10. `func_in[7:0]` (CUT output) is captured into `ff[0]` of each scan chain
11. Existing chain contents shift right by one position

**Compactor path (response):**

12. `scan_en=1` again — shift phase begins for next pattern
13. As patterns shift out, `scan_out_raw[i] = ff[DEPTH-1]` of each chain
14. Mask controller ANDs each output: `scan_out_mask[i] = scan_out_raw[i] & ~mask_code[i]`
    — this blocks any chain suspected of carrying X values
15. All 8 masked outputs are XORed into a single bit: `xor_all = ^scan_out_mask`
16. `xor_all` is injected into the 16-bit MISR feedback at every shift clock
17. After all patterns, `signature[15:0]` holds the compacted response

---

## Timing Behavior

```
Clock:    ___┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
          ___|_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_|

scan_en:  ────────────────────────┐         ┌──────────────
          (1) shift mode          │  capture │  shift mode
                                  └─────────┘
                                  1 clock
Phase:    |<── DEPTH shift clocks ──>|<cap>|<── DEPTH+N ──>|
               (load test pattern)         (shift out resp)

S[7:0]:   valid combinationally from q[3:0] — no register latency
R[7:0]:   first valid data at scan_out after DEPTH shift clocks
MISR:     accumulates during shift-out phase, holds during capture
```

**Critical timing note:** The XOR phase shifter is purely combinational — `s[i]` is valid
within the same clock cycle that `q` updates. There is no registered pipeline stage between
the LFSR and the scan chain inputs, which is intentional: it eliminates one wasted shift cycle
per pattern and matches EDT continuous-flow behavior.

---

## Module Descriptions

### `ring_lfsr.v` — Ring Generator

4-bit ring-connected LFSR with two external EDT channel injectors.

- **Polynomial:** x⁴ + x³ + 1 (primitive, maximal-length sequence = 15)
- **Injectors:** `edt_ch[0]` at tap 0, `edt_ch[1]` at tap 2
- **Seed load:** synchronous, one-cycle, full parallel load
- **Purpose:** Generates pseudo-random base sequences; injectors add free variables
  that increase the probability of solving AX=Z for care bit placement

Without injectors: 4 free variables (Q0–Q3 = LFSR seed only)
With 2 injectors: 4 + 2×(shift_cycles) free variables — significantly improves
encoding efficiency for heavily-specified scan slices.

### `xor_phase_shifter.v` — XOR Tree (Decompressor)

Purely combinational. Takes `q[3:0]` from LFSR, outputs `s[7:0]` to scan chains.

All 8 outputs are **linearly independent** over GF(2):
```
s[0] = q[0]^q[1]        s[4] = q[1]^q[3]
s[1] = q[0]^q[2]        s[5] = q[2]^q[3]
s[2] = q[0]^q[3]        s[6] = q[0]^q[1]^q[2]
s[3] = q[1]^q[2]        s[7] = q[0]^q[1]^q[3]
```

Inter-channel separation is guaranteed by construction: no two outputs are identical
for any non-zero LFSR state. This prevents correlated errors between scan chains
that would reduce compactor observability.

### `scan_chain.v` — Parameterized Scan Register

Standard DFT scan element. Two modes:

| Mode | scan_en | Operation |
|---|---|---|
| Shift | 1 | `ff <= {ff[DEPTH-2:0], scan_in}` — LSB to MSB |
| Capture | 0 | `ff <= {func_in, ff[DEPTH-1:1]}` — CUT response into MSB |

`scan_out = ff[DEPTH-1]` — data appears at output after exactly `DEPTH` shift clocks.

Parameter `DEPTH` controls chain length. Default 4. In a real design this would be
set to match the longest combinational path depth in the CUT partition.

### `mask_controller.v` — X-Contamination Blocking

Single-cycle combinational logic. One AND gate per scan chain.

```verilog
scan_out_mask = scan_out_raw & ~mask_code;
```

`mask_code[i]=1` forces chain `i` output to 0 before it reaches the XOR compactor.
This prevents X values captured from black boxes, uninitialized logic, or false paths
from propagating into the MISR and corrupting the signature.

In production EDT, the mask bits are encoded into the tail of the compressed pattern
on ATE — they consume ATE channels but do not go through the decompressor.

### `xor_compactor.v` — Spatial XOR Tree + 16-bit MISR

**Level 1 — Spatial compaction:**
```
xor_all = XOR of all 8 masked scan outputs
```
8 scan outputs → 1 bit per shift cycle. This is the XOR tree referenced in the
project title. It reduces the ATE output pin count by 8×.

**Level 2 — Time compaction (MISR):**
Polynomial: x¹⁶ + x¹² + x³ + x + 1 (primitive, maximal-length)

```
Aliasing probability = 1/2¹⁶ = 0.00153%
```

Feedback taps at positions 0, 1, 3, 12. `xor_all` is injected at the feedback point
every shift clock. After all patterns complete, `signature[15:0]` is the compacted
response fingerprint.

### `edt_top.v` — Top-Level Integration

Connects all five submodules. Parameterized with `CHAIN_DEPTH` and `NUM_CHAINS`.
Top-level instance name `edt_top` matches Tessent TestKompress naming convention.

---

## Design Decisions and Tradeoffs

### Why Ring LFSR over standard LFSR?

Standard Fibonacci/Galois LFSR has a maximum fanout path through the feedback XOR
chain that scales with register width. Ring LFSR (ring generator) limits the feedback
path to a single XOR gate in the worst case — one between adjacent stages — which
reduces propagation delay in the decompressor critical path. At 4-bit width this
is not critical, but at production scale (20–32 bit ring generators) timing closure
on the decompressor becomes a real constraint.

### Why XOR phase shifter over direct LFSR output?

A 4-bit LFSR has only 4 outputs. Without a phase shifter, you can drive at most
4 scan chains, limiting compression ratio. XOR combinations of those 4 outputs
produce 8 linearly independent sequences — each is a valid maximal-length sequence
displaced in phase from the others. This is the fundamental mechanism that allows
EDT to drive more scan chains than the LFSR degree without reducing encoding efficiency.

### Why 16-bit MISR over shorter signature?

A 3-bit MISR (as implemented in early project iterations) has aliasing probability
of 12.5% — unacceptable for production test where missing 1 in 8 faults is a
quality escape. The 16-bit MISR reduces this to 0.0015%. In production, 32-bit
or 64-bit MISRs are common for high-reliability devices.

### Area vs Compression Tradeoff

| Component | Gate count (approx) | Contributes to |
|---|---|---|
| 4-bit Ring LFSR | 8 FFs + 2 XOR | Decompressor |
| XOR Phase Shifter | 14 XOR gates | Decompressor |
| 8 Scan Chains (depth 4) | 32 FFs | Test data path |
| Mask Controller | 8 AND gates | Compactor |
| 16-bit MISR | 16 FFs + 20 XOR | Compactor |
| **Total overhead** | **~100 gates** | |

For a 10K gate CUT, this is approximately 1% area overhead — consistent with
industry EDT overhead targets of 1–3%.

---

## Performance Metrics

| Metric | Value | Notes |
|---|---|---|
| ATE input channels | 4 | seed_in[3:0] |
| Internal scan chains | 8 | SC0–SC7 |
| Stimulus compression ratio | 2× | 8 chains / 4 channels |
| Response compaction | 8 bits → 16-bit sig | per shift cycle |
| MISR aliasing probability | 0.0015% | x¹⁶+x¹²+x³+x+1 |
| Chain depth | 4 FFs | parameterized |
| Test patterns | 8 | configurable |
| Uncompressed stimulus bits | 256 | 8 patterns × 4 depth × 8 chains |
| Compressed stimulus bits | 128 | 8 patterns × 4 depth × 4 channels |
| Scan overhead (area) | ~1% | for 10K gate CUT |
| Clock frequency target | 100 MHz | combinational phase shifter |

---

## File Structure

```
edt-xor-test-compression/
│
├── rtl/
│   ├── ring_lfsr.v            # Ring generator with EDT channel injectors
│   ├── xor_phase_shifter.v    # XOR tree decompressor (4→8)
│   ├── scan_chain.v           # Parameterized shift+capture chain
│   ├── mask_controller.v      # X-contamination blocking
│   ├── xor_compactor.v        # Spatial XOR tree + 16-bit MISR
│   └── edt_top.v              # Top-level integration
│
├── tb/
│   └── tb_edt_top.v           # Self-checking testbench
│
├── sim/
│   └── wave.vcd               # Generated after simulation run
│
├── docs/
│   └── architecture.md        # Detailed signal-level architecture notes
│
├── edt_complete.v             # Single-file version (all modules + TB)
├── README.md
└── LICENSE
```

---

## How to Simulate

**Multi-file:**
```bash
iverilog -o sim rtl/ring_lfsr.v rtl/xor_phase_shifter.v rtl/scan_chain.v \
         rtl/mask_controller.v rtl/xor_compactor.v rtl/edt_top.v \
         tb/tb_edt_top.v
vvp sim
gtkwave sim/wave.vcd
```

**Single file:**
```bash
iverilog -o sim edt_complete.v && vvp sim
gtkwave wave.vcd
```

---

## Expected Simulation Output

```
==================================================
  XOR Tree Based Test Compression Scheme (EDT)
==================================================
  Scan Chains  : 8 chains x 4 FF depth
  Compression  : 2x stimulus
  Aliasing     : 1/2^16 = 0.0015%
==================================================

[TEST 1] Reset Verification
[RESET] Released at time 30000
[PASS ] Signature = 0 after reset

[TEST 2] LFSR Seed Load
[SEED ] seed=1010 edt_ch=01 loaded | q=1010

[TEST 3] Full Scan Test - Fault Free
[PAT  ] PAT_0 | seed=0001 ch=00 resp=00 mask=00
  [SHIFT] q=0001 s=00110001 raw=00000000 sig=0000
  [SHIFT] q=0010 s=01100010 raw=00000000 sig=0000
  [SHIFT] q=0100 s=11000100 raw=00000000 sig=0000
  [SHIFT] q=1000 s=10001000 raw=00000000 sig=0000
  [CAPT ] func=00000000 masked=00000000 sig=0000
...
[SIG  ] FINAL SIGNATURE = XXXX (hex)

[TEST 4] X-Masking Verification
[MASK ] Masking SC0 - simulating X contamination
[CHECK] SC0 blocked by mask_code=8'h01 ✓

[TEST 5] Fault Injection
[FAULT] PAT_3 func_in 7E→7F (bit0 stuck-at-1)
[PASS ] Fault detected - signature mismatch confirmed

==================================================
  Tests run       : 6
  Final signature : XXXX
==================================================
```

**After first clean run:** Copy the printed signature into `GOLDEN_SIG` parameter
in `tb_edt_top.v` line 34. Re-run — all tests auto-report PASS/FAIL.

---

## Synthesis Notes

**Tool:** Yosys (open source) or Vivado for FPGA target

**Yosys synthesis:**
```bash
yosys -p "read_verilog rtl/*.v; synth -top edt_top; stat"
```

**Expected resource usage (estimated, 4-bit LFSR, 8 chains, depth 4):**

| Resource | Count | Notes |
|---|---|---|
| Flip-flops | ~52 | 4 LFSR + 32 scan + 16 MISR |
| XOR gates / LUTs | ~36 | phase shifter + MISR feedback |
| AND gates | 8 | mask controller |
| MUX (2:1) | 8 | scan_en select in scan chains |
| **Total** | **~104 cells** | |

**ASIC flow differences:**
- In a real ASIC flow (Synopsys DC or Cadence Genus), the EDT logic is inserted
  post-synthesis at gate level by the DFT tool (Tessent TestKompress / Synopsys DFT MAX)
- Scan chains are stitched by the tool, not manually instantiated
- Phase shifter tap selection is optimized algorithmically to maximize encoding efficiency
- Ring generator polynomial is chosen based on CUT scan chain count and depth

---

## Limitations

These are known architectural gaps relative to production EDT:

1. **No ATPG integration** — Test patterns are manually specified in the testbench.
   A real flow would use Tessent ATPG or Synopsys TetraMAX to generate care-bit-minimal
   test cubes, then solve AX=Z to find LFSR seeds automatically.

2. **No fault coverage measurement** — There is no fault simulator connected to the
   CUT. `func_in` is driven with pre-computed expected values, not simulated fault
   propagation. True fault coverage (stuck-at, transition, path delay) cannot be
   measured without a fault simulation engine.

3. **Simplified EDT model** — Production EDT uses a continuous-flow decompressor where
   new seed bits are injected into the ring generator every clock cycle while scan chains
   are being loaded simultaneously. This design uses discrete seed-load + shift phases.

4. **Fixed compression ratio** — The 2× ratio is determined by the static 4-in/8-out
   phase shifter. Production tools perform encoding efficiency analysis per-pattern and
   adjust dynamically. Some patterns may require more ATE channels than others.

5. **No bypass mode** — A production EDT chip includes bypass muxes that allow the
   ATE to directly access scan chains, bypassing decompressor and compactor. This is
   critical for debug after a signature failure — without bypass you cannot identify
   which scan cell failed.

6. **3-bit MISR in early iterations** — Initial implementation used a 3-bit MISR
   with 12.5% aliasing. Upgraded to 16-bit (0.0015%) in final version. Production
   devices use 32-bit or 64-bit MISRs.

---

## Future Work

- **Bypass mode implementation** — Add `bypass_en` mux to allow direct ATE→scan
  chain access, enabling per-chain debug after signature failure
- **Continuous-flow decompressor** — Implement the true EDT injection model where
  ATE bits feed the ring generator every shift clock simultaneously with scan loading
- **ATPG-compatible test cube interface** — Accept care-bit sparse test vectors
  and implement GF(2) Gaussian elimination to solve for LFSR seed automatically
- **Fault coverage estimation** — Integrate a stuck-at fault model on a simple CUT
  to demonstrate actual fault detection rate
- **Power-aware compression** — Add scan enable gating to reduce switching activity
  during shift — industry target is <30% toggle rate during scan shift
- **Scalability study** — Parametrize to 32 chains / 8 ATE channels and demonstrate
  4× compression with a 32-bit ring generator

---

## Reference Architecture

This implementation is based on:

- EDT architecture as described in **Analog and Digital Testing, Debug and Diagnosis**
  — Dr. Sudeendra Kumar K, Department of ECE
- VLSI Tutorials: Test Compression — EDT (vlsitutorials.com)
- Mentor Tessent TestKompress architecture documentation
- Touba, N.A., "Survey of Test Vector Compression Techniques," IEEE Design & Test, 2006
- Rajski et al., "Embedded Deterministic Test," IEEE TCAD, 2004

---

## Keywords

`verilog` `dft` `design-for-test` `test-compression` `edt` `embedded-deterministic-test`
`scan-chain` `lfsr` `ring-generator` `xor-tree` `misr` `phase-shifter` `vlsi`
`digital-design` `rtl` `icarus-verilog` `gtkwave` `semiconductor` `atpg`
