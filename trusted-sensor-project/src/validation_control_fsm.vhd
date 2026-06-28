library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity validation_control_fsm is
    generic (
        BOARD_ID_HOLD_CYCLES : natural := 62500000  -- about 0.5 sec at 125 MHz
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        user_start : in std_logic;
        retry      : in std_logic;

        puf_busy  : in std_logic;
        puf_done  : in std_logic;
        puf_valid : in std_logic;

        sensor_done : in std_logic;
        sensor_pass : in std_logic;

        start_auth : out std_logic;

        validation_enable  : out std_logic;
        start_sensor_check : out std_logic;

        auth_pass    : out std_logic;
        auth_fail    : out std_logic;
        system_ready : out std_logic;

        display_code : out std_logic_vector(3 downto 0);
        state_dbg    : out std_logic_vector(3 downto 0)
    );
end entity validation_control_fsm;

architecture rtl of validation_control_fsm is

    type state_t is (
        S_IDLE,
        S_AUTH_START,
        S_AUTH_WAIT,
        S_AUTH_CHECK,
        S_AUTH_PASS,
        S_BOARD_IDENTIFIED,
        S_AUTH_FAIL,
        S_VALIDATION_READY,
        S_SENSOR_START,
        S_SENSOR_WAIT,
        S_SENSOR_PASS,
        S_SENSOR_FAIL
    );

    signal state : state_t := S_IDLE;

    signal hold_cnt : natural range 0 to BOARD_ID_HOLD_CYCLES := 0;

    signal start_auth_reg         : std_logic := '0';
    signal start_sensor_check_reg : std_logic := '0';

    signal validation_enable_reg  : std_logic := '0';
    signal auth_pass_reg          : std_logic := '0';
    signal auth_fail_reg          : std_logic := '0';
    signal system_ready_reg       : std_logic := '0';

    signal display_code_reg : std_logic_vector(3 downto 0) := "0000";
    signal state_dbg_reg    : std_logic_vector(3 downto 0) := "0000";

begin

    start_auth         <= start_auth_reg;
    start_sensor_check <= start_sensor_check_reg;

    validation_enable  <= validation_enable_reg;
    auth_pass          <= auth_pass_reg;
    auth_fail          <= auth_fail_reg;
    system_ready       <= system_ready_reg;

    display_code       <= display_code_reg;
    state_dbg          <= state_dbg_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE;

                hold_cnt <= 0;

                start_auth_reg <= '0';
                start_sensor_check_reg <= '0';

                validation_enable_reg <= '0';
                auth_pass_reg <= '0';
                auth_fail_reg <= '0';
                system_ready_reg <= '0';

                display_code_reg <= "0000";
                state_dbg_reg <= "0000";

            else
                -- default pulse outputs
                start_auth_reg <= '0';
                start_sensor_check_reg <= '0';

                case state is

                    ----------------------------------------------------------------
                    -- 0000 = IDLE
                    ----------------------------------------------------------------
                    when S_IDLE =>
                        validation_enable_reg <= '0';
                        auth_pass_reg <= '0';
                        auth_fail_reg <= '0';
                        system_ready_reg <= '0';

                        display_code_reg <= "0000";
                        state_dbg_reg <= "0000";

                        hold_cnt <= 0;

                        if user_start = '1' then
                            state <= S_AUTH_START;
                        end if;

                    ----------------------------------------------------------------
                    -- 0001 = AUTH START
                    ----------------------------------------------------------------
                    when S_AUTH_START =>
                        validation_enable_reg <= '0';
                        auth_pass_reg <= '0';
                        auth_fail_reg <= '0';
                        system_ready_reg <= '0';

                        display_code_reg <= "0001";
                        state_dbg_reg <= "0001";

                        start_auth_reg <= '1';

                        state <= S_AUTH_WAIT;

                    ----------------------------------------------------------------
                    -- 0010 = AUTH WAIT
                    ----------------------------------------------------------------
                    when S_AUTH_WAIT =>
                        validation_enable_reg <= '0';
                        system_ready_reg <= '0';

                        display_code_reg <= "0010";
                        state_dbg_reg <= "0010";

                        if puf_done = '1' then
                            state <= S_AUTH_CHECK;
                        end if;

                    ----------------------------------------------------------------
                    -- 0011 = AUTH CHECK
                    ----------------------------------------------------------------
                    when S_AUTH_CHECK =>
                        display_code_reg <= "0011";
                        state_dbg_reg <= "0011";

                        if puf_valid = '1' then
                            state <= S_AUTH_PASS;
                        else
                            state <= S_AUTH_FAIL;
                        end if;

                    ----------------------------------------------------------------
                    -- 0100 = AUTH PASS
                    -- short internal pass state
                    ----------------------------------------------------------------
                    when S_AUTH_PASS =>
                        auth_pass_reg <= '1';
                        auth_fail_reg <= '0';
                        validation_enable_reg <= '1';
                        system_ready_reg <= '0';

                        display_code_reg <= "0100";
                        state_dbg_reg <= "0100";

                        hold_cnt <= 0;
                        state <= S_BOARD_IDENTIFIED;

                    ----------------------------------------------------------------
                    -- 1011 = BOARD IDENTIFIED / PUF PASS
                    -- visible hold state before READY
                    ----------------------------------------------------------------
                    when S_BOARD_IDENTIFIED =>
                        auth_pass_reg <= '1';
                        auth_fail_reg <= '0';
                        validation_enable_reg <= '1';
                        system_ready_reg <= '0';

                        display_code_reg <= "1011";
                        state_dbg_reg <= "1011";

                        if hold_cnt = BOARD_ID_HOLD_CYCLES then
                            hold_cnt <= 0;
                            state <= S_VALIDATION_READY;
                        else
                            hold_cnt <= hold_cnt + 1;
                        end if;

                    ----------------------------------------------------------------
                    -- 0101 = AUTH FAIL
                    ----------------------------------------------------------------
                    when S_AUTH_FAIL =>
                        auth_pass_reg <= '0';
                        auth_fail_reg <= '1';
                        validation_enable_reg <= '0';
                        system_ready_reg <= '0';

                        display_code_reg <= "0101";
                        state_dbg_reg <= "0101";

                        -- retry auth from fail state
                        if retry = '1' or user_start = '1' then
                            state <= S_AUTH_START;
                        end if;

                    ----------------------------------------------------------------
                    -- 0110 = VALIDATION READY
                    ----------------------------------------------------------------
                    when S_VALIDATION_READY =>
                        auth_pass_reg <= '1';
                        auth_fail_reg <= '0';
                        validation_enable_reg <= '1';
                        system_ready_reg <= '1';

                        display_code_reg <= "0110";
                        state_dbg_reg <= "0110";

                        if user_start = '1' then
                            state <= S_SENSOR_START;
                        end if;

                    ----------------------------------------------------------------
                    -- 0111 = SENSOR START
                    ----------------------------------------------------------------
                    when S_SENSOR_START =>
                        auth_pass_reg <= '1';
                        auth_fail_reg <= '0';
                        validation_enable_reg <= '1';
                        system_ready_reg <= '0';

                        display_code_reg <= "0111";
                        state_dbg_reg <= "0111";

                        start_sensor_check_reg <= '1';

                        state <= S_SENSOR_WAIT;

                    ----------------------------------------------------------------
                    -- 1000 = SENSOR WAIT
                    ----------------------------------------------------------------
                    when S_SENSOR_WAIT =>
                        auth_pass_reg <= '1';
                        auth_fail_reg <= '0';
                        validation_enable_reg <= '1';
                        system_ready_reg <= '0';

                        display_code_reg <= "1000";
                        state_dbg_reg <= "1000";

                        if sensor_done = '1' then
                            if sensor_pass = '1' then
                                state <= S_SENSOR_PASS;
                            else
                                state <= S_SENSOR_FAIL;
                            end if;
                        end if;

                    ----------------------------------------------------------------
                    -- 1001 = SENSOR PASS
                    ----------------------------------------------------------------
                    when S_SENSOR_PASS =>
                        auth_pass_reg <= '1';
                        auth_fail_reg <= '0';
                        validation_enable_reg <= '1';
                        system_ready_reg <= '0';

                        display_code_reg <= "1001";
                        state_dbg_reg <= "1001";

                        -- key 1 runs another sensor check
                        if user_start = '1' then
                            state <= S_SENSOR_START;

                        -- key 2 returns to ready
                        elsif retry = '1' then
                            state <= S_VALIDATION_READY;
                        end if;

                    ----------------------------------------------------------------
                    -- 1010 = SENSOR FAIL
                    ----------------------------------------------------------------
                    when S_SENSOR_FAIL =>
                        auth_pass_reg <= '1';
                        auth_fail_reg <= '0';
                        validation_enable_reg <= '1';
                        system_ready_reg <= '0';

                        display_code_reg <= "1010";
                        state_dbg_reg <= "1010";

                        -- key 1 runs another sensor check
                        if user_start = '1' then
                            state <= S_SENSOR_START;

                        -- key 2 returns to ready
                        elsif retry = '1' then
                            state <= S_VALIDATION_READY;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;