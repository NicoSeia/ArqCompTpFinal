`include "riscv_defs.vh"
// Testbench de dmem.v (BRAM: palabra de 32 bits, escritura por byte, lectura
// sincrona, puerto B de debug independiente).
module tb_dmem;

  reg                     clk = 0;
  reg                     enable;
  reg  [`DMEM_ADDR_W-1:0] addr;
  reg  [31:0]             wdata;
  reg  [3:0]              we;
  wire [31:0]             rdata;
  reg  [`DMEM_ADDR_W-1:0] debug_addr;
  wire [7:0]              debug_data;

  integer errors = 0;
  integer checks = 0;

  dmem dut (
      .clk(clk), .enable(enable),
      .addr(addr), .wdata(wdata), .we(we), .rdata(rdata),
      .debug_addr(debug_addr), .debug_data(debug_data)
  );

  always #5 clk = ~clk;

  task check32(input [31:0] got, input [31:0] exp, input [8*48-1:0] name);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] got=%08h esperado=%08h", name, got, exp);
      end
    end
  endtask

  task check8(input [7:0] got, input [7:0] exp, input [8*48-1:0] name);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] got=%02h esperado=%02h", name, got, exp);
      end
    end
  endtask

  // escribe en un flanco (we != 0)
  task do_write(input [`DMEM_ADDR_W-1:0] a, input [31:0] d, input [3:0] mask);
    begin
      addr = a; wdata = d; we = mask;
      @(posedge clk); #1;
      we = 4'b0000;
    end
  endtask

  // presenta la direccion y espera el flanco: rdata ya es el dato
  task do_read(input [`DMEM_ADDR_W-1:0] a);
    begin
      addr = a; we = 4'b0000;
      @(posedge clk); #1;
    end
  endtask

  initial begin
    enable = 1; addr = 0; wdata = 0; we = 0; debug_addr = 0;
    @(posedge clk); #1;

    // --- inicial: toda la memoria en 0 ---
    do_read(12'd0);
    check32(rdata, 32'h0, "memoria inicial en 0");

    // --- escritura de palabra completa y relectura ---
    do_write(12'd0, 32'hDEADBEEF, 4'b1111);
    do_read(12'd0);
    check32(rdata, 32'hDEADBEEF, "word write/read");

    // --- la lectura es SINCRONA: antes del flanco el dato aun no cambio ---
    addr = 12'd4; we = 0;
    #1;
    check32(rdata, 32'hDEADBEEF, "sincrona: rdata no cambia antes del flanco");
    @(posedge clk); #1;
    check32(rdata, 32'h0, "sincrona: rdata cambia en el flanco (addr 4 = 0)");

    // --- escritura por byte: solo cambian los bytes habilitados ---
    do_write(12'd8, 32'hAABBCCDD, 4'b1111);
    do_write(12'd8, 32'h11223344, 4'b0001);   // byte 0 -> 44
    do_read(12'd8);
    check32(rdata, 32'hAABBCC44, "byte-enable 0001");
    do_write(12'd8, 32'h11223344, 4'b1000);   // byte 3 -> 11
    do_read(12'd8);
    check32(rdata, 32'h11BBCC44, "byte-enable 1000");
    do_write(12'd8, 32'h99887766, 4'b0110);   // bytes 1 y 2 -> 77, 88
    do_read(12'd8);
    check32(rdata, 32'h11887744, "byte-enable 0110");

    // --- we=0 no escribe ---
    do_write(12'd8, 32'hFFFFFFFF, 4'b0000);
    do_read(12'd8);
    check32(rdata, 32'h11887744, "we=0 no modifica");

    // --- read-first: escribir y leer la misma direccion devuelve el valor viejo ---
    addr = 12'd8; wdata = 32'h00000000; we = 4'b1111;
    @(posedge clk); #1;
    check32(rdata, 32'h11887744, "read-first: rdata trae el valor previo a la escritura");
    we = 4'b0000;
    do_read(12'd8);
    check32(rdata, 32'h0, "despues de la escritura el valor nuevo ya esta");

    // --- enable=0: el puerto A se congela (no escribe y rdata se mantiene) ---
    do_write(12'd16, 32'hCAFEF00D, 4'b1111);
    do_read(12'd16);
    check32(rdata, 32'hCAFEF00D, "preparacion enable");
    enable = 0;
    addr = 12'd16; wdata = 32'h12345678; we = 4'b1111;
    @(posedge clk); #1;
    check32(rdata, 32'hCAFEF00D, "enable=0: rdata congelado");
    addr = 12'd20; we = 4'b0000;
    @(posedge clk); #1;
    check32(rdata, 32'hCAFEF00D, "enable=0: rdata no sigue a la direccion");
    enable = 1;
    do_read(12'd16);
    check32(rdata, 32'hCAFEF00D, "enable=0: la escritura bloqueada no se hizo");

    // --- puerto B (debug): lee un byte, 1 ciclo despues ---
    debug_addr = 12'd16;
    @(posedge clk); #1;
    check8(debug_data, 8'h0D, "debug byte 0 (LSB de CAFEF00D)");
    debug_addr = 12'd17;
    @(posedge clk); #1;
    check8(debug_data, 8'hF0, "debug byte 1");
    debug_addr = 12'd18;
    @(posedge clk); #1;
    check8(debug_data, 8'hFE, "debug byte 2");
    debug_addr = 12'd19;
    @(posedge clk); #1;
    check8(debug_data, 8'hCA, "debug byte 3 (MSB)");

    // --- el puerto B NO pisa la salida del puerto A ---
    do_read(12'd16);
    check32(rdata, 32'hCAFEF00D, "preparacion puerto B");
    debug_addr = 12'd8;                      // otra direccion distinta
    enable = 0;                              // pipeline congelado, como en DUMP_MEM
    @(posedge clk); #1;
    @(posedge clk); #1;
    check32(rdata, 32'hCAFEF00D, "puerto B no pisa rdata del puerto A");
    check8(debug_data, 8'h00, "debug lee otra direccion mientras A esta congelado");
    enable = 1;

    // --- ultima palabra de la memoria ---
    do_write(12'd4092, 32'h0BADF00D, 4'b1111);
    do_read(12'd4092);
    check32(rdata, 32'h0BADF00D, "ultima palabra (addr 4092)");
    debug_addr = 12'd4095;
    @(posedge clk); #1;
    check8(debug_data, 8'h0B, "debug ultimo byte (addr 4095)");

    if (errors == 0)
      $display("DMEM_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("DMEM_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule