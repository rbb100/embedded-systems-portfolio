// command_fsm.v
module command_fsm #(
    parameter CLK_FREQ   = 125_000_000,
    parameter BAUD_RATE  = 115_200,
    parameter N_RO       = 16,
    parameter N_VOTES    = 9,
    parameter MAX_CMD    = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire rx,
    output wire tx,
    output reg  trojan_en,
    output wire led_pass,
    output wire led_trojan
);

    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_busy;

    uart_trx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart (
        .clk(clk),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_busy(tx_busy),
        .tx(tx),
        .rx(rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    reg  [$clog2(N_RO)-1:0] ro_sel_i, ro_sel_j;
    reg                     puf_measure_en;
    wire                    puf_done;
    wire                    puf_raw_bit;

    ro_puf_array #(
        .N_RO(N_RO)
    ) puf (
        .clk(clk),
        .rst_n(rst_n),
        .measure_en(puf_measure_en),
        .ro_sel_i(ro_sel_i),
        .ro_sel_j(ro_sel_j),
        .trojan_en(trojan_en),
        .response_bit(puf_raw_bit),
        .done(puf_done)
    );

    wire mv_measure_req;
    wire mv_stable_bit;
    wire mv_valid;
    reg  mv_start;

    majority_vote #(
        .N_VOTES(N_VOTES)
    ) mv (
        .clk(clk),
        .rst_n(rst_n),
        .start(mv_start),
        .puf_done(puf_done),
        .puf_bit(puf_raw_bit),
        .measure_req(mv_measure_req),
        .stable_bit(mv_stable_bit),
        .valid(mv_valid)
    );

    always @(*) begin
        puf_measure_en = mv_measure_req;
    end

    reg [7:0] cmd_buf [0:MAX_CMD-1];
    reg [3:0] cmd_len;

    reg [7:0] tx_buf [0:15];
    reg [3:0] tx_len;
    reg [3:0] tx_idx;

    reg [5:0] challenge_idx;

    localparam S_IDLE    = 4'd0;
    localparam S_RX_CMD  = 4'd1;
    localparam S_PARSE   = 4'd2;
    localparam S_MEASURE = 4'd3;
    localparam S_WAIT_MV = 4'd4;
    localparam S_TX_LOAD = 4'd5;
    localparam S_TX_SEND = 4'd6;
    localparam S_TX_WAIT = 4'd7;

    reg [3:0] state;
    reg       last_pass;

    assign led_pass   = last_pass;
    assign led_trojan = trojan_en;

    task load_ready;
        begin
            tx_buf[0] <= "R";
            tx_buf[1] <= "E";
            tx_buf[2] <= "A";
            tx_buf[3] <= "D";
            tx_buf[4] <= "Y";
            tx_buf[5] <= 8'h0A;
            tx_len    <= 6;
        end
    endtask

    task load_ack;
        begin
            tx_buf[0] <= "A";
            tx_buf[1] <= "C";
            tx_buf[2] <= "K";
            tx_buf[3] <= 8'h0A;
            tx_len    <= 4;
        end
    endtask

    task load_err;
        begin
            tx_buf[0] <= "E";
            tx_buf[1] <= "R";
            tx_buf[2] <= "R";
            tx_buf[3] <= 8'h0A;
            tx_len    <= 4;
        end
    endtask

    task load_resp;
        input bit_val;
        begin
            tx_buf[0] <= "R";
            tx_buf[1] <= "E";
            tx_buf[2] <= "S";
            tx_buf[3] <= "P";
            tx_buf[4] <= ":";
            tx_buf[5] <= bit_val ? "1" : "0";
            tx_buf[6] <= 8'h0A;
            tx_len    <= 7;
        end
    endtask

    function cmd_is_ping;
        input dummy;
        begin
            cmd_is_ping = (cmd_len >= 4 &&
                           cmd_buf[0]=="P" && cmd_buf[1]=="I" &&
                           cmd_buf[2]=="N" && cmd_buf[3]=="G");
        end
    endfunction

    function cmd_is_enroll;
        input dummy;
        begin
            cmd_is_enroll = (cmd_len >= 6 &&
                             cmd_buf[0]=="E" && cmd_buf[1]=="N" &&
                             cmd_buf[2]=="R" && cmd_buf[3]=="O" &&
                             cmd_buf[4]=="L" && cmd_buf[5]=="L");
        end
    endfunction

    function cmd_is_auth;
        input dummy;
        begin
            cmd_is_auth = (cmd_len >= 4 &&
                           cmd_buf[0]=="A" && cmd_buf[1]=="U" &&
                           cmd_buf[2]=="T" && cmd_buf[3]=="H");
        end
    endfunction

    function cmd_is_chal;
        input dummy;
        begin
            cmd_is_chal = ((cmd_len == 6 || cmd_len == 7) &&
                           cmd_buf[0]=="C" && cmd_buf[1]=="H" &&
                           cmd_buf[2]=="A" && cmd_buf[3]=="L" &&
                           cmd_buf[4]==":");
        end
    endfunction

    function cmd_is_trojan_on;
        input dummy;
        begin
            cmd_is_trojan_on = (cmd_len >= 9 &&
                                cmd_buf[0]=="T" && cmd_buf[1]=="R" &&
                                cmd_buf[2]=="O" && cmd_buf[3]=="J" &&
                                cmd_buf[4]=="A" && cmd_buf[5]=="N" &&
                                cmd_buf[6]==":" && cmd_buf[7]=="O" &&
                                cmd_buf[8]=="N");
        end
    endfunction

    function cmd_is_trojan_off;
        input dummy;
        begin
            cmd_is_trojan_off = (cmd_len >= 10 &&
                                 cmd_buf[0]=="T" && cmd_buf[1]=="R" &&
                                 cmd_buf[2]=="O" && cmd_buf[3]=="J" &&
                                 cmd_buf[4]=="A" && cmd_buf[5]=="N" &&
                                 cmd_buf[6]==":" && cmd_buf[7]=="O" &&
                                 cmd_buf[8]=="F" && cmd_buf[9]=="F");
        end
    endfunction

    function [5:0] parse_challenge;
        input dummy;
        reg [5:0] val;
        begin
            if (cmd_len == 6)
                val = cmd_buf[5] - "0";
            else
                val = (cmd_buf[5] - "0") * 6'd10 + (cmd_buf[6] - "0");
            parse_challenge = val;
        end
    endfunction

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            cmd_len       <= 0;
            tx_valid      <= 0;
            tx_idx        <= 0;
            tx_len        <= 0;
            tx_data       <= 8'd0;
            trojan_en     <= 0;
            last_pass     <= 0;
            mv_start      <= 0;
            ro_sel_i      <= 0;
            ro_sel_j      <= 0;
            challenge_idx <= 0;

            for (k = 0; k < MAX_CMD; k = k + 1)
                cmd_buf[k] <= 8'd0;

            for (k = 0; k < 16; k = k + 1)
                tx_buf[k] <= 8'd0;

        end else begin
            tx_valid <= 0;
            mv_start <= 0;

            case (state)

                S_IDLE: begin
                    cmd_len <= 0;
                    if (rx_valid) begin
                        // Ignore stray CR/LF in idle
                        if (rx_data == 8'h0D || rx_data == 8'h0A) begin
                            state <= S_IDLE;
                        end else begin
                            for (k = 0; k < MAX_CMD; k = k + 1)
                                cmd_buf[k] <= 8'd0;
                            cmd_buf[0] <= rx_data;
                            cmd_len    <= 1;
                            state      <= S_RX_CMD;
                        end
                    end
                end

                S_RX_CMD: begin
                    if (rx_valid) begin
                        // Ignore carriage return
                        if (rx_data == 8'h0D) begin
                            state <= S_RX_CMD;
                        end
                        // Parse on line feed
                        else if (rx_data == 8'h0A || cmd_len >= MAX_CMD-1) begin
                            state <= S_PARSE;
                        end
                        else begin
                            cmd_buf[cmd_len] <= rx_data;
                            cmd_len          <= cmd_len + 1;
                        end
                    end
                end

                S_PARSE: begin
                    if (cmd_is_ping(0) || cmd_is_enroll(0) || cmd_is_auth(0)) begin
                        load_ready;
                        state <= S_TX_LOAD;

                    end else if (cmd_is_chal(0)) begin
                        challenge_idx <= parse_challenge(0);
                        ro_sel_i      <= parse_challenge(0) % N_RO;
                        ro_sel_j      <= (parse_challenge(0) + 1) % N_RO;
                        state         <= S_MEASURE;

                    end else if (cmd_is_trojan_on(0)) begin
                        trojan_en <= 1;
                        load_ack;
                        state <= S_TX_LOAD;

                    end else if (cmd_is_trojan_off(0)) begin
                        trojan_en <= 0;
                        load_ack;
                        state <= S_TX_LOAD;

                    end else begin
                        load_err;
                        state <= S_TX_LOAD;
                    end
                end

                S_MEASURE: begin
                    mv_start <= 1;
                    state    <= S_WAIT_MV;
                end

                S_WAIT_MV: begin
                    if (mv_valid) begin
                        load_resp(mv_stable_bit);
                        last_pass <= mv_stable_bit;
                        state     <= S_TX_LOAD;
                    end
                end

                S_TX_LOAD: begin
                    tx_idx <= 0;
                    state  <= S_TX_SEND;
                end

                S_TX_SEND: begin
                    if (!tx_busy) begin
                        tx_data  <= tx_buf[tx_idx];
                        tx_valid <= 1;
                        state    <= S_TX_WAIT;
                    end
                end

                S_TX_WAIT: begin
                    if (!tx_busy) begin
                        if (tx_idx >= tx_len - 1) begin
                            cmd_len <= 0;
                            state   <= S_IDLE;
                        end else begin
                            tx_idx <= tx_idx + 1;
                            state  <= S_TX_SEND;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule