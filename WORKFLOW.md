# Tiny Tapeout 8-bit CPU — Project Workflow

This document describes the goals, constraints, tools and day-to-day workflow for
this project. Keep it in the root of the repo and update it as decisions are made.

---

## 1. Project goal

Design a simple 8-bit CPU in Verilog that fits in **1 tile (1x1), or at most 2 tiles (1x2)**
on a Tiny Tapeout shuttle, verify it in simulation and on an FPGA, and submit it
for fabrication.

The priority is a design that is **finished and working**, not one that is
maximally clever. Extra features are added only once the core CPU passes all tests
and fits in the area budget.

---

## 2. Hard constraints

### 2.1 Area

- One tile is roughly 160 × 100 µm (on SKY130), around 1000 simple logic gates.
- Flip-flops are much larger than simple gates. **Storage is the main area cost.**
- On-chip RAM/ROM is not realistic beyond a few registers.
- Always check utilization in the GitHub Actions report after significant changes.

### 2.2 I/O (fixed Tiny Tapeout pinout)

```verilog
module tt_um_<name> (
    input  wire [7:0] ui_in,    // dedicated inputs
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // bidirectional pins: input path
    output wire [7:0] uio_out,  // bidirectional pins: output path
    output wire [7:0] uio_oe,   // bidirectional enable: 1 = output, 0 = input
    input  wire       ena,      // high when the design is selected (can be ignored)
    input  wire       clk,      // clock
    input  wire       rst_n     // reset, ACTIVE LOW
);
```

Only these pins exist. Every memory access, debug signal and control line has to
go through them.

---

## 3. Architecture plan (draft — fill in as decisions are made)

### 3.1 Style

- Accumulator-based, 8-bit data path.
- Multi-cycle control FSM: FETCH → DECODE → EXECUTE (no pipelining).
- 8-bit address space (256 bytes) to start with.

### 3.2 Registers

| Register | Width | Purpose |
|----------|-------|---------|
| A        | 8     | Accumulator |
| PC       | 8     | Program counter |
| IR       | 8     | Instruction register |
| Flags    | 2     | Z (zero), C (carry) |
| _(opt.)_ B / X | 8 | Second register or index register (if area allows) |

### 3.3 Memory interface (external)

Program and data memory live **off-chip**, emulated by the RP2040/RP2350 on the
Tiny Tapeout demo board.

Draft pin assignment:

| Pins        | Direction | Use |
|-------------|-----------|-----|
| `uo_out[7:0]` | out     | Memory address |
| `ui_in[7:0]`  | in      | Read data from memory |
| `uio[7:0]`    | out/in  | Write data to memory / control signals (TBD) |

Open questions:
- [ ] How are read/write strobes signalled (dedicated uio pins?)
- [ ] How many clock cycles does the microcontroller need per access?
- [ ] How is a program loaded before the CPU starts running?

The chip will be clocked slowly enough that the microcontroller can keep up.

### 3.4 Instruction set

To be specified before writing RTL. Draft: 4-bit opcode, ~16 instructions.

| Opcode | Mnemonic | Operation | Cycles |
|--------|----------|-----------|--------|
| 0x0    | NOP      | —         | TBD    |
| 0x1    | LDA addr | A ← M[addr] | TBD  |
| 0x2    | STA addr | M[addr] ← A | TBD  |
| 0x3    | ADD addr | A ← A + M[addr] | TBD |
| 0x4    | SUB addr | A ← A − M[addr] | TBD |
| ...    | ...      | AND, OR, XOR, shifts, LDI | ... |
| ...    | JMP addr | PC ← addr | TBD |
| ...    | JZ / JC  | Conditional jumps | TBD |
| 0xF    | HLT      | Stop | TBD |

**Stretch goals (only if area allows, likely requires 1x2 tiles):**
stack pointer with CALL/RET, index register, extra general-purpose register,
simple interrupt.

---

## 4. Development environment

All development happens in **WSL2 (Ubuntu)** on Windows.

### 4.1 Tools

| Tool | Purpose |
|------|---------|
| Git + GitHub | Version control; GitHub Actions run the ASIC flow |
| VS Code + WSL extension + Verilog extension | Editor |
| Icarus Verilog (`iverilog`) | RTL simulator used by the cocotb tests |
| Python 3 + cocotb | Testbenches (in `test/`) |
| Verilator | Linting only |
| GTKWave (or Surfer) | Waveform viewer |
| Yosys + nextpnr-ice40 (OSS CAD Suite) | FPGA synthesis for the iCE40 UP5K |

Install the basics:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git iverilog verilator gtkwave python3-venv python3-pip make
```

### 4.2 Rules

- Keep the repo in the Linux filesystem (`~/projects/...`), **not** under `/mnt/c/`.
- Open the project from Ubuntu with `code .` so VS Code runs inside WSL.
- WSL cannot see USB devices by default. Use `usbipd-win` to pass the FPGA board
  through, or program it from the Windows side.

### 4.3 First-time setup of the test environment

```bash
cd test
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Remember `source venv/bin/activate` in every new terminal.

---

## 5. Repository layout

Based on the Tiny Tapeout Verilog template:

```
.
├── info.yaml              # Project metadata: top module, source files, tiles, pinout
├── src/
│   ├── project.v          # Top-level wrapper (tt_um_<name>) — pin mapping only
│   ├── cpu.v              # CPU core (to be created)
│   ├── alu.v              # ALU (to be created)
│   └── ...                # Other modules; list every file in info.yaml
├── test/
│   ├── Makefile           # cocotb runner (RTL and GATES=yes modes)
│   ├── tb.v               # Verilog testbench wrapper
│   ├── test.py            # cocotb tests
│   └── requirements.txt
├── docs/
│   └── info.md            # Datasheet text: how the CPU works, how to test it
├── tools/                 # Assembler and helper scripts (to be created)
├── .github/workflows/     # CI: GDS hardening, tests, docs
└── WORKFLOW.md            # This file
```

Keep the top-level wrapper thin: it only maps Tiny Tapeout pins to the CPU core's
ports. This makes the core easy to reuse in the FPGA build and in unit tests.

---

## 6. Day-to-day workflow

```
 write/modify RTL ──► lint ──► simulate (cocotb) ──► inspect waveforms
        ▲                                                   │
        └──────────────── fix bugs ◄────────────────────────┘
                              │ tests pass
                              ▼
                   commit + push to GitHub
                              │
                              ▼
     GitHub Actions: tests, hardening (GDS), precheck, gate-level sim
                              │
                              ▼
           check utilization + warnings in the Actions summary
                              │
                              ▼
               periodically: test on the FPGA dev kit
```

### 6.1 Lint

```bash
verilator --lint-only -Wall src/*.v
```

Fix all warnings about widths, latches and unused signals, or document why a
warning is acceptable.

### 6.2 Simulate

```bash
cd test
source venv/bin/activate
make -B
```

### 6.3 Inspect waveforms

```bash
gtkwave tb.fst      # or tb.vcd, depending on the Makefile settings
```

### 6.4 Push and check the ASIC flow

```bash
git add -A
git commit -m "describe the change"
git push
```

Then on GitHub, open the **Actions** tab and check:
- [ ] Tests pass
- [ ] GDS job passes (hardening + precheck)
- [ ] Gate-level simulation passes
- [ ] Utilization is acceptable (note the number in the log below)

### 6.5 Gate-level simulation locally (optional)

The GDS action runs the cocotb tests against the hardened netlist. Doing this
locally requires local hardening — see the Tiny Tapeout guide
"Hardening Tiny Tapeout Projects Locally". Not needed at the start.

---

## 7. Verification strategy

1. **Unit tests** for each module (ALU first), exhaustively where practical
   (e.g. all 256 × 256 input pairs for 8-bit ALU operations).
2. **Instruction tests**: one test per instruction, checking registers, flags
   and memory after execution.
3. **Program tests**: small programs assembled with the Python assembler
   (e.g. counting loop, Fibonacci, 8-bit multiply by repeated addition).
4. **Memory model in cocotb**: a Python model of the external memory that
   responds on the same pins the RP2040 will use on the real board.
5. **Reset tests**: CPU starts in a known state after `rst_n` is released.

---

## 8. FPGA testing

Hardware: **Tiny Tapeout FPGA Development Kit** (ETR demo board + iCE40 UP5K
"ASIC simulator" breakout).

- The breakout replaces the ASIC, so the design sees the same pins, switches,
  7-segment display, PMOD headers and RP2040 as the real chip.
- Build with the open-source flow (Yosys + nextpnr-ice40).
- Check the Tiny Tapeout docs for how bitstreams are loaded onto the breakout
  and whether the template includes an FPGA build workflow.
- Test the memory interface with the RP2040 firmware here before submitting.

---

## 9. Verilog rules and common pitfalls

- [ ] Single clock (`clk`) for everything. No derived or gated clocks.
- [ ] Reset is **active low** (`rst_n`). Reset every state register.
- [ ] Drive **every** output: `uo_out`, `uio_out` and `uio_oe`. Tie unused bits to 0.
- [ ] `uio_oe` bit = 1 means that pin is an output.
- [ ] No inferred latches: every `always @(*)` block assigns every output on every path
      (assign defaults at the top of the block).
- [ ] Use non-blocking (`<=`) in clocked blocks, blocking (`=`) in combinational blocks.
- [ ] No `initial` blocks in synthesizable code (they are ignored on the ASIC).
- [ ] Explicit widths on constants (`8'h00`, not `0`) to avoid width warnings.
- [ ] Plain Verilog-2005 is the safe default. Yosys supports some SystemVerilog,
      but check before relying on it.
- [ ] Every source file is listed in `info.yaml`.

---

## 10. Milestones

- [ ] Template repo created, unchanged template passes GitHub Actions
- [ ] Local simulation working (`make -B` passes)
- [ ] ISA and memory interface specified (sections 3.3 and 3.4 filled in)
- [ ] ALU implemented and tested
- [ ] Control FSM + registers implemented; single instructions pass
- [ ] Python assembler written; program tests pass
- [ ] Fits in target tile count with margin
- [ ] Runs on the FPGA dev kit with the RP2040 acting as memory
- [ ] `docs/info.md` written (how it works + how to test it)
- [ ] Submitted to a shuttle

---

## 11. Log

Record utilization and notable decisions here as the project progresses.

| Date | Change | Tiles | Utilization | Notes |
|------|--------|-------|-------------|-------|
|      | Template baseline | 1x1 | | |

---

## 12. Links

- Tiny Tapeout: https://tinytapeout.com
- Local hardening guide: https://tinytapeout.com/guides/local-hardening/
- Tiny Tapeout support tools: https://github.com/TinyTapeout/tt-support-tools
- GDS action: https://github.com/TinyTapeout/tt-gds-action
- cocotb docs: https://docs.cocotb.org
