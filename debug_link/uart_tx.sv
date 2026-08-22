module uart_tx #(
    parameter NB_DATA = 8,
    parameter S_TICK = 16
) (
    input logic clk, reset,
    input logic tx,                                                             // Señal de arranque de transmisión
    input logic s_tick,                                                         // Pulso del generador de baud rate
    input logic [NB_DATA-1:0] data_in,                                          // Dato de entrada (paralelo)
    output logic tx_done_tick,                                                  // Pulso de finalización de transmisión
    output logic tx_serial                                                      // Salida serial de datos (idle en 1)
);
    logic [1:0]         state_reg, state_next;
    logic [2:0]         n_data_bits_reg, n_data_bits_next;
    logic [3:0]         s_tick_reg, s_tick_next;                                // Contador de s_ticks
    logic [NB_DATA-1:0] data_reg, data_next;                                    // Registro para almacenar el dato a enviar
    logic tx_reg, tx_next;                                                      // Registro de la salida serial (para evitar glitches)

    localparam [1:0]                                                            // Definición de los estados de la máquina
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11;

    // Bloque secuencial: actualización de registros en cada flanco de clock
    always_ff @(posedge clk) begin
        if (reset) begin
            state_reg       <= IDLE;
            n_data_bits_reg <= 0;
            s_tick_reg      <= 0;
            data_reg        <= 0;
            tx_reg          <= 1'b1;                                            // La línea TX en reposo (idle) se mantiene en '1'
        end else begin
            state_reg       <= state_next;                                      // Se carga el siguiente estado
            n_data_bits_reg <= n_data_bits_next;                                // Se carga el índice del bit actual
            s_tick_reg      <= s_tick_next;                                     // Se carga el tick actual
            data_reg        <= data_next;                                       // Se carga el dato 
            tx_reg          <= tx_next;                                         // Se actualiza la salida serial
        end
    end

    // Bloque combinacional: lógica de próximo estado y salidas
    always_comb begin
        // Asignaciones por defecto: mantener valores anteriores
        state_next       = state_reg;
        tx_done_tick     = 1'b0;                                                // El pulso de 'done' es '1' solo por un ciclo
        data_next        = data_reg;
        n_data_bits_next = n_data_bits_reg;
        s_tick_next      = s_tick_reg;
        tx_next          = tx_reg;

        case (state_reg)
            IDLE: begin
                tx_next = 1'b1;                                                 // Mantiene la línea en alto (idle)
                if (tx) begin                                                   // Detecta la señal de arranque 'tx'
                    state_next  = START;
                    s_tick_next = 0;                                            // Resetea el contador de ticks
                    data_next   = data_in;                                      // Carga el dato paralelo que se va a enviar
                end
            end

            START: begin
                tx_next = 1'b0;                                                 // Envía el bit de START (un '0')
                if (s_tick) begin
                    if (s_tick_reg == 15) begin                         // Espera un período de bit completo (S_TICK ticks)
                        s_tick_next      = 0;
                        n_data_bits_next = 0;                                   // Prepara el contador para el primer bit de dato
                        state_next       = DATA;                                // Pasa al estado de envío de datos
                    end else begin
                        s_tick_next = s_tick_reg + 1;                           // Incrementa el contador de ticks
                    end
                end
            end

            DATA: begin
                tx_next = data_reg[0];                                          // Pone en la salida el bit menos significativo (LSB)
                if (s_tick) begin
                    if (s_tick_reg == 15) begin                           // Espera un período de bit completo
                        s_tick_next = 0;
                        data_next = data_reg >> 1;                              // Desplaza el dato a la derecha para preparar el siguiente bit
                        if (n_data_bits_reg == NB_DATA-1) begin                 // Si ya se enviaron todos los bits
                            state_next = STOP;                                  // Pasa al estado de STOP
                        end else begin
                            n_data_bits_next = n_data_bits_reg + 1;             // Incrementa el contador de bits enviados
                        end
                    end else begin
                        s_tick_next = s_tick_reg + 1;                           // Incrementa el contador de ticks
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;                                                 // Envía el bit de STOP (un '1')
                if (s_tick) begin
                    if (s_tick_reg == (S_TICK-1)) begin                           // Espera un período de bit completo
                        state_next   = IDLE;                                    // Vuelve al estado IDLE
                        tx_done_tick = 1'b1;                                    // Genera el pulso de 'done'
                    end else begin
                        s_tick_next = s_tick_reg + 1;                           // Incrementa el contador de ticks
                    end
                end
            end
        endcase
    end
    
    assign tx_serial = tx_reg;                                                  // Asigna la salida registrada a la línea serial final
endmodule