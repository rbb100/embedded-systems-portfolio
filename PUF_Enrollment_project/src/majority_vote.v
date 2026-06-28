// majority_vote.v
// ---------------
// Majority Vote Stabilizer for RO-PUF responses.
//
// Collects N_VOTES single-bit measurements from the PUF array
// and outputs the majority result. Eliminates transient noise
// and reduces BER significantly.
//
// N_VOTES must be odd (9 or 15 recommended per project proposal).
//
// Interface:
//   - Pulses measure_req to ro_puf_array, waits for puf_done
//   - After N_VOTES samples, outputs stable_bit and asserts valid

module majority_vote #(
    parameter N_VOTES = 9   // Must be odd. Use 9 or 15.
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,          // start a new majority-vote measurement
    input  wire puf_done,       // single measurement complete from ro_puf_array
    input  wire puf_bit,        // raw bit from ro_puf_array
    output reg  measure_req,    // trigger next measurement in ro_puf_array
    output reg  stable_bit,     // majority-voted output bit
    output reg  valid           // stable_bit is ready
);

    localparam VOTE_BITS = $clog2(N_VOTES) + 1;

    reg [VOTE_BITS-1:0] vote_count;   // number of 1s seen
    reg [$clog2(N_VOTES):0] sample_count; // total samples taken

    // ── FSM ───────────────────────────────────────────────────────────────────
    localparam IDLE    = 2'd0;
    localparam REQUEST = 2'd1;
    localparam WAIT    = 2'd2;
    localparam DECIDE  = 2'd3;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            vote_count   <= 0;
            sample_count <= 0;
            measure_req  <= 0;
            stable_bit   <= 0;
            valid        <= 0;
        end else begin
            case (state)
                IDLE: begin
                    valid       <= 0;
                    measure_req <= 0;
                    if (start) begin
                        vote_count   <= 0;
                        sample_count <= 0;
                        state        <= REQUEST;
                    end
                end

                REQUEST: begin
                    measure_req <= 1;
                    state       <= WAIT;
                end

                WAIT: begin
                    measure_req <= 0;
                    if (puf_done) begin
                        vote_count   <= vote_count + puf_bit;
                        sample_count <= sample_count + 1;
                        if (sample_count >= N_VOTES - 1)
                            state <= DECIDE;
                        else
                            state <= REQUEST;
                    end
                end

                DECIDE: begin
                    stable_bit <= (vote_count > N_VOTES / 2) ? 1'b1 : 1'b0;
                    valid      <= 1;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
