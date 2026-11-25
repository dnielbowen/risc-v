// ============================================================================
// Minimal, Instructive Single-Cycle RV32I RISC-V Processor
// ============================================================================
// Implements the complete unprivileged RV32I Base Integer Instruction Set:
//   - LUI, AUIPC
//   - JAL, JALR
//   - BEQ, BNE, BLT, BGE, BLTU, BGEU
//   - LB, LH, LW, LBU, LHU
//   - SB, SH, SW
//   - ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
//   - ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
//   - FENCE (NOP in single-cycle), ECALL / EBREAK (halt signal)
// ============================================================================

`timescale 1ns / 1ps

module rv32i_cpu (
    input  wire        clk,
    input  wire        rst,

    // Instruction Memory Interface
    output reg  [31:0] pc,
    input  wire [31:0] instr,

    // Data Memory Interface
    output wire [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg  [ 3:0] dmem_wstrb,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata,

    // Status
    output reg         halted
);

    // ------------------------------------------------------------------------
    // 1. Instruction Field Extraction
    //    RISC-V keeps source/destination register fields in fixed bit positions
    //    across all instruction formats!
    // ------------------------------------------------------------------------
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] funct7 = instr[31:25];

    // Major RV32I Opcodes
    localparam OP_LUI    = 7'b0110111; // Load Upper Immediate
    localparam OP_AUIPC  = 7'b0010111; // Add Upper Immediate to PC
    localparam OP_JAL    = 7'b1101111; // Jump and Link
    localparam OP_JALR   = 7'b1100111; // Jump and Link Register
    localparam OP_BRANCH = 7'b1100011; // Conditional Branches
    localparam OP_LOAD   = 7'b0000011; // Memory Loads
    localparam OP_STORE  = 7'b0100011; // Memory Stores
    localparam OP_IMM    = 7'b0010011; // Register-Immediate ALU ops
    localparam OP_REG    = 7'b0110011; // Register-Register ALU ops
    localparam OP_FENCE  = 7'b0001111; // Memory ordering (NOP here)
    localparam OP_SYSTEM = 7'b1110011; // ECALL / EBREAK

    // ------------------------------------------------------------------------
    // 2. Immediate Generator (Sign-Extended to 32 bits)
    //    Notice how instr[31] is always the sign bit in every format.
    // ------------------------------------------------------------------------
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // ------------------------------------------------------------------------
    // 3. Register File (32 x 32-bit registers; x0 is hardwired to 0)
    // ------------------------------------------------------------------------
    reg [31:0] regs [0:31];

    wire [31:0] rs1_val = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    wire [31:0] rs2_val = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    // ------------------------------------------------------------------------
    // 4. Arithmetic Logic Unit (ALU)
    //    Shared between OP_REG and OP_IMM instructions.
    // ------------------------------------------------------------------------
    wire [31:0] alu_a = rs1_val;
    wire [31:0] alu_b = (opcode == OP_REG) ? rs2_val : imm_i;

    // SUB vs ADD and SRA vs SRL are distinguished by instr[30] (funct7[5])
    wire is_sub = (opcode == OP_REG) && instr[30];
    wire is_sra = instr[30];

    reg [31:0] alu_out;
    always @(*) begin
        case (funct3)
            3'b000: alu_out = is_sub ? (alu_a - alu_b) : (alu_a + alu_b);                   // ADD / SUB / ADDI
            3'b001: alu_out = alu_a << alu_b[4:0];                                          // SLL / SLLI
            3'b010: alu_out = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;            // SLT / SLTI (signed)
            3'b011: alu_out = (alu_a < alu_b) ? 32'd1 : 32'd0;                              // SLTU / SLTIU (unsigned)
            3'b100: alu_out = alu_a ^ alu_b;                                                // XOR / XORI
            3'b101: alu_out = is_sra ? ($signed(alu_a) >>> alu_b[4:0]) : (alu_a >> alu_b[4:0]); // SRL / SRA / SRLI / SRAI
            3'b110: alu_out = alu_a | alu_b;                                                // OR / ORI
            3'b111: alu_out = alu_a & alu_b;                                                // AND / ANDI
        endcase
    end

    // ------------------------------------------------------------------------
    // 5. Branch Comparator
    // ------------------------------------------------------------------------
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000: branch_taken = (rs1_val == rs2_val);                   // BEQ
            3'b001: branch_taken = (rs1_val != rs2_val);                   // BNE
            3'b100: branch_taken = ($signed(rs1_val) <  $signed(rs2_val)); // BLT
            3'b101: branch_taken = ($signed(rs1_val) >= $signed(rs2_val)); // BGE
            3'b110: branch_taken = (rs1_val <  rs2_val);                   // BLTU
            3'b111: branch_taken = (rs1_val >= rs2_val);                   // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // 6. Load / Store Unit (Byte, Halfword, Word alignment & sign-extension)
    // ------------------------------------------------------------------------
    assign dmem_addr = rs1_val + ((opcode == OP_STORE) ? imm_s : imm_i);
    assign dmem_re   = (opcode == OP_LOAD);
    wire [1:0] byte_offset = dmem_addr[1:0];

    // Store steering: shift rs2 data and generate byte write strobes
    always @(*) begin
        dmem_wstrb = 4'b0000;
        dmem_wdata = 32'd0;
        if (opcode == OP_STORE) begin
            case (funct3)
                3'b000: begin // SB (Store Byte)
                    dmem_wstrb = 4'b0001 << byte_offset;
                    dmem_wdata = {4{rs2_val[7:0]}};
                end
                3'b001: begin // SH (Store Halfword)
                    dmem_wstrb = byte_offset[1] ? 4'b1100 : 4'b0011;
                    dmem_wdata = {2{rs2_val[15:0]}};
                end
                3'b010: begin // SW (Store Word)
                    dmem_wstrb = 4'b1111;
                    dmem_wdata = rs2_val;
                end
                default: begin
                    dmem_wstrb = 4'b0000;
                    dmem_wdata = 32'd0;
                end
            endcase
        end
    end

    // Load extraction: select byte/halfword/word and sign/zero extend
    wire [ 7:0] load_byte = (dmem_rdata >> (byte_offset * 8)) & 8'hFF;
    wire [15:0] load_half = byte_offset[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

    reg [31:0] load_val;
    always @(*) begin
        case (funct3)
            3'b000: load_val = {{24{load_byte[7]}}, load_byte};  // LB  (sign-extended)
            3'b001: load_val = {{16{load_half[15]}}, load_half}; // LH  (sign-extended)
            3'b010: load_val = dmem_rdata;                       // LW  (full word)
            3'b100: load_val = {24'd0, load_byte};               // LBU (zero-extended)
            3'b101: load_val = {16'd0, load_half};               // LHU (zero-extended)
            default: load_val = dmem_rdata;
        endcase
    end

    // ------------------------------------------------------------------------
    // 7. Writeback Multiplexer & Next PC Logic
    // ------------------------------------------------------------------------
    wire [31:0] pc_plus_4 = pc + 32'd4;

    wire reg_we = (opcode == OP_LUI)   || (opcode == OP_AUIPC) ||
                  (opcode == OP_JAL)   || (opcode == OP_JALR)  ||
                  (opcode == OP_LOAD)  || (opcode == OP_IMM)   ||
                  (opcode == OP_REG);

    reg [31:0] wb_data;
    always @(*) begin
        case (opcode)
            OP_LUI:   wb_data = imm_u;
            OP_AUIPC: wb_data = pc + imm_u;
            OP_JAL,
            OP_JALR:  wb_data = pc_plus_4;
            OP_LOAD:  wb_data = load_val;
            default:  wb_data = alu_out; // OP_IMM, OP_REG
        endcase
    end

    wire [31:0] next_pc =
        (opcode == OP_JAL)                       ? (pc + imm_j) :
        (opcode == OP_JALR)                      ? ((rs1_val + imm_i) & ~32'd1) :
        ((opcode == OP_BRANCH) && branch_taken)  ? (pc + imm_b) :
                                                   pc_plus_4;

    // ------------------------------------------------------------------------
    // 8. Sequential State Update (PC and Register File)
    // ------------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            pc     <= 32'h0000_0000;
            halted <= 1'b0;
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (!halted) begin
            if (opcode == OP_SYSTEM) begin
                halted <= 1'b1; // Halt on ECALL / EBREAK
            end else begin
                pc <= next_pc;
                if (reg_we && (rd != 5'd0))
                    regs[rd] <= wb_data;
            end
        end
    end

endmodule
