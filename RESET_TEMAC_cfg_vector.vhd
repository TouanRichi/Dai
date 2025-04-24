-------------------------------------------------------------------------
-- Author: Trinh Quang Kien, BMKTVXL 2020
-- Module: RESET_TEMAC_cfg_vector entity
-- Project: Artix-7 XC7A35T board demo
-- Begin Date: 08/07/2019 08:35:13 AM
-- Revision History Date Author Comments
--   29/11/20 manhdq changed the coding style
-- Purpose:
-- 
-------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
library UNISIM;
use UNISIM.VCOMPONENTS.all;
-------------------------------------------------------------------------
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
-- use IEEE.NUMERIC_STD.all;
-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
-- library UNISIM;
-- use UNISIM.VCOMPONENTS.all;
-------------------------------------------------------------------------
entity RESET_TEMAC_cfg_vector is
  port (
    -- clocks -------------------------------------------------------
    DCM_LOCKED : in std_logic; -- locked from MMCM (PLL)
    GTX_CLK    : in std_logic; -- 125 MHz not delay
    REFCLK     : in std_logic; -- 200Mhz  
    -- asynchronous resets ------------------------------------------                                            
    GLBL_RST      : in std_logic; -- active 1
    GLBL_RST_INTN : out std_logic; -- reset active 0
    VECTOR_RESETN : out std_logic; -- reset active 0 ,reset of axi_lite
    PHY_RESETN    : out std_logic -- reset phy active 0
  );
end RESET_TEMAC_cfg_vector;
-------------------------------------------------------------------------
architecture RTL of RESET_TEMAC_cfg_vector is
  -- define internal signals ------------------------------------------
  signal VECTOR_RESET_INT  : std_logic;
  signal VECTOR_PRE_RESETN : std_logic := '0';
  signal GLBL_RST_INT      : std_logic;
  signal PHY_RESETN_INT    : std_logic;
  signal PHY_RESET_COUNT   : unsigned(5 downto 0) := (others => '0');
  ---------------------------------------------------------------------
  signal IDELAYCTRL_RESET_IN   : std_logic; -- Used to trigger reset_sync generation in refclk domain.
  signal IDELAYCTRL_RESET_SYNC : std_logic; -- Used to create a reset pulse in the IDELAYCTRL refclk domain.
  signal IDELAY_RESET_CNT      : std_logic_vector(3 downto 0); -- Counter to create a long IDELAYCTRL reset pulse.
  signal IDELAYCTRL_RESET      : std_logic;
  signal IDELAYCTRL_READY      : std_logic;
  signal DCM_LOCKED_SYNC       : std_logic;
  ---------------------------------------------------------------------
  -- Component declaration for the reset synchroniser
  ---------------------------------------------------------------------
  component TEMAC_reset_sync
    port (
      CLK       : in std_logic; -- clock to be sync'ed to
      ENABLE    : in std_logic;
      RESET_IN  : in std_logic; -- Active high asynchronous reset
      RESET_OUT : out std_logic -- "Synchronised" reset signal
    );
  end component;
  ---------------------------------------------------------------------
  -- Component declaration for the synchroniser
  ---------------------------------------------------------------------
  component TEMAC_sync_block
    port (
      CLK      : in std_logic;
      DATA_IN  : in std_logic;
      DATA_OUT : out std_logic
    );
  end component;
  -------------------------------------------------------------------------
begin
  dcm_sync : TEMAC_sync_block
  port map
  (
    CLK      => GTX_CLK,
    DATA_IN  => DCM_LOCKED,
    DATA_OUT => DCM_LOCKED_SYNC
  );
  -- global reset -----------------------------------------------------
  glbl_reset_gen : TEMAC_reset_sync
  port map
  (
    CLK       => GTX_CLK,
    ENABLE    => DCM_LOCKED_SYNC,
    RESET_IN  => GLBL_RST,
    RESET_OUT => GLBL_RST_INT
  );
  GLBL_RST_INTN <= not GLBL_RST_INT;
  -- Vector controller reset ------------------------------------------
  vector_reset_gen : TEMAC_reset_sync
  port map
  (
    CLK       => GTX_CLK,
    ENABLE    => DCM_LOCKED_SYNC,
    RESET_IN  => GLBL_RST,
    RESET_OUT => VECTOR_RESET_INT
  );
  -- Create fully synchronous reset in the global clock domain --------   
  vector_reset_p : process (GTX_CLK)
  begin
    if GTX_CLK'event and GTX_CLK = '1' then
      if vector_reset_int = '1' then
        vector_pre_resetn <= '0';
        VECTOR_RESETN     <= '0';
      else
        vector_pre_resetn <= '1';
        VECTOR_RESETN     <= vector_pre_resetn;
      end if;
    end if;
  end process vector_reset_p;
  ---------------------------------------------------------------------
  -- PHY reset 
  -- the phy reset output (active low) needs to be held for 
  -- at least 10x25MHZ cycles
  -- this is derived using the 125MHz available and a 6 bit counter
  ---------------------------------------------------------------------
  phy_reset_p : process (GTX_CLK)
  begin
    if GTX_CLK'event and GTX_CLK = '1' then
      if GLBL_RST_INT = '1' then
        PHY_RESETN_INT  <= '0';
        PHY_RESET_COUNT <= (others => '0');
      else
        if PHY_RESET_COUNT /= "111111" then
          PHY_RESET_COUNT <= PHY_RESET_COUNT + "000001";
        else
          PHY_RESETN_INT <= '1';
        end if;
      end if;
    end if;
  end process phy_reset_p;
  ---------------------------------------------------------------------
  PHY_RESETN          <= PHY_RESETN_INT;
  IDELAYCTRL_RESET_IN <= GLBL_RST_INT or not IDELAYCTRL_READY;
  ---------------------------------------------------------------------
  idelayctrl_reset_gen : TEMAC_reset_sync
  port map
  (
    CLK       => REFCLK,
    ENABLE    => '1',
    RESET_IN  => IDELAYCTRL_RESET_IN,
    RESET_OUT => IDELAYCTRL_RESET_SYNC
  );
  ---------------------------------------------------------------------
  process (REFCLK)
  begin
    if REFCLK'event and REFCLK = '1' then
      if IDELAYCTRL_RESET_SYNC = '1' then
        IDELAY_RESET_CNT <= "0000";
        IDELAYCTRL_RESET <= '1';
      else
        IDELAYCTRL_RESET <= '1';
        case IDELAY_RESET_CNT is
          when "0000" => IDELAY_RESET_CNT <= "0001";
          when "0001" => IDELAY_RESET_CNT <= "0010";
          when "0010" => IDELAY_RESET_CNT <= "0011";
          when "0011" => IDELAY_RESET_CNT <= "0100";
          when "0100" => IDELAY_RESET_CNT <= "0101";
          when "0101" => IDELAY_RESET_CNT <= "0110";
          when "0110" => IDELAY_RESET_CNT <= "0111";
          when "0111" => IDELAY_RESET_CNT <= "1000";
          when "1000" => IDELAY_RESET_CNT <= "1001";
          when "1001" => IDELAY_RESET_CNT <= "1010";
          when "1010" => IDELAY_RESET_CNT <= "1011";
          when "1011" => IDELAY_RESET_CNT <= "1100";
          when "1100" => IDELAY_RESET_CNT <= "1101";
          when "1101" => IDELAY_RESET_CNT <= "1110";
          when others => IDELAY_RESET_CNT <= "1110";
            IDELAYCTRL_RESET                <= '0';
        end case;
      end if;
    end if;
  end process;
  ---------------------------------------------------------------------
  temac_idelayctrl : IDELAYCTRL
  generic map(
    SIM_DEVICE => "7SERIES"
  )
  port map
  (
    RDY    => IDELAYCTRL_READY,
    REFCLK => REFCLK,
    RST    => IDELAYCTRL_RESET
  );
end RTL;