-- ro_array.vhd
-- Day 2 RO-PUF primitive for the Trusted Sensor Validation Console.
--
-- SIM_MODE = true:
--   Safe behavioral model for Vivado/XSim simulation. It produces deterministic,
--   non-zero, different counter values for each RO pair.
--
-- SIM_MODE = false:
--   Hardware-oriented RO fabric. This instantiates 64 ring oscillators for
--   NUM_PAIRS = 32. KEEP and DONT_TOUCH attributes are applied to the inverter
--   chain so Vivado does not remove the intentional combinational loop.
--
-- Note: Real RO counters are asynchronous to clk. For a class project this is
-- acceptable as a PUF primitive, but constrain/review timing carefully in a
-- larger design.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Single odd-stage ring oscillator
-- ============================================================
entity ro_osc is
    generic (
        STAGES : positive := 5
    );
    port (
        en     : in  std_logic;
        ro_out : out std_logic
    );
end entity;

architecture rtl of ro_osc is
    signal inv_chain : std_logic_vector(STAGES-1 downto 0) := (others => '0');

    attribute KEEP       : string;
    attribute DONT_TOUCH : string;
    attribute KEEP       of inv_chain : signal is "TRUE";
    attribute DONT_TOUCH of inv_chain : signal is "TRUE";
begin
    assert (STAGES mod 2 = 1)
        report "RO must have an odd number of inverter stages"
        severity failure;

    -- Gate the oscillator with en. When en = 0, force the chain to a stable value.
    inv_chain(0) <= (not inv_chain(STAGES-1)) when en = '1' else '0';

    gen_inv : for i in 1 to STAGES-1 generate
        inv_chain(i) <= not inv_chain(i-1);
    end generate;

    ro_out <= inv_chain(STAGES-1);
end architecture;

-- ============================================================
-- 32-pair RO array -> 32-bit PUF response
-- ============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ro_array is
    generic (
        NUM_PAIRS     : positive := 32;
        RO_STAGES     : positive := 5;
        COUNTER_WIDTH : positive := 24;
        WINDOW_CYCLES : natural  := 5000;
        SIM_MODE      : boolean  := true
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;  -- active-high synchronous reset for control
        start        : in  std_logic;  -- one-clock pulse starts measurement
        busy         : out std_logic;
        done         : out std_logic;  -- one-clock pulse when response is ready
        response     : out std_logic_vector(NUM_PAIRS-1 downto 0);

        -- Debug outputs for simulation/ILA. Pair i is stored in slice
        -- ((i+1)*COUNTER_WIDTH-1 downto i*COUNTER_WIDTH).
        count_a_flat : out std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);
        count_b_flat : out std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of ro_array is
    type counter_array_t is array (natural range <>) of unsigned(COUNTER_WIDTH-1 downto 0);

    signal count_a      : counter_array_t(0 to NUM_PAIRS-1) := (others => (others => '0'));
    signal count_b      : counter_array_t(0 to NUM_PAIRS-1) := (others => (others => '0'));
    signal response_reg : std_logic_vector(NUM_PAIRS-1 downto 0) := (others => '0');

    function sim_step(idx : natural) return unsigned is
        variable step_nat : natural;
    begin
        -- Deterministic per-RO speed model. Adjacent RO indices intentionally
        -- receive different increments, so each pair gets distinct counts.
        step_nat := ((idx * 7 + 3) mod 17) + 1;
        return to_unsigned(step_nat, COUNTER_WIDTH);
    end function;
begin
    response <= response_reg;

    gen_flat : for i in 0 to NUM_PAIRS-1 generate
        count_a_flat((i+1)*COUNTER_WIDTH-1 downto i*COUNTER_WIDTH) <= std_logic_vector(count_a(i));
        count_b_flat((i+1)*COUNTER_WIDTH-1 downto i*COUNTER_WIDTH) <= std_logic_vector(count_b(i));
    end generate;

    -- ========================================================
    -- Simulation-safe behavioral model
    -- ========================================================
    sim_gen : if SIM_MODE generate
        type state_t is (S_IDLE, S_RUN, S_COMPARE);
        signal state      : state_t := S_IDLE;
        signal window_cnt : unsigned(31 downto 0) := (others => '0');
    begin
        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    state        <= S_IDLE;
                    window_cnt   <= (others => '0');
                    busy         <= '0';
                    done         <= '0';
                    response_reg <= (others => '0');
                    for i in 0 to NUM_PAIRS-1 loop
                        count_a(i) <= (others => '0');
                        count_b(i) <= (others => '0');
                    end loop;
                else
                    done <= '0';

                    case state is
                        when S_IDLE =>
                            busy <= '0';
                            if start = '1' then
                                window_cnt <= (others => '0');
                                busy       <= '1';
                                for i in 0 to NUM_PAIRS-1 loop
                                    count_a(i) <= (others => '0');
                                    count_b(i) <= (others => '0');
                                end loop;
                                state <= S_RUN;
                            end if;

                        when S_RUN =>
                            busy <= '1';
                            if window_cnt < to_unsigned(WINDOW_CYCLES, window_cnt'length) then
                                window_cnt <= window_cnt + 1;
                                for i in 0 to NUM_PAIRS-1 loop
                                    count_a(i) <= count_a(i) + sim_step(2*i);
                                    count_b(i) <= count_b(i) + sim_step(2*i + 1);
                                end loop;
                            else
                                state <= S_COMPARE;
                            end if;

                        when S_COMPARE =>
                            for i in 0 to NUM_PAIRS-1 loop
                                if count_a(i) > count_b(i) then
                                    response_reg(i) <= '1';
                                else
                                    response_reg(i) <= '0';
                                end if;
                            end loop;
                            busy  <= '0';
                            done  <= '1';
                            state <= S_IDLE;
                    end case;
                end if;
            end if;
        end process;
    end generate;

    -- ========================================================
    -- Hardware-oriented RO fabric
    -- ========================================================
    hw_gen : if not SIM_MODE generate
        signal ro_a           : std_logic_vector(NUM_PAIRS-1 downto 0);
        signal ro_b           : std_logic_vector(NUM_PAIRS-1 downto 0);
        signal measure_active : std_logic := '0';
        signal clear_counts   : std_logic := '0';
        signal window_cnt     : unsigned(31 downto 0) := (others => '0');
    begin
        gen_pairs : for i in 0 to NUM_PAIRS-1 generate
            osc_a : entity work.ro_osc
                generic map (STAGES => RO_STAGES)
                port map (
                    en     => measure_active,
                    ro_out => ro_a(i)
                );

            osc_b : entity work.ro_osc
                generic map (STAGES => RO_STAGES)
                port map (
                    en     => measure_active,
                    ro_out => ro_b(i)
                );

            -- Count RO-A rising edges during the measurement window.
            process(ro_a(i), rst, clear_counts)
            begin
                if rst = '1' or clear_counts = '1' then
                    count_a(i) <= (others => '0');
                elsif rising_edge(ro_a(i)) then
                    if measure_active = '1' then
                        count_a(i) <= count_a(i) + 1;
                    end if;
                end if;
            end process;

            -- Count RO-B rising edges during the measurement window.
            process(ro_b(i), rst, clear_counts)
            begin
                if rst = '1' or clear_counts = '1' then
                    count_b(i) <= (others => '0');
                elsif rising_edge(ro_b(i)) then
                    if measure_active = '1' then
                        count_b(i) <= count_b(i) + 1;
                    end if;
                end if;
            end process;
        end generate;

        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    measure_active <= '0';
                    clear_counts   <= '0';
                    window_cnt     <= (others => '0');
                    busy           <= '0';
                    done           <= '0';
                    response_reg   <= (others => '0');
                else
                    done         <= '0';
                    clear_counts <= '0';

                    if start = '1' and measure_active = '0' then
                        clear_counts   <= '1';
                        measure_active <= '1';
                        window_cnt     <= (others => '0');
                        busy           <= '1';

                    elsif measure_active = '1' then
                        if window_cnt < to_unsigned(WINDOW_CYCLES, window_cnt'length) then
                            window_cnt <= window_cnt + 1;
                        else
                            measure_active <= '0';
                            busy           <= '0';
                            done           <= '1';
                            for i in 0 to NUM_PAIRS-1 loop
                                if count_a(i) > count_b(i) then
                                    response_reg(i) <= '1';
                                else
                                    response_reg(i) <= '0';
                                end if;
                            end loop;
                        end if;
                    end if;
                end if;
            end if;
        end process;
    end generate;
end architecture;
