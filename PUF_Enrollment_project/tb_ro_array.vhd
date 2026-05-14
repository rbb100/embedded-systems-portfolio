-- tb_ro_array.vhd
-- Day 2 simulation testbench.
-- Verifies that all 32 RO pairs produce non-zero and distinct pair counts.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_ro_array is
end entity;

architecture sim of tb_ro_array is
    constant NUM_PAIRS     : positive := 32;
    constant COUNTER_WIDTH : positive := 16;
    constant WINDOW_CYCLES : natural  := 200;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal start        : std_logic := '0';
    signal busy         : std_logic;
    signal done         : std_logic;
    signal response     : std_logic_vector(NUM_PAIRS-1 downto 0);
    signal count_a_flat : std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);
    signal count_b_flat : std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);
begin
    clk <= not clk after 4 ns; -- 125 MHz Zybo-style clock

    dut : entity work.ro_array
        generic map (
            NUM_PAIRS     => NUM_PAIRS,
            RO_STAGES     => 5,
            COUNTER_WIDTH => COUNTER_WIDTH,
            WINDOW_CYCLES => WINDOW_CYCLES,
            SIM_MODE      => true
        )
        port map (
            clk          => clk,
            rst          => rst,
            start        => start,
            busy         => busy,
            done         => done,
            response     => response,
            count_a_flat => count_a_flat,
            count_b_flat => count_b_flat
        );

    stim : process
        variable ca : unsigned(COUNTER_WIDTH-1 downto 0);
        variable cb : unsigned(COUNTER_WIDTH-1 downto 0);
    begin
        wait for 40 ns;
        rst <= '0';
        wait until rising_edge(clk);

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until done = '1';
        wait for 1 ns;

        for i in 0 to NUM_PAIRS-1 loop
            ca := unsigned(count_a_flat((i+1)*COUNTER_WIDTH-1 downto i*COUNTER_WIDTH));
            cb := unsigned(count_b_flat((i+1)*COUNTER_WIDTH-1 downto i*COUNTER_WIDTH));

            assert ca /= 0
                report "FAIL: RO A counter is zero for pair " & integer'image(i)
                severity failure;

            assert cb /= 0
                report "FAIL: RO B counter is zero for pair " & integer'image(i)
                severity failure;

            assert ca /= cb
                report "FAIL: RO pair counts are not distinct for pair " & integer'image(i)
                severity failure;
        end loop;

        report "PASS: all 32 RO pairs produced non-zero distinct pair counts";
        report "PUF response = 0x" & to_hstring(response);
        wait;
    end process;
end architecture;
