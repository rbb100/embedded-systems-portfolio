// fir6_8bit.v
// 6-tap FIR filter with 8-bit signed input, 8-bit signed coefficients, and 8-bit quantized output.
// - Computes: y[n] = sum_{k=0..5} h[k] * x[n-k]
// - Fixed-point scaling via arithmetic right shift (SHIFT).
// - Saturation to signed 8-bit output range [-128, 127].

`timescale 1ns/1ps

module fir6_8bit #(
    
    parameter signed [7:0] C0 =  8'sd3,
    parameter signed [7:0] C1 =  8'sd8,
    parameter signed [7:0] C2 =  8'sd13,
    parameter signed [7:0] C3 =  8'sd13,
    parameter signed [7:0] C4 =  8'sd8,
    parameter signed [7:0] C5 =  8'sd3,

    // Scaling shift (arithmetic): larger SHIFT => smaller output magnitude.
    // Choose SHIFT based on coefficient sum / expected dynamic range.
    parameter integer SHIFT = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,       // active-low synchronous reset
    input  wire signed   [7:0]   sample_in,  // x[n]
    output reg  signed   [7:0]   y_out       // quantized output
);

    // Delay line for x[n-1]..x[n-5]
    reg signed [7:0] x1, x2, x3, x4, x5;

    // Internal arithmetic widths
    // product: 8b * 8b -> 16b signed
    wire signed [15:0] p0 = sample_in * C0;
    wire signed [15:0] p1 = x1        * C1;
    wire signed [15:0] p2 = x2        * C2;
    wire signed [15:0] p3 = x3        * C3;
    wire signed [15:0] p4 = x4        * C4;
    wire signed [15:0] p5 = x5        * C5;

    // Sum of 6 products: use a wider accumulator
    wire signed [23:0] acc_w = {{8{p0[15]}},p0} +
                              {{8{p1[15]}},p1} +
                              {{8{p2[15]}},p2} +
                              {{8{p3[15]}},p3} +
                              {{8{p4[15]}},p4} +
                              {{8{p5[15]}},p5};

    // Scaled value (still wide)
    wire signed [23:0] scaled_w = acc_w >>> SHIFT;

    // Saturation helper
    function signed [7:0] sat8;
        input signed [23:0] v;
        begin
            if (v > 24'sd127)      sat8 = 8'sd127;
            else if (v < -24'sd128) sat8 = -8'sd128;
            else                    sat8 = v[7:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            x1 <= 8'sd0; x2 <= 8'sd0; x3 <= 8'sd0; x4 <= 8'sd0; x5 <= 8'sd0;
            y_out <= 8'sd0;
        end else begin
            // Update output for current sample & history
            y_out <= sat8(scaled_w);

            // Shift delay line
            x5 <= x4;
            x4 <= x3;
            x3 <= x2;
            x2 <= x1;
            x1 <= sample_in;
        end
    end

endmodule
