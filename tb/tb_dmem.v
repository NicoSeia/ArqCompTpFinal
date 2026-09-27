`include "riscv_defs.vh"
module tb_dmem;

  reg                     clk = 0;
  reg                     mem_read, mem_write, mem_unsigned;
  reg  [`MEM_SIZE_W-1:0]  mem_size;
  reg  [`DMEM_ADDR_W-1:0] addr;
  reg  [`XLEN-1:0]        wdata;
  wire [`XLEN-1:0]        rdata;
  reg  [`DMEM_ADDR_W-1:0] debug_addr;
  wire [7:0]              debug_data;

  integer errors = 0;
  integer checks = 0;

  // Verilog no tiene .* : puertos explicitos. enable=1 (era el default en SV).
  dmem dut (
      .clk(clk), .enable(1'b1), .mem_read(mem_read), .mem_write(mem_write),
      .mem_size(mem_size), .mem_unsigned(mem_unsigned), .addr(addr), .wdata(wdata),
      .debug_addr(debug_addr), .rdata(rdata), .debug_data(debug_data)
  );

  always #5 clk = ~clk;

  task automatic do_write(input [`DMEM_ADDR_W-1:0] a, input [`XLEN-1:0] d, input [`MEM_SIZE_W-1:0] sz);
    begin
      addr = a; wdata = d; mem_size = sz; mem_write = 1; mem_read = 0;
      @(posedge clk); #1;
      mem_write = 0;
    end
  endtask

  task automatic expect_read(
      input [`DMEM_ADDR_W-1:0] a, input [`MEM_SIZE_W-1:0] sz, input uns,
      input [`XLEN-1:0] expected, input [8*64-1:0] name
  );
    begin
      addr = a; mem_size = sz; mem_unsigned = uns; mem_read = 1; mem_write = 0;
      #1;
      checks = checks + 1;
      if (rdata !== expected) begin
        errors = errors + 1;
        $display("ERROR: [%0s] rdata=%08h (esperado %08h)", name, rdata, expected);
      end
      mem_read = 0;
    end
  endtask

  initial begin
    mem_read = 0; mem_write = 0; mem_unsigned = 0; addr = {`DMEM_ADDR_W{1'b0}}; wdata = {`XLEN{1'b0}}; mem_size = `MEM_WORD;

    // --- word: escribir y releer completo ---
    do_write(12'd0, 32'hDEADBEEF, `MEM_WORD);
    expect_read(12'd0, `MEM_WORD, 1'b0, 32'hDEADBEEF, "word - write/read basico");

    // --- little-endian: el byte menos significativo va en la direccion mas baja ---
    expect_read(12'd0, `MEM_BYTE, 1'b1, 32'h000000EF, "byte[0] - LSB del word en addr 0");
    expect_read(12'd3, `MEM_BYTE, 1'b1, 32'h000000DE, "byte[3] - MSB del word en addr 3");

    // --- half con y sin signo ---
    do_write(12'd8, 32'hFFFF8001, `MEM_HALF);  // solo importan los 16 bits bajos: 0x8001
    expect_read(12'd8, `MEM_HALF, 1'b0, 32'hFFFF8001, "half con signo - 0x8001 es negativo");
    expect_read(12'd8, `MEM_HALF, 1'b1, 32'h00008001, "half sin signo - mismo bit pattern, sin extender signo");

    // --- byte con y sin signo ---
    do_write(12'd16, 32'h000000C0, `MEM_BYTE);  // 0xC0 = 1100_0000
    expect_read(12'd16, `MEM_BYTE, 1'b0, 32'hFFFFFFC0, "byte con signo - 0xC0 es negativo");
    expect_read(12'd16, `MEM_BYTE, 1'b1, 32'h000000C0, "byte sin signo");

    // --- mem_read=0 da 0 sin importar el contenido ---
    addr = 12'd0; mem_size = `MEM_WORD; mem_read = 0; #1;
    checks = checks + 1;
    if (rdata !== {`XLEN{1'b0}}) begin
      errors = errors + 1;
      $display("ERROR: [mem_read=0] rdata=%08h (esperado 0)", rdata);
    end

    // --- mem_write=0 no modifica memoria ---
    addr = 12'd0; wdata = 32'h11111111; mem_size = `MEM_WORD; mem_write = 0;
    @(posedge clk); #1;
    expect_read(12'd0, `MEM_WORD, 1'b0, 32'hDEADBEEF, "mem_write=0 - memoria sin cambios");

    // --- puerto de debug: lee un byte cualquiera sin pasar por mem_read ---
    mem_read = 0;  // el puerto normal ni siquiera esta habilitado
    debug_addr = 12'd0;
    #1;
    checks = checks + 1;
    if (debug_data !== 8'hEF) begin  // LSB de 0xDEADBEEF
      errors = errors + 1;
      $display("ERROR: [debug port] debug_data=%02h (esperado ef)", debug_data);
    end

    if (errors == 0)
      $display("DMEM_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("DMEM_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
