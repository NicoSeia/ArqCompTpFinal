`timescale 1ns / 1ps

module baud_rate_gen #(
    parameter CLK_FREQ = 100_000_000,  // Frecuencia de reloj, ej. 100 MHz
    parameter BAUD     = 9600          // Baud rate deseado
)(
    input  logic clk,
    input  logic reset,
    output logic tick
);

    // Número de ciclos de reloj por cada "tick" de oversampling (16x)
    localparam integer DIVISOR = CLK_FREQ / (BAUD * 16);
    localparam integer NB_COUNT = $clog2(DIVISOR);

    logic [NB_COUNT-1:0] count_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            count_reg <= 0;
            tick <= 1'b0;
        end else begin
            if (count_reg == DIVISOR - 1) begin
                count_reg <= 0;
                tick <= 1'b1;     // Pulso de un solo ciclo
            end else begin
                count_reg <= count_reg + 1'b1;
                tick <= 1'b0;
            end
        end
    end

endmodule