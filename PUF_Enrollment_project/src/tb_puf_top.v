`timescale 1ns/1ps

module tb_puf_top;

    reg  clk_125mhz = 0;
    reg  btn_rst    = 1;
    reg  uart_rx    = 1;
    wire uart_tx;
    wire [1:0] led;

    always #4 clk_125mhz = ~clk_125mhz;

    puf_top dut (
        .clk_125mhz(clk_125mhz),
        .btn_rst   (btn_rst),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .led       (led)
    );

    localparam integer BIT_NS = 8680;
    localparam [7:0] NL = 8'h0A;

    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            uart_rx = 1'b0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_NS);
            end
            uart_rx = 1'b1; #(BIT_NS);
        end
    endtask

    task send_ping;
        begin
            uart_send_byte("P");
            uart_send_byte("I");
            uart_send_byte("N");
            uart_send_byte("G");
            uart_send_byte(NL);
        end
    endtask

    task send_enroll;
        begin
            uart_send_byte("E");
            uart_send_byte("N");
            uart_send_byte("R");
            uart_send_byte("O");
            uart_send_byte("L");
            uart_send_byte("L");
            uart_send_byte(NL);
        end
    endtask

    task send_auth;
        begin
            uart_send_byte("A");
            uart_send_byte("U");
            uart_send_byte("T");
            uart_send_byte("H");
            uart_send_byte(NL);
        end
    endtask

    task send_chal0;
        begin
            uart_send_byte("C");
            uart_send_byte("H");
            uart_send_byte("A");
            uart_send_byte("L");
            uart_send_byte(":");
            uart_send_byte("0");
            uart_send_byte(NL);
        end
    endtask

    task send_trojan_on;
        begin
            uart_send_byte("T");
            uart_send_byte("R");
            uart_send_byte("O");
            uart_send_byte("J");
            uart_send_byte("A");
            uart_send_byte("N");
            uart_send_byte(":");
            uart_send_byte("O");
            uart_send_byte("N");
            uart_send_byte(NL);
        end
    endtask

    task send_trojan_off;
        begin
            uart_send_byte("T");
            uart_send_byte("R");
            uart_send_byte("O");
            uart_send_byte("J");
            uart_send_byte("A");
            uart_send_byte("N");
            uart_send_byte(":");
            uart_send_byte("O");
            uart_send_byte("F");
            uart_send_byte("F");
            uart_send_byte(NL);
        end
    endtask

    reg [7:0] mon_buf [0:31];
    integer   mon_len;
    reg       mon_active;

    task clear_monitor;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                mon_buf[i] = 8'h00;
            mon_len    = 0;
            mon_active = 1;
        end
    endtask

    task stop_monitor;
        begin
            mon_active = 0;
        end
    endtask

    task print_monitor;
        integer i;
        begin
            $write("  DUT TX: ");
            for (i = 0; i < mon_len; i = i + 1) begin
                if (mon_buf[i] == NL)
                    $write("\\n");
                else if (mon_buf[i] >= 8'd32 && mon_buf[i] < 8'd127)
                    $write("%c", mon_buf[i]);
                else
                    $write("[0x%02h]", mon_buf[i]);
            end
            $write("\n");
        end
    endtask

    task wait_dut_idle;
        begin
            wait(dut.fsm.state == 4'd0);
            repeat (2000) @(posedge clk_125mhz);
        end
    endtask

    always @(posedge clk_125mhz) begin
        if (mon_active && dut.fsm.tx_valid) begin
            if (mon_len < 32) begin
                mon_buf[mon_len] <= dut.fsm.tx_data;
                mon_len <= mon_len + 1;
            end
        end
    end

    initial begin
        $dumpfile("tb_puf_top.vcd");
        $dumpvars(0, tb_puf_top);

        btn_rst    = 1'b1;
        uart_rx    = 1'b1;
        mon_active = 0;
        mon_len    = 0;

        repeat (100) @(posedge clk_125mhz);
        btn_rst = 1'b0;

        repeat (500) @(posedge clk_125mhz);
        wait_dut_idle();

        $display("\n=== PUF RTL Debug Testbench ===\n");

        $display("[T1] PING -> expect READY");
        clear_monitor();
        send_ping();
        repeat (120000) @(posedge clk_125mhz);
        stop_monitor();
        print_monitor();
        wait_dut_idle();

        $display("[T2] ENROLL -> expect READY");
        clear_monitor();
        send_enroll();
        repeat (120000) @(posedge clk_125mhz);
        stop_monitor();
        print_monitor();
        wait_dut_idle();

        $display("[T3] AUTH -> expect READY");
        clear_monitor();
        send_auth();
        repeat (120000) @(posedge clk_125mhz);
        stop_monitor();
        print_monitor();
        wait_dut_idle();

        $display("[T4] CHAL:0 -> expect RESP:0 or RESP:1");
        clear_monitor();
        send_chal0();
        repeat (120000) @(posedge clk_125mhz);
        stop_monitor();
        print_monitor();
        wait_dut_idle();

        $display("[T5] TROJAN:ON -> expect ACK");
        clear_monitor();
        send_trojan_on();
        repeat (120000) @(posedge clk_125mhz);
        stop_monitor();
        print_monitor();
        $display("  LED[1]=%b (expect 1)", led[1]);
        wait_dut_idle();

        $display("[T6] CHAL:0 in trojan mode -> expect RESP");
        clear_monitor();
        send_chal0();
        repeat (120000) @(posedge clk_125mhz);
        stop_monitor();
        print_monitor();
        wait_dut_idle();

        $display("[T7] TROJAN:OFF -> expect ACK");
        clear_monitor();
        send_trojan_off();
        repeat (120000) @(posedge clk_125mhz);
        stop_monitor();
        print_monitor();
        $display("  LED[1]=%b (expect 0)", led[1]);
        wait_dut_idle();

        $display("\n=== Done ===\n");
        $finish;
    end

    initial begin
        #800_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule