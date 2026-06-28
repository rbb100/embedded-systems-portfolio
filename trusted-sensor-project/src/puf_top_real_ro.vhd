library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity puf_top_real_ro is
    generic (
        NUM_PAIRS         : positive := 32;
        RO_STAGES         : positive := 5;
        COUNTER_WIDTH     : positive := 24;
        WINDOW_CYCLES     : natural  := 50000;
        HAMMING_THRESHOLD : natural := 8;
        ENROLLED_RESPONSE : std_logic_vector(31 downto 0) := x"82111903"
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;

        start_auth : in  std_logic;

        auth_busy  : out std_logic;
        auth_done  : out std_logic;
        auth_valid : out std_logic;

        puf_response : out std_logic_vector(NUM_PAIRS-1 downto 0);

        count_a_flat : out std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0);
        count_b_flat : out std_logic_vector(NUM_PAIRS*COUNTER_WIDTH-1 downto 0)
    );
end entity puf_top_real_ro;

architecture rtl of puf_top_real_ro is

    signal puf_busy_sig : std_logic := '0';
    signal puf_done_sig : std_logic := '0';

    signal response_sig : std_logic_vector(NUM_PAIRS-1 downto 0) := (others => '0');

    signal valid_reg : std_logic := '0';

    --------------------------------------------------------------------
    -- Hamming distance helper
    --------------------------------------------------------------------
    function popcount(v : std_logic_vector) return natural is
        variable count : natural := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then
                count := count + 1;
            end if;
        end loop;

        return count;
    end function;

begin

    --------------------------------------------------------------------
    -- Output assignments
    --------------------------------------------------------------------
    auth_busy <= puf_busy_sig;
    auth_done <= puf_done_sig;
    auth_valid <= valid_reg;

    puf_response <= response_sig;

    --------------------------------------------------------------------
    -- Real RO-PUF array
    --------------------------------------------------------------------
    u_real_ro_puf : entity work.real_ro_puf_array
        generic map (
            NUM_PAIRS     => NUM_PAIRS,
            RO_STAGES     => RO_STAGES,
            COUNTER_WIDTH => COUNTER_WIDTH,
            WINDOW_CYCLES => WINDOW_CYCLES,
            SETTLE_CYCLES => 16
        )
        port map (
            clk   => clk,
            rst   => rst,

            start => start_auth,

            busy  => puf_busy_sig,
            done  => puf_done_sig,

            response => response_sig,

            count_a_flat => count_a_flat,
            count_b_flat => count_b_flat
        );

    --------------------------------------------------------------------
    -- Authentication check
    --
    -- When real RO-PUF measurement is done:
    -- 1. Compare live response with enrolled response.
    -- 2. Count Hamming distance.
    -- 3. Pass if distance <= HAMMING_THRESHOLD.
    --------------------------------------------------------------------
    process(clk)
        variable hd : natural range 0 to 32;
        variable enrolled_slice : std_logic_vector(NUM_PAIRS-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_reg <= '0';

            else
                -- Clear previous auth result when a new auth starts
                if start_auth = '1' then
                    valid_reg <= '0';
                end if;

                if puf_done_sig = '1' then

                    enrolled_slice := ENROLLED_RESPONSE(NUM_PAIRS-1 downto 0);

                    hd := popcount(response_sig xor enrolled_slice);

                    if hd <= HAMMING_THRESHOLD then
                        valid_reg <= '1';
                    else
                        valid_reg <= '0';
                    end if;

                end if;
            end if;
        end if;
    end process;

end architecture rtl;