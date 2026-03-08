# Scalable Systolic Array — UVM Testbench

A parameterized UVM testbench for verifying an NxN weight-stationary systolic array that computes C = A × B matrix multiplications with double-buffered weights and support for back-to-back pipelined transactions.

## Architecture

The testbench targets a cycle-accurate behavioral reference model (`sa_ref_model_sv`) and uses a standard UVM layered architecture:

```
┌──────────────────────────────────────────────────┐
│  sa_tb_top                                       │
│    sa_if  ◄──────►  sa_ref_model_sv (DUT)        │
│    run_test("sa_directed_test_8_4")              │
└──────────────────────────────────────────────────┘

UVM Hierarchy:
┌──────────────────────────────────────────────────┐
│  sa_env                                          │
│  ┌──────────────┐  ┌──────────────┐              │
│  │  sa_agent     │  │ sa_scoreboard│              │
│  │   driver  ───────► ap_exp      │              │
│  │   monitor ───────► ap_act      │              │
│  │   sequencer   │  └──────────────┘              │
│  └──────────────┘                                │
│  ┌───────────────────┐                           │
│  │ sa_cov_subscriber │                           │
│  └───────────────────┘                           │
└──────────────────────────────────────────────────┘
```

## Key Features

- **Fully parameterized** — All components are parameterized by `DIN_WIDTH` and `N`, making it straightforward to verify different array sizes
- **Self-checking** — Expected results are auto-computed via a golden `matmul` function in `post_randomize()`; no manual golden values needed
- **Back-to-back pipelining** — Driver supports overlapping B-preload with A-streaming for consecutive transactions, testing the most realistic operating mode
- **Functional coverage** — Covers matrix patterns (zero, identity, all-same, max/min values), sign combinations, and back-to-back chaining scenarios
- **Forked output capture** — Monitor spawns independent threads per `out_valid` pulse, naturally handling overlapping output streams

## File Structure

| File             | Description                                                     |
|------------------|-----------------------------------------------------------------|
| `matrix_pkg.sv`  | Golden matrix multiplication function (shared reference model)  |
| `sa_if.sv`       | SystemVerilog interface with clocking blocks and modports       |
| `sa_ref.sv`      | Cycle-accurate behavioral reference model (DUT under test)      |
| `sa_pkg.sv`      | All UVM components: seq_item, driver, monitor, scoreboard, coverage, agent, env, tests |
| `testbench.sv`   | Top-level: clock gen, reset, DUT instantiation, UVM test launch |

## Test Plan

| Test | Description | Transactions |
|------|-------------|--------------|
| 1 | Zero matrices (A=0, B=0) | 1 |
| 2 | Identity A, random B | 1 |
| 3 | All-same values (A=3, B=3) | 1 |
| 4 | Max positive values (+7) | 1 |
| 5 | Min negative values (-8) | 1 |
| 6 | Fully random | 4 |
| 7 | Back-to-back consecutive (3 chained) | 3 |
| **Total** | | **12 comparisons** |

## Design Parameters

- `DIN_WIDTH = 8` — 8-bit signed input elements
- `N = 4` — 4×4 systolic array
- `M = N` — Square matrix multiplication (NxN × NxN)

## How to Run

### EDA Playground (recommended)
1. Go to [edaplayground.com](https://edaplayground.com)
2. Set simulator to **Synopsys VCS** and check **UVM 1.2**
3. Design file: `sa_ref.sv`
4. Testbench file: `testbench.sv`
5. Run options: `+UVM_TESTNAME=sa_directed_test_8_4 +UVM_VERBOSITY=UVM_MEDIUM`

### Expected Output
```
===== SA-Level Scoreboard =====
PASS: 12   FAIL: 0
================================
TEST PASSED
```

## Assumptions

1. M is constrained equal to N (square matrices only)
2. Partial-sum feedback `c_din` is tied to zero
3. Element values are constrained to `[-8, +7]` to avoid overflow
4. Single clock domain at the SA module level

