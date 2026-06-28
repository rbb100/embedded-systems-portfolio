// Moore FSM: output = 1 when number of 1's so far is a multiple of 3.
// Exposes internal state as an output for monitoring.

module fsm_mod (
    input  wire clk,
    input  wire rst_n,     // active low reset
    input  wire in_bit,    // serial input bit
    output reg  out_bit,   // output after each bit received
    output wire [1:0] state_out // <-- exposed state for observation
);

    // State encoding
    localparam S0 = 2'b00; // count mod 3 = 0 → output 1
    localparam S1 = 2'b01; // count mod 3 = 1 → output 0
    localparam S2 = 2'b10; // count mod 3 = 2 → output 0

    reg [1:0] state, next_state;

    // Sequential block: state register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S0; // initial: 0 ones → output = 1
        else
            state <= next_state;
    end

    // Combinational block: next state + output
    always @(*) begin
        next_state = state;
        out_bit = 1'b0;

        case (state)
            S0: begin
                out_bit = 1'b1;
                if (in_bit) next_state = S1;
                else        next_state = S0;
            end
            S1: begin
                out_bit = 1'b0;
                if (in_bit) next_state = S2;
                else        next_state = S1;
            end
            S2: begin
                out_bit = 1'b0;
                if (in_bit) next_state = S0;
                else        next_state = S2;
            end
            default: begin
                next_state = S0;
                out_bit = 1'b1;
            end
        endcase
    end

    assign state_out = state;

endmodule
