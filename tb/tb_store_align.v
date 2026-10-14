`include "riscv_defs.vh"
// Testbench exhaustivo de store_align: todas las combinaciones de tamano y
// addr[1:0], con mem_write=1 y mem_write=0.
module tb_store_align;

  reg                   mem_write;
  reg [`MEM_SIZE_W-1:0] mem_size;
  reg [1:0]             addr_lo;
  reg [31:0]            wdata;
  wire [3:0]            byte_en;
  wire [31:0]           wdata_aligned;

  integer errors = 0;
  integer checks = 0;

  store_align dut (
      .mem_write(mem_write), .mem_size(mem_size), .addr_lo(addr_lo), .wdata(wdata),
      .byte_en(byte_en), .wdata_aligned(wdata_aligned)
  );

  task check(input [3:0] exp_be, input [31:0] exp_data, input check_data, input [8*40-1:0] name);
    begin
      #1;
      checks = checks + 1;
      if (byte_en !== exp_be) begin
        errors = errors + 1;
        $display("ERROR: [%0s] byte_en=%b esperado=%b", name, byte_en, exp_be);
      end
      if (check_data) begin
        checks = checks + 1;
        // solo importan los carriles habilitados
        if (((wdata_aligned ^ exp_data) &
             {{8{exp_be[3]}}, {8{exp_be[2]}}, {8{exp_be[1]}}, {8{exp_be[0]}}}) !== 32'd0) begin
          errors = errors + 1;
          $display("ERROR: [%0s] dato=%08h esperado=%08h (mascara %b)", name, wdata_aligned, exp_data, exp_be);
        end
      end
    end
  endtask

  initial begin
    wdata = 32'hA1B2C3D4;
    mem_write = 1;

    // ---- sb: cualquier direccion, el byte bajo de wdata va al carril elegido ----
    mem_size = `MEM_BYTE;
    addr_lo = 2'd0; check(4'b0001, 32'h000000D4, 1, "sb offset 0");
    addr_lo = 2'd1; check(4'b0010, 32'h0000D400, 1, "sb offset 1");
    addr_lo = 2'd2; check(4'b0100, 32'h00D40000, 1, "sb offset 2");
    addr_lo = 2'd3; check(4'b1000, 32'hD4000000, 1, "sb offset 3");

    // ---- sh: alineado en 0 o 2; impar se ignora ----
    mem_size = `MEM_HALF;
    addr_lo = 2'd0; check(4'b0011, 32'h0000C3D4, 1, "sh offset 0");
    addr_lo = 2'd2; check(4'b1100, 32'hC3D40000, 1, "sh offset 2");
    addr_lo = 2'd1; check(4'b0000, 32'h0, 0, "sh desalineado (1) no escribe");
    addr_lo = 2'd3; check(4'b0000, 32'h0, 0, "sh desalineado (3) no escribe");

    // ---- sw: solo offset 0 ----
    mem_size = `MEM_WORD;
    addr_lo = 2'd0; check(4'b1111, 32'hA1B2C3D4, 1, "sw offset 0");
    addr_lo = 2'd1; check(4'b0000, 32'h0, 0, "sw desalineado (1) no escribe");
    addr_lo = 2'd2; check(4'b0000, 32'h0, 0, "sw desalineado (2) no escribe");
    addr_lo = 2'd3; check(4'b0000, 32'h0, 0, "sw desalineado (3) no escribe");

    // ---- mem_write = 0: nunca escribe ----
    mem_write = 0;
    mem_size = `MEM_WORD; addr_lo = 2'd0; check(4'b0000, 32'h0, 0, "mem_write=0 (sw)");
    mem_size = `MEM_BYTE; addr_lo = 2'd1; check(4'b0000, 32'h0, 0, "mem_write=0 (sb)");
    mem_size = `MEM_HALF; addr_lo = 2'd2; check(4'b0000, 32'h0, 0, "mem_write=0 (sh)");

    if (errors == 0)
      $display("STORE_ALIGN_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("STORE_ALIGN_TB: %0d errores en %0d checks", errors, checks);
    $finish;
  end

endmodule