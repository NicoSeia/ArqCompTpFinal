`timescale 1ps/1ps
// Nota Verilog-2001: stall ya no tiene valor por defecto (antes 1'b0).
module pc_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,     // antes default 1'b0
    input  wire [31:0] pc_next,
    output reg  [31:0] pc
);

  always @(posedge clk) begin
    if (rst) begin
      pc <= 32'd0;
    end else if (!stall) begin
      pc <= pc_next;
    end
  end

endmodule
