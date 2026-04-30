module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx,
    output logic       tx_busy,
    output logic       tx_done
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        START   = 3'b001,
        DATA    = 3'b010,
        PARITY  = 3'b011,
        STOP    = 3'b100
    } state_t;

    state_t state;

    logic [15:0] clk_count;
    logic [2:0]  bit_index;
    logic [7:0]  tx_shift;
    logic        parity_bit;

    // ----------------------------------------------------------
    // FSM + Datapath (single always_ff block)
    // FIX: state is updated directly here; the separate state-register
    // block (state <= next_state) has been removed.
    // ----------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            clk_count  <= '0;
            bit_index  <= '0;
            tx_shift   <= '0;
            parity_bit <= 1'b0;
            tx         <= 1'b1;   // UART idle is HIGH
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                // ---- IDLE: Wait for tx_start ----
                IDLE: begin
                    tx        <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_count <= '0;
                    bit_index <= '0;
                    if (tx_start) begin
                        tx_shift   <= tx_data;
                        parity_bit <= ~^tx_data;   // Odd parity
                        tx_busy    <= 1'b1;
                        state      <= START;
                    end
                end

                // ---- START: Transmit start bit (LOW) ----
                START: begin
                    tx <= 1'b0;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        state     <= DATA;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // ---- DATA: Transmit 8 data bits LSB first ----
                DATA: begin
                    tx <= tx_shift[bit_index];
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        if (bit_index == 3'b111) begin
                            bit_index <= '0;
                            state     <= PARITY;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // ---- PARITY: Transmit odd parity bit ----
                PARITY: begin
                    tx <= parity_bit;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        state     <= STOP;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // ---- STOP: Transmit stop bit (HIGH) ----
                STOP: begin
                    tx <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        tx_done   <= 1'b1;
                        tx_busy   <= 1'b0;
                        state     <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule