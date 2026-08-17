`timescale 1ps/1ps
module control_unit
  import riscv_pkg::*;
(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output ctrl_t       ctrl,
    output logic        illegal
);

  always_comb begin
    // Valores por defecto: instrucción inerte, no escribe nada
    ctrl.reg_write    = 1'b0;
    ctrl.mem_read     = 1'b0;
    ctrl.mem_write    = 1'b0;
    ctrl.wb_src       = WB_ALU;
    ctrl.alu_src      = 1'b0;
    ctrl.branch       = 1'b0;
    ctrl.jump         = 1'b0;
    ctrl.jalr         = 1'b0;
    ctrl.mem_unsigned = 1'b0;
    ctrl.alu_op       = ALU_ADD;
    ctrl.mem_size     = MEM_WORD;
    ctrl.imm_src      = IMM_X;
    illegal           = 1'b0;

    unique case (opcode)

      // ------------------------------------------------------------ R-type
      OP_R: begin
        ctrl.reg_write = 1'b1;
        unique case (funct3)
          3'b000:  ctrl.alu_op = funct7[5] ? ALU_SUB : ALU_ADD;  // add / sub
          3'b001:  ctrl.alu_op = ALU_SLL;
          3'b010:  ctrl.alu_op = ALU_SLT;
          3'b011:  ctrl.alu_op = ALU_SLTU;
          3'b100:  ctrl.alu_op = ALU_XOR;
          3'b101:  ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;  // srl / sra
          3'b110:  ctrl.alu_op = ALU_OR;
          3'b111:  ctrl.alu_op = ALU_AND;
          default: illegal = 1'b1;
        endcase
      end

      // ------------------------------------------------- I-type ALU inmediato
      OP_IMM: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b1;
        ctrl.imm_src   = IMM_I;
        unique case (funct3)
          3'b000:  ctrl.alu_op = ALU_ADD;                          // addi
          3'b001:  ctrl.alu_op = ALU_SLL;                          // slli
          3'b010:  ctrl.alu_op = ALU_SLT;                          // slti
          3'b011:  ctrl.alu_op = ALU_SLTU;                         // sltiu
          3'b100:  ctrl.alu_op = ALU_XOR;                          // xori
          3'b101:  ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;    // srai / srli
          3'b110:  ctrl.alu_op = ALU_OR;                           // ori
          3'b111:  ctrl.alu_op = ALU_AND;                          // andi
          default: illegal = 1'b1;
        endcase
      end

      // ------------------------------------------------------------- Loads
      OP_LOAD: begin
        ctrl.reg_write = 1'b1;
        ctrl.mem_read  = 1'b1;
        ctrl.alu_src   = 1'b1;
        ctrl.wb_src    = WB_MEM;
        ctrl.imm_src   = IMM_I;
        ctrl.alu_op    = ALU_ADD;
        unique case (funct3)
          3'b000: begin ctrl.mem_size = MEM_BYTE; ctrl.mem_unsigned = 1'b0; end  // lb
          3'b001: begin ctrl.mem_size = MEM_HALF; ctrl.mem_unsigned = 1'b0; end  // lh
          3'b010: begin ctrl.mem_size = MEM_WORD; ctrl.mem_unsigned = 1'b0; end  // lw
          3'b100: begin ctrl.mem_size = MEM_BYTE; ctrl.mem_unsigned = 1'b1; end  // lbu
          3'b101: begin ctrl.mem_size = MEM_HALF; ctrl.mem_unsigned = 1'b1; end  // lhu
          default: illegal = 1'b1;
        endcase
      end

      // ------------------------------------------------------------ Stores
      OP_STORE: begin
        ctrl.mem_write = 1'b1;
        ctrl.alu_src   = 1'b1;
        ctrl.imm_src   = IMM_S;
        ctrl.alu_op    = ALU_ADD;
        unique case (funct3)
          3'b000:  ctrl.mem_size = MEM_BYTE;  // sb
          3'b001:  ctrl.mem_size = MEM_HALF;  // sh
          3'b010:  ctrl.mem_size = MEM_WORD;  // sw
          default: illegal = 1'b1;
        endcase
      end

      // ---------------------------------------------------------- Branches
      OP_BRANCH: begin
        ctrl.branch  = 1'b1;
        ctrl.imm_src = IMM_B;
        ctrl.alu_op  = ALU_SUB;  // next_pc_logic usa el flag zero + funct3[0] para beq/bne
        unique case (funct3)
          3'b000:  ;  // beq
          3'b001:  ;  // bne
          default: illegal = 1'b1;
        endcase
      end

      // ---------------------------------------------------------------- Lui
      OP_LUI: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b1;
        ctrl.imm_src   = IMM_U;
        ctrl.alu_op    = ALU_PASS;  // resultado = inmediato, sin sumar nada
      end

      // ---------------------------------------------------------------- Jal
      OP_JAL: begin
        ctrl.reg_write = 1'b1;
        ctrl.wb_src    = WB_PC4;
        ctrl.jump      = 1'b1;
        ctrl.imm_src   = IMM_J;
      end

      // --------------------------------------------------------------- Jalr
      OP_JALR: begin
        ctrl.reg_write = 1'b1;
        ctrl.wb_src    = WB_PC4;
        ctrl.jump      = 1'b1;
        ctrl.jalr      = 1'b1;
        ctrl.imm_src   = IMM_I;
        unique case (funct3)
          3'b000:  ;  // jalr válido
          default: illegal = 1'b1;
        endcase
      end

      default: illegal = 1'b1;

    endcase
  end

endmodule