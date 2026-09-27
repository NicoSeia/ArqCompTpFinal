// -----------------------------------------------------------------------------
// id_ex_reg.v
// Latch ID/EX. Reemplaza a pipe_reg #(.T(id_ex_t)).
//
// Los campos de control (antes agrupados en ctrl_t) viajan acá como
// puertos individuales -- no como un bus empaquetado -- para no depender
// de offsets calculados a mano. Es más verboso pero cualquier cambio
// futuro (agregar/sacar un campo de control) es local a este archivo y a
// quien lo instancia, no una cuenta de bits en cascada.
// -----------------------------------------------------------------------------

module id_ex_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,
    input  wire        stall,

    // datos
    input  wire        d_valid,
    input  wire [31:0] d_pc,          // para pc_target = pc + imm en EX
    input  wire [31:0] d_pc_plus4,    // viaja hasta WB (jal/jalr)
    input  wire [31:0] d_rs1_data,
    input  wire [31:0] d_rs2_data,
    input  wire [31:0] d_imm,
    input  wire [4:0]  d_rs1,         // número de registro (no el dato) -> forwarding
    input  wire [4:0]  d_rs2,
    input  wire [4:0]  d_rd,
    input  wire [2:0]  d_funct3,      // distingue beq/bne en EX

    // control (ex ctrl_t, ahora aplanado en puertos individuales)
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
    output reg  [31:0] q_pc,
    output reg  [31:0] q_pc_plus4,
    output reg  [31:0] q_rs1_data,
    output reg  [31:0] q_rs2_data,
    output reg  [31:0] q_imm,
    output reg  [4:0]  q_rs1,
    output reg  [4:0]  q_rs2,
    output reg  [4:0]  q_rd,
    output reg  [2:0]  q_funct3,

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
      q_pc           <= 32'd0;
      q_pc_plus4     <= 32'd0;
      q_rs1_data     <= 32'd0;
      q_rs2_data     <= 32'd0;
      q_imm          <= 32'd0;
      q_rs1          <= 5'd0;
      q_rs2          <= 5'd0;
      q_rd           <= 5'd0;
      q_funct3       <= 3'd0;
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
      q_pc           <= d_pc;
      q_pc_plus4     <= d_pc_plus4;
      q_rs1_data     <= d_rs1_data;
      q_rs2_data     <= d_rs2_data;
      q_imm          <= d_imm;
      q_rs1          <= d_rs1;
      q_rs2          <= d_rs2;
      q_rd           <= d_rd;
      q_funct3       <= d_funct3;
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
