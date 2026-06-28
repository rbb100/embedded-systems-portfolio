library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity oled_status_display is
    generic (
        CLOCK_HZ : integer := 125000000;
        SPI_HZ   : integer := 5000000
    );
    port (
        clk                : in  std_logic;
        rst                : in  std_logic;

        status_code        : in  std_logic_vector(3 downto 0);
        status_valid_pulse : in  std_logic;

        busy               : out std_logic;
        init_done          : out std_logic;

        oled_cs            : out std_logic;
        oled_sdin          : out std_logic;
        oled_sclk          : out std_logic;
        oled_dc            : out std_logic;
        oled_res           : out std_logic;
        oled_vbat          : out std_logic;
        oled_vdd           : out std_logic
    );
end oled_status_display;

architecture RTL of oled_status_display is

    subtype byte_t is std_logic_vector(7 downto 0);

    constant SPI_DIV     : integer := CLOCK_HZ / (SPI_HZ * 2);
    constant DELAY_5MS   : integer := CLOCK_HZ / 200;
    constant DELAY_100MS : integer := CLOCK_HZ / 10;

    type state_t is (
        WAIT_POWER,
        VDD_ON,
        WAIT_VDD,
        RES_LOW,
        WAIT_RES_LOW,
        RES_HIGH,
        WAIT_RES_HIGH,
        VBAT_ON,
        WAIT_VBAT,

        INIT_LOAD,
        INIT_NEXT,

        SPI_LOW,
        SPI_HIGH,
        SPI_FINISH,

        PAGE_CMD0,
        PAGE_CMD1,
        PAGE_CMD2,
        DRAW_DATA,
        DRAW_NEXT,

        IDLE
    );

    type init_rom_t is array (0 to 24) of byte_t;

    constant INIT_CMDS : init_rom_t := (
        0  => x"AE",
        1  => x"D5", 2  => x"80",
        3  => x"A8", 4  => x"1F",
        5  => x"D3", 6  => x"00",
        7  => x"40",
        8  => x"8D", 9  => x"14",
        10 => x"20", 11 => x"00",
        12 => x"A1",
        13 => x"C8",
        14 => x"DA", 15 => x"02",
        16 => x"81", 17 => x"8F",
        18 => x"D9", 19 => x"F1",
        20 => x"DB", 21 => x"40",
        22 => x"A4",
        23 => x"A6",
        24 => x"AF"
    );

    signal state           : state_t := WAIT_POWER;
    signal after_spi_state : state_t := WAIT_POWER;

    signal spi_cnt         : integer range 0 to SPI_DIV-1 := 0;
    signal spi_ce          : std_logic := '0';

    signal delay_cnt       : integer range 0 to DELAY_100MS := 0;

    signal tx_byte         : byte_t := x"00";
    signal tx_dc           : std_logic := '0';
    signal bit_idx         : integer range 0 to 7 := 7;

    signal init_idx        : integer range 0 to 24 := 0;

    signal page            : integer range 0 to 3 := 0;
    signal col             : integer range 0 to 127 := 0;

    signal status_disp     : std_logic_vector(3 downto 0) := "0000";

    signal busy_int        : std_logic := '1';
    signal init_done_int   : std_logic := '0';

    --------------------------------------------------------------------
    -- Character IDs
    --------------------------------------------------------------------
    constant CH_SPACE : integer := 0;
    constant CH_A     : integer := 1;
    constant CH_C     : integer := 2;
    constant CH_D     : integer := 3;
    constant CH_E     : integer := 4;
    constant CH_F     : integer := 5;
    constant CH_H     : integer := 6;
    constant CH_I     : integer := 7;
    constant CH_K     : integer := 8;
    constant CH_L     : integer := 9;
    constant CH_N     : integer := 10;
    constant CH_O     : integer := 11;
    constant CH_P     : integer := 12;
    constant CH_R     : integer := 13;
    constant CH_S     : integer := 14;
    constant CH_T     : integer := 15;
    constant CH_U     : integer := 16;
    constant CH_W     : integer := 17;
    constant CH_Y     : integer := 18;

    --------------------------------------------------------------------
    -- 5x7 uppercase font
    --------------------------------------------------------------------
    function font_col(ch : integer; fcol : integer) return byte_t is
        variable b : byte_t := x"00";
    begin
        case ch is

            when CH_SPACE =>
                b := x"00";

            -- A
            when CH_A =>
                case fcol is
                    when 0 => b := x"7E";
                    when 1 => b := x"11";
                    when 2 => b := x"11";
                    when 3 => b := x"11";
                    when 4 => b := x"7E";
                    when others => b := x"00";
                end case;

            -- C
            when CH_C =>
                case fcol is
                    when 0 => b := x"3E";
                    when 1 => b := x"41";
                    when 2 => b := x"41";
                    when 3 => b := x"41";
                    when 4 => b := x"22";
                    when others => b := x"00";
                end case;

            -- D
            when CH_D =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"41";
                    when 2 => b := x"41";
                    when 3 => b := x"22";
                    when 4 => b := x"1C";
                    when others => b := x"00";
                end case;

            -- E
            when CH_E =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"49";
                    when 2 => b := x"49";
                    when 3 => b := x"49";
                    when 4 => b := x"41";
                    when others => b := x"00";
                end case;

            -- F
            when CH_F =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"09";
                    when 2 => b := x"09";
                    when 3 => b := x"09";
                    when 4 => b := x"01";
                    when others => b := x"00";
                end case;

            -- H
            when CH_H =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"08";
                    when 2 => b := x"08";
                    when 3 => b := x"08";
                    when 4 => b := x"7F";
                    when others => b := x"00";
                end case;

            -- I
            when CH_I =>
                case fcol is
                    when 0 => b := x"00";
                    when 1 => b := x"41";
                    when 2 => b := x"7F";
                    when 3 => b := x"41";
                    when 4 => b := x"00";
                    when others => b := x"00";
                end case;

            -- K
            when CH_K =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"08";
                    when 2 => b := x"14";
                    when 3 => b := x"22";
                    when 4 => b := x"41";
                    when others => b := x"00";
                end case;

            -- L
            when CH_L =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"40";
                    when 2 => b := x"40";
                    when 3 => b := x"40";
                    when 4 => b := x"40";
                    when others => b := x"00";
                end case;

            -- N
            when CH_N =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"02";
                    when 2 => b := x"04";
                    when 3 => b := x"08";
                    when 4 => b := x"7F";
                    when others => b := x"00";
                end case;

            -- O
            when CH_O =>
                case fcol is
                    when 0 => b := x"3E";
                    when 1 => b := x"41";
                    when 2 => b := x"41";
                    when 3 => b := x"41";
                    when 4 => b := x"3E";
                    when others => b := x"00";
                end case;

            -- P
            when CH_P =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"09";
                    when 2 => b := x"09";
                    when 3 => b := x"09";
                    when 4 => b := x"06";
                    when others => b := x"00";
                end case;

            -- R
            when CH_R =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"09";
                    when 2 => b := x"19";
                    when 3 => b := x"29";
                    when 4 => b := x"46";
                    when others => b := x"00";
                end case;

            -- S
            when CH_S =>
                case fcol is
                    when 0 => b := x"46";
                    when 1 => b := x"49";
                    when 2 => b := x"49";
                    when 3 => b := x"49";
                    when 4 => b := x"31";
                    when others => b := x"00";
                end case;

            -- T
            when CH_T =>
                case fcol is
                    when 0 => b := x"01";
                    when 1 => b := x"01";
                    when 2 => b := x"7F";
                    when 3 => b := x"01";
                    when 4 => b := x"01";
                    when others => b := x"00";
                end case;

            -- U
            when CH_U =>
                case fcol is
                    when 0 => b := x"3F";
                    when 1 => b := x"40";
                    when 2 => b := x"40";
                    when 3 => b := x"40";
                    when 4 => b := x"3F";
                    when others => b := x"00";
                end case;

            -- W
            when CH_W =>
                case fcol is
                    when 0 => b := x"7F";
                    when 1 => b := x"20";
                    when 2 => b := x"18";
                    when 3 => b := x"20";
                    when 4 => b := x"7F";
                    when others => b := x"00";
                end case;

            -- Y
            when CH_Y =>
                case fcol is
                    when 0 => b := x"07";
                    when 1 => b := x"08";
                    when 2 => b := x"70";
                    when 3 => b := x"08";
                    when 4 => b := x"07";
                    when others => b := x"00";
                end case;

            when others =>
                b := x"00";
        end case;

        return b;
    end function;

    function font_byte(ch : integer; local_col : integer) return byte_t is
    begin
        if local_col = 0 or local_col > 5 then
            return x"00";
        else
            return font_col(ch, local_col - 1);
        end if;
    end function;

    --------------------------------------------------------------------
    -- Message character selector
    -- 16 characters max across the OLED row.
    --------------------------------------------------------------------
    function char_at_pos(pos : integer; code : std_logic_vector(3 downto 0)) return integer is
    begin
        case code is

            -- 0000 = IDLE
            when "0000" =>
                case pos is
                    when 0 => return CH_I;
                    when 1 => return CH_D;
                    when 2 => return CH_L;
                    when 3 => return CH_E;
                    when others => return CH_SPACE;
                end case;

            -- 0001 = AUTH START
            when "0001" =>
                case pos is
                    when 0 => return CH_A;
                    when 1 => return CH_U;
                    when 2 => return CH_T;
                    when 3 => return CH_H;
                    when 4 => return CH_SPACE;
                    when 5 => return CH_S;
                    when 6 => return CH_T;
                    when 7 => return CH_A;
                    when 8 => return CH_R;
                    when 9 => return CH_T;
                    when others => return CH_SPACE;
                end case;

            -- 0010 = AUTH WAIT
            when "0010" =>
                case pos is
                    when 0 => return CH_A;
                    when 1 => return CH_U;
                    when 2 => return CH_T;
                    when 3 => return CH_H;
                    when 4 => return CH_SPACE;
                    when 5 => return CH_W;
                    when 6 => return CH_A;
                    when 7 => return CH_I;
                    when 8 => return CH_T;
                    when others => return CH_SPACE;
                end case;

            -- 0011 = AUTH CHECK
            when "0011" =>
                case pos is
                    when 0 => return CH_A;
                    when 1 => return CH_U;
                    when 2 => return CH_T;
                    when 3 => return CH_H;
                    when 4 => return CH_SPACE;
                    when 5 => return CH_C;
                    when 6 => return CH_H;
                    when 7 => return CH_E;
                    when 8 => return CH_C;
                    when 9 => return CH_K;
                    when others => return CH_SPACE;
                end case;

            -- 0100 = AUTH PASS
            when "0100" =>
                case pos is
                    when 0 => return CH_A;
                    when 1 => return CH_U;
                    when 2 => return CH_T;
                    when 3 => return CH_H;
                    when 4 => return CH_SPACE;
                    when 5 => return CH_P;
                    when 6 => return CH_A;
                    when 7 => return CH_S;
                    when 8 => return CH_S;
                    when others => return CH_SPACE;
                end case;

            -- 0101 = AUTH FAIL
            when "0101" =>
                case pos is
                    when 0 => return CH_A;
                    when 1 => return CH_U;
                    when 2 => return CH_T;
                    when 3 => return CH_H;
                    when 4 => return CH_SPACE;
                    when 5 => return CH_F;
                    when 6 => return CH_A;
                    when 7 => return CH_I;
                    when 8 => return CH_L;
                    when others => return CH_SPACE;
                end case;

            -- 0110 = READY
            when "0110" =>
                case pos is
                    when 0 => return CH_R;
                    when 1 => return CH_E;
                    when 2 => return CH_A;
                    when 3 => return CH_D;
                    when 4 => return CH_Y;
                    when others => return CH_SPACE;
                end case;

            -- 0111 = SENSOR START
            when "0111" =>
                case pos is
                    when 0 => return CH_S;
                    when 1 => return CH_E;
                    when 2 => return CH_N;
                    when 3 => return CH_S;
                    when 4 => return CH_O;
                    when 5 => return CH_R;
                    when 6 => return CH_SPACE;
                    when 7 => return CH_S;
                    when 8 => return CH_T;
                    when 9 => return CH_A;
                    when 10 => return CH_R;
                    when 11 => return CH_T;
                    when others => return CH_SPACE;
                end case;

            -- 1000 = SENSOR WAIT
            when "1000" =>
                case pos is
                    when 0 => return CH_S;
                    when 1 => return CH_E;
                    when 2 => return CH_N;
                    when 3 => return CH_S;
                    when 4 => return CH_O;
                    when 5 => return CH_R;
                    when 6 => return CH_SPACE;
                    when 7 => return CH_W;
                    when 8 => return CH_A;
                    when 9 => return CH_I;
                    when 10 => return CH_T;
                    when others => return CH_SPACE;
                end case;

            -- 1001 = SENSOR PASS
            when "1001" =>
                case pos is
                    when 0 => return CH_S;
                    when 1 => return CH_E;
                    when 2 => return CH_N;
                    when 3 => return CH_S;
                    when 4 => return CH_O;
                    when 5 => return CH_R;
                    when 6 => return CH_SPACE;
                    when 7 => return CH_P;
                    when 8 => return CH_A;
                    when 9 => return CH_S;
                    when 10 => return CH_S;
                    when others => return CH_SPACE;
                end case;

            -- 1010 = SENSOR FAIL
            when "1010" =>
                case pos is
                    when 0 => return CH_S;
                    when 1 => return CH_E;
                    when 2 => return CH_N;
                    when 3 => return CH_S;
                    when 4 => return CH_O;
                    when 5 => return CH_R;
                    when 6 => return CH_SPACE;
                    when 7 => return CH_F;
                    when 8 => return CH_A;
                    when 9 => return CH_I;
                    when 10 => return CH_L;
                    when others => return CH_SPACE;
                end case;

                       -- 1011 = PUF PASS / BOARD IDENTIFIED
            when "1011" =>
                case pos is
                    when 0 => return CH_P;
                    when 1 => return CH_U;
                    when 2 => return CH_F;
                    when 3 => return CH_SPACE;
                    when 4 => return CH_P;
                    when 5 => return CH_A;
                    when 6 => return CH_S;
                    when 7 => return CH_S;
                    when others => return CH_SPACE;
                end case;
                
            when others =>
                case pos is
                    when 0 => return CH_U;
                    when 1 => return CH_N;
                    when 2 => return CH_K;
                    when 3 => return CH_N;
                    when 4 => return CH_O;
                    when 5 => return CH_W;
                    when 6 => return CH_N;
                    when others => return CH_SPACE;
                end case;

        end case;
    end function;

    function draw_byte(p : integer; c : integer; code : std_logic_vector(3 downto 0)) return byte_t is
        variable char_pos  : integer;
        variable local_col : integer;
        variable ch        : integer;
    begin
        -- Draw on page 1 only.
        if p /= 1 then
            return x"00";
        end if;

        char_pos  := c / 8;
        local_col := c mod 8;

        ch := char_at_pos(char_pos, code);

        return font_byte(ch, local_col);
    end function;

begin

    busy      <= busy_int;
    init_done <= init_done_int;

    --------------------------------------------------------------------
    -- SPI clock enable
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                spi_cnt <= 0;
                spi_ce  <= '0';
            else
                if spi_cnt = SPI_DIV-1 then
                    spi_cnt <= 0;
                    spi_ce  <= '1';
                else
                    spi_cnt <= spi_cnt + 1;
                    spi_ce  <= '0';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- OLED FSM
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= WAIT_POWER;
                delay_cnt     <= DELAY_100MS;

                oled_cs       <= '1';
                oled_sdin     <= '0';
                oled_sclk     <= '0';
                oled_dc       <= '0';
                oled_res      <= '1';

                -- Active-low power control
                oled_vdd      <= '1';
                oled_vbat     <= '1';

                init_idx      <= 0;
                page          <= 0;
                col           <= 0;

                busy_int      <= '1';
                init_done_int <= '0';

                status_disp   <= "0000";

            else
                case state is

                    when WAIT_POWER =>
                        busy_int <= '1';

                        if delay_cnt = 0 then
                            state <= VDD_ON;
                        else
                            delay_cnt <= delay_cnt - 1;
                        end if;

                    when VDD_ON =>
                        oled_vdd  <= '0';
                        delay_cnt <= DELAY_5MS;
                        state     <= WAIT_VDD;

                    when WAIT_VDD =>
                        if delay_cnt = 0 then
                            state <= RES_LOW;
                        else
                            delay_cnt <= delay_cnt - 1;
                        end if;

                    when RES_LOW =>
                        oled_res  <= '0';
                        delay_cnt <= DELAY_5MS;
                        state     <= WAIT_RES_LOW;

                    when WAIT_RES_LOW =>
                        if delay_cnt = 0 then
                            state <= RES_HIGH;
                        else
                            delay_cnt <= delay_cnt - 1;
                        end if;

                    when RES_HIGH =>
                        oled_res  <= '1';
                        delay_cnt <= DELAY_5MS;
                        state     <= WAIT_RES_HIGH;

                    when WAIT_RES_HIGH =>
                        if delay_cnt = 0 then
                            state <= VBAT_ON;
                        else
                            delay_cnt <= delay_cnt - 1;
                        end if;

                    when VBAT_ON =>
                        oled_vbat <= '0';
                        delay_cnt <= DELAY_100MS;
                        state     <= WAIT_VBAT;

                    when WAIT_VBAT =>
                        if delay_cnt = 0 then
                            init_idx <= 0;
                            state    <= INIT_LOAD;
                        else
                            delay_cnt <= delay_cnt - 1;
                        end if;

                    ----------------------------------------------------------------
                    -- Initialization commands
                    ----------------------------------------------------------------
                    when INIT_LOAD =>
                        tx_byte         <= INIT_CMDS(init_idx);
                        tx_dc           <= '0';
                        bit_idx         <= 7;
                        after_spi_state <= INIT_NEXT;
                        state           <= SPI_LOW;

                    when INIT_NEXT =>
                        if init_idx = 24 then
                            init_done_int <= '1';

                            status_disp <= status_code;

                            page     <= 0;
                            col      <= 0;
                            busy_int <= '1';
                            state    <= PAGE_CMD0;
                        else
                            init_idx <= init_idx + 1;
                            state    <= INIT_LOAD;
                        end if;

                    ----------------------------------------------------------------
                    -- SPI byte send helper
                    ----------------------------------------------------------------
                    when SPI_LOW =>
                        if spi_ce = '1' then
                            oled_cs   <= '0';
                            oled_dc   <= tx_dc;
                            oled_sclk <= '0';
                            oled_sdin <= tx_byte(bit_idx);
                            state     <= SPI_HIGH;
                        end if;

                    when SPI_HIGH =>
                        if spi_ce = '1' then
                            oled_sclk <= '1';

                            if bit_idx = 0 then
                                state <= SPI_FINISH;
                            else
                                bit_idx <= bit_idx - 1;
                                state   <= SPI_LOW;
                            end if;
                        end if;

                    when SPI_FINISH =>
                        if spi_ce = '1' then
                            oled_sclk <= '0';
                            oled_cs   <= '1';
                            state     <= after_spi_state;
                        end if;

                    ----------------------------------------------------------------
                    -- Page/column addressing
                    ----------------------------------------------------------------
                    when PAGE_CMD0 =>
                        tx_byte         <= std_logic_vector(to_unsigned(16#B0# + page, 8));
                        tx_dc           <= '0';
                        bit_idx         <= 7;
                        after_spi_state <= PAGE_CMD1;
                        state           <= SPI_LOW;

                    when PAGE_CMD1 =>
                        tx_byte         <= x"00";
                        tx_dc           <= '0';
                        bit_idx         <= 7;
                        after_spi_state <= PAGE_CMD2;
                        state           <= SPI_LOW;

                    when PAGE_CMD2 =>
                        tx_byte         <= x"10";
                        tx_dc           <= '0';
                        bit_idx         <= 7;
                        after_spi_state <= DRAW_DATA;
                        state           <= SPI_LOW;

                    ----------------------------------------------------------------
                    -- Draw display RAM
                    ----------------------------------------------------------------
                    when DRAW_DATA =>
                        tx_byte         <= draw_byte(page, col, status_disp);
                        tx_dc           <= '1';
                        bit_idx         <= 7;
                        after_spi_state <= DRAW_NEXT;
                        state           <= SPI_LOW;

                    when DRAW_NEXT =>
                        if col = 127 then
                            col <= 0;

                            if page = 3 then
                                busy_int <= '0';
                                state    <= IDLE;
                            else
                                page  <= page + 1;
                                state <= PAGE_CMD0;
                            end if;
                        else
                            col   <= col + 1;
                            state <= DRAW_DATA;
                        end if;

                    when IDLE =>
                        busy_int <= '0';

                        if status_valid_pulse = '1' then
                            status_disp <= status_code;

                            page     <= 0;
                            col      <= 0;
                            busy_int <= '1';
                            state    <= PAGE_CMD0;
                        end if;

                    when others =>
                        state <= WAIT_POWER;

                end case;
            end if;
        end if;
    end process;

end RTL;