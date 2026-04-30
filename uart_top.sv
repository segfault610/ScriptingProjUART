module uart_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst_n,

    // TX interface
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_line,
    output logic       tx_busy,
    output logic       tx_done,

    // RX interface
    input  logic       rx_line,
    output logic [7:0] rx_data,
    output logic       rx_done,
    output logic       rx_error
);

    // ----------------------------------------------------------
    // TX instance
    // ----------------------------------------------------------
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (tx_data),
        .tx_start (tx_start),
        .tx       (tx_line),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    // ----------------------------------------------------------
    // RX instance
    // ----------------------------------------------------------
    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (rx_line),
        .rx_data  (rx_data),
        .rx_done  (rx_done),
        .rx_error (rx_error)
    );

endmodule