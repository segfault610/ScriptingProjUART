`timescale 1ns/1ps

class uart_transaction;
    logic [7:0] data;

    function void gen();
        data = $urandom_range(0, 255);
    endfunction
endclass

class uart_scoreboard;
    int pass_count;
    int fail_count;
    int fd;

    function new(string log_file);
        pass_count = 0;
        fail_count = 0;
        fd = $fopen(log_file, "w");
        if (fd == 0)
            $fatal(1, "Could not open scoreboard log file: %s", log_file);
        $fwrite(fd, "# UART Top-Level Scoreboard Log\n");
        $fwrite(fd, "# Format: STATUS | TX_DATA | RX_DATA | PARITY_ERR | DONE\n");
        $fwrite(fd, "#--------------------------------------------------\n");
    endfunction

    function void check(
        logic [7:0] tx_data,
        logic [7:0] rx_data,
        logic       rx_error,
        logic       rx_done
    );
        string status;
        if (rx_done && !rx_error && rx_data === tx_data) begin
            status = "PASS";
            pass_count++;
        end else begin
            status = "FAIL";
            fail_count++;
        end
        $display("[%s] TX=0x%02X RX=0x%02X rx_done=%0b rx_error=%0b",
                  status, tx_data, rx_data, rx_done, rx_error);
        $fwrite(fd, "%s | TX=0x%02X | RX=0x%02X | parity_err=%0b | done=%0b\n",
                status, tx_data, rx_data, rx_error, rx_done);
    endfunction

    function void summary();
        $display("======================================");
        $display(" SCOREBOARD: PASS=%0d FAIL=%0d TOTAL=%0d",
                  pass_count, fail_count, pass_count + fail_count);
        $display("======================================");
        $fwrite(fd, "#--------------------------------------------------\n");
        $fwrite(fd, "SUMMARY: PASS=%0d FAIL=%0d TOTAL=%0d\n",
                pass_count, fail_count, pass_count + fail_count);
        $fclose(fd);
    endfunction
endclass

module tb_uart_top_random;

    parameter CLK_FREQ   = 50_000_000;
    parameter BAUD_RATE  = 115200;
    parameter NUM_TESTS  = 50;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD   = 1_000_000_000 / CLK_FREQ;

    logic       clk;
    logic       rst_n;
    logic [7:0] tx_data_in;
    logic       tx_start;
    logic       tx_busy;
    logic       tx_done;
    logic [7:0] rx_data_out;
    logic       rx_done;
    logic       rx_error;

    logic loopback_wire;

    uart_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (tx_data_in),
        .tx_start (tx_start),
        .tx_line  (loopback_wire),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done),
        .rx_line  (loopback_wire),
        .rx_data  (rx_data_out),
        .rx_done  (rx_done),
        .rx_error (rx_error)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        uart_transaction tr;
        uart_scoreboard  sb;
        logic [7:0] sent_data;
        int seed_val;
        string log_name;

        if (!$value$plusargs("seed=%0d", seed_val))
            seed_val = 42;

        $srandom(seed_val);
        $sformat(log_name, "scoreboard_seed%0d.log", seed_val);

        sb = new(log_name);
        tr = new();

        $display("===========================================");
        $display(" UART Top Random Testbench - Team 12");
        $display(" Seed=%0d  Tests=%0d  Log=%s", seed_val, NUM_TESTS, log_name);
        $display("===========================================");

        rst_n      = 0;
        tx_start   = 0;
        tx_data_in = '0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        repeat(NUM_TESTS) begin
            tr.gen();
            sent_data = tr.data;

            tx_data_in = sent_data;
            @(posedge clk);

            tx_start = 1;
            @(posedge clk);
            tx_start = 0;

            @(posedge clk iff (rx_done || rx_error));

            sb.check(sent_data, rx_data_out, rx_error, rx_done);

            @(posedge clk iff (!tx_busy));
            repeat(CLKS_PER_BIT * 5) @(posedge clk);
        end

        sb.summary();
        $finish;
    end

    initial begin
        #(CLK_PERIOD * CLKS_PER_BIT * (NUM_TESTS + 5) * 20);
        $display("[TIMEOUT] Simulation exceeded max time!");
        $finish;
    end

    initial begin
        $dumpfile("tb_uart_top_random.vcd");
        $dumpvars(0, tb_uart_top_random);
    end

endmodule
