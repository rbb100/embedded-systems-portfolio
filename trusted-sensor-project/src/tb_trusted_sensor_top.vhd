-- tb_trusted_sensor_top.vhd
-- Testbench for trusted_sensor_top
--
-- Tests:
-- 1. User starts authentication
-- 2. FSM starts PUF authentication
-- 3. PUF returns auth_valid = 1
-- 4. FSM enters validation-ready state
-- 5. User starts sensor check
-- 6. Sensor check passes

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_trusted_sensor_top is
end entity tb_trusted_sensor_top;

architecture sim of tb_trusted_sensor_top is

    constant CLK_PERIOD    : time := 8 ns;
    constant NUM_PAIRS     : positive := 32;
    constant COUNTER_WIDTH : positive := 12;
    constant WINDOW_CYCLES : natural  := 200;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal user_start : std_logic := '0';
    signal retry      : std_logic := '0';

    signal sensor_done : std_logic := '0';
    signal sensor_pass : std_logic := '0';

    signal validation_enable  : std_logic;
    signal start_sensor_check : std_logic;
    signal auth_pass          : std_logic;
    signal auth_fail          : std_logic;
    signal system_ready       : std_logic;

    signal puf_response : std_logic_vector(NUM_PAIRS-1 downto 0);
    signal auth_busy    : std_logic;
    signal auth_done    : std_logic;
    signal auth_valid   : std_logic;

    signal display_code : std_logic_vector(3 downto 0);
    signal state_dbg    : std_logic_vector(3 downto 0);

    signal count_a_flat : std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);
    signal count_b_flat : std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);

begin

    --------------------------------------------------------------------
    -- Clock generation
    --------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    --------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------
    dut : entity work.trusted_sensor_top
        generic map (
            NUM_PAIRS         => NUM_PAIRS,
            RO_STAGES         => 5,
            COUNTER_WIDTH     => COUNTER_WIDTH,
            WINDOW_CYCLES     => WINDOW_CYCLES,
            HAMMING_THRESHOLD => 4,
            SIM_MODE          => true
        )
        port map (
            clk => clk,
            rst => rst,

            user_start => user_start,
            retry      => retry,

            sensor_done => sensor_done,
            sensor_pass => sensor_pass,

            validation_enable  => validation_enable,
            start_sensor_check => start_sensor_check,
            auth_pass          => auth_pass,
            auth_fail          => auth_fail,
            system_ready       => system_ready,

            puf_response => puf_response,
            auth_busy    => auth_busy,
            auth_done    => auth_done,
            auth_valid   => auth_valid,

            display_code => display_code,
            state_dbg    => state_dbg,

            count_a_flat => count_a_flat,
            count_b_flat => count_b_flat
        );

    --------------------------------------------------------------------
    -- Stimulus
    --------------------------------------------------------------------
    stim_proc : process
    begin

        report "Starting trusted_sensor_top simulation";

        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        rst <= '1';
        wait for 5 * CLK_PERIOD;

        rst <= '0';
        wait for 5 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- Step 1: User starts board authentication
        ----------------------------------------------------------------
        report "User starts PUF authentication";

        user_start <= '1';
        wait for CLK_PERIOD;
        user_start <= '0';

        ----------------------------------------------------------------
        -- Step 2: Wait until system becomes ready
        ----------------------------------------------------------------
        wait until system_ready = '1';
        wait for 2 * CLK_PERIOD;

        report "PUF response = 0x" & to_hstring(to_bitvector(puf_response));

        assert puf_response = x"C718638C"
            report "FAIL: PUF response is not C718638C"
            severity failure;

        assert auth_valid = '1'
            report "FAIL: auth_valid should be 1"
            severity failure;

        assert auth_pass = '1'
            report "FAIL: auth_pass should be 1"
            severity failure;

        assert auth_fail = '0'
            report "FAIL: auth_fail should be 0"
            severity failure;

        assert validation_enable = '1'
            report "FAIL: validation_enable should be 1"
            severity failure;

        assert system_ready = '1'
            report "FAIL: system_ready should be 1"
            severity failure;

        assert display_code = "0110"
            report "FAIL: display_code should be 0110 for VALIDATION_READY"
            severity failure;

        report "PASS: Authentication completed and validation mode enabled";

        ----------------------------------------------------------------
        -- Step 3: User starts sensor validation check
        ----------------------------------------------------------------
        wait for 10 * CLK_PERIOD;

        report "User starts sensor validation check";

        user_start <= '1';
        wait for CLK_PERIOD;
        user_start <= '0';

        ----------------------------------------------------------------
        -- Step 4: Fake sensor check result
        -- Later this will come from real TMP3/ALS validation block.
        ----------------------------------------------------------------
        wait for 10 * CLK_PERIOD;

        sensor_pass <= '0';
        sensor_done <= '1';
        wait for CLK_PERIOD;

        sensor_done <= '0';

        ----------------------------------------------------------------
        -- Step 5: Wait for FSM to enter SENSOR_PASS state
        ----------------------------------------------------------------
        wait until state_dbg = "1010";
        wait for 2 * CLK_PERIOD;

        assert validation_enable = '1'
            report "FAIL: validation_enable should stay high during sensor pass"
            severity failure;

        assert auth_pass = '1'
            report "FAIL: auth_pass should remain high"
            severity failure;

        assert state_dbg = "1001"
            report "FAIL: FSM did not enter SENSOR_PASS state"
            severity failure;

        assert display_code = "1001"
            report "FAIL: display_code should be 1001 for SENSOR_PASS"
            severity failure;

        report "PASS: Sensor validation pass path works";

        ----------------------------------------------------------------
        -- End simulation
        ----------------------------------------------------------------
        report "PASS: trusted_sensor_top full authentication + sensor-ready flow works";

        wait;

    end process;

end architecture sim;