library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pmod_als_reader is
    generic (
        CLK_DIV_HALF : natural := 62 -- about 1 MHz SCLK from 125 MHz
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start : in std_logic;

        -- Pmod ALS SPI
        als_cs_n  : out std_logic;
        als_sclk  : out std_logic;
        als_sdata : in  std_logic;

        busy : out std_logic;
        done : out std_logic;

        als_value : out std_logic_vector(7 downto 0);
        raw_shift_dbg : out std_logic_vector(15 downto 0)
    );
end entity pmod_als_reader;

architecture rtl of pmod_als_reader is

    type state_t is (
        S_IDLE,
        S_SETUP,
        S_TRANSFER,
        S_FINISH
    );

    signal state : state_t := S_IDLE;

    signal cs_reg   : std_logic := '1';
    signal sclk_reg : std_logic := '1'; -- idle high for ADC081S021-style read
    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    signal div_cnt : natural range 0 to CLK_DIV_HALF := 0;
    signal bit_cnt : natural range 0 to 15 := 0;

    signal shift_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal value_reg : std_logic_vector(7 downto 0) := (others => '0');

begin

    als_cs_n <= cs_reg;
    als_sclk <= sclk_reg;
    busy <= busy_reg;
    done <= done_reg;

    als_value <= value_reg;
    raw_shift_dbg <= shift_reg;

    process(clk)
        variable shifted : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= S_IDLE;

                cs_reg <= '1';
                sclk_reg <= '1';
                busy_reg <= '0';
                done_reg <= '0';

                div_cnt <= 0;
                bit_cnt <= 0;

                shift_reg <= (others => '0');
                value_reg <= (others => '0');

            else
                done_reg <= '0';

                case state is

                    when S_IDLE =>
                        cs_reg <= '1';
                        sclk_reg <= '1';
                        busy_reg <= '0';
                        div_cnt <= 0;
                        bit_cnt <= 0;

                        if start = '1' then
                            cs_reg <= '0';
                            sclk_reg <= '1';
                            busy_reg <= '1';
                            shift_reg <= (others => '0');
                            div_cnt <= 0;
                            bit_cnt <= 0;
                            state <= S_SETUP;
                        end if;

                    when S_SETUP =>
                        -- Keep CS low while SCLK is idle high,
                        -- then create the first falling edge.
                        busy_reg <= '1';
                        cs_reg <= '0';

                        if div_cnt = CLK_DIV_HALF - 1 then
                            div_cnt <= 0;
                            sclk_reg <= '0'; -- first falling edge after CS low
                            state <= S_TRANSFER;
                        else
                            div_cnt <= div_cnt + 1;
                        end if;

                    when S_TRANSFER =>
                        busy_reg <= '1';
                        cs_reg <= '0';

                        if div_cnt = CLK_DIV_HALF - 1 then
                            div_cnt <= 0;

                            -- Toggle SCLK
                            sclk_reg <= not sclk_reg;

                            -- Sample on low-to-high edge.
                            -- Because signal assignment updates later,
                            -- sclk_reg = '0' means this cycle creates rising edge.
                            if sclk_reg = '0' then
                                shifted := shift_reg(14 downto 0) & als_sdata;
                                shift_reg <= shifted;

                                if bit_cnt = 15 then
                                    -- 3 leading zeros, 8 data bits, trailing zeros.
                                    -- Captured MSB-first into shifted[15:0],
                                    -- so data is shifted(12 downto 5).
                                    value_reg <= shifted(12 downto 5);

                                    cs_reg <= '1';
                                    sclk_reg <= '1';
                                    busy_reg <= '0';
                                    done_reg <= '1';

                                    state <= S_FINISH;
                                else
                                    bit_cnt <= bit_cnt + 1;
                                end if;
                            end if;

                        else
                            div_cnt <= div_cnt + 1;
                        end if;

                    when S_FINISH =>
                        done_reg <= '0';
                        state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;