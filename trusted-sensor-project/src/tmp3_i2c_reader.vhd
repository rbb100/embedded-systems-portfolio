library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tmp3_i2c_reader is
    generic (
        TICK_CYCLES : natural := 6250; -- slow I2C timing, safe for debug
        I2C_ADDR    : std_logic_vector(6 downto 0) := "1001000" -- default 0x48
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start : in std_logic;

        tmp3_scl : inout std_logic;
        tmp3_sda : inout std_logic;

        busy      : out std_logic;
        done      : out std_logic;
        valid     : out std_logic;
        ack_error : out std_logic;

        raw_temp : out std_logic_vector(15 downto 0);
        temp_c   : out std_logic_vector(7 downto 0)
    );
end entity tmp3_i2c_reader;

architecture rtl of tmp3_i2c_reader is

    type state_t is (
        S_IDLE,

        S_START_A,
        S_START_B,
        S_START_C,

        S_WRITE_SETUP,
        S_WRITE_HIGH,
        S_WRITE_LOW,

        S_ACK_SETUP,
        S_ACK_HIGH,
        S_ACK_LOW,

        S_READ_SETUP,
        S_READ_HIGH,
        S_READ_LOW,

        S_SEND_ACK_SETUP,
        S_SEND_ACK_HIGH,
        S_SEND_ACK_LOW,

        S_STOP_A,
        S_STOP_B,
        S_STOP_C,

        S_DONE
    );

    signal state : state_t := S_IDLE;

    -- Open-drain control:
    -- '1' means FPGA drives line low.
    -- '0' means FPGA releases line to pull-up.
    signal scl_low : std_logic := '0';
    signal sda_low : std_logic := '0';

    signal busy_reg      : std_logic := '0';
    signal done_reg      : std_logic := '0';
    signal valid_reg     : std_logic := '0';
    signal ack_error_reg : std_logic := '0';

    signal tick_cnt : natural range 0 to TICK_CYCLES := 0;
    signal step     : natural range 0 to 6 := 0;
    signal bit_idx  : natural range 0 to 7 := 7;

    signal write_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal read_byte  : std_logic_vector(7 downto 0) := (others => '0');

    signal msb_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal lsb_byte : std_logic_vector(7 downto 0) := (others => '0');

    signal ack_sample : std_logic := '1';
    signal ack_to_send : std_logic := '1';

    signal raw_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal temp_reg : std_logic_vector(7 downto 0) := (others => '0');

begin

    --------------------------------------------------------------------
    -- I2C open-drain outputs
    --------------------------------------------------------------------
    tmp3_scl <= '0' when scl_low = '1' else 'Z';
    tmp3_sda <= '0' when sda_low = '1' else 'Z';

    busy      <= busy_reg;
    done      <= done_reg;
    valid     <= valid_reg;
    ack_error <= ack_error_reg;

    raw_temp <= raw_reg;
    temp_c   <= temp_reg;

    process(clk)
        variable raw_next : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE;

                scl_low <= '0';
                sda_low <= '0';

                busy_reg <= '0';
                done_reg <= '0';
                valid_reg <= '0';
                ack_error_reg <= '0';

                tick_cnt <= 0;
                step <= 0;
                bit_idx <= 7;

                write_byte <= (others => '0');
                read_byte  <= (others => '0');
                msb_byte   <= (others => '0');
                lsb_byte   <= (others => '0');

                ack_sample <= '1';
                ack_to_send <= '1';

                raw_reg  <= (others => '0');
                temp_reg <= (others => '0');

            else
                done_reg <= '0';

                case state is

                    ----------------------------------------------------
                    -- IDLE
                    ----------------------------------------------------
                    when S_IDLE =>
                        scl_low <= '0';
                        sda_low <= '0';

                        busy_reg <= '0';
                        tick_cnt <= 0;

                        if start = '1' then
                            busy_reg <= '1';
                            valid_reg <= '0';
                            ack_error_reg <= '0';
                            step <= 0;
                            state <= S_START_A;
                        end if;

                    ----------------------------------------------------
                    -- START / repeated START
                    ----------------------------------------------------
                    when S_START_A =>
                        scl_low <= '0';
                        sda_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_START_B;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_START_B =>
                        -- SDA goes low while SCL is high
                        scl_low <= '0';
                        sda_low <= '1';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_START_C;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_START_C =>
                        scl_low <= '1';
                        sda_low <= '1';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            bit_idx <= 7;

                            if step = 0 then
                                write_byte <= I2C_ADDR & '0'; -- address + write
                            else
                                write_byte <= I2C_ADDR & '1'; -- address + read
                            end if;

                            state <= S_WRITE_SETUP;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    ----------------------------------------------------
                    -- WRITE byte
                    ----------------------------------------------------
                    when S_WRITE_SETUP =>
                        scl_low <= '1';

                        if write_byte(bit_idx) = '0' then
                            sda_low <= '1';
                        else
                            sda_low <= '0';
                        end if;

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_WRITE_HIGH;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_WRITE_HIGH =>
                        scl_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_WRITE_LOW;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_WRITE_LOW =>
                        scl_low <= '1';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;

                            if bit_idx = 0 then
                                bit_idx <= 7;
                                state <= S_ACK_SETUP;
                            else
                                bit_idx <= bit_idx - 1;
                                state <= S_WRITE_SETUP;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    ----------------------------------------------------
                    -- Read ACK from TMP3
                    ----------------------------------------------------
                    when S_ACK_SETUP =>
                        scl_low <= '1';
                        sda_low <= '0'; -- release SDA

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_ACK_HIGH;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_ACK_HIGH =>
                        scl_low <= '0';
                        sda_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            ack_sample <= tmp3_sda;
                            state <= S_ACK_LOW;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_ACK_LOW =>
                        scl_low <= '1';
                        sda_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;

                            if ack_sample = '1' then
                                ack_error_reg <= '1';
                                state <= S_STOP_A;
                            else
                                case step is
                                    when 0 =>
                                        -- Address write ACK received.
                                        -- Send temperature register pointer 0x00.
                                        step <= 1;
                                        write_byte <= x"00";
                                        bit_idx <= 7;
                                        state <= S_WRITE_SETUP;

                                    when 1 =>
                                        -- Register pointer ACK received.
                                        -- Repeated START.
                                        step <= 2;
                                        state <= S_START_A;

                                    when 2 =>
                                        -- Address read ACK received.
                                        -- Read temperature MSB.
                                        step <= 3;
                                        bit_idx <= 7;
                                        read_byte <= (others => '0');
                                        state <= S_READ_SETUP;

                                    when others =>
                                        state <= S_STOP_A;
                                end case;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    ----------------------------------------------------
                    -- READ byte
                    ----------------------------------------------------
                    when S_READ_SETUP =>
                        scl_low <= '1';
                        sda_low <= '0'; -- release SDA

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_READ_HIGH;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_READ_HIGH =>
                        scl_low <= '0';
                        sda_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            read_byte(bit_idx) <= tmp3_sda;
                            state <= S_READ_LOW;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_READ_LOW =>
                        scl_low <= '1';
                        sda_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;

                            if bit_idx = 0 then
                                if step = 3 then
                                    -- Finished MSB. ACK and read LSB.
                                    msb_byte <= read_byte;
                                    ack_to_send <= '0'; -- ACK
                                    step <= 4;
                                    state <= S_SEND_ACK_SETUP;
                                else
                                    -- Finished LSB. NACK and stop.
                                    lsb_byte <= read_byte;
                                    ack_to_send <= '1'; -- NACK
                                    step <= 6;
                                    state <= S_SEND_ACK_SETUP;
                                end if;

                                bit_idx <= 7;
                            else
                                bit_idx <= bit_idx - 1;
                                state <= S_READ_SETUP;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    ----------------------------------------------------
                    -- Send ACK/NACK to TMP3
                    ----------------------------------------------------
                    when S_SEND_ACK_SETUP =>
                        scl_low <= '1';

                        if ack_to_send = '0' then
                            sda_low <= '1'; -- ACK = drive low
                        else
                            sda_low <= '0'; -- NACK = release high
                        end if;

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_SEND_ACK_HIGH;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_SEND_ACK_HIGH =>
                        scl_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_SEND_ACK_LOW;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_SEND_ACK_LOW =>
                        scl_low <= '1';
                        sda_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;

                            if step = 4 then
                                -- Read LSB next.
                                step <= 5;
                                bit_idx <= 7;
                                read_byte <= (others => '0');
                                state <= S_READ_SETUP;
                            else
                                state <= S_STOP_A;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    ----------------------------------------------------
                    -- STOP
                    ----------------------------------------------------
                    when S_STOP_A =>
                        scl_low <= '1';
                        sda_low <= '1';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_STOP_B;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_STOP_B =>
                        scl_low <= '0';
                        sda_low <= '1';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;
                            state <= S_STOP_C;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_STOP_C =>
                        scl_low <= '0';
                        sda_low <= '0';

                        if tick_cnt = TICK_CYCLES - 1 then
                            tick_cnt <= 0;

                            raw_next := msb_byte & lsb_byte;
                            raw_reg <= raw_next;

                            -- For positive room temperatures,
                            -- integer Celsius is approximately MSB byte.
                            if msb_byte(7) = '0' then
                                temp_reg <= msb_byte;
                            else
                                temp_reg <= x"00";
                            end if;

                            if ack_error_reg = '0' then
                                valid_reg <= '1';
                            else
                                valid_reg <= '0';
                            end if;

                            state <= S_DONE;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;

                    when S_DONE =>
                        busy_reg <= '0';
                        done_reg <= '1';
                        state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;