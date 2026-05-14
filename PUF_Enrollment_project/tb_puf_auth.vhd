-- tb_puf_auth.vhd
-- Day 3 authentication testbench.
-- Cases:
--   1. Exact enrolled response       -> pass
--   2. 3 flipped bits                -> pass
--   3. 10 flipped bits               -> fail

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_puf_auth is
end entity;

architecture sim of tb_puf_auth is
    constant ENROLLED : std_logic_vector(31 downto 0) := x"A5A55A5A";

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal ro_response : std_logic_vector(31 downto 0) := (others => '0');
    signal auth_valid  : std_logic;
begin
    clk <= not clk after 4 ns;

    dut : entity work.puf_auth
        generic map (
            RESPONSE_WIDTH    => 32,
            HAMMING_THRESHOLD => 4,
            ENROLLED_RESPONSE => ENROLLED
        )
        port map (
            clk         => clk,
            rst         => rst,
            ro_response => ro_response,
            auth_valid  => auth_valid
        );

    stim : process
    begin
        wait for 40 ns;
        rst <= '0';

        -- Case 1: exact match, distance = 0, should pass.
        ro_response <= ENROLLED;
        wait until rising_edge(clk);
        wait for 1 ns;
        assert auth_valid = '1'
            report "FAIL: exact match should authenticate"
            severity failure;

        -- Case 2: 3 bits flipped, distance = 3, should pass for threshold 4.
        ro_response <= ENROLLED xor x"00000007";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert auth_valid = '1'
            report "FAIL: 3-bit mismatch should authenticate"
            severity failure;

        -- Case 3: 10 bits flipped, distance = 10, should fail for threshold 4.
        -- 0x000003FF has exactly ten 1 bits.
        ro_response <= ENROLLED xor x"000003FF";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert auth_valid = '0'
            report "FAIL: 10-bit mismatch should not authenticate"
            severity failure;

        report "PASS: puf_auth exact/3-bit/10-bit test cases behaved correctly";
        wait;
    end process;
end architecture;
