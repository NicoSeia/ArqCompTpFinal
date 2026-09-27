`include "riscv_defs.vh"
module tb_imem;

  reg                      clk = 0;
  reg                      we;
  reg  [`IMEM_ADDR_W-1:0]  waddr;
  reg  [31:0]              wdata;
  reg  [`IMEM_ADDR_W+1:0]  addr;
  wire [31:0]              instr;

  integer errors = 0;
  integer checks = 0;

  imem dut (.clk(clk), .we(we), .waddr(waddr), .wdata(wdata), .addr(addr), .instr(instr));

  always #5 clk = ~clk;

  task automatic expect_instr(input [`IMEM_ADDR_W+1:0] addr_i, input [31:0] expected, input [8*80-1:0] name);
    begin
      addr = addr_i;
      #1;
      checks = checks + 1;
      if (instr !== expected) begin
        errors = errors + 1;
        $display("ERROR: [%0s] addr=%0d -> instr=%08h (esperado %08h)", name, addr_i, instr, expected);
      end
    end
  endtask

  initial begin
    we = 0; waddr = {`IMEM_ADDR_W{1'b0}}; wdata = 32'd0; addr = {(`IMEM_ADDR_W+2){1'b0}};

    // referencia jerárquica: todavía no hay ensamblador, cargamos a mano
    dut.mem[0] = 32'h002081B3;  // add x3, x1, x2
    dut.mem[1] = 32'h40208233;  // sub x4, x1, x2
    dut.mem[2] = 32'h0000006F;  // jal x0, 0

    // --- direccionamiento por byte, dividiendo por 4 ---
    expect_instr(12'd0,  32'h002081B3, "addr=0 -> mem[0]");
    expect_instr(12'd4,  32'h40208233, "addr=4 -> mem[1]");
    expect_instr(12'd8,  32'h0000006F, "addr=8 -> mem[2]");

    // --- una dirección no alineada tiene que caer en la misma palabra
    //     que la dirección alineada anterior (se ignoran los 2 bits bajos) ---
    expect_instr(12'd5, 32'h40208233, "addr=5 (no alineada) -> misma palabra que addr=4");

    // --- posición no inicializada -> NOP por defecto ---
    expect_instr(12'd12, 32'h00000013, "addr=12 -> NOP por defecto");

    // --- puerto de escritura (LOAD_WORD de la Debug Unit): direccion de
    //     PALABRA, no de byte, a diferencia del puerto de lectura ---
    @(negedge clk);  // armar la escritura lejos de cualquier flanco de subida
    waddr = 10'd3; wdata = 32'hCAFEF00D; we = 1;
    addr = 12'd12;  // leyendo la misma palabra (byte 12 = word 3) ANTES del flanco
    #1;
    checks = checks + 1;
    if (instr === 32'hCAFEF00D) begin
      errors = errors + 1;
      $display("ERROR: [escritura] la escritura se vio ANTES del flanco de clock (debe ser sincrona)");
    end

    @(posedge clk); #1;
    we = 0;
    expect_instr(12'd12, 32'hCAFEF00D, "escritura - se ve DESPUES del flanco, en waddr=3 (byte 12)");

    // --- we=0 no escribe nada, aunque waddr/wdata cambien ---
    @(negedge clk);
    waddr = 10'd3; wdata = 32'h11111111; we = 0;
    @(posedge clk); #1;
    expect_instr(12'd12, 32'hCAFEF00D, "we=0 - no modifica lo que ya habia");

    if (errors == 0)
      $display("IMEM_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("IMEM_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
