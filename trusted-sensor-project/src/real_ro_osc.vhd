library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity real_ro_osc is
    generic (
        STAGES : positive := 5
    );
    port (
        en     : in  std_logic;
        ro_out : out std_logic
    );
end entity real_ro_osc;

architecture rtl of real_ro_osc is

    signal n : std_logic_vector(STAGES-1 downto 0);

    attribute KEEP : string;
    attribute DONT_TOUCH : string;

    attribute KEEP of n : signal is "TRUE";
    attribute DONT_TOUCH of u_gate : label is "TRUE";

begin

    --------------------------------------------------------------------
    -- First stage: NAND enable gate.
    -- When en = 0, oscillator is forced into stable state.
    -- When en = 1, this acts as an inverter in the loop.
    --------------------------------------------------------------------
    u_gate : LUT2
        generic map (
            INIT => X"7"   -- NAND: not(I0 and I1)
        )
        port map (
            O  => n(0),
            I0 => n(STAGES-1),
            I1 => en
        );

    --------------------------------------------------------------------
    -- Remaining inverter stages.
    -- Total inversion count = 1 NAND/inverter + 4 LUT inverters = 5.
    --------------------------------------------------------------------
    gen_inv : for i in 1 to STAGES-1 generate
        u_inv : LUT1
            generic map (
                INIT => "01" -- inverter
            )
            port map (
                O  => n(i),
                I0 => n(i-1)
            );
    end generate;

    ro_out <= n(STAGES-1);

end architecture rtl;