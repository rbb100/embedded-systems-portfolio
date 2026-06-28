// tb_fir6_8bit.v
// Self-checking testbench for fir6_8bit.
// - Drives random + directed stimuli
// - Computes golden model with same fixed-point math (SHIFT + sat)
// - Compares DUT output and reports pass/fail.
//
// Run:
//   iverilog -g2005-sv -o sim fir6_8bit.v tb_fir6_8bit.v
//   vvp sim
//   gtkwave fir.vcd

`timescale 1ns/1ps

module tb_fir6_8bit;

    // Match DUT parameters here
    localparam signed [7:0] C0 =  8'sd3;
    localparam signed [7:0] C1 =  8'sd8;
    localparam signed [7:0] C2 =  8'sd13;
    localparam signed [7:0] C3 =  8'sd13;
    localparam signed [7:0] C4 =  8'sd8;
    localparam signed [7:0] C5 =  8'sd3;
    localparam integer SHIFT = 5;

    reg clk;
    reg rst_n;
    reg signed [7:0] sample_in;
    wire signed [7:0] y_out;

    fir6_8bit #(
        .C0(C0), .C1(C1), .C2(C2), .C3(C3), .C4(C4), .C5(C5),
        .SHIFT(SHIFT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_in(sample_in),
        .y_out(y_out)
    );

    // Clock
    initial clk = 1'b0;
    always #5 clk = ~clk; // 100MHz

    // Golden model state (history)
    integer x1, x2, x3, x4, x5;

    function signed [7:0] sat8;
        input integer v;
        begin
            if (v > 127)        sat8 = 8'sd127;
            else if (v < -128)  sat8 = -8'sd128;
            else                sat8 = v[7:0];
        end
    endfunction

    task apply_sample;
        input signed [7:0] s;
        begin
            // Drive sample slightly before posedge
            @(negedge clk);
            sample_in <= s;
        end
    endtask

    integer acc, scaled;
    integer errors;
    integer i;

    initial begin
        $dumpfile("fir.vcd");
        $dumpvars(0, tb_fir6_8bit);

        // Init
        sample_in = 8'sd0;
        rst_n = 1'b0;
        x1 = 0; x2 = 0; x3 = 0; x4 = 0; x5 = 0;
        errors = 0;

        // Hold reset for a few cycles
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        // --- Directed test: impulse ---
        apply_sample(8'sd32);
        for (i = 0; i < 15; i = i + 1) begin
            if (i != 0) apply_sample(8'sd0);

            @(posedge clk);
            #1;

            // Golden: acc = s*C0 + x1*C1 + ...
            acc = $signed(sample_in) * $signed(C0) +
                  x1 * $signed(C1) +
                  x2 * $signed(C2) +
                  x3 * $signed(C3) +
                  x4 * $signed(C4) +
                  x5 * $signed(C5);

            // Arithmetic shift right by SHIFT (integer keeps sign)
            scaled = acc >>> SHIFT;

            if (y_out !== sat8(scaled)) begin
                $display("IMPULSE MISMATCH @%0t: in=%0d y=%0d exp=%0d acc=%0d scaled=%0d",
                         $time, $signed(sample_in), $signed(y_out), $signed(sat8(scaled)), acc, scaled);
                errors = errors + 1;
            end

            // Update golden history after checking (matches DUT ordering)
            x5 = x4; x4 = x3; x3 = x2; x2 = x1; x1 = $signed(sample_in);
        end

        // --- Random test ---
        for (i = 0; i < 500; i = i + 1) begin
            apply_sample($random);

            @(posedge clk);
            #1;

            acc = $signed(sample_in) * $signed(C0) +
                  x1 * $signed(C1) +
                  x2 * $signed(C2) +
                  x3 * $signed(C3) +
                  x4 * $signed(C4) +
                  x5 * $signed(C5);

            scaled = acc >>> SHIFT;

            if (y_out !== sat8(scaled)) begin
                $display("RAND MISMATCH @%0t: in=%0d y=%0d exp=%0d acc=%0d scaled=%0d (i=%0d)",
                         $time, $signed(sample_in), $signed(y_out), $signed(sat8(scaled)), acc, scaled, i);
                errors = errors + 1;
            end

            x5 = x4; x4 = x3; x3 = x2; x2 = x1; x1 = $signed(sample_in);
        end

        if (errors == 0) begin
            $display("✅ PASS: No mismatches.");
        end else begin
            $display("❌ FAIL: %0d mismatches.", errors);
        end

        $finish;
    end

endmodule
