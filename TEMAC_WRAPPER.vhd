----------------------------------------------------------------------------------
-- Author: Trinh Quang Kien, BMKTVXL 2020
-- Module: TEMAC_CORE entity
-- Project: Artix-7 XC7A35T board demo
-- Begin Date: 10/18/2019 04:39:52 PM
-- Revision History Date Author Comments
--   29/11/20 manhdq changed the coding style
-- Purpose:
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
library UNISIM;
use UNISIM.VCOMPONENTS.all;
----------------------------------------------------------------------------------
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
-- use IEEE.NUMERIC_STD.all;
-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
-- library UNISIM;
-- use UNISIM.VCOMPONENTS.all;
-- thiet ke chi su dung cho giao thuc RGMII
----------------------------------------------------------------------------------
entity TEMAC_WRAPPER is
  port (
    CLK125B     : in std_logic; -- Global CLK_125Mhz tuong ung voi gtx_clk
    CLK125B_D2N : in std_logic; -- CLK_125Mhz with delay 2ns, tuong ung voi gtx_clk90
    -- kiem tra neu trong mach tx_delay da 
    -- delay 2ns thi gtx_clk90 se khong can delay 2ns nua (chi can delay 1 lan)
    -- Sync reset with CLK125B -----------------------------------------------                                             
    GLBL_RST_INTN : in std_logic; -- Reset active 0, tuong ung voi glbl_rstn
    -- Sync reset with CLK125MHz ---------------------------------------------                                        
    VECTOR_RESETN : in std_logic; -- Reset active 0
    -- Pinout for RGMII protocol ---------------------------------------------
    RGMII_TXD    : out std_logic_vector(3 downto 0); -- tx data
    RGMII_TX_CTL : out std_logic; -- tx valid
    RGMII_TXC    : out std_logic; -- tx clock
    RGMII_RXD    : in std_logic_vector(3 downto 0); -- rx data
    RGMII_RX_CTL : in std_logic; -- rx valid
    RGMII_RXC    : in std_logic; -- rx clock
    -- AXIS interface --------------------------------------------------------
    -- Transmit side, sync with TX_MAC_ACLK ----------------------------------
    TX_MAC_ACLK        : out std_logic; -- clock of tx_mac
    TX_RESET           : out std_logic; -- reset of tx_mac, active '1'
    TX_AXIS_MAC_TDATA  : in std_logic_vector(7 downto 0); -- data of tx_mac
    TX_AXIS_MAC_TVALID : in std_logic; -- valid of tx_mac
    TX_AXIS_MAC_TLAST  : in std_logic; -- last of tx_mac
    TX_AXIS_MAC_TREADY : out std_logic; -- ready of tx_mac when tx ready to receive data
    TX_AXIS_MAC_TUSER  : in std_logic_vector(0 downto 0); -- allow MAC send an error to PHY
    -- Receive side, sync with RX_MAC_ACLK -----------------------------------
    RX_MAC_ACLK        : out std_logic; -- clock of rx_mac
    RX_RESET           : out std_logic; -- reset of rx_mac, active '1'
    RX_AXIS_MAC_TDATA  : out std_logic_vector(7 downto 0); -- data of rx_mac
    RX_AXIS_MAC_TVALID : out std_logic; -- valid of rx_mac
    RX_AXIS_MAC_TLAST  : out std_logic; -- last of rx_mac
    RX_AXIS_MAC_TUSER  : out std_logic; -- frame error tuser = 1, assert with RX_AXIS_MAC_TLAST
    -- Connection status when connect with Phy -------------------------------
    LINK_STATUS : out std_logic; -- Link Status from the Temac
    -- '0': Link down, '1': Link up
    CLOCK_SPEED : out std_logic_vector(1 downto 0); -- Link Speed from the Temac
    -- "00": 10 Mbps, "01": 100 Mbps, "10": 1000 Mbps
    SIM_MAC_SPEED    : in std_logic_vector(1 downto 0); -- speed for simulation
    SIM_UPDATE_SPEED : in std_logic; -- update for simulation 
    SIMULATION       : in std_logic -- '1' : simulation,'0' : implementation	
  );
end TEMAC_WRAPPER;
-------------------------------------------------------------------------
architecture behavioral of TEMAC_WRAPPER is
  ---------------------------------------------------------------------
  signal INBAND_CLOCK_SPEED : std_logic_vector(1 downto 0);
  signal UPDATE_SPEED       : std_logic;
  signal MAC_SPEED          : std_logic_vector(1 downto 0);
  signal UPDATE_SPEED_SM    : std_logic;
  signal MAC_SPEED_SM       : std_logic_vector(1 downto 0);
  -- SIGNALS OF PRO_AUTO_SPEED---------------
  constant COUNTER_LIMIT          : integer := 25_000_000;
  signal INBAND_CLOCK_SPEED_cross : std_logic_vector(1 downto 0);
  signal INBAND_CLOCK_SPEED_d     : std_logic_vector(1 downto 0);
  signal SPEED                    : std_logic_vector(1 downto 0);
  signal STATE                    : std_logic                        := '0';
  signal CNT                      : integer range 0 to COUNTER_LIMIT := 0;
  -- configuration_vector interface ------------------------------------
  signal RX_CONFIGURATION_VECTOR : std_logic_vector(79 downto 0);
  signal TX_CONFIGURATION_VECTOR : std_logic_vector(79 downto 0);

  ------------------------------------------------------------------------------
  component TEMAC_IP
    port (
      GTX_CLK   : in std_logic; -- clk125M
      GTX_CLK90 : in std_logic; -- clk125M delay 2ns, kiem tra neu trong mach tx_delay da
      -- delay 2ns thi gtx_clk90 se khong can delay 2ns nua (chi can delay 1 lan)
      -----------------------------------------------------------
      GLBL_RSTN : in std_logic; -- active 0
      -----------------------------------------------------------
      RX_AXI_RSTN          : in std_logic;
      TX_AXI_RSTN          : in std_logic;
      RX_STATISTICS_VECTOR : out std_logic_vector(27 downto 0);
      RX_STATISTICS_VALID  : out std_logic;
      RX_MAC_ACLK          : out std_logic;
      RX_RESET             : out std_logic;
      RX_ENABLE            : out std_logic;
      RX_AXIS_MAC_TDATA    : out std_logic_vector(7 downto 0);
      RX_AXIS_MAC_TVALID   : out std_logic;
      RX_AXIS_MAC_TLAST    : out std_logic;
      RX_AXIS_MAC_TUSER    : out std_logic;
      -----------------------------------------------------------
      TX_IFG_DELAY         : in std_logic_vector (7 downto 0);
      TX_STATISTICS_VECTOR : out std_logic_vector(31 downto 0);
      TX_STATISTICS_VALID  : out std_logic;
      TX_MAC_ACLK          : out std_logic;
      TX_RESET             : out std_logic;
      TX_ENABLE            : out std_logic;
      TX_AXIS_MAC_TDATA    : in std_logic_vector(7 downto 0);
      TX_AXIS_MAC_TVALID   : in std_logic;
      TX_AXIS_MAC_TLAST    : in std_logic;
      TX_AXIS_MAC_TUSER    : in std_logic_vector(0 downto 0);
      TX_AXIS_MAC_TREADY   : out std_logic;
      -----------------------------------------------------------
      PAUSE_REQ : in std_logic;
      PAUSE_VAL : in std_logic_vector(15 downto 0);
      -----------------------------------------------------------
      SPEEDIS100   : out std_logic;
      SPEEDIS10100 : out std_logic;
      -----------------------------------------------------------
      RGMII_TXD    : out std_logic_vector(3 downto 0);
      RGMII_TX_CTL : out std_logic;
      RGMII_TXC    : out std_logic;
      RGMII_RXD    : in std_logic_vector(3 downto 0);
      RGMII_RX_CTL : in std_logic;
      RGMII_RXC    : in std_logic;
      -----------------------------------------------------------
      INBAND_LINK_STATUS      : out std_logic;
      INBAND_CLOCK_SPEED      : out std_logic_vector(1 downto 0);
      INBAND_DUPLEX_STATUS    : out std_logic;
      RX_CONFIGURATION_VECTOR : in std_logic_vector(79 downto 0);
      -----------------------------------------------------------
      TX_CONFIGURATION_VECTOR : in std_logic_vector(79 downto 0)
    );
  end component;
  ------------------------------------------------------------------------------
  component TEMAC_config_vector_sm is
    port (
      GTX_CLK                 : in std_logic;
      GTX_RESETN              : in std_logic;
      MAC_SPEED               : in std_logic_vector(1 downto 0);
      UPDATE_SPEED            : in std_logic;
      RX_CONFIGURATION_VECTOR : out std_logic_vector(79 downto 0);
      TX_CONFIGURATION_VECTOR : out std_logic_vector(79 downto 0)
    );
  end component;
  ----------------------------------------------------------------------------------
begin
  TEMAC_CORE : TEMAC_IP
  port map
  (
    GTX_CLK   => CLK125B,
    GTX_CLK90 => CLK125B_D2N, -- clk125M delay 2ns, kiem tra neu trong mach tx_delay da 
    -- delay 2ns thi gtx_clk90 se khong can delay 2ns nua (chi can delay 1 lan)
    GLBL_RSTN => GLBL_RST_INTN, -- active 0
    --------------------------------------------------------------------------
    RX_AXI_RSTN          => '1',
    TX_AXI_RSTN          => '1',
    RX_STATISTICS_VECTOR => open,
    RX_STATISTICS_VALID  => open,
    RX_MAC_ACLK          => RX_MAC_ACLK,
    RX_RESET             => RX_RESET,
    RX_ENABLE            => open,
    RX_AXIS_MAC_TDATA    => RX_AXIS_MAC_TDATA,
    RX_AXIS_MAC_TVALID   => RX_AXIS_MAC_TVALID,
    RX_AXIS_MAC_TLAST    => RX_AXIS_MAC_TLAST,
    RX_AXIS_MAC_TUSER    => RX_AXIS_MAC_TUSER,
    --------------------------------------------------------------------------	
    TX_IFG_DELAY => (others => '0'),
    TX_STATISTICS_VECTOR => open,
    TX_STATISTICS_VALID  => open,
    TX_MAC_ACLK          => TX_MAC_ACLK,
    TX_RESET             => TX_RESET,
    TX_ENABLE            => open,
    TX_AXIS_MAC_TDATA    => TX_AXIS_MAC_TDATA,
    TX_AXIS_MAC_TVALID   => TX_AXIS_MAC_TVALID,
    TX_AXIS_MAC_TLAST    => TX_AXIS_MAC_TLAST,
    TX_AXIS_MAC_TUSER    => TX_AXIS_MAC_TUSER,
    TX_AXIS_MAC_TREADY   => TX_AXIS_MAC_TREADY,
    --------------------------------------------------------------------------	
    PAUSE_REQ            => '0',
    PAUSE_VAL => (others => '0'),
    SPEEDIS100           => open,
    SPEEDIS10100         => open,
    RGMII_TXD            => RGMII_TXD,
    RGMII_TX_CTL         => RGMII_TX_CTL,
    RGMII_TXC            => RGMII_TXC,
    RGMII_RXD            => RGMII_RXD,
    RGMII_RX_CTL         => RGMII_RX_CTL,
    RGMII_RXC            => RGMII_RXC,
    INBAND_LINK_STATUS   => LINK_STATUS,
    INBAND_CLOCK_SPEED   => INBAND_CLOCK_SPEED,
    INBAND_DUPLEX_STATUS => open,
    --------------------------------------------------------------------------						    
    RX_CONFIGURATION_VECTOR => RX_CONFIGURATION_VECTOR,
    TX_CONFIGURATION_VECTOR => TX_CONFIGURATION_VECTOR
  );
  ------------------------------------------------------------------------------
  config_vector_controller : TEMAC_config_vector_sm
  port map
  (
    gtx_clk                 => CLK125B,
    gtx_resetn              => VECTOR_RESETN,
    mac_speed               => MAC_SPEED_SM,
    update_speed            => UPDATE_SPEED_SM,
    rx_configuration_vector => RX_CONFIGURATION_VECTOR,
    tx_configuration_vector => TX_CONFIGURATION_VECTOR
  );
  ------------------------------------------------------------------------------
  CLOCK_SPEED  <= INBAND_CLOCK_SPEED;
  MAC_SPEED_SM <= MAC_SPEED when (SIMULATION = '0') else
    SIM_MAC_SPEED;
  UPDATE_SPEED_SM <= UPDATE_SPEED when (SIMULATION = '0') else
    SIM_UPDATE_SPEED;
  --------------------------------
  pro_auto_speed : process (CLK125B)
  begin
    if rising_edge(CLK125B) then
      if GLBL_RST_INTN = '0' then
        UPDATE_SPEED <= '0';
        STATE        <= '0';
        CNT          <= 0;
      else
        case STATE is
            ---------------------------------------------
          when '0' =>
            INBAND_CLOCK_SPEED_cross <= INBAND_CLOCK_SPEED;
            INBAND_CLOCK_SPEED_d     <= INBAND_CLOCK_SPEED_cross;
            SPEED                    <= INBAND_CLOCK_SPEED_d;
            if SPEED /= INBAND_CLOCK_SPEED_d then
              UPDATE_SPEED <= '1';
              MAC_SPEED    <= INBAND_CLOCK_SPEED_d;
              STATE        <= '1';
            else
              UPDATE_SPEED <= '0';
              STATE        <= '0';
            end if;
            -----------------------------------------------
          when '1' =>
            UPDATE_SPEED <= '0';
            if CNT = COUNTER_LIMIT then
              CNT   <= 0;
              STATE <= '0';
            else
              STATE <= '1';
              CNT   <= CNT + 1;
            end if;
          when others =>
            STATE <= '0';
            ----------------------------------------------
        end case;
      end if;
    end if;
  end process;
end behavioral;
----------------------------------------------------------------------------------
