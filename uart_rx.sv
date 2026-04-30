module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_done,
    output logic       rx_error
);
 
    localparam CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT      = CLKS_PER_BIT / 2;
 
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
    logic [7:0]  rx_shift;
    logic rx_sync1, rx_sync2; 
    logic parity_calc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            clk_count   <= '0;
            bit_index   <= '0;
            rx_shift    <= '0;
            rx_data     <= '0;
            rx_done     <= 1'b0;
            rx_error    <= 1'b0;
            parity_calc <= 1'b0;
        end else begin
            rx_done  <= 1'b0;
            rx_error <= 1'b0;
 
            case (state)
                IDLE: begin
                    clk_count   <= '0;
                    bit_index   <= '0;
                    parity_calc <= 1'b0;
                    if (rx_sync2 == 1'b0)
                        state <= START;
                end
 
                START: begin
                    if (clk_count == HALF_BIT - 1) begin
                        clk_count <= '0;
                        if (rx_sync2 == 1'b0)       
                            state <= DATA;
                        else
                            state <= IDLE;           
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
 
                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count               <= '0;
                        rx_shift[bit_index]     <= rx_sync2;
                        parity_calc             <= parity_calc ^ rx_sync2;
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
 
                PARITY: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        if ((parity_calc ^ rx_sync2) != 1'b1)
                            rx_error <= 1'b1;
                        state <= STOP;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
 
                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        if (rx_sync2 == 1'b1) begin   
                            rx_data <= rx_shift;
                            rx_done <= 1'b1;
                        end else begin
                            rx_error <= 1'b1;          
                        end
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
 
                default: state <= IDLE;
            endcase
        end
    end
endmodule
