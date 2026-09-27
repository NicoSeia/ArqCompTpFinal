// -----------------------------------------------------------------------------
// ex_mem_reg.v
// Latch EX/MEM. Reemplaza a pipe_reg #(.T(ex_mem_t)).
//
// Nota: sigue transportando el bloque de control completo (12 campos),
// igual que hacía ex_mem_t, aunque MEM/WB solo termine usando una parte
// (reg_write, wb_src, mem_read, mem_write, mem_size, mem_unsigned). Se
// mantiene así por simetría con el diseño original; como ya no es un
// bus empaquetado, recortar los campos que no llegan a usarse en esta
// etapa es un cambio local y seguro el día que se quiera hacer, no una
// cuenta de offsets en cascada.
// -----------------------------------------------------------------------------

module ex_mem_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,
    input  wire        stall,

    // datos
    input  wire        d_valid,
    input  wire [31:0] d_alu_result,
    input  wire [31:0] d_rs2_data,    // dato a guardar si es store
    input  wire [4:0]  d_rd,
    input  wire [31:0] d_pc_plus4,

    // control
    input  wire        d_reg_write,
    input  wire        d_mem_read,
    input  wire        d_mem_write,
    input  wire [1:0]  d_wb_src,
    input  wire        d_alu_src,
    input  wire        d_branch,
    input  wire        d_jump,
    input  wire        d_jalr,
    input  wire        d_mem_unsigned,
    input  wire [3:0]  d_alu_op,
    input  wire [1:0]  d_mem_size,
    input  wire [2:0]  d_imm_src,

    // datos
    output reg          q_valid,
    output reg  [31:0] q_alu_result,
    output reg  [31:0] q_rs2_data,
    output reg  [4:0]  q_rd,
    output reg  [31:0] q_pc_plus4,

    // control
    output reg          q_reg_write,
    output reg          q_mem_read,
    output reg          q_mem_write,
    output reg  [1:0]  q_wb_src,
    output reg          q_alu_src,
    output reg          q_branch,
    output reg          q_jump,
    output reg          q_jalr,
    output reg          q_mem_unsigned,
    output reg  [3:0]  q_alu_op,
    output reg  [1:0]  q_mem_size,
    output reg  [2:0]  q_imm_src
);

  always @(posedge clk) begin
    if (rst || flush) begin
      q_valid        <= 1'b0;
      q_alu_result   <= 32'd0;
      q_rs2_data     <= 32'd0;
      q_rd           <= 5'd0;
      q_pc_plus4     <= 32'd0;
      q_reg_write    <= 1'b0;
      q_mem_read     <= 1'b0;
      q_mem_write    <= 1'b0;
      q_wb_src       <= 2'd0;
      q_alu_src      <= 1'b0;
      q_branch       <= 1'b0;
      q_jump         <= 1'b0;
      q_jalr         <= 1'b0;
      q_mem_unsigned <= 1'b0;
      q_alu_op       <= 4'd0;
      q_mem_size     <= 2'd0;
      q_imm_src      <= 3'd0;
    end else if (!stall) begin
      q_valid        <= d_valid;
      q_alu_result   <= d_alu_result;
      q_rs2_data     <= d_rs2_data;
      q_rd           <= d_rd;
      q_pc_plus4     <= d_pc_plus4;
      q_reg_write    <= d_reg_write;
      q_mem_read     <= d_mem_read;
      q_mem_write    <= d_mem_write;
      q_wb_src       <= d_wb_src;
      q_alu_src      <= d_alu_src;
      q_branch       <= d_branch;
      q_jump         <= d_jump;
      q_jalr         <= d_jalr;
      q_mem_unsigned <= d_mem_unsigned;
      q_alu_op       <= d_alu_op;
      q_mem_size     <= d_mem_size;
      q_imm_src      <= d_imm_src;
    end
  end

endmodule
