// -----------------------------------------------------------------------------
// tb_mem_wb_reg.v
// Testbench dirigido para mem_wb_reg.
// -----------------------------------------------------------------------------
module tb_mem_wb_reg;

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
  reg  [31:0] d_mem_data, d_alu_result, d_pc_plus4;
  reg  [4:0]  d_rd;
  reg         d_reg_write, d_mem_read, d_mem_write, d_alu_src;
  reg         d_branch, d_jump, d_jalr, d_mem_unsigned;
  reg  [1:0]  d_wb_src, d_mem_size;
  reg  [3:0]  d_alu_op;
  reg  [2:0]  d_imm_src;

  wire        q_valid;
  wire [31:0] q_mem_data, q_alu_result, q_pc_plus4;
  wire [4:0]  q_rd;
  wire        q_reg_write, q_mem_read, q_mem_write, q_alu_src;
  wire        q_branch, q_jump, q_jalr, q_mem_unsigned;
  wire [1:0]  q_wb_src, q_mem_size;
  wire [3:0]  q_alu_op;
  wire [2:0]  q_imm_src;

  mem_wb_reg dut (
      .clk(clk), .rst(rst), .flush(flush), .stall(stall),
      .d_valid(d_valid), .d_mem_data(d_mem_data), .d_alu_result(d_alu_result),
      .d_pc_plus4(d_pc_plus4), .d_rd(d_rd),
      .d_reg_write(d_reg_write), .d_mem_read(d_mem_read), .d_mem_write(d_mem_write),
      .d_wb_src(d_wb_src), .d_alu_src(d_alu_src), .d_branch(d_branch),
      .d_jump(d_jump), .d_jalr(d_jalr), .d_mem_unsigned(d_mem_unsigned),
      .d_alu_op(d_alu_op), .d_mem_size(d_mem_size), .d_imm_src(d_imm_src),
      .q_valid(q_valid), .q_mem_data(q_mem_data), .q_alu_result(q_alu_result),
      .q_pc_plus4(q_pc_plus4), .q_rd(q_rd),
      .q_reg_write(q_reg_write), .q_mem_read(q_mem_read), .q_mem_write(q_mem_write),
      .q_wb_src(q_wb_src), .q_alu_src(q_alu_src), .q_branch(q_branch),
      .q_jump(q_jump), .q_jalr(q_jalr), .q_mem_unsigned(q_mem_unsigned),
      .q_alu_op(q_alu_op), .q_mem_size(q_mem_size), .q_imm_src(q_imm_src)
  );

  initial begin
    rst = 1; flush = 0; stall = 0;
    d_valid = 1;
    d_mem_data = 32'hD000_0001; d_alu_result = 32'hD000_0002; d_pc_plus4 = 32'hD000_0003;
    d_rd = 5'd23;
    d_reg_write = 1; d_mem_read = 0; d_mem_write = 1;
    d_wb_src = 2'd0; d_alu_src = 1; d_branch = 0;
    d_jump = 1; d_jalr = 0; d_mem_unsigned = 1;
    d_alu_op = 4'd9; d_mem_size = 2'd0; d_imm_src = 3'd3;

    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "reset limpia valid");
    check_word(q_mem_data, 32'd0, "reset limpia mem_data");

    rst = 0;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b1, "avance normal - valid");
    check_word(q_mem_data, 32'hD000_0001, "mem_data");
    check_word(q_alu_result, 32'hD000_0002, "alu_result (no cruzado con mem_data)");
    check_word(q_pc_plus4, 32'hD000_0003, "pc_plus4");
    check_field(q_rd, 5'd23, "rd");
    check_bit(q_reg_write, 1'b1, "reg_write");
    check_bit(q_mem_read, 1'b0, "mem_read (no cruzado con mem_write)");
    check_bit(q_mem_write, 1'b1, "mem_write");
    check_field(q_wb_src, 2'd0, "wb_src");
    check_bit(q_alu_src, 1'b1, "alu_src");
    check_bit(q_branch, 1'b0, "branch (no cruzado con jump)");
    check_bit(q_jump, 1'b1, "jump");
    check_bit(q_jalr, 1'b0, "jalr");
    check_bit(q_mem_unsigned, 1'b1, "mem_unsigned");
    check_field(q_alu_op, 4'd9, "alu_op");
    check_field(q_mem_size, 2'd0, "mem_size");
    check_field(q_imm_src, 3'd3, "imm_src");

    // stall: no debe cambiar aunque la entrada cambie
    stall = 1;
    d_rd = 5'd31;
    @(posedge clk); #1;
    check_field(q_rd, 5'd23, "stall congela rd");
    stall = 0;

    // flush: limpia todo a 0
    flush = 1;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "flush limpia valid");
    check_bit(q_reg_write, 1'b0, "flush limpia reg_write");
    flush = 0;

    if (errors == 0)
      $display("MEM_WB_REG_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("MEM_WB_REG_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
