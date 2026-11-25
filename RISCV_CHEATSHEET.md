# RISC-V (RV32I) Crash Course & Instruction Cheat Sheet

A practical guide to how a RISC-V CPU works from the ground up, how its registers and calling conventions are organized, and every instruction in the base 32-bit integer ISA (**RV32I**) plus common pseudo-instructions and extensions.

---

## Part 1: High-Level Crash Course — How a RISC-V CPU Works

### 1. The Load-Store Philosophy
RISC-V is a **Load-Store Architecture**. Unlike x86 (where a single instruction can read memory, add a register to it, and write the result back to memory), RISC-V strictly separates operations into two categories:
1. **Memory Access (`LW`, `SW`, etc.):** Only copies data between RAM and the 32 internal registers.
2. **Compute & Control (`ADD`, `XOR`, `BEQ`, etc.):** Operates *exclusively* on the 32 internal registers and immediate constants encoded inside the instruction.

### 2. The 5 Phases of Executing an Instruction
In our single-cycle processor (`rv32i_cpu.v`), all five phases happen within a single clock cycle as signals propagate through combinational logic before the next rising clock edge (`posedge clk`):

1. **Instruction Fetch (IF):**
   The Program Counter (`PC`) holds the 32-bit byte address of the current instruction. Instruction memory outputs the 32-bit word `instr` at `mem[PC]`.
2. **Instruction Decode & Register Read (ID):**
   Fixed slices of `instr` select source registers `rs1` (`instr[19:15]`) and `rs2` (`instr[24:20]`), while the Immediate Generator extracts and sign-extends constants embedded in the instruction.
3. **Execute / Address Calculation (EX):**
   The Arithmetic Logic Unit (ALU) either computes a math/logic result (e.g., `rs1 + rs2`), evaluates a branch condition (e.g., `rs1 == rs2`), or adds `rs1 + offset` to compute a memory address.
4. **Memory Access (MEM):**
   If the instruction is a Load (`LW`, `LB`, etc.) or Store (`SW`, `SB`, etc.), data memory is read from or written to at the address calculated by the ALU.
5. **Writeback (WB):**
   On the rising clock edge, the destination register `rd` (`instr[11:7]`) is updated with the result (from the ALU, memory, or `PC + 4` for jumps), and `PC` advances to `PC + 4` (or the branch/jump target).

---

## Part 2: Register Layout & ABI Calling Convention

RV32I has **32 general-purpose registers** (`x0` through `x31`), each 32 bits wide, plus the **Program Counter (`pc`)**.

* **`x0` (`zero`) is hardwired to `0`.** Reading it always yields `0`; writing to it discards the result. This single hardware trick eliminates the need for special `NOP`, `MOV`, `CLR`, or `CMP` instructions!
* While the hardware treats `x1`–`x31` identically, software follows the **Application Binary Interface (ABI)** convention so functions compiled by different tools can call each other safely:
  * **Caller-Saved (Temporary):** The calling function must save these on the stack if it still needs their values after calling a subroutine (`jal`).
  * **Callee-Saved (Preserved):** A called subroutine must restore these to their original values before returning (`ret`).

| Register | ABI Name | Role / Description | Saver |
| :--- | :--- | :--- | :--- |
| `x0` | `zero` | Hardwired constant `0` (writes are ignored) | — |
| `x1` | `ra` | **Return Address** — stores where a function call (`jal`) should return | Caller |
| `x2` | `sp` | **Stack Pointer** — points to the top of the downward-growing stack | Callee |
| `x3` | `gp` | **Global Pointer** — base address for accessing global variables quickly | — |
| `x4` | `tp` | **Thread Pointer** — points to thread-local storage | — |
| `x5`–`x7` | `t0`–`t2` | **Temporaries** — scratch registers any function can clobber freely | Caller |
| `x8` | `s0` / `fp` | **Saved register 0 / Frame Pointer** — optional base of current stack frame | Callee |
| `x9` | `s1` | **Saved register 1** — preserved across function calls | Callee |
| `x10`–`x11` | `a0`–`a1` | **Function Arguments 0–1 & Return Values** (`a0` holds the primary return value) | Caller |
| `x12`–`x17` | `a2`–`a7` | **Function Arguments 2–7** | Caller |
| `x18`–`x27` | `s2`–`s11` | **Saved registers 2–11** — preserved across function calls | Callee |
| `x28`–`x31` | `t3`–`t6` | **Temporaries 3–6** — extra scratch registers | Caller |
| `pc` | `pc` | **Program Counter** — address of current instruction (not directly addressable as `xN`) | — |

---

## Part 3: Instruction Encoding Formats

Every base RV32I instruction is **32 bits (4 bytes) wide** and aligned to a 4-byte boundary. Notice how `opcode`, `rd`, `funct3`, `rs1`, and `rs2` never move, and `instr[31]` is always the sign bit:

```text
 31          25 24     20 19     15 14  12 11          7 6            0
+--------------+---------+---------+------+-------------+--------------+
|    funct7    |   rs2   |   rs1   |funct3|     rd      |    opcode    |  R-type (Register-Register ALU)
+--------------+---------+---------+------+-------------+--------------+
|         imm[11:0]      |   rs1   |funct3|     rd      |    opcode    |  I-type (ALU Imm, Loads, JALR)
+--------------+---------+---------+------+-------------+--------------+
|  imm[11:5]   |   rs2   |   rs1   |funct3|  imm[4:0]   |    opcode    |  S-type (Stores)
+--------------+---------+---------+------+-------------+--------------+
| imm[12|10:5] |   rs2   |   rs1   |funct3| imm[4:1|11] |    opcode    |  B-type (Conditional Branches)
+--------------+---------+---------+------+-------------+--------------+
|                imm[31:12]               |     rd      |    opcode    |  U-type (Upper Immediate: LUI/AUIPC)
+-----------------------------------------+-------------+--------------+
|         imm[20|10:1|11|19:12]           |     rd      |    opcode    |  J-type (Unconditional Jump: JAL)
+-----------------------------------------+-------------+--------------+
```

*Note on `B-type` and `J-type` immediates:* Because instructions are at least 2-byte (or 4-byte) aligned, bit 0 of a branch or jump offset is *always `0`* and is not stored in the instruction—giving branches and jumps double the reach!

---

## Part 4: Complete RV32I Base Instruction Set (All 40 Instructions)

In the tables below:
* `sext(x)` = sign-extend `x` to 32 bits
* `zext(x)` = zero-extend `x` to 32 bits
* `<s` / `>=s` = signed 32-bit two's-complement comparison
* `<u` / `>=u` = unsigned 32-bit comparison

### 1. Upper Immediate Instructions (U-Type)
Used to construct 32-bit constants or PC-relative addresses (paired with `ADDI`, `LW`, `JALR`, etc.).

| Instruction | Syntax | Operation | Opcode | Description |
| :--- | :--- | :--- | :--- | :--- |
| **LUI** | `lui rd, imm20` | `rd = imm20 << 12` | `0110111` | Load Upper Immediate (places 20 bits into `[31:12]`, zeroes `[11:0]`) |
| **AUIPC** | `auipc rd, imm20` | `rd = pc + (imm20 << 12)` | `0010111` | Add Upper Immediate to PC (for position-independent code) |

### 2. Unconditional Jumps (J-Type & I-Type)
Used for function calls (`jal`), returns (`jalr`), and long jumps.

| Instruction | Syntax | Operation | Opcode | funct3 | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **JAL** | `jal rd, offset` | `rd = pc + 4; pc = pc + sext(offset)` | `1101111` | — | Jump and Link (` ±1 MB ` range) |
| **JALR** | `jalr rd, offset(rs1)` | `t = pc + 4; pc = (rs1 + sext(offset)) & ~1; rd = t` | `1100111` | `000` | Jump and Link Register (indirect jump/call/return) |

### 3. Conditional Branches (B-Type, Opcode `1100011`)
Compares two registers directly and jumps within a `±4 KB` range if true.

| Instruction | Syntax | Condition (`pc += sext(offset)`) | funct3 | Description |
| :--- | :--- | :--- | :--- | :--- |
| **BEQ** | `beq rs1, rs2, label` | `rs1 == rs2` | `000` | Branch if Equal |
| **BNE** | `bne rs1, rs2, label` | `rs1 != rs2` | `001` | Branch if Not Equal |
| **BLT** | `blt rs1, rs2, label` | `rs1 <s rs2` | `100` | Branch if Less Than (Signed) |
| **BGE** | `bge rs1, rs2, label` | `rs1 >=s rs2` | `101` | Branch if Greater or Equal (Signed) |
| **BLTU** | `bltu rs1, rs2, label` | `rs1 <u rs2` | `110` | Branch if Less Than (Unsigned) |
| **BGEU** | `bgeu rs1, rs2, label` | `rs1 >=u rs2` | `111` | Branch if Greater or Equal (Unsigned) |

### 4. Memory Loads (I-Type, Opcode `0000011`)
Reads memory at byte address `rs1 + sext(imm12)` and writes to `rd`.

| Instruction | Syntax | Operation | funct3 | Description |
| :--- | :--- | :--- | :--- | :--- |
| **LB** | `lb rd, offset(rs1)` | `rd = sext(MEM[rs1 + sext(offset)][7:0])` | `000` | Load Byte (8-bit, sign-extended) |
| **LH** | `lh rd, offset(rs1)` | `rd = sext(MEM[rs1 + sext(offset)][15:0])` | `001` | Load Halfword (16-bit, sign-extended) |
| **LW** | `lw rd, offset(rs1)` | `rd = MEM[rs1 + sext(offset)][31:0]` | `010` | Load Word (32-bit) |
| **LBU** | `lbu rd, offset(rs1)` | `rd = zext(MEM[rs1 + sext(offset)][7:0])` | `100` | Load Byte Unsigned (8-bit, zero-extended) |
| **LHU** | `lhu rd, offset(rs1)` | `rd = zext(MEM[rs1 + sext(offset)][15:0])` | `101` | Load Halfword Unsigned (16-bit, zero-extended) |

### 5. Memory Stores (S-Type, Opcode `0100011`)
Writes the low byte/halfword/word of `rs2` to memory at `rs1 + sext(imm12)`.

| Instruction | Syntax | Operation | funct3 | Description |
| :--- | :--- | :--- | :--- | :--- |
| **SB** | `sb rs2, offset(rs1)` | `MEM[rs1 + sext(offset)][7:0] = rs2[7:0]` | `000` | Store Byte (lowest 8 bits) |
| **SH** | `sh rs2, offset(rs1)` | `MEM[rs1 + sext(offset)][15:0] = rs2[15:0]` | `001` | Store Halfword (lowest 16 bits) |
| **SW** | `sw rs2, offset(rs1)` | `MEM[rs1 + sext(offset)][31:0] = rs2[31:0]` | `010` | Store Word (all 32 bits) |

### 6. Register-Immediate ALU Operations (I-Type, Opcode `0010011`)
Performs arithmetic or bitwise operations with a 12-bit sign-extended immediate (`-2048` to `+2047`).

| Instruction | Syntax | Operation | funct3 | funct7 | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ADDI** | `addi rd, rs1, imm12` | `rd = rs1 + sext(imm12)` | `000` | — | Add Immediate (no `subi` needed; use negative `imm12`) |
| **SLTI** | `slti rd, rs1, imm12` | `rd = (rs1 <s sext(imm12)) ? 1 : 0` | `010` | — | Set Less Than Immediate (Signed) |
| **SLTIU** | `sltiu rd, rs1, imm12` | `rd = (rs1 <u sext(imm12)) ? 1 : 0` | `011` | — | Set Less Than Immediate (Unsigned) |
| **XORI** | `xori rd, rs1, imm12` | `rd = rs1 ^ sext(imm12)` | `100` | — | Bitwise XOR Immediate |
| **ORI** | `ori rd, rs1, imm12` | `rd = rs1 \| sext(imm12)` | `110` | — | Bitwise OR Immediate |
| **ANDI** | `andi rd, rs1, imm12` | `rd = rs1 & sext(imm12)` | `111` | — | Bitwise AND Immediate |
| **SLLI** | `slli rd, rs1, shamt` | `rd = rs1 << shamt` | `001` | `0000000` | Shift Left Logical Immediate (`shamt` = 0..31) |
| **SRLI** | `srli rd, rs1, shamt` | `rd = rs1 >>u shamt` | `101` | `0000000` | Shift Right Logical Immediate (zero-fill) |
| **SRAI** | `srai rd, rs1, shamt` | `rd = rs1 >>s shamt` | `101` | `0100000` | Shift Right Arithmetic Immediate (sign-bit fill) |

### 7. Register-Register ALU Operations (R-Type, Opcode `0110011`)
Performs arithmetic or bitwise operations between `rs1` and `rs2`.

| Instruction | Syntax | Operation | funct3 | funct7 | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ADD** | `add rd, rs1, rs2` | `rd = rs1 + rs2` | `000` | `0000000` | Add registers |
| **SUB** | `sub rd, rs1, rs2` | `rd = rs1 - rs2` | `000` | `0100000` | Subtract `rs2` from `rs1` |
| **SLL** | `sll rd, rs1, rs2` | `rd = rs1 << rs2[4:0]` | `001` | `0000000` | Shift Left Logical by `rs2[4:0]` |
| **SLT** | `slt rd, rs1, rs2` | `rd = (rs1 <s rs2) ? 1 : 0` | `010` | `0000000` | Set Less Than (Signed) |
| **SLTU** | `sltu rd, rs1, rs2` | `rd = (rs1 <u rs2) ? 1 : 0` | `011` | `0000000` | Set Less Than (Unsigned) |
| **XOR** | `xor rd, rs1, rs2` | `rd = rs1 ^ rs2` | `100` | `0000000` | Bitwise XOR |
| **SRL** | `srl rd, rs1, rs2` | `rd = rs1 >>u rs2[4:0]` | `101` | `0000000` | Shift Right Logical (zero-fill) |
| **SRA** | `sra rd, rs1, rs2` | `rd = rs1 >>s rs2[4:0]` | `101` | `0100000` | Shift Right Arithmetic (sign-bit fill) |
| **OR** | `or rd, rs1, rs2` | `rd = rs1 \| rs2` | `110` | `0000000` | Bitwise OR |
| **AND** | `and rd, rs1, rs2` | `rd = rs1 & rs2` | `111` | `0000000` | Bitwise AND |

### 8. Memory Ordering & System Instructions

| Instruction | Syntax | Encoding / Opcode | Description |
| :--- | :--- | :--- | :--- |
| **FENCE** | `fence` | Opcode `0001111` | Orders device I/O and memory accesses across cores/threads |
| **ECALL** | `ecall` | `0x00000073` (`1110011`) | Environment Call (system call into OS / trap handler) |
| **EBREAK** | `ebreak` | `0x00100073` (`1110011`) | Environment Breakpoint (transfers control to debugger / halts sim) |

---

## Part 5: Essential Pseudo-Instructions

When you write or read RISC-V assembly, you will often see instructions like `mv`, `li`, `ret`, or `ble`. These are **pseudo-instructions**—shorthand aliases that the assembler translates directly into one or two of the 40 real hardware instructions above!

| Pseudo-Instruction | Expands To (Real RV32I) | Meaning |
| :--- | :--- | :--- |
| `nop` | `addi x0, x0, 0` | No Operation |
| `mv rd, rs` | `addi rd, rs, 0` | Copy register `rs` to `rd` |
| `not rd, rs` | `xori rd, rs, -1` | Bitwise NOT (one's complement) |
| `neg rd, rs` | `sub rd, x0, rs` | Arithmetic negate (`0 - rs`) |
| `seqz rd, rs` | `sltiu rd, rs, 1` | Set `rd = 1` if `rs == 0`, else `0` |
| `snez rd, rs` | `sltu rd, x0, rs` | Set `rd = 1` if `rs != 0`, else `0` |
| `li rd, imm` | `addi` (small) or `lui` + `addi` (32-bit) | Load arbitrary 32-bit constant into `rd` |
| `la rd, symbol` | `auipc rd, hi` + `addi rd, rd, lo` | Load PC-relative address of `symbol` |
| `j label` | `jal x0, label` | Unconditional jump (discard return address) |
| `jr rs` | `jalr x0, 0(rs)` | Jump to address in register `rs` |
| `call func` | `auipc ra, hi` + `jalr ra, lo(ra)` | Call function `func` and save return address in `ra` |
| `ret` | `jalr x0, 0(ra)` | Return from function using `ra` (`x1`) |
| `beqz rs, label` | `beq rs, x0, label` | Branch if `rs == 0` |
| `bnez rs, label` | `bne rs, x0, label` | Branch if `rs != 0` |
| `bgt rs1, rs2, label` | `blt rs2, rs1, label` | Branch if `rs1 > rs2` (swaps operands!) |
| `ble rs1, rs2, label` | `bge rs2, rs1, label` | Branch if `rs1 <= rs2` (swaps operands!) |

---

## Part 6: Common Standard Extensions (Beyond RV32I)

RISC-V is modular: every chip implements the base integer ISA (`I`) and adds single-letter extensions as needed. For example, **`RV64GC`** (the standard profile for Linux application processors) is shorthand for **`RV64IMAFDC_Zicsr_Zifencei`**:

| Extension | Name | Key Instructions Added |
| :--- | :--- | :--- |
| **M** | Integer Multiply / Divide | `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU` |
| **A** | Atomic Memory Operations | `LR.W` (Load-Reserved), `SC.W` (Store-Conditional), `AMOSWAP.W`, `AMOADD.W`, ... |
| **F** / **D** | Single / Double Float | `f0`–`f31` registers, `FLW`/`FSW`, `FADD.S`, `FMUL.S`, `FMADD.S`, ... |
| **C** | Compressed (16-bit) | 16-bit encodings for the most common instructions (`C.LW`, `C.ADDI`, `C.JAL`, ...) to shrink code size by ~25–30% |
| **Zicsr** | Control & Status Registers | `CSRRW`, `CSRRS`, `CSRRC` (reads/writes cycle counters, trap vectors, privilege state) |
| **V** | Vector Operations | SIMD / vector length-agnostic processing (`v0`–`v31`) |
