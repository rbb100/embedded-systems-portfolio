`timescale 1ns / 1ps

module carry_lookahead_adder_tb;

    // Inputs
    reg [7:0] A_in;
    reg [7:0] B_in;
    reg C_in_in;

    // Outputs
    wire [7:0] Sum_out;
    wire C_out_out;

    // Instantiate the 8-bit Carry Lookahead Adder
    carry_lookahead_adder_8bit uut (
        .A(A_in),
        .B(B_in),
        .C_in(C_in_in),
        .Sum(Sum_out),
        .C_out(C_out_out)
    );

    // Initial block for stimulus generation
    initial begin
        // Initialize Inputs
        A_in = 8'b0;
        B_in = 8'b0;
        C_in_in = 1'b0;

        $display("-----------------------------------------------------------------------");
        $display("Time | A   (H) | B   (H) | Cin | Expected (H) | Sum  (H) | Cout | Check");
        $display("-----------------------------------------------------------------------");

        // Test Case 1: Simple addition (5 + 10)
        #10 A_in = 8'd5; B_in = 8'd10; C_in_in = 1'b0;
        #10 check_result(A_in, B_in, C_in_in, Sum_out, C_out_out);

        // Test Case 2: Max values (255 + 0)
        #10 A_in = 8'hFF; B_in = 8'h00; C_in_in = 1'b0;
        #10 check_result(A_in, B_in, C_in_in, Sum_out, C_out_out);

        // Test Case 3: Overflow (255 + 1)
        #10 A_in = 8'hFF; B_in = 8'h01; C_in_in = 1'b0;
        #10 check_result(A_in, B_in, C_in_in, Sum_out, C_out_out);

        // Test Case 4: Carry-in check (127 + 128 + C_in=1)
        #10 A_in = 8'd127; B_in = 8'd128; C_in_in = 1'b1;
        #10 check_result(A_in, B_in, C_in_in, Sum_out, C_out_out);

        // Test Case 5: Zero + Zero
        #10 A_in = 8'd0; B_in = 8'd0; C_in_in = 1'b0;
        #10 check_result(A_in, B_in, C_in_in, Sum_out, C_out_out);

        #10 $finish;
    end

    // Task to calculate expected result and compare with aligned output
    task check_result;
        input [7:0] A;
        input [7:0] B;
        input C_in;
        input [7:0] Sum_actual;
        input C_out_actual;
        reg [8:0] sum_expected;
        reg [7:0] Sum_expected_val;
        reg C_out_expected_val;
        reg [0:0] pass_fail;

        begin
            sum_expected = A + B + C_in;
            Sum_expected_val = sum_expected[7:0];
            C_out_expected_val = sum_expected[8];

            pass_fail = (Sum_actual == Sum_expected_val) && (C_out_actual == C_out_expected_val);

            // Using fixed-width formatters for clean alignment
            $display("%0tns | %3d (%2h) | %3d (%2h) | %1b | %4d (%2h) | %4d (%2h) | %4b | %4s",
                $time,
                A, A,
                B, B,
                C_in,
                sum_expected, Sum_expected_val,
                Sum_actual, Sum_actual,
                C_out_actual,
                pass_fail ? "PASS" : "FAIL"
            );
        end
    endtask

endmodule