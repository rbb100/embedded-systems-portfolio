`timescale 1ns/1ps

module tb_fsm;
    reg clk;
    reg rst_n;
    reg in_bit;
    wire out_bit;
    wire [1:0] current_state;

    // Instantiate DUT
    fsm_mod dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_bit(in_bit),
        .out_bit(out_bit),
        .state_out(current_state) // connect internal state
    );

    // Clock generation: 10ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    reg [27:0] seq;
    integer i;

    initial begin
        $dumpfile("fsm_dump.vcd");
        $dumpvars(0, tb_fsm);

        seq = 28'b0010100111010011101001101110; // 28-bit sequence

        rst_n = 0;
        in_bit = 0;
        #12;
        rst_n = 1;

        $display(" time(ns) | in | out | state ");
        $display("------------------------------");
        #1;
        $display("%8t |  x |  %b  |  %b (initial)", $time, out_bit, current_state);

        for (i = 27; i >= 0; i = i - 1) begin
            in_bit = seq[i];
            @(posedge clk);
            #1;
            $display("%8t |  %b |  %b  |  %b", $time, in_bit, out_bit, current_state);
        end

        #20;
        $finish;
    end
endmodule
