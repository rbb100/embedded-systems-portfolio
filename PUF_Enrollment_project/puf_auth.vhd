-- puf_auth.vhd
-- Day 3 PUF authentication comparator.
-- Compares live RO-PUF response against enrolled reference using Hamming distance.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.puf_enroll_pkg.ALL;

entity puf_auth is
    generic (
        RESPONSE_WIDTH    : positive := 32;
        HAMMING_THRESHOLD : natural  := DEFAULT_HD_THRESHOLD;
        ENROLLED_RESPONSE : std_logic_vector(RESPONSE_WIDTH-1 downto 0) := ENROLLED_RESPONSE_32
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        ro_response : in  std_logic_vector(RESPONSE_WIDTH-1 downto 0);
        auth_valid  : out std_logic
    );
end entity;

architecture rtl of puf_auth is
    function popcount(v : std_logic_vector) return natural is
        variable c : natural := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then
                c := c + 1;
            end if;
        end loop;
        return c;
    end function;
begin
    process(clk)
        variable distance : natural range 0 to RESPONSE_WIDTH;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                auth_valid <= '0';
            else
                distance := popcount(ro_response xor ENROLLED_RESPONSE);

                if distance <= HAMMING_THRESHOLD then
                    auth_valid <= '1';
                else
                    auth_valid <= '0';
                end if;
            end if;
        end if;
    end process;
end architecture;
