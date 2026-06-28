library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity real_ro_puf_array is
    generic (
        NUM_PAIRS     : positive := 32;
        RO_STAGES     : positive := 5;
        COUNTER_WIDTH : positive := 24;
        WINDOW_CYCLES : natural  := 50000;
        SETTLE_CYCLES : natural  := 16
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;

        start : in std_logic;

        busy  : out std_logic;
        done  : out std_logic;

        response : out std_logic_vector(NUM_PAIRS-1 downto 0);

        count_a_flat : out std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);
        count_b_flat : out std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0)
    );
end entity real_ro_puf_array;

architecture rtl of real_ro_puf_array is

    constant NUM_RO : natural := NUM_PAIRS * 2;

    type state_t is (
        S_IDLE,
        S_CLEAR,
        S_MEASURE,
        S_SETTLE,
        S_COMPARE,
        S_DONE
    );

    type count_array_t is array (natural range <>) of unsigned(COUNTER_WIDTH-1 downto 0);

    signal state : state_t := S_IDLE;

    signal ro_sig : std_logic_vector(NUM_RO-1 downto 0);

    signal counts : count_array_t(0 to NUM_RO-1) := (others => (others => '0'));

    signal clear_counts : std_logic := '0';
    signal measure_en   : std_logic := '0';

    signal window_cnt : natural range 0 to WINDOW_CYCLES := 0;
    signal settle_cnt : natural range 0 to SETTLE_CYCLES := 0;

    signal response_reg : std_logic_vector(NUM_PAIRS-1 downto 0) := (others => '0');

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    attribute KEEP : string;
    attribute DONT_TOUCH : string;

    attribute KEEP of ro_sig : signal is "TRUE";
    attribute DONT_TOUCH of ro_sig : signal is "TRUE";
    attribute KEEP of counts : signal is "TRUE";
    attribute DONT_TOUCH of counts : signal is "TRUE";

begin

    busy <= busy_reg;
    done <= done_reg;
    response <= response_reg;

    --------------------------------------------------------------------
    -- Instantiate real ROs
    --------------------------------------------------------------------
    gen_ro : for i in 0 to NUM_RO-1 generate
        u_ro : entity work.real_ro_osc
            generic map (
                STAGES => RO_STAGES
            )
            port map (
                en     => measure_en,
                ro_out => ro_sig(i)
            );
    end generate;

    --------------------------------------------------------------------
    -- Count RO edges.
    -- Each RO clocks its own counter.
    --------------------------------------------------------------------
    gen_count : for i in 0 to NUM_RO-1 generate
        process(ro_sig(i), rst, clear_counts)
        begin
            if rst = '1' or clear_counts = '1' then
                counts(i) <= (others => '0');

            elsif rising_edge(ro_sig(i)) then
                if measure_en = '1' then
                    counts(i) <= counts(i) + 1;
                end if;
            end if;
        end process;
    end generate;

    --------------------------------------------------------------------
    -- Flatten debug counters
    --------------------------------------------------------------------
    gen_flat : for p in 0 to NUM_PAIRS-1 generate
        count_a_flat((p+1)*COUNTER_WIDTH-1 downto p*COUNTER_WIDTH)
            <= std_logic_vector(counts(2*p));

        count_b_flat((p+1)*COUNTER_WIDTH-1 downto p*COUNTER_WIDTH)
            <= std_logic_vector(counts(2*p + 1));
    end generate;

    --------------------------------------------------------------------
    -- Measurement control FSM
    --------------------------------------------------------------------
    process(clk)
        variable tmp_response : std_logic_vector(NUM_PAIRS-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE;

                clear_counts <= '0';
                measure_en <= '0';

                window_cnt <= 0;
                settle_cnt <= 0;

                response_reg <= (others => '0');

                busy_reg <= '0';
                done_reg <= '0';

            else
                done_reg <= '0';

                case state is

                    when S_IDLE =>
                        clear_counts <= '0';
                        measure_en <= '0';
                        busy_reg <= '0';

                        if start = '1' then
                            busy_reg <= '1';
                            state <= S_CLEAR;
                        end if;

                    when S_CLEAR =>
                        busy_reg <= '1';
                        clear_counts <= '1';
                        measure_en <= '0';

                        window_cnt <= 0;
                        settle_cnt <= 0;

                        state <= S_MEASURE;

                    when S_MEASURE =>
                        busy_reg <= '1';
                        clear_counts <= '0';
                        measure_en <= '1';

                        if window_cnt = WINDOW_CYCLES then
                            measure_en <= '0';
                            window_cnt <= 0;
                            settle_cnt <= 0;
                            state <= S_SETTLE;
                        else
                            window_cnt <= window_cnt + 1;
                        end if;

                    when S_SETTLE =>
                        busy_reg <= '1';
                        clear_counts <= '0';
                        measure_en <= '0';

                        if settle_cnt = SETTLE_CYCLES then
                            settle_cnt <= 0;
                            state <= S_COMPARE;
                        else
                            settle_cnt <= settle_cnt + 1;
                        end if;

                    when S_COMPARE =>
                        busy_reg <= '1';
                        clear_counts <= '0';
                        measure_en <= '0';

                        tmp_response := (others => '0');

                        for p in 0 to NUM_PAIRS-1 loop
                        if counts(2*p) > counts(2*p + 1) then
                             tmp_response(p) := '1';
                        else
                             tmp_response(p) := '0';
                        end if;
                        end loop;

                        response_reg <= tmp_response;

                        state <= S_DONE;

                    when S_DONE =>
                        busy_reg <= '0';
                        done_reg <= '1';
                        clear_counts <= '0';
                        measure_en <= '0';

                        state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;