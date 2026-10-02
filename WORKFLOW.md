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

## 3. Architecture (specified)

### 3.1 Style

- Accumulator-based, 8-bit data path.
- Multi-cycle control FSM (FETCH → OPERAND → EXEC), no pipelining.
- **7-bit address space (128 bytes)**. The pin budget does not allow an 8-bit
  address plus 8-bit write data plus a write-enable (17 outputs needed, 16 available).
  An 8-bit address with two-cycle multiplexed writes is a possible later extension.

### 3.2 Registers

| Register | Width | Purpose |
|----------|-------|---------|
| A        | 8     | Accumulator |
| PC       | 7     | Program counter (wraps from 0x7F to 0x00) |
| IR       | 8     | Instruction register (opcode byte) |
| MAR      | 7     | Memory address register (operand address for memory instructions) |
| Flags    | 2     | Z (zero), C (carry / borrow) |
| State    | 2     | FSM state: FETCH, OPERAND, EXEC, HALT |

About 34 flip-flops in total. Reset values: PC = 0, A = 0, Z = 0, C = 0, state = FETCH.

_(Stretch)_ B / X register, stack pointer, if area allows.

### 3.3 Memory interface (external)

Program and data memory live **off-chip**, emulated by the RP2040/RP2350 on the
Tiny Tapeout demo board. The same protocol is used by the cocotb memory model.

#### Pin assignment

| Pins           | Direction | Use |
|----------------|-----------|-----|
| `uo_out[6:0]`  | out       | ADDR[6:0], memory address |
| `uo_out[7]`    | out       | WE, write enable: 1 = this cycle is a write |
| `ui_in[7:0]`   | in        | Read data from memory |
| `uio_out[7:0]` | out       | WE = 1: write data (A). WE = 0: status byte (below) |
| `uio_oe[7:0]`  | —         | Always `8'hFF` (all bidirectional pins are outputs) |

#### Status byte (on `uio_out` when WE = 0)

| Bit | Name | Meaning |
|-----|------|---------|
| 0   | HALT | CPU has executed HLT and is stopped |
| 1   | SYNC | This cycle is an opcode fetch (useful for tracing) |
| 2   | Z    | Zero flag |
| 3   | C    | Carry / borrow flag |
| 7:4 | —    | 0 (reserved) |

#### Protocol

The microcontroller (or the cocotb testbench) **drives the clock**, so memory
always appears to answer within the same cycle. Each cycle:

1. After the rising edge, the CPU's outputs settle.
2. The memory side reads `uo_out`: ADDR and WE.
   - WE = 1: store `uio_out` into `mem[ADDR]`.
   - WE = 0: drive `mem[ADDR]` onto `ui_in`. Check status bit HALT.
3. The memory side pulses `clk`. The CPU samples `ui_in` on the rising edge.

In cocotb: `await FallingEdge(dut.clk)`, read the address, drive `ui_in`.

#### Program loading

The microcontroller fills its memory array while holding `rst_n` low, then
releases reset. The CPU starts fetching at address 0x00. When HALT is seen, results
can be read directly from the microcontroller's memory array.

Note for the real board: the demo board DIP switches also connect to `ui_in` and
likely need to be off while the RP2040 drives those pins (check the demo board docs).

### 3.4 Instruction set

#### Encoding

```
Opcode byte:   [7:4] opcode   [3] I (1 = immediate operand)   [2:0] sub-op
Operand byte:  address (bits [6:0] used) or immediate value (8 bits)
```

- Two-byte instructions: LD, ST, ADD, ADC, SUB, CMP, AND, OR, XOR, JMP, Jcc.
- One-byte instructions: NOP, unary group, HLT.
- The I bit applies to LD and the ALU instructions (ADD, ADC, SUB, CMP, AND, OR, XOR).
  I = 0: operand byte is an address, operand = M[addr]. I = 1: operand byte is the value.
- STA with I = 1 is not a valid instruction (the assembler never emits it).

#### Instructions

| Opcode | Mnemonic | Bytes | Operation | Flags | Cycles |
|--------|----------|-------|-----------|-------|--------|
| 0x0    | NOP                 | 1 | —                            | —    | 2 |
| 0x1    | LDA addr / LDI #n   | 2 | A ← operand                  | Z    | 3 / 2 |
| 0x2    | STA addr            | 2 | M[addr] ← A                  | —    | 3 |
| 0x3    | ADD addr / ADD #n   | 2 | A ← A + operand              | Z, C | 3 / 2 |
| 0x4    | ADC addr / ADC #n   | 2 | A ← A + operand + C          | Z, C | 3 / 2 |
| 0x5    | SUB addr / SUB #n   | 2 | A ← A − operand              | Z, C | 3 / 2 |
| 0x6    | CMP addr / CMP #n   | 2 | A − operand, flags only      | Z, C | 3 / 2 |
| 0x7    | AND addr / AND #n   | 2 | A ← A & operand              | Z    | 3 / 2 |
| 0x8    | OR addr / OR #n     | 2 | A ← A \| operand             | Z    | 3 / 2 |
| 0x9    | XOR addr / XOR #n   | 2 | A ← A ^ operand              | Z    | 3 / 2 |
| 0xA    | Unary group         | 1 | See sub-ops below            | see below | 2 |
| 0xB    | JMP addr            | 2 | PC ← addr                    | —    | 2 |
| 0xC    | Jcc addr            | 2 | If condition: PC ← addr      | —    | 2 |
| 0xD    | —                   |   | Reserved                     |      |   |
| 0xE    | —                   |   | Reserved (future: CALL/RET or I/O port) | |   |
| 0xF    | HLT                 | 1 | Stop until reset             | —    | — |

Cycles: "3 / 2" means memory operand / immediate operand.

#### Unary group (opcode 0xA, sub-op in bits [2:0])

| Sub-op | Mnemonic | Operation | Flags |
|--------|----------|-----------|-------|
| 000 | SHL | C ← A[7], A ← {A[6:0], 0}  | Z, C |
| 001 | SHR | C ← A[0], A ← {0, A[7:1]}  | Z, C |
| 010 | ROL | C ← A[7], A ← {A[6:0], C}  | Z, C |
| 011 | ROR | C ← A[0], A ← {C, A[7:1]}  | Z, C |
| 100 | INC | A ← A + 1                  | Z    |
| 101 | DEC | A ← A − 1                  | Z    |
| 110 | NOT | A ← ~A                     | Z    |
| 111 | CLC | C ← 0                      | C    |

#### Conditional jumps (opcode 0xC, sub-op in bits [1:0])

| Sub-op | Mnemonic | Jumps if |
|--------|----------|----------|
| 00 | JZ  | Z = 1 |
| 01 | JNZ | Z = 0 |
| 10 | JC  | C = 1 |
| 11 | JNC | C = 0 |

#### Flag conventions

- Z = 1 when the result written to A (or the CMP result) is zero.
- ADD / ADC: C = carry out of bit 7.
- SUB / CMP: C = **borrow**, i.e. bit 8 of `{1'b0, A} - {1'b0, operand}`.
  After `CMP x`, JC jumps if A < x (unsigned), JZ jumps if A = x.
- INC and DEC affect Z only, so they can be used as loop counters without touching C.
- AND, OR, XOR, NOT and LD affect Z only.

#### Control FSM

| State   | Address bus | Action |
|---------|-------------|--------|
| FETCH   | PC  | IR ← `ui_in`, PC ← PC + 1, SYNC = 1. Next: OPERAND (two-byte), EXEC (one-byte) or HALT (HLT) |
| OPERAND | PC  | PC ← PC + 1. Immediate: execute, next FETCH. JMP / taken Jcc: PC ← operand, next FETCH. Memory op: MAR ← operand, next EXEC |
| EXEC    | MAR (memory ops) / PC (one-byte ops) | Memory read: execute with `ui_in`. STA: WE = 1, write data = A. One-byte op: execute. Next: FETCH |
| HALT    | PC  | Stay until reset. Status HALT = 1 |

#### Example program

```
; 5 x 3 by repeated addition
start:  LDI #0
        STA result
loop:   LDA count      ; sets Z when count is 0
        JZ  done
        DEC
        STA count
        LDA result
        ADD x
        STA result
        JMP loop
done:   HLT

x:      .byte 5
count:  .byte 3
result: .byte 0
```

**Stretch goals (only if area allows):** stack pointer with CALL/RET, index
register, extra general-purpose register, simple interrupt, 8-bit address space
with multiplexed writes.

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

- [x] Template repo created, unchanged template passes GitHub Actions
- [x] Local simulation working (`make -B` passes)
- [x] ISA and memory interface specified (sections 3.3 and 3.4 filled in)
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
| 2026-09-30 | ISA and memory interface specified | 1x1 | | 7-bit address (128 B), MCU-driven clock, status byte on uio |

---

## 12. Links

- Tiny Tapeout: https://tinytapeout.com
- Local hardening guide: https://tinytapeout.com/guides/local-hardening/
- Tiny Tapeout support tools: https://github.com/TinyTapeout/tt-support-tools
- GDS action: https://github.com/TinyTapeout/tt-gds-action
- cocotb docs: https://docs.cocotb.org