library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pmod_kypd is
    generic (
        SCAN_CYCLES    : natural := 125000; -- 1 ms at 125 MHz
        DEBOUNCE_TICKS : natural := 2
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- PMOD KYPD
        kypd_col : out std_logic_vector(3 downto 0);
        kypd_row : in  std_logic_vector(3 downto 0);

        key_valid : out std_logic;
        key_code  : out std_logic_vector(3 downto 0)
    );
end entity pmod_kypd;

architecture rtl of pmod_kypd is

    signal scan_count : natural range 0 to SCAN_CYCLES := 0;
    signal col_idx    : natural range 0 to 3 := 0;

    signal row_sync_0 : std_logic_vector(3 downto 0) := (others => '1');
    signal row_sync_1 : std_logic_vector(3 downto 0) := (others => '1');

    signal last_candidate : std_logic_vector(3 downto 0) := x"0";
    signal stable_count   : natural range 0 to DEBOUNCE_TICKS := 0;
    signal release_count  : natural range 0 to 4 := 0;
    signal pressed_latched : std_logic := '0';

    function decode_key(row_idx : natural; col_idx : natural) return std_logic_vector is
        variable key : std_logic_vector(3 downto 0) := x"0";
    begin
        -- Assumed keypad layout:
        -- 1 2 3 A
        -- 4 5 6 B
        -- 7 8 9 C
        -- 0 F E D
        --
        -- kypd_col[0] = COL4
        -- kypd_col[1] = COL3
        -- kypd_col[2] = COL2
        -- kypd_col[3] = COL1
        --
        -- kypd_row[0] = ROW4
        -- kypd_row[1] = ROW3
        -- kypd_row[2] = ROW2
        -- kypd_row[3] = ROW1

        case row_idx is
            when 3 => -- ROW1
                case col_idx is
                    when 3 => key := x"1";
                    when 2 => key := x"2";
                    when 1 => key := x"3";
                    when 0 => key := x"A";
                    when others => key := x"0";
                end case;

            when 2 => -- ROW2
                case col_idx is
                    when 3 => key := x"4";
                    when 2 => key := x"5";
                    when 1 => key := x"6";
                    when 0 => key := x"B";
                    when others => key := x"0";
                end case;

            when 1 => -- ROW3
                case col_idx is
                    when 3 => key := x"7";
                    when 2 => key := x"8";
                    when 1 => key := x"9";
                    when 0 => key := x"C";
                    when others => key := x"0";
                end case;

            when 0 => -- ROW4
                case col_idx is
                    when 3 => key := x"0";
                    when 2 => key := x"F";
                    when 1 => key := x"E";
                    when 0 => key := x"D";
                    when others => key := x"0";
                end case;

            when others =>
                key := x"0";
        end case;

        return key;
    end function;

begin

    -- Drive one column low at a time
    process(col_idx)
    begin
        case col_idx is
            when 0 => kypd_col <= "1110"; -- COL4 low
            when 1 => kypd_col <= "1101"; -- COL3 low
            when 2 => kypd_col <= "1011"; -- COL2 low
            when 3 => kypd_col <= "0111"; -- COL1 low
            when others => kypd_col <= "1111";
        end case;
    end process;

    process(clk)
        variable found_now : std_logic;
        variable row_idx_v : natural range 0 to 3;
        variable candidate : std_logic_vector(3 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                scan_count      <= 0;
                col_idx         <= 0;
                row_sync_0      <= (others => '1');
                row_sync_1      <= (others => '1');
                last_candidate  <= x"0";
                stable_count    <= 0;
                release_count   <= 0;
                pressed_latched <= '0';
                key_valid       <= '0';
                key_code        <= x"0";
            else
                key_valid <= '0';

                row_sync_0 <= kypd_row;
                row_sync_1 <= row_sync_0;

                if scan_count = SCAN_CYCLES then
                    scan_count <= 0;

                    found_now := '0';
                    row_idx_v := 0;
                    candidate := x"0";

                    -- Active-low row detection
                    if row_sync_1(0) = '0' then
                        found_now := '1';
                        row_idx_v := 0;
                    elsif row_sync_1(1) = '0' then
                        found_now := '1';
                        row_idx_v := 1;
                    elsif row_sync_1(2) = '0' then
                        found_now := '1';
                        row_idx_v := 2;
                    elsif row_sync_1(3) = '0' then
                        found_now := '1';
                        row_idx_v := 3;
                    end if;

                    if found_now = '1' then
                        candidate := decode_key(row_idx_v, col_idx);
                        release_count <= 0;

                        if candidate = last_candidate then
                            if stable_count < DEBOUNCE_TICKS then
                                stable_count <= stable_count + 1;
                            end if;

                            if stable_count = DEBOUNCE_TICKS - 1 and pressed_latched = '0' then
                                key_code        <= candidate;
                                key_valid       <= '1';
                                pressed_latched <= '1';
                            end if;
                        else
                            last_candidate <= candidate;
                            stable_count   <= 1;
                        end if;

                    else
                        -- Need a few no-key column samples before declaring release
                        if release_count < 4 then
                            release_count <= release_count + 1;
                        else
                            stable_count    <= 0;
                            pressed_latched <= '0';
                            last_candidate  <= x"0";
                        end if;
                    end if;

                    if col_idx = 3 then
                        col_idx <= 0;
                    else
                        col_idx <= col_idx + 1;
                    end if;

                else
                    scan_count <= scan_count + 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;