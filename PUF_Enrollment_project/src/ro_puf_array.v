// ro_puf_array.v
// --------------
// Simulation-friendly / hardware-aware RO-PUF array.
//
// SIM_MODE = 1:
//   Uses deterministic per-RO accumulators for reliable behavioral simulation.
//
// SIM_MODE = 0:
//   Keeps the same external interface, but for real hardware you would typically
//   replace the SIM_MODE block with true RO fabric logic.
//
// Response bit = 1 if count(ROi) > count(ROj) over measurement window.

module ro_puf_array #(
    parameter N_RO         = 16,
    parameter COUNTER_BITS = 16,
    parameter WINDOW_BITS  = 16,
    parameter WINDOW_SIZE  = 16'd5000,   // much faster for simulation
    parameter SIM_MODE     = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         measure_en,
    input  wire [$clog2(N_RO)-1:0]      ro_sel_i,
    input  wire [$clog2(N_RO)-1:0]      ro_sel_j,
    input  wire                         trojan_en,
    output reg                          response_bit,
    output reg                          done
);

    reg [COUNTER_BITS-1:0] counter_i;
    reg [COUNTER_BITS-1:0] counter_j;
    reg [WINDOW_BITS-1:0]  window_cnt;

    localparam IDLE    = 2'd0;
    localparam MEASURE = 2'd1;
    localparam COMPARE = 2'd2;

    reg [1:0] state;

    // ------------------------------------------------------------
    // Simulation-friendly per-RO "speed" table
    // Higher increment => faster virtual oscillator
    // ------------------------------------------------------------
    function [7:0] ro_step;
        input [$clog2(N_RO)-1:0] idx;
        begin
            case (idx)
                0:  ro_step = 8'd3;
                1:  ro_step = 8'd5;
                2:  ro_step = 8'd7;
                3:  ro_step = 8'd9;
                4:  ro_step = 8'd4;
                5:  ro_step = 8'd6;
                6:  ro_step = 8'd8;
                7:  ro_step = 8'd10;
                8:  ro_step = 8'd11;
                9:  ro_step = 8'd12;
                10: ro_step = 8'd13;
                11: ro_step = 8'd14;
                12: ro_step = 8'd15;
                13: ro_step = 8'd16;
                14: ro_step = 8'd17;
                15: ro_step = 8'd18;
                default: ro_step = 8'd1;
            endcase
        end
    endfunction

    wire trojan_hit_i = trojan_en && (ro_sel_i < N_RO/2);
    wire trojan_hit_j = trojan_en && (ro_sel_j < N_RO/2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            counter_i    <= 0;
            counter_j    <= 0;
            window_cnt   <= 0;
            response_bit <= 0;
            done         <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (measure_en) begin
                        counter_i  <= 0;
                        counter_j  <= 0;
                        window_cnt <= 0;
                        state      <= MEASURE;
                    end
                end

                MEASURE: begin
                    window_cnt <= window_cnt + 1'b1;

                    if (SIM_MODE) begin
                        // Deterministic simulation model
                        if (!trojan_hit_i)
                            counter_i <= counter_i + ro_step(ro_sel_i);
                        // Trojan hit freezes/slows selected lower-half RO
                        else
                            counter_i <= counter_i + 0;

                        if (!trojan_hit_j)
                            counter_j <= counter_j + ro_step(ro_sel_j);
                        else
                            counter_j <= counter_j + 0;
                    end else begin
                        // Placeholder for real hardware-oriented counting.
                        // For now this still gives deterministic behavior.
                        if (!trojan_hit_i)
                            counter_i <= counter_i + ro_step(ro_sel_i);
                        else
                            counter_i <= counter_i + 0;

                        if (!trojan_hit_j)
                            counter_j <= counter_j + ro_step(ro_sel_j);
                        else
                            counter_j <= counter_j + 0;
                    end

                    if (window_cnt >= WINDOW_SIZE - 1)
                        state <= COMPARE;
                end

                COMPARE: begin
                    response_bit <= (counter_i > counter_j) ? 1'b1 : 1'b0;
                    done         <= 1'b1;
                    state        <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule