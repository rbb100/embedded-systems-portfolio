// full_adder module is used to calculate P and G signals
module full_adder (
    input a,
    input b,
    input c_in,
    output sum,
    output c_out,
    output p, // Propagate signal
    output g  // Generate signal
);
    // Standard Full Adder logic
    assign sum = a ^ b ^ c_in;
    assign c_out = (a & b) | (c_in & (a ^ b));

    // P = A XOR B
    // G = A AND B
    assign p = a ^ b;
    assign g = a & b;
endmodule

module carry_lookahead_adder_8bit (
    input [7:0] A,
    input [7:0] B,
    input C_in,
    output [7:0] Sum,
    output C_out
);
    // Wires for Propagate (P), Generate (G), and internal Carry (C) signals
    wire [7:0] P;
    wire [7:0] G;
    wire [8:0] C; // C[0] is C_in, C[8] is C_out

    // C[0] is the input carry
    assign C[0] = C_in;

    // Instantiate 8 full adders to compute P, G, and Sum
    // using a generate block 
    generate
        genvar i;
        for (i = 0; i < 8; i = i + 1) begin : fa_inst
            full_adder fa_i (
                .a(A[i]),
                .b(B[i]),
                .c_in(C[i]),
                .sum(Sum[i]),
                .c_out(), // Unused in this CLA approach
                .p(P[i]),
                .g(G[i])
            );
        end
    endgenerate

    // Carry Lookahead Logic (Expanded Carry Computation for C[1] to C[4])
    // C[i+1] = G[i] | (P[i] & C[i])
    
    // C[1] = G[0] | (P[0] & C[0])
    assign C[1] = G[0] | (P[0] & C[0]);

    // C[2] = G[1] | (P[1] & C[1])
    assign C[2] = G[1] | (P[1] & G[0]) | (P[1] & P[0] & C[0]);

    // C[3] = G[2] | (P[2] & C[2])
    assign C[3] = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0]) | (P[2] & P[1] & P[0] & C[0]);

    // C[4] = G[3] | (P[3] & C[3])
    assign C[4] = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1]) | (P[3] & P[2] & P[1] & G[0]) | (P[3] & P[2] & P[1] & P[0] & C[0]);

    // Recursive calculation for C[5] through C[8] (C_out)
    // For simplicity and synthesis tool optimization, the remaining carries are often done recursively:
    assign C[5] = G[4] | (P[4] & C[4]);
    assign C[6] = G[5] | (P[5] & C[5]);
    assign C[7] = G[6] | (P[6] & C[6]);
    assign C[8] = G[7] | (P[7] & C[7]);

    // C_out is the final carry from the 8th stage
    assign C_out = C[8];

endmodule