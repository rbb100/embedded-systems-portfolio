// uart_trx.v
// ----------
// UART Transmitter + Receiver for Zybo Z7
// 8N1 format: 8 data bits, no parity, 1 stop bit
//
// Parameters:
//   CLK_FREQ  : System clock frequency in Hz (default 100MHz)
//   BAUD_RATE : Serial baud rate (default 115200)
//
// TX Interface:
//   tx_data   : 8-bit data to send
//   tx_valid  : pulse high for 1 cycle to start transmission
//   tx_busy   : high while transmitting (do not load new data)
//   tx        : serial output pin → connect to Pi RX
//
// RX Interface:
//   rx        : serial input pin ← connect to Pi TX
//   rx_data   : 8-bit received data
//   rx_valid  : pulses high for 1 cycle when rx_data is ready

module uart_trx #(
    parameter CLK_FREQ  = 125_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,

    // TX
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output reg        tx_busy,
    output reg        tx,

    // RX
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868 @ 100MHz/115200

    // ── TX ────────────────────────────────────────────────────────────────────
    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    reg [1:0]  tx_state;
    reg [15:0] tx_clk_cnt;
    reg [2:0]  tx_bit_idx;
    reg [7:0]  tx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            tx_clk_cnt <= 0;
            tx_bit_idx <= 0;
            tx_busy    <= 0;
            tx         <= 1'b1;   // idle high
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx    <= 1'b1;
                    tx_busy <= 0;
                    if (tx_valid) begin
                        tx_shift   <= tx_data;
                        tx_busy    <= 1;
                        tx_clk_cnt <= 0;
                        tx_state   <= TX_START;
                    end
                end

                TX_START: begin
                    tx <= 1'b0;   // start bit
                    if (tx_clk_cnt >= CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        tx_bit_idx <= 0;
                        tx_state   <= TX_DATA;
                    end else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                end

                TX_DATA: begin
                    tx <= tx_shift[tx_bit_idx];
                    if (tx_clk_cnt >= CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        if (tx_bit_idx == 7) begin
                            tx_state <= TX_STOP;
                        end else
                            tx_bit_idx <= tx_bit_idx + 1;
                    end else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                end

                TX_STOP: begin
                    tx <= 1'b1;   // stop bit
                    if (tx_clk_cnt >= CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        tx_busy    <= 0;
                        tx_state   <= TX_IDLE;
                    end else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // ── RX ────────────────────────────────────────────────────────────────────
    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    reg [1:0]  rx_state;
    reg [15:0] rx_clk_cnt;
    reg [2:0]  rx_bit_idx;
    reg [7:0]  rx_shift;

    // 2FF synchronizer to avoid metastability on async rx input
    reg rx_sync1, rx_sync2;
    always @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            rx_clk_cnt <= 0;
            rx_bit_idx <= 0;
            rx_data    <= 0;
            rx_valid   <= 0;
        end else begin
            rx_valid <= 0;  // default: no new byte

            case (rx_state)
                RX_IDLE: begin
                    if (!rx_sync2) begin  // falling edge = start bit
                        rx_clk_cnt <= 0;
                        rx_state   <= RX_START;
                    end
                end

                RX_START: begin
                    // Sample in middle of start bit
                    if (rx_clk_cnt >= (CLKS_PER_BIT / 2) - 1) begin
                        if (!rx_sync2) begin  // still low - valid start bit
                            rx_clk_cnt <= 0;
                            rx_bit_idx <= 0;
                            rx_state   <= RX_DATA;
                        end else
                            rx_state <= RX_IDLE;  // glitch, ignore
                    end else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                end

                RX_DATA: begin
                    if (rx_clk_cnt >= CLKS_PER_BIT - 1) begin
                        rx_clk_cnt             <= 0;
                        rx_shift[rx_bit_idx]   <= rx_sync2;
                        if (rx_bit_idx == 7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_idx <= rx_bit_idx + 1;
                    end else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                end

                RX_STOP: begin
                    if (rx_clk_cnt >= CLKS_PER_BIT - 1) begin
                        if (rx_sync2) begin   // valid stop bit (high)
                            rx_data  <= rx_shift;
                            rx_valid <= 1;
                        end
                        rx_state <= RX_IDLE;
                    end else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule