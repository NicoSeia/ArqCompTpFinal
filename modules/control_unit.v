`timescale 1ps/1ps
`include "riscv_defs.vh"
// Antes: un unico puerto de salida `ctrl` empaquetado en un bus de
// `CTRL_W` bits (con `define de rango para cada campo). Ahora: 12 puertos
// de salida individuales, uno por campo -- la logica interna es identica,
// solo cambio COMO se expone cada bit hacia afuera.
module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,

    output reg                     reg_write,
    output reg                     mem_read,
    output reg                     mem_write,
    output reg  [`WB_SRC_W-1:0]    wb_src,
    output reg                     alu_src,
    output reg                     branch,
    output reg                     jump,
    output reg                     jalr,
    output reg                     mem_unsigned,
    output reg  [`ALU_OP_W-1:0]    alu_op,
    output reg  [`MEM_SIZE_W-1:0]  mem_size,
    output reg  [`IMM_SRC_W-1:0]   imm_src,
    output reg                     illegal
);

  always @* begin
    // Valores por defecto: instrucción inerte, no escribe nada
    reg_write    = 1'b0;
    mem_read     = 1'b0;
    mem_write    = 1'b0;
    wb_src       = `WB_ALU;
    alu_src      = 1'b0;
    branch       = 1'b0;
    jump         = 1'b0;
    jalr         = 1'b0;
    mem_unsigned = 1'b0;
    alu_op       = `ALU_ADD;
    mem_size     = `MEM_WORD;
    imm_src      = `IMM_X;
    illegal      = 1'b0;

    case (opcode)

      // ------------------------------------------------------------ R-type
      `OP_R: begin
        reg_write = 1'b1;
        case (funct3)
          3'b000:  alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;  // add / sub
          3'b001:  alu_op = `ALU_SLL;
          3'b010:  alu_op = `ALU_SLT;
          3'b011:  alu_op = `ALU_SLTU;
          3'b100:  alu_op = `ALU_XOR;
          3'b101:  alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;  // srl / sra
          3'b110:  alu_op = `ALU_OR;
          3'b111:  alu_op = `ALU_AND;
          default: illegal = 1'b1;
        endcase
      end

      // ------------------------------------------------- I-type ALU inmediato
      `OP_IMM: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;
        imm_src   = `IMM_I;
        case (funct3)
          3'b000:  alu_op = `ALU_ADD;                          // addi
          3'b001:  alu_op = `ALU_SLL;                          // slli
          3'b010:  alu_op = `ALU_SLT;                          // slti
          3'b011:  alu_op = `ALU_SLTU;                         // sltiu
          3'b100:  alu_op = `ALU_XOR;                          // xori
          3'b101:  alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;   // srai / srli
          3'b110:  alu_op = `ALU_OR;                           // ori
          3'b111:  alu_op = `ALU_AND;                          // andi
          default: illegal = 1'b1;
        endcase
      end

      // ------------------------------------------------------------- Loads
      `OP_LOAD: begin
        reg_write = 1'b1;
        mem_read  = 1'b1;
        alu_src   = 1'b1;
        wb_src    = `WB_MEM;
        imm_src   = `IMM_I;
        alu_op    = `ALU_ADD;
        case (funct3)
          3'b000: begin mem_size = `MEM_BYTE; mem_unsigned = 1'b0; end  // lb
          3'b001: begin mem_size = `MEM_HALF; mem_unsigned = 1'b0; end  // lh
          3'b010: begin mem_size = `MEM_WORD; mem_unsigned = 1'b0; end  // lw
          3'b100: begin mem_size = `MEM_BYTE; mem_unsigned = 1'b1; end  // lbu
          3'b101: begin mem_size = `MEM_HALF; mem_unsigned = 1'b1; end  // lhu
          default: illegal = 1'b1;
        endcase
      end

      // ------------------------------------------------------------ Stores
      `OP_STORE: begin
        mem_write = 1'b1;
        alu_src   = 1'b1;
        imm_src   = `IMM_S;
        alu_op    = `ALU_ADD;
        case (funct3)
          3'b000:  mem_size = `MEM_BYTE;  // sb
          3'b001:  mem_size = `MEM_HALF;  // sh
          3'b010:  mem_size = `MEM_WORD;  // sw
          default: illegal = 1'b1;
        endcase
      end

      // ---------------------------------------------------------- Branches
      `OP_BRANCH: begin
        branch  = 1'b1;
        imm_src = `IMM_B;
        alu_op  = `ALU_SUB;  // next_pc_logic usa el flag zero + funct3[0] para beq/bne
        case (funct3)
          3'b000:  ;  // beq
          3'b001:  ;  // bne
          default: illegal = 1'b1;
        endcase
      end

      // ---------------------------------------------------------------- Lui
      `OP_LUI: begin
        reg_write = 1'b1;
        alu_src   = 1'b1;
        imm_src   = `IMM_U;
        alu_op    = `ALU_PASS;  // resultado = inmediato, sin sumar nada
      end

      // ---------------------------------------------------------------- Jal
      `OP_JAL: begin
        reg_write = 1'b1;
        wb_src    = `WB_PC4;
        jump      = 1'b1;
        imm_src   = `IMM_J;
      end

      // --------------------------------------------------------------- Jalr
      `OP_JALR: begin
        reg_write = 1'b1;
        wb_src    = `WB_PC4;
        jump      = 1'b1;
        jalr      = 1'b1;
        imm_src   = `IMM_I;
        case (funct3)
          3'b000:  ;  // jalr válido
          default: illegal = 1'b1;
        endcase
      end

      default: illegal = 1'b1;

    endcase
  end

endmodule
