library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity trusted_sensor_console_final_hw is
    generic (
        NUM_PAIRS         : positive := 32;
        COUNTER_WIDTH     : positive := 24;
        HAMMING_THRESHOLD : natural := 8;

        ENROLLED_RESPONSE : std_logic_vector(31 downto 0) := x"82111903";

        ALS_THRESHOLD     : natural := 64;
        TMP3_PASS_C       : natural := 30
    );
    port (
        clk : in std_logic;

        -- Board reset button
        rst_btn : in std_logic;

        ----------------------------------------------------------------
        -- KYPD PMOD on JA
        ----------------------------------------------------------------
        kypd_col : out std_logic_vector(3 downto 0);
        kypd_row : in  std_logic_vector(3 downto 0);

        ----------------------------------------------------------------
        -- Shared sensor port on JB
        ----------------------------------------------------------------
        sensor_jb1_cs       : out   std_logic;
        sensor_jb3_scl_miso : inout std_logic;
        sensor_jb4_sda_sclk : inout std_logic;

        ----------------------------------------------------------------
        -- OLED PMOD on JD
        ----------------------------------------------------------------
        oled_cs   : out std_logic;
        oled_sdin : out std_logic;
        oled_sclk : out std_logic;
        oled_dc   : out std_logic;
        oled_res  : out std_logic;
        oled_vbat : out std_logic;
        oled_vdd  : out std_logic;

        ----------------------------------------------------------------
        -- Board LEDs
        ----------------------------------------------------------------
        led : out std_logic_vector(3 downto 0)
    );
end entity trusted_sensor_console_final_hw;

architecture rtl of trusted_sensor_console_final_hw is

    signal rst : std_logic := '0';

    --------------------------------------------------------------------
    -- KYPD signals
    --------------------------------------------------------------------
    signal key_valid : std_logic := '0';
    signal key_code  : std_logic_vector(3 downto 0) := (others => '0');

    signal user_start_pulse : std_logic := '0';
    signal retry_pulse      : std_logic := '0';

    --------------------------------------------------------------------
    -- FSM / PUF signals
    --------------------------------------------------------------------
    signal start_auth_sig : std_logic := '0';

    signal auth_busy_sig  : std_logic := '0';
    signal auth_done_sig  : std_logic := '0';
    signal auth_valid_sig : std_logic := '0';

    signal validation_enable_sig  : std_logic := '0';
    signal start_sensor_check_sig : std_logic := '0';

    signal auth_pass_sig    : std_logic := '0';
    signal auth_fail_sig    : std_logic := '0';
    signal system_ready_sig : std_logic := '0';

    --------------------------------------------------------------------
    -- Sensor validation signals
    --------------------------------------------------------------------
    signal sensor_busy_sig : std_logic := '0';
    signal sensor_done_sig : std_logic := '0';
    signal sensor_pass_sig : std_logic := '0';

    signal sensor_type_dbg_sig : std_logic_vector(1 downto 0) := "00";
    signal als_value_dbg_sig   : std_logic_vector(7 downto 0) := (others => '0');
    signal tmp3_temp_dbg_sig   : std_logic_vector(7 downto 0) := (others => '0');

    --------------------------------------------------------------------
    -- Debug/status
    --------------------------------------------------------------------
    signal display_code_sig : std_logic_vector(3 downto 0) := (others => '0');
    signal state_dbg_sig    : std_logic_vector(3 downto 0) := (others => '0');

    signal puf_response_sig : std_logic_vector(NUM_PAIRS-1 downto 0) := (others => '0');

    signal count_a_flat_sig : std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);
    signal count_b_flat_sig : std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);

    --------------------------------------------------------------------
    -- OLED update signals
    --------------------------------------------------------------------
    signal oled_busy_sig  : std_logic := '0';
    signal oled_ready_sig : std_logic := '0';

    signal oled_status_code  : std_logic_vector(3 downto 0) := (others => '0');
    signal oled_status_pulse : std_logic := '0';

    signal last_sent_code : std_logic_vector(3 downto 0) := (others => '0');
    signal pending_code   : std_logic_vector(3 downto 0) := (others => '0');

    --------------------------------------------------------------------
    -- Optional debug attributes for ILA later
    --------------------------------------------------------------------
    attribute mark_debug : string;
    attribute mark_debug of key_valid              : signal is "true";
    attribute mark_debug of key_code               : signal is "true";
    attribute mark_debug of user_start_pulse       : signal is "true";
    attribute mark_debug of retry_pulse            : signal is "true";
    attribute mark_debug of auth_busy_sig          : signal is "true";
    attribute mark_debug of auth_done_sig          : signal is "true";
    attribute mark_debug of auth_valid_sig         : signal is "true";
    attribute mark_debug of puf_response_sig       : signal is "true";
    attribute mark_debug of validation_enable_sig  : signal is "true";
    attribute mark_debug of sensor_done_sig        : signal is "true";
    attribute mark_debug of sensor_pass_sig        : signal is "true";
    attribute mark_debug of sensor_type_dbg_sig    : signal is "true";
    attribute mark_debug of als_value_dbg_sig      : signal is "true";
    attribute mark_debug of tmp3_temp_dbg_sig      : signal is "true";
    attribute mark_debug of display_code_sig       : signal is "true";
    attribute mark_debug of state_dbg_sig          : signal is "true";

begin

    rst <= rst_btn;

    -- LEDs show FSM state code
    led <= display_code_sig;

    --------------------------------------------------------------------
    -- KYPD scanner
    --------------------------------------------------------------------
    u_kypd : entity work.pmod_kypd
        port map (
            clk => clk,
            rst => rst,

            kypd_col => kypd_col,
            kypd_row => kypd_row,

            key_valid => key_valid,
            key_code  => key_code
        );

    -- Key mapping:
    -- Key 1 = start authentication / start sensor check
    -- Key 2 = retry/back
    user_start_pulse <= '1' when key_valid = '1' and key_code = x"1" else '0';
    retry_pulse      <= '1' when key_valid = '1' and key_code = x"2" else '0';

    --------------------------------------------------------------------
    -- Main control FSM
    -- This should be the updated version that includes PUF PASS / 1011.
    --------------------------------------------------------------------
    u_control_fsm : entity work.validation_control_fsm
        port map (
            clk => clk,
            rst => rst,

            user_start => user_start_pulse,
            retry      => retry_pulse,

            puf_busy  => auth_busy_sig,
            puf_done  => auth_done_sig,
            puf_valid => auth_valid_sig,

            sensor_done => sensor_done_sig,
            sensor_pass => sensor_pass_sig,

            start_auth => start_auth_sig,

            validation_enable  => validation_enable_sig,
            start_sensor_check => start_sensor_check_sig,

            auth_pass    => auth_pass_sig,
            auth_fail    => auth_fail_sig,
            system_ready => system_ready_sig,

            display_code => display_code_sig,
            state_dbg    => state_dbg_sig
        );

    --------------------------------------------------------------------
    -- RO-PUF
    --------------------------------------------------------------------

u_puf_top : entity work.puf_top_real_ro
    generic map (
        NUM_PAIRS         => NUM_PAIRS,
        RO_STAGES         => 5,
        COUNTER_WIDTH     => COUNTER_WIDTH,
        WINDOW_CYCLES     => 50000,
        HAMMING_THRESHOLD => HAMMING_THRESHOLD,
        ENROLLED_RESPONSE => ENROLLED_RESPONSE
    )
    port map (
        clk => clk,
        rst => rst,

        start_auth => start_auth_sig,

        auth_busy  => auth_busy_sig,
        auth_done  => auth_done_sig,
        auth_valid => auth_valid_sig,

        puf_response => puf_response_sig,

        count_a_flat => count_a_flat_sig,
        count_b_flat => count_b_flat_sig
    );

    --------------------------------------------------------------------
    -- Shared JB sensor-port validation
    --------------------------------------------------------------------
    u_sensor_port_validation : entity work.sensor_port_validation_core
        generic map (
            ALS_THRESHOLD => ALS_THRESHOLD,
            TMP3_PASS_C   => TMP3_PASS_C
        )
        port map (
            clk => clk,
            rst => rst,

            validation_enable  => validation_enable_sig,
            start_sensor_check => start_sensor_check_sig,

            sensor_jb1_cs       => sensor_jb1_cs,
            sensor_jb3_scl_miso => sensor_jb3_scl_miso,
            sensor_jb4_sda_sclk => sensor_jb4_sda_sclk,

            sensor_busy => sensor_busy_sig,
            sensor_done => sensor_done_sig,
            sensor_pass => sensor_pass_sig,

            sensor_type_dbg => sensor_type_dbg_sig,

            als_value_dbg => als_value_dbg_sig,
            tmp3_temp_dbg => tmp3_temp_dbg_sig
        );

    --------------------------------------------------------------------
    -- OLED update controller
    -- Sends update whenever display_code changes.
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                oled_status_code  <= "0000";
                oled_status_pulse <= '0';
                last_sent_code    <= "0000";
                pending_code      <= "0000";
            else
                oled_status_pulse <= '0';

                pending_code <= display_code_sig;

                if oled_ready_sig = '1' and oled_busy_sig = '0' then
                    if pending_code /= last_sent_code then
                        oled_status_code  <= pending_code;
                        oled_status_pulse <= '1';
                        last_sent_code    <= pending_code;
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- OLED status display
    --------------------------------------------------------------------
    u_oled_status : entity work.oled_status_display
        generic map (
            CLOCK_HZ => 125000000,
            SPI_HZ   => 5000000
        )
        port map (
            clk                => clk,
            rst                => rst,

            status_code        => oled_status_code,
            status_valid_pulse => oled_status_pulse,

            busy               => oled_busy_sig,
            init_done          => oled_ready_sig,

            oled_cs            => oled_cs,
            oled_sdin          => oled_sdin,
            oled_sclk          => oled_sclk,
            oled_dc            => oled_dc,
            oled_res           => oled_res,
            oled_vbat          => oled_vbat,
            oled_vdd           => oled_vdd
        );

end architecture rtl;