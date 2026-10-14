module board_top (
    input  wire clk,        // 100 MHz Basys3 (W5)
    input  wire reset,      // btn (U18)
    input  wire rx_serial,
    output wire tx_serial
);
    wire clk_core, locked;

    clk_wiz_0 u_clk (
        .clk_in1 (clk),
        .reset   (1'b0),
        .clk_out1(clk_core),
        .locked  (locked)
    );

    // el core se mantiene en reset hasta que el MMCM enganche
    system_top #(
        .CLK_FREQ (55_000_000),   // MUY IMPORTANTE: el baud depende de esto
        .BAUD_RATE(9600)
    ) u_sys (
        .clk      (clk_core),
        .reset    (reset | ~locked),
        .rx_serial(rx_serial),
        .tx_serial(tx_serial)
    );
endmodule
