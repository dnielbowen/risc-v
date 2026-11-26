// ============================================================================
// Testbench & SoC Wrapper for rv32i_cpu
// ============================================================================
// Provides:
//   - 64 KB unified RAM (loaded from firmware.hex)
//   - Memory-mapped UART TX at 0x1000_0000 (prints characters to console)
//   - Memory-mapped Result/Debug port at 0x1000_0004
//   - Optional instruction-by-instruction trace (+trace)
//   - VCD waveform generation (rv32i_wave.vcd)
// ============================================================================

`timescale 1ns / 1ps

module tb_rv32i;

    reg clk = 1'b0;
    reg rst = 1'b1;

    always #5 clk = ~clk; // 100 MHz simulation clock

    wire [31:0] pc;
    wire [31:0] instr;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [ 3:0] dmem_wstrb;
    wire        dmem_re;
    wire [31:0] dmem_rdata;
    wire        halted;

    // Instantiate RV32I CPU
    rv32i_cpu uut (
        .clk        (clk),
        .rst        (rst),
        .pc         (pc),
        .instr      (instr),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_wstrb (dmem_wstrb),
        .dmem_re    (dmem_re),
        .dmem_rdata (dmem_rdata),
        .halted     (halted)
    );

    // 64 KB Unified Memory (16,384 x 32-bit words)
    localparam MEM_WORDS = 16384;
    reg [31:0] mem [0:MEM_WORDS-1];

    // Instruction Fetch (Combinational read for single-cycle execution)
    assign instr = mem[pc[15:2]];

    // Data Read (Combinational read from RAM)
    wire is_ram_addr = (dmem_addr < 32'h0001_0000);
    assign dmem_rdata = is_ram_addr ? mem[dmem_addr[15:2]] : 32'd0;

    // Data Write & Memory-Mapped I/O
    integer cycle_count = 0;
    reg trace_en = 1'b0;

    always @(posedge clk) begin
        if (!rst && !halted) begin
            cycle_count <= cycle_count + 1;

            if (trace_en) begin
                $display("[cycle %04d] PC=0x%08x | INSTR=0x%08x | x10(a0)=0x%08x",
                         cycle_count, pc, instr, uut.regs[10]);
            end

            // Memory Write Handling
            if (|dmem_wstrb) begin
                if (dmem_addr == 32'h1000_0000) begin
                    // Virtual UART TX: print lowest byte to stdout
                    if (trace_en) begin
                      $write("UART: %c\n", dmem_wdata[7:0]);
                    end else begin
                      $write("%c", dmem_wdata[7:0]);
                    end
                    $fflush();
                end else if (dmem_addr == 32'h1000_0004) begin
                    $display("\n[MMIO Debug] CPU wrote 0x%08x (%0d) to 0x1000_0004",
                             dmem_wdata, $signed(dmem_wdata));
                end else if (is_ram_addr) begin
                    if (dmem_wstrb[0]) mem[dmem_addr[15:2]][ 7: 0] <= dmem_wdata[ 7: 0];
                    if (dmem_wstrb[1]) mem[dmem_addr[15:2]][15: 8] <= dmem_wdata[15: 8];
                    if (dmem_wstrb[2]) mem[dmem_addr[15:2]][23:16] <= dmem_wdata[23:16];
                    if (dmem_wstrb[3]) mem[dmem_addr[15:2]][31:24] <= dmem_wdata[31:24];
                end
            end
        end
    end

    integer idx;
    reg [1023:0] hex_file;

    initial begin
        if ($test$plusargs("trace"))
            trace_en = 1'b1;

        if (!$value$plusargs("firmware=%s", hex_file))
            hex_file = "firmware.hex";

        // Initialize memory to zero, then load firmware
        for (idx = 0; idx < MEM_WORDS; idx = idx + 1)
            mem[idx] = 32'h0000_0000;

        $readmemh(hex_file, mem);

        $dumpfile("rv32i_wave.vcd");
        $dumpvars(0, tb_rv32i);

        $display("==============================================================");
        $display(" Starting RV32I Verilog Simulation (Icarus Verilog)");
        $display("==============================================================");

        #20 rst = 1'b0;

        // Wait until CPU executes ECALL/EBREAK or timeout
        while (!halted && cycle_count < 100000) begin
            @(posedge clk);
        end

        $display("--------------------------------------------------------------");
        if (halted) begin
            $display(" CPU Halted cleanly on SYSTEM instruction at PC = 0x%08x", pc);
        end else begin
            $display(" WARNING: Simulation timed out after %0d cycles!", cycle_count);
        end
        $display(" Total clock cycles executed : %0d", cycle_count);
        $display(" Return value in x10 (a0)    : 0x%08x (%0d)", uut.regs[10], $signed(uut.regs[10]));
        $display(" Stack pointer x2 (sp)       : 0x%08x", uut.regs[2]);
        $display("==============================================================");
        $finish;
    end

endmodule
