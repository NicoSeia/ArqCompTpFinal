`timescale 1ps/1ps
module pipe_reg #(
    parameter type T = logic
) (
    input  logic clk,
    input  logic rst,
    input  logic flush,
    input  logic stall,
    input  T     d,
    output T     q
);

  always_ff @(posedge clk) begin
    if (rst || flush) begin
      q <= '0;
    end else if (!stall) begin
      q <= d;
    end
  end

endmodule