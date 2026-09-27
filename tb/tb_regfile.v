`include "riscv_defs.vh"
module tb_regfile;

  reg                    clk = 0;
  reg                    rst;
  reg                    we;
  reg  [`REG_ADDR_W-1:0] rs1_addr, rs2_addr, rd_addr;
  reg  [`XLEN-1:0]       rd_data;
  wire [`XLEN-1:0]       rs1_data, rs2_data;
  reg  [`REG_ADDR_W-1:0] debug_addr;
  wire [`XLEN-1:0]       debug_data;

  integer errors = 0;
  integer checks = 0;

  // Verilog no tiene .* : puertos explicitos. enable=1 (era el default en SV).
  regfile dut (
      .clk(clk), .rst(rst), .enable(1'b1), .we(we),
      .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr), .rd_data(rd_data),
      .debug_addr(debug_addr), .rs1_data(rs1_data), .rs2_data(rs2_data), .debug_data(debug_data)
  );

  always #5 clk = ~clk;  // periodo 10

  task automatic expect_val(input [`XLEN-1:0] got, input [`XLEN-1:0] exp, input [8*64-1:0] name);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] valor=%0h (esperado %0h)", name, got, exp);
      end
    end
  endtask

  initial begin
    // --- Reset: todos los registros en 0 ---
    rst = 1; we = 0; rd_addr = 5'd0; rd_data = 32'd0; rs1_addr = 5'd0; rs2_addr = 5'd0;
    @(posedge clk); #1;
    rst = 0;

    rs1_addr = 5'd1; rs2_addr = 5'd31; #1;
    expect_val(rs1_data, 32'd0, "reset - x1 en 0");
    expect_val(rs2_data, 32'd0, "reset - x31 en 0");

    // --- x0 hardwireado a 0, incluso intentando escribirlo ---
    rd_addr = 5'd0; rd_data = 32'hDEADBEEF; we = 1;
    @(posedge clk); #1;
    we = 0;
    rs1_addr = 5'd0; #1;
    expect_val(rs1_data, 32'd0, "x0 - escritura ignorada, sigue en 0");

    // --- Escritura y lectura basica ---
    rd_addr = 5'd5; rd_data = 32'hCAFEBABE; we = 1;
    @(posedge clk); #1;
    we = 0;
    rs1_addr = 5'd5; #1;
    expect_val(rs1_data, 32'hCAFEBABE, "escritura basica - x5");

    // --- Lectura simultanea en los dos puertos, registros distintos ---
    rd_addr = 5'd10; rd_data = 32'h11111111; we = 1;
    @(posedge clk); #1;
    we = 0;
    rs1_addr = 5'd5; rs2_addr = 5'd10; #1;
    expect_val(rs1_data, 32'hCAFEBABE, "puerto 1 - x5 sigue correcto");
    expect_val(rs2_data, 32'h11111111, "puerto 2 - x10");

    // --- Orden write-before-read: en el mismo ciclo en que se escribe,
    //     la lectura combinacional todavia tiene que ver el valor VIEJO ---
    rd_addr = 5'd5; rd_data = 32'hA5A5A5A5; we = 1;
    rs1_addr = 5'd5; #1;
    expect_val(rs1_data, 32'hCAFEBABE, "durante la escritura - lectura ve el valor viejo");
    @(posedge clk); #1;
    we = 0;
    expect_val(rs1_data, 32'hA5A5A5A5, "despues del flanco - lectura ve el valor nuevo");

    // --- puerto de debug: lee x10 sin tocar lo que rs1/rs2 estan leyendo ---
    rs1_addr = 5'd5; rs2_addr = 5'd0;  // el pipeline "sigue leyendo" x5
    debug_addr = 5'd10;
    #1;
    expect_val(debug_data, 32'h11111111, "debug port - lee x10 sin interferir con rs1/rs2");
    expect_val(rs1_data, 32'hA5A5A5A5, "debug port - rs1 no se vio afectado");

    // --- debug port tambien respeta x0 ---
    debug_addr = 5'd0;
    #1;
    expect_val(debug_data, 32'd0, "debug port - x0 siempre 0");

    if (errors == 0)
      $display("REGFILE_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("REGFILE_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
