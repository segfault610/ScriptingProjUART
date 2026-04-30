`timescale 1ns/1ps

module tb_uart_rx_directed;

    // ---- Parameters (must match DUT) ----
    parameter CLK_FREQ  = 50_000_000;
    parameter BAUD_RATE = 115200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD   = 1_000_000_000 / CLK_FREQ; // ns

    // ---- DUT signals ----
    logic       clk;
    logic       rst_n;
    logic       rx;
    logic [7:0] rx_data;
    logic       rx_done;
    logic       rx_error;

    // ---- Scoreboard counters ----
    int pass_count = 0;
    int fail_count = 0;

    // ---- DUT Instantiation ----
    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (rx),
        .rx_data  (rx_data),
        .rx_done  (rx_done),
        .rx_error (rx_error)
    );

    // ---- Clock generation ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Task: Send one UART frame ----
    // Adds odd parity automatically
    task automatic send_uart_frame(input logic [7:0] data, input logic inject_parity_err = 0);
        logic parity;
        int i;
        parity = ~^data; // Odd parity

        // Start bit
        rx = 0;
        repeat(CLKS_PER_BIT) @(posedge clk);

        // Data bits LSB first
        for (i = 0; i < 8; i++) begin
            rx = data[i];
            repeat(CLKS_PER_BIT) @(posedge clk);
        end

        // Parity bit (optionally corrupt for error injection)
        rx = inject_parity_err ? ~parity : parity;
        repeat(CLKS_PER_BIT) @(posedge clk);

        // Stop bit
        rx = 1;
        repeat(CLKS_PER_BIT) @(posedge clk);

        // Extra idle time between frames
        repeat(CLKS_PER_BIT * 2) @(posedge clk);
    endtask

    // ---- Task: Check result ----
    task automatic check(
        input logic [7:0] expected_data,
        input logic       expect_error,
        input string      test_name
    );
        // Wait for rx_done or rx_error
        @(posedge clk iff (rx_done || rx_error));

        if (expect_error) begin
            if (rx_error) begin
                $display("[PASS] %s | rx_error asserted as expected", test_name);
                pass_count++;
            end else begin
                $display("[FAIL] %s | Expected rx_error=1, got rx_error=0", test_name);
                fail_count++;
            end
        end else begin
            if (rx_done && !rx_error && rx_data === expected_data) begin
                $display("[PASS] %s | rx_data=0x%02X as expected", test_name, rx_data);
                pass_count++;
            end else begin
                $display("[FAIL] %s | Expected=0x%02X Got=0x%02X rx_done=%0b rx_error=%0b",
                          test_name, expected_data, rx_data, rx_done, rx_error);
                fail_count++;
            end
        end
    endtask

    // ============================================================
    // Main test sequence
    // ============================================================
    initial begin
        $display(" UART RX Directed Testbench - Team 12");

        // Reset
        rst_n = 0;
        rx    = 1;   // Idle line
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5)  @(posedge clk);

        // ---- Test 1: 0xA5 ----
        fork
            send_uart_frame(8'hA5);
            check(8'hA5, 0, "TC1: Data=0xA5");
        join

        // ---- Test 2: 0x00 ----
        fork
            send_uart_frame(8'h00);
            check(8'h00, 0, "TC2: Data=0x00");
        join

        // ---- Test 3: 0xFF ----
        fork
            send_uart_frame(8'hFF);
            check(8'hFF, 0, "TC3: Data=0xFF");
        join

        // ---- Test 4: 0x55 ----
        fork
            send_uart_frame(8'h55);
            check(8'h55, 0, "TC4: Data=0x55");
        join

        // ---- Test 5: 0xAA ----
        fork
            send_uart_frame(8'hAA);
            check(8'hAA, 0, "TC5: Data=0xAA");
        join

        // ---- Test 6: 0x12 ----
        fork
            send_uart_frame(8'h12);
            check(8'h12, 0, "TC6: Data=0x12");
        join

        // ---- Test 7: 0xDE ----
        fork
            send_uart_frame(8'hDE);
            check(8'hDE, 0, "TC7: Data=0xDE");
        join

        // ---- Test 8: 0x7F ----
        fork
            send_uart_frame(8'h7F);
            check(8'h7F, 0, "TC8: Data=0x7F");
        join

        // ---- Test 9: 0x80 ----
        fork
            send_uart_frame(8'h80);
            check(8'h80, 0, "TC9: Data=0x80");
        join

        // ---- Test 10: 0x01 ----
        fork
            send_uart_frame(8'h01);
            check(8'h01, 0, "TC10: Data=0x01");
        join

        // ---- Test 11: Parity Error Injection ----
        fork
            send_uart_frame(8'hBE, 1);   // inject_parity_err=1
            check(8'hBE, 1, "TC11: Parity Error Injection");
        join

        // ---- Test 12: 0xC3 ----
        fork
            send_uart_frame(8'hC3);
            check(8'hC3, 0, "TC12: Data=0xC3");
        join

        // ---- Summary ----
        $display("======================================");
        $display(" Results: PASS=%0d  FAIL=%0d  TOTAL=%0d",
                  pass_count, fail_count, pass_count + fail_count);
        $display("======================================");

        if (fail_count > 0)
            $display("** SOME TESTS FAILED - Review waveforms **");
        else
            $display("** ALL TESTS PASSED **");

        $finish;
    end

    // ---- Timeout watchdog ----
    // FIX: Original timeout (CLK_PERIOD * CLKS_PER_BIT * 200) was only ~1.7 ms,
    // not enough to cover 12 UART frames (~1.1 ms) plus reset/idle overhead.
    // Each frame is 12 bits * CLKS_PER_BIT clocks; 12 frames * 15 bits * CLKS_PER_BIT
    // with margin gives a safe upper bound of CLKS_PER_BIT * 12 * 20.
    initial begin
        #(CLK_PERIOD * CLKS_PER_BIT * 12 * 20);
        $display("[TIMEOUT] Simulation exceeded maximum time!");
        $finish;
    end

    // ---- VCD dump for waveform viewer ----
    initial begin
        $dumpfile("tb_uart_rx_directed.vcd");
        $dumpvars(0, tb_uart_rx_directed);
    end

endmodule