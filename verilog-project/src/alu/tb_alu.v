`timescale 1ns/1ps

module tb_alu;
    // DUT I/O
    reg  signed [31:0] a, b;
    reg         [2:0]  aluop;
    wire signed [31:0] y;

    // Instantiate your ALU (module name must be "alu")
    alu dut(.a(a), .b(b), .aluop(aluop), .y(y));

    // pretty printer: ord = "1st", "2nd", ...
    task run_case;
        input [31:0] dummy;             // unused placeholder to allow simple numbering if you want
        input [127:0] ord;              // e.g., "1st", "2nd", ...
        input  signed [31:0] ta, tb;
        input         [2:0]  top;
    begin
        a = ta; b = tb; aluop = top; #1; // small delta for combinational settle
        $display("%0s Test data: input A is %0d, input B is %0d, ALUOp is %03b, result is %0d.",
                 ord, a, b, aluop, y);
    end
    endtask

    initial begin
        // 1) ADD  (010)
        run_case(0, "1st", 32'sd1,  32'sd2,  3'b010);
        // 2) SUB  (110)
        run_case(0, "2nd", 32'sd3,  32'sd4,  3'b110);
        // 3) AND  (000)
        run_case(0, "3rd", 32'sd5,  32'sd12, 3'b000);
        // 4) OR   (001)
        run_case(0, "4th", 32'sd5,  32'sd12, 3'b001);
        // 5) SLT  (111)  signed compare: -1 < 1 -> 1
        run_case(0, "5th", -32'sd1, 32'sd1,  3'b111);

        $finish;
    end
endmodule
