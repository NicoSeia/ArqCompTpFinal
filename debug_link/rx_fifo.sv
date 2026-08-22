`timescale 1ns / 1ps

module rx_fifo #(
    parameter B = 16,  // Bits en una palabra
    parameter W = 8   // Bits de direccion
)(
    input  logic         clk, reset,
    input  logic         rd, wr,
    input  logic [B-1:0] w_data,
    output logic         empty, full,
    output logic [B-1:0] r_data
);

    // Declaracion de senales
    logic [B-1:0] array_reg [2**W-1:0];      // Memoria de registros para almacenar datos
    logic [W-1:0] w_ptr_reg, w_ptr_next;     // Puntero de escritura (actual y proximo)
    logic [W-1:0] r_ptr_reg, r_ptr_next;     // Puntero de lectura (actual y proximo)
    logic         full_reg, full_next;       // Bandera de FIFO lleno
    logic         empty_reg, empty_next;     // Bandera de FIFO vacio


    // --- Cuerpo del modulo ---

    // Operacion de escritura en la memoria
    always_ff @(posedge clk)
        if (wr && !full_reg)                 // Solo se escribe si 'wr' esta activo y no esta lleno
            array_reg[w_ptr_reg] <= w_data;

    // Operacion de lectura de la memoria
    assign r_data = array_reg[r_ptr_reg];    // La salida siempre expone el dato apuntado por r_ptr_reg


    // Registros para los punteros y las banderas de estado
    always_ff @(posedge clk, posedge reset)
        if (reset)
        begin
            w_ptr_reg <= 0;
            r_ptr_reg <= 0;
            full_reg  <= 1'b0;               // Al inicio no esta lleno
            empty_reg <= 1'b1;               // Al inicio esta vacio
        end
        else
        begin
            w_ptr_reg <= w_ptr_next;         // Se actualiza el puntero de escritura
            r_ptr_reg <= r_ptr_next;         // Se actualiza el puntero de lectura
            full_reg  <= full_next;          // Se actualiza la bandera 'full'
            empty_reg <= empty_next;         // Se actualiza la bandera 'empty'
        end


    // Logica combinacional para calcular el proximo estado de los punteros y banderas
    always_comb
    begin
        // Por defecto, los valores se mantienen
        w_ptr_next = w_ptr_reg;
        r_ptr_next = r_ptr_reg;
        full_next  = full_reg;
        empty_next = empty_reg;

        // Se evaluan las operaciones de lectura/escritura
        if (wr && !full_reg && rd && !empty_reg) // Caso 1: Escritura y Lectura simultanea
        begin
           w_ptr_next = w_ptr_reg + 1;
           r_ptr_next = r_ptr_reg + 1;
        end
        else if (wr && !full_reg)              // Caso 2: Solo Escritura
        begin
            w_ptr_next = w_ptr_reg + 1;
            empty_next = 1'b0;                 // Si se escribe, ya no puede estar vacio
            if ((w_ptr_reg + 1) == r_ptr_reg)
                full_next = 1'b1;              // Si el proximo puntero de escritura alcanza al de lectura, se llenara
        end
        else if (rd && !empty_reg)             // Caso 3: Solo Lectura
        begin
            r_ptr_next = r_ptr_reg + 1;
            full_next = 1'b0;                  // Si se lee, ya no puede estar lleno
            if ((r_ptr_reg + 1) == w_ptr_reg)
                empty_next = 1'b1;             // Si el proximo puntero de lectura alcanza al de escritura, se vaciara
        end
    end

    // Asignacion final a las salidas del modulo
    assign full = full_reg;
    assign empty = empty_reg;

endmodule