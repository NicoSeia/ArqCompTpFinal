// -----------------------------------------------------------------------------
// if_id_reg.v
// Latch IF/ID. Reemplaza a pipe_reg #(.T(if_id_t)) — mismos campos que
// if_id_t en riscv_pkg.sv, pero como puertos individuales en vez de un
// struct packed (Verilog-2001 no tiene parameter type ni struct).
//
// rst y flush hacen lo mismo (cargan una burbuja: valid=0, resto en 0):
// rst es el reset global, flush es la limpieza puntual que dispara
// branch_resolve cuando se toma un salto en EX.
// stall lo usa la hazard_unit (load-use) y la Debug Unit (paso a paso) --
// se conecta como el OR de todas las razones para no avanzar.
// -----------------------------------------------------------------------------

module if_id_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,
    input  wire        stall,

    input  wire        d_valid,
    input  wire [31:0] d_pc,
    input  wire [31:0] d_pc_plus4,
    input  wire [31:0] d_instr,

    output reg          q_valid,
    output reg  [31:0] q_pc,
    output reg  [31:0] q_pc_plus4,
    output reg  [31:0] q_instr
);

  always @(posedge clk) begin
    if (rst || flush) begin
      q_valid    <= 1'b0;
      q_pc       <= 32'd0;
      q_pc_plus4 <= 32'd0;
      q_instr    <= 32'd0;
    end else if (!stall) begin
      q_valid    <= d_valid;
      q_pc       <= d_pc;
      q_pc_plus4 <= d_pc_plus4;
      q_instr    <= d_instr;
    end
  end

endmodule
