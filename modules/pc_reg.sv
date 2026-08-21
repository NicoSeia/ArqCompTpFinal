`timescale 1ps/1ps
module pc_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        stall = 1'b0,
    input  logic [31:0] pc_next,
    output logic [31:0] pc
);

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= 32'd0;
    end else if (!stall) begin
      pc <= pc_next;      
    end
  end

endmodule