library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity button_pulse is
    generic (
        STABLE_CYCLES : natural := 1250000
    );
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        btn_in : in  std_logic;

        pulse  : out std_logic;
        level  : out std_logic
    );
end entity button_pulse;

architecture rtl of button_pulse is

    signal sync0 : std_logic := '0';
    signal sync1 : std_logic := '0';

    signal stable_level : std_logic := '0';
    signal prev_level   : std_logic := '0';

    signal cnt : natural range 0 to STABLE_CYCLES := 0;

begin

    level <= stable_level;
    pulse <= '1' when stable_level = '1' and prev_level = '0' else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sync0 <= '0';
                sync1 <= '0';

                stable_level <= '0';
                prev_level <= '0';
                cnt <= 0;

            else
                sync0 <= btn_in;
                sync1 <= sync0;

                prev_level <= stable_level;

                if sync1 = stable_level then
                    cnt <= 0;
                else
                    if cnt = STABLE_CYCLES then
                        stable_level <= sync1;
                        cnt <= 0;
                    else
                        cnt <= cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;