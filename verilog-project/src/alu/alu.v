// 32-bit signed ALU
module alu (
    input  signed [31:0] a,
    input  signed [31:0] b,
    input        [2:0]   aluop,   // 000 and, 001 or, 010 add, 110 sub, 111 slt
    output reg signed [31:0] y
);

    always @* begin
        case (aluop)
            3'b000: y = a & b;                 // AND
            3'b001: y = a | b;                 // OR
            3'b010: y = a + b;                 // ADD (signed)
            3'b110: y = a - b;                 // SUB (signed)
            3'b111: y = (a < b) ? 32'sd1 : 32'sd0; // SLT (set-on-less-than, signed)
            default: y = 32'sbx;               // undefined op -> unknown
        endcase
    end
endmodule
