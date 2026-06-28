library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sensor_port_validation_core is
    generic (
        ALS_THRESHOLD : natural := 64;
        TMP3_PASS_C   : natural := 30
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        validation_enable  : in std_logic;
        start_sensor_check : in std_logic;

        ----------------------------------------------------------------
        -- Shared JB sensor port
        --
        -- ALS on JB:
        --   JB1 = ALS CS
        --   JB3 = ALS MISO
        --   JB4 = ALS SCLK
        --
        -- TMP3 on JB shifted-right:
        --   JB3 = TMP3 SCL
        --   JB4 = TMP3 SDA
        ----------------------------------------------------------------
        sensor_jb1_cs       : out   std_logic;
        sensor_jb3_scl_miso : inout std_logic;
        sensor_jb4_sda_sclk : inout std_logic;

        sensor_busy : out std_logic;
        sensor_done : out std_logic;
        sensor_pass : out std_logic;

        -- Debug:
        -- 00 = unknown / no valid sensor
        -- 01 = ALS path used
        -- 10 = TMP3 path used
        sensor_type_dbg : out std_logic_vector(1 downto 0);

        als_value_dbg : out std_logic_vector(7 downto 0);
        tmp3_temp_dbg : out std_logic_vector(7 downto 0)
    );
end entity sensor_port_validation_core;

architecture rtl of sensor_port_validation_core is

    type state_t is (
        S_IDLE,

        S_ALS_START,
        S_ALS_WAIT,
        S_ALS_EVAL,

        S_TMP3_START,
        S_TMP3_WAIT,
        S_TMP3_EVAL,

        S_DONE
    );

    signal state : state_t := S_IDLE;

    --------------------------------------------------------------------
    -- ALS signals
    --------------------------------------------------------------------
    signal als_start : std_logic := '0';
    signal als_busy  : std_logic := '0';
    signal als_done  : std_logic := '0';

    signal als_cs_sig    : std_logic := '1';
    signal als_sclk_sig  : std_logic := '0';
    signal als_value     : std_logic_vector(7 downto 0) := (others => '0');
    signal als_raw_shift : std_logic_vector(15 downto 0) := (others => '0');

    signal als_active : std_logic := '0';

    --------------------------------------------------------------------
    -- TMP3 signals
    --------------------------------------------------------------------
    signal tmp3_start     : std_logic := '0';
    signal tmp3_busy      : std_logic := '0';
    signal tmp3_done      : std_logic := '0';
    signal tmp3_valid     : std_logic := '0';
    signal tmp3_ack_error : std_logic := '0';

    signal tmp3_raw_temp : std_logic_vector(15 downto 0) := (others => '0');
    signal tmp3_temp_c   : std_logic_vector(7 downto 0) := (others => '0');

    --------------------------------------------------------------------
    -- Output registers
    --------------------------------------------------------------------
    signal sensor_busy_reg : std_logic := '0';
    signal sensor_done_reg : std_logic := '0';
    signal sensor_pass_reg : std_logic := '0';

    signal sensor_type_reg : std_logic_vector(1 downto 0) := "00";

begin

    sensor_busy <= sensor_busy_reg;
    sensor_done <= sensor_done_reg;
    sensor_pass <= sensor_pass_reg;

    sensor_type_dbg <= sensor_type_reg;

    als_value_dbg <= als_value;
    tmp3_temp_dbg <= tmp3_temp_c;

    --------------------------------------------------------------------
    -- Shared JB pin control
    --------------------------------------------------------------------

    -- JB1 is ALS CS.
    -- TMP3 does not use JB1, so keep it high unless ALS is active.
    sensor_jb1_cs <= als_cs_sig when als_active = '1' else '1';

    -- JB4 is ALS SCLK during ALS mode.
    -- During TMP3 mode, tmp3_i2c_reader controls this pin as SDA.
    sensor_jb4_sda_sclk <= als_sclk_sig when als_active = '1' else 'Z';

    -- JB3 is ALS MISO during ALS mode.
    -- During TMP3 mode, tmp3_i2c_reader controls this pin as SCL.
    -- No direct assignment needed here.

    --------------------------------------------------------------------
    -- ALS reader
    --------------------------------------------------------------------
    u_als_reader : entity work.pmod_als_reader
        port map (
            clk => clk,
            rst => rst,

            start => als_start,

            als_cs_n  => als_cs_sig,
            als_sclk  => als_sclk_sig,
            als_sdata => sensor_jb3_scl_miso,

            busy => als_busy,
            done => als_done,

            als_value => als_value,
            raw_shift_dbg => als_raw_shift
        );

    --------------------------------------------------------------------
    -- TMP3 reader
    --------------------------------------------------------------------
    u_tmp3_reader : entity work.tmp3_i2c_reader
        generic map (
            TICK_CYCLES => 6250,
            I2C_ADDR    => "1001000" -- 0x48
        )
        port map (
            clk => clk,
            rst => rst,

            start => tmp3_start,

            tmp3_scl => sensor_jb3_scl_miso,
            tmp3_sda => sensor_jb4_sda_sclk,

            busy      => tmp3_busy,
            done      => tmp3_done,
            valid     => tmp3_valid,
            ack_error => tmp3_ack_error,

            raw_temp => tmp3_raw_temp,
            temp_c   => tmp3_temp_c
        );

    --------------------------------------------------------------------
    -- Sensor auto-detect + validation FSM
    --------------------------------------------------------------------
    process(clk)
        variable als_int  : natural range 0 to 255;
        variable temp_int : natural range 0 to 255;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE;

                als_start  <= '0';
                tmp3_start <= '0';
                als_active <= '0';

                sensor_busy_reg <= '0';
                sensor_done_reg <= '0';
                sensor_pass_reg <= '0';
                sensor_type_reg <= "00";

            else
                als_start <= '0';
                tmp3_start <= '0';
                sensor_done_reg <= '0';

                case state is

                    ----------------------------------------------------
                    -- Wait for validation request
                    ----------------------------------------------------
                    when S_IDLE =>
                        sensor_busy_reg <= '0';
                        sensor_pass_reg <= '0';
                        sensor_type_reg <= "00";
                        als_active <= '0';

                        if validation_enable = '1' and start_sensor_check = '1' then
                            sensor_busy_reg <= '1';
                            state <= S_ALS_START;
                        end if;

                    ----------------------------------------------------
                    -- Try ALS first
                    ----------------------------------------------------
                    when S_ALS_START =>
                        sensor_busy_reg <= '1';
                        sensor_type_reg <= "00";

                        als_active <= '1';
                        als_start <= '1';

                        state <= S_ALS_WAIT;

                    when S_ALS_WAIT =>
                        sensor_busy_reg <= '1';
                        als_active <= '1';

                        if als_done = '1' then
                            state <= S_ALS_EVAL;
                        end if;

                    when S_ALS_EVAL =>
                        sensor_busy_reg <= '1';
                        als_active <= '1';

                        als_int := to_integer(unsigned(als_value));

                        -- ALS has no ID register.
                        -- If the SPI frame is all 1s or all 0s, assume no valid ALS response.
                        if als_raw_shift /= x"FFFF" and als_raw_shift /= x"0000" then
                            sensor_type_reg <= "01";

                            if als_int >= ALS_THRESHOLD then
                                sensor_pass_reg <= '1';
                            else
                                sensor_pass_reg <= '0';
                            end if;

                            state <= S_DONE;

                        else
                            -- No valid ALS frame detected.
                            -- Release ALS pins and try TMP3.
                            als_active <= '0';
                            state <= S_TMP3_START;
                        end if;

                    ----------------------------------------------------
                    -- Try TMP3 second
                    ----------------------------------------------------
                    when S_TMP3_START =>
                        sensor_busy_reg <= '1';
                        sensor_type_reg <= "00";
                        als_active <= '0';

                        tmp3_start <= '1';
                        state <= S_TMP3_WAIT;

                    when S_TMP3_WAIT =>
                        sensor_busy_reg <= '1';
                        als_active <= '0';

                        if tmp3_done = '1' then
                            state <= S_TMP3_EVAL;
                        end if;

                    when S_TMP3_EVAL =>
                        sensor_busy_reg <= '1';
                        als_active <= '0';

                        if tmp3_valid = '1' and tmp3_ack_error = '0' then
                            sensor_type_reg <= "10";

                            temp_int := to_integer(unsigned(tmp3_temp_c));

                            -- PASS if temperature is at or below threshold
                            -- FAIL if temperature is above threshold
                            if temp_int <= TMP3_PASS_C then
                                sensor_pass_reg <= '1';
                            else
                                sensor_pass_reg <= '0';
                            end if;

                        else
                            -- Unknown / no valid sensor
                            sensor_type_reg <= "00";
                            sensor_pass_reg <= '0';
                        end if;

                        state <= S_DONE;

                    ----------------------------------------------------
                    -- Finish validation transaction
                    ----------------------------------------------------
                    when S_DONE =>
                        sensor_busy_reg <= '0';
                        sensor_done_reg <= '1';
                        als_active <= '0';
                        state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;