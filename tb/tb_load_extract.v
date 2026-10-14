`include "riscv_defs.vh"
// Testbench exhaustivo de load_extract: lb/lbu/lh/lhu/lw en todos los offsets.
module tb_load_extract;

  reg                   mem_read;
  reg [`MEM_SIZE_W-1:0] mem_size;
  reg                   mem_unsigned;
  reg [1:0]             addr_lo;
  reg [31:0]            word;
  wire [31:0]           rdata;

  integer errors = 0;
  integer checks = 0;

  load_extract dut (
      .mem_read(mem_read), .mem_size(mem_size), .mem_unsigned(mem_unsigned),
      .addr_lo(addr_lo), .word(word), .rdata(rdata)
  );

  task check(input [31:0] exp, input [8*40-1:0] name);
    begin
      #1;
      checks = checks + 1;
      if (rdata !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] rdata=%08h esperado=%08h", name, rdata, exp);
      end
    end
  endtask

  initial begin
    // bytes 0..3 = 0x80, 0x7F, 0xC0, 0x01  (negativo, positivo, negativo, positivo)
    word = 32'h01C07F80;
    mem_read = 1;

    // ---- lb (con signo) ----
    mem_size = `MEM_BYTE; mem_unsigned = 0;
    addr_lo = 2'd0; check(32'hFFFFFF80, "lb offset 0 (0x80 -> negativo)");
    addr_lo = 2'd1; check(32'h0000007F, "lb offset 1 (0x7F)");
    addr_lo = 2'd2; check(32'hFFFFFFC0, "lb offset 2 (0xC0 -> negativo)");
    addr_lo = 2'd3; check(32'h00000001, "lb offset 3 (0x01)");

    // ---- lbu (sin signo) ----
    mem_unsigned = 1;
    addr_lo = 2'd0; check(32'h00000080, "lbu offset 0");
    addr_lo = 2'd1; check(32'h0000007F, "lbu offset 1");
    addr_lo = 2'd2; check(32'h000000C0, "lbu offset 2");
    addr_lo = 2'd3; check(32'h00000001, "lbu offset 3");

    // halfwords: bajo = 0x7F80 (positivo), alto = 0x01C0 (positivo); cambio para probar signo
    word = 32'h8001_F234;   // bajo = 0xF234 (negativo), alto = 0x8001 (negativo)

    // ---- lh (con signo) ----
    mem_size = `MEM_HALF; mem_unsigned = 0;
    addr_lo = 2'd0; check(32'hFFFFF234, "lh offset 0 (negativo)");
    addr_lo = 2'd2; check(32'hFFFF8001, "lh offset 2 (negativo)");
    addr_lo = 2'd1; check(32'h0,        "lh desalineado (1) da 0");
    addr_lo = 2'd3; check(32'h0,        "lh desalineado (3) da 0");

    // ---- lhu (sin signo) ----
    mem_unsigned = 1;
    addr_lo = 2'd0; check(32'h0000F234, "lhu offset 0");
    addr_lo = 2'd2; check(32'h00008001, "lhu offset 2");
    addr_lo = 2'd1; check(32'h0,        "lhu desalineado (1) da 0");

    // ---- lw ----
    mem_size = `MEM_WORD; mem_unsigned = 0;
    addr_lo = 2'd0; check(32'h8001F234, "lw offset 0");
    addr_lo = 2'd1; check(32'h0,        "lw desalineado (1) da 0");
    addr_lo = 2'd2; check(32'h0,        "lw desalineado (2) da 0");
    addr_lo = 2'd3; check(32'h0,        "lw desalineado (3) da 0");

    // ---- mem_read = 0 (la instruccion en WB no es un load): siempre 0 ----
    mem_read = 0;
    mem_size = `MEM_WORD; addr_lo = 2'd0; check(32'h0, "mem_read=0 (lw)");
    mem_size = `MEM_BYTE; addr_lo = 2'd1; check(32'h0, "mem_read=0 (lb)");

    if (errors == 0)
      $display("LOAD_EXTRACT_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("LOAD_EXTRACT_TB: %0d errores en %0d checks", errors, checks);
    $finish;
  end

endmodule