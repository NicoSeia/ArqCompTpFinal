// -----------------------------------------------------------------------------
// tb_ex_mem_reg.v
// Testbench dirigido para ex_mem_reg.
// -----------------------------------------------------------------------------
module tb_ex_mem_reg;

  reg clk = 0;
  always #5 clk = ~clk;

  integer errors = 0;
  integer checks = 0;

  task automatic check_bit(input val, input exp, input [255:0] name);
    begin
      checks = checks + 1;
      if (val !== exp) begin
        errors = errors + 1;
        $display("FAIL [%0s] got=%0b esperado=%0b", name, val, exp);
      end
    end
  endtask

  task automatic check_word(input [31:0] val, input [31:0] exp, input [255:0] name);
    begin
      checks = checks + 1;
      if (val !== exp) begin
        errors = errors + 1;
        $display("FAIL [%0s] got=%08h esperado=%08h", name, val, exp);
      end
    end
  endtask

  task automatic check_field(input [31:0] val, input [31:0] exp, input [255:0] name);
    begin
      checks = checks + 1;
      if (val !== exp) begin
        errors = errors + 1;
        $display("FAIL [%0s] got=%0d esperado=%0d", name, val, exp);
      end
    end
  endtask

  reg         rst, flush, stall;
  reg         d_valid;
  reg  [31:0] d_alu_result, d_rs2_data, d_pc_plus4;
  reg  [4:0]  d_rd;
  reg         d_reg_write, d_mem_read, d_mem_write, d_alu_src;
  reg         d_branch, d_jump, d_jalr, d_mem_unsigned;
  reg  [1:0]  d_wb_src, d_mem_size;
  reg  [3:0]  d_alu_op;
  reg  [2:0]  d_imm_src;

  wire        q_valid;
  wire [31:0] q_alu_result, q_rs2_data, q_pc_plus4;
  wire [4:0]  q_rd;
  wire        q_reg_write, q_mem_read, q_mem_write, q_alu_src;
  wire        q_branch, q_jump, q_jalr, q_mem_unsigned;
  wire [1:0]  q_wb_src, q_mem_size;
  wire [3:0]  q_alu_op;
  wire [2:0]  q_imm_src;

  ex_mem_reg dut (
      .clk(clk), .rst(rst), .flush(flush), .stall(stall),
      .d_valid(d_valid), .d_alu_result(d_alu_result), .d_rs2_data(d_rs2_data),
      .d_rd(d_rd), .d_pc_plus4(d_pc_plus4),
      .d_reg_write(d_reg_write), .d_mem_read(d_mem_read), .d_mem_write(d_mem_write),
      .d_wb_src(d_wb_src), .d_alu_src(d_alu_src), .d_branch(d_branch),
      .d_jump(d_jump), .d_jalr(d_jalr), .d_mem_unsigned(d_mem_unsigned),
      .d_alu_op(d_alu_op), .d_mem_size(d_mem_size), .d_imm_src(d_imm_src),
      .q_valid(q_valid), .q_alu_result(q_alu_result), .q_rs2_data(q_rs2_data),
      .q_rd(q_rd), .q_pc_plus4(q_pc_plus4),
      .q_reg_write(q_reg_write), .q_mem_read(q_mem_read), .q_mem_write(q_mem_write),
      .q_wb_src(q_wb_src), .q_alu_src(q_alu_src), .q_branch(q_branch),
      .q_jump(q_jump), .q_jalr(q_jalr), .q_mem_unsigned(q_mem_unsigned),
      .q_alu_op(q_alu_op), .q_mem_size(q_mem_size), .q_imm_src(q_imm_src)
  );

  initial begin
    rst = 1; flush = 0; stall = 0;
    d_valid = 1;
    d_alu_result = 32'hC000_0001; d_rs2_data = 32'hC000_0002; d_pc_plus4 = 32'hC000_0003;
    d_rd = 5'd17;
    d_reg_write = 1; d_mem_read = 1; d_mem_write = 0;
    d_wb_src = 2'd1; d_alu_src = 0; d_branch = 1;
    d_jump = 0; d_jalr = 1; d_mem_unsigned = 0;
    d_alu_op = 4'd3; d_mem_size = 2'd2; d_imm_src = 3'd1;

    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "reset limpia valid");
    check_word(q_alu_result, 32'd0, "reset limpia alu_result");

    rst = 0;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b1, "avance normal - valid");
    check_word(q_alu_result, 32'hC000_0001, "alu_result");
    check_word(q_rs2_data, 32'hC000_0002, "rs2_data (no cruzado con alu_result)");
    check_word(q_pc_plus4, 32'hC000_0003, "pc_plus4");
    check_field(q_rd, 5'd17, "rd");
    check_bit(q_reg_write, 1'b1, "reg_write");
    check_bit(q_mem_read, 1'b1, "mem_read");
    check_bit(q_mem_write, 1'b0, "mem_write (no cruzado con mem_read)");
    check_field(q_wb_src, 2'd1, "wb_src");
    check_bit(q_alu_src, 1'b0, "alu_src");
    check_bit(q_branch, 1'b1, "branch");
    check_bit(q_jump, 1'b0, "jump (no cruzado con branch)");
    check_bit(q_jalr, 1'b1, "jalr");
    check_bit(q_mem_unsigned, 1'b0, "mem_unsigned");
    check_field(q_alu_op, 4'd3, "alu_op");
    check_field(q_mem_size, 2'd2, "mem_size");
    check_field(q_imm_src, 3'd1, "imm_src");

    // stall: no debe cambiar aunque la entrada cambie
    stall = 1;
    d_rd = 5'd31;
    @(posedge clk); #1;
    check_field(q_rd, 5'd17, "stall congela rd");
    stall = 0;

    // flush: limpia todo a 0
    flush = 1;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "flush limpia valid");
    check_bit(q_reg_write, 1'b0, "flush limpia reg_write");
    flush = 0;

    if (errors == 0)
      $display("EX_MEM_REG_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("EX_MEM_REG_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
