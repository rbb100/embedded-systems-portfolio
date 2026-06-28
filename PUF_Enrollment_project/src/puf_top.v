// puf_top.v
// ---------
// Top-level wrapper for PUF Attestation System on Zybo Z7
// Using 125MHz on-board clock directly (no MMCM needed)
// CLK_FREQ = 125_000_000 throughout all modules

module puf_top (
    input  wire clk_125mhz,   // Zybo on-board oscillator (125 MHz)
    input  wire btn_rst,      // BTN0 - active high reset button
    input  wire uart_rx,      // UART RX from Raspberry Pi
    output wire uart_tx,      // UART TX to Raspberry Pi
    output wire [1:0] led     // LED[0]=pass, LED[1]=trojan
);

    // ── Clock - 125MHz used directly ─────────────────────────────────────────
    wire sys_clk;
    assign sys_clk = clk_125mhz;

    // ── Reset Synchronizer ────────────────────────────────────────────────────
    // btn_rst is active-high on Zybo → invert for active-low rst_n
    reg rst_sync1, rst_sync2;
    wire rst_n = rst_sync2;

    always @(posedge sys_clk) begin
        rst_sync1 <= ~btn_rst;
        rst_sync2 <= rst_sync1;
    end

    // ── Command FSM ───────────────────────────────────────────────────────────
    wire trojan_en_w;
    wire led_pass_w;
    wire led_trojan_w;

    command_fsm #(
        .CLK_FREQ  (125_000_000),
        .BAUD_RATE (115_200),
        .N_RO      (16),
        .N_VOTES   (9)
    ) fsm (
        .clk       (sys_clk),
        .rst_n     (rst_n),
        .rx        (uart_rx),
        .tx        (uart_tx),
        .trojan_en (trojan_en_w),
        .led_pass  (led_pass_w),
        .led_trojan(led_trojan_w)
    );

    assign led[0] = led_pass_w;
    assign led[1] = led_trojan_w;

endmodule