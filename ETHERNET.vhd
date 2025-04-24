-------------------------------------------------------------------------------------
-- Author: Trinh Quang Kien, BMVXL 2020
-- Module: TEMAC_WRAPPER V4.0
-- Project: Artix-7 XC7A35T board demo
-- Begin Date: 1/05/2020
-- Revision History Date Author Comments
--   1/05/20 Kien Created V1.0
--   10/09/20 V2.0 Kien add multithread V2.0 
--   16/09/20 V3.0 Kien changed the TEMAC and AXI interface to 
--	 9/12/20  V3.1 manhdq changed the coding style
--	 9/12/24  V4.0 Kien reoganize code
-- still have problem with standard test file
-- Purpose:
-- This is the TOP level design of the project
-- multithread PR CORE
-------------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
-------------------------------------------------------------------------------------
entity ETHERNET is
  port (
    CLK_50M     : in std_logic; -- 50M free runing clock
    BUTTON      : in std_logic_vector(3 downto 0); -- 4 nút nhân trên mạch, sử dụng 1.
    SYS_RESET_N : in std_logic;
    LED_CORE    : out std_logic; -- LED on SOM
    -- LED         : out std_logic_vector(7 downto 0);
    -- RGMII Interface ----------------------------------------------------------
    RTL1_RGMII_RXC    : in std_logic;
    RTL1_RGMII_RXD    : in std_logic_vector(3 downto 0);
    RTL1_RGMII_RXCTL  : in std_logic;
    RTL1_RGMII_TXC    : out std_logic;
    RTL1_RGMII_TXD    : out std_logic_vector(3 downto 0);
    RTL1_RGMII_TXCTL  : out std_logic;
    RTL1_RGMII_RESETN : out std_logic;
    --ADC1 interface --
    ADC1_CLK  : out std_logic;
    ADC1_DATA : in std_logic_vector(9 downto 0)
  );
end ETHERNET;
-------------------------------------------------------------------------------------
architecture behavioral of ETHERNET is
  constant CLK_FREQ     : integer := 125_000_000; -- tan so su dung cho CLK (Hz)
  signal SYS_RESET      : std_logic;
  signal LED_CORE_local : std_logic := '0';
  -- signal LED_local      : std_logic_vector(7 downto 0) := (others => '0');
  signal TEST_CNT : integer := 0;
  -------------------------------------------
  constant DATA_WIDTH        : natural   := 512;
  constant COUNTER_LIMIT     : integer   := 100_000_000 * 5 - 1; -- simulation = 50, implement = 100_000_000 * 5 - 1
  constant RECOVER_LIMIT     : integer   := 100_000_000 / 1_000 - 1; -- simulation = 20, implement = 100_000_000/1_000 - 1
  constant COUNTER_LIMIT_RST : integer   := 25_000_000; -- simulation = 25, implement = 25_000_000
  constant SIMULATION        : std_logic := '0'; -- '1': simulation
  -- '0': implementation
  signal CORE_IN_TVALID : std_logic;
  signal CORE_IN_TREADY : std_logic;
  signal CORE_IN_TDATA  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal CORE_IN_TKEEP  : std_logic_vector(DATA_WIDTH/8 - 1 downto 0);
  signal CORE_IN_TLAST  : std_logic;
  signal CORE_IN_TUSER  : std_logic_vector(DATA_WIDTH/8 - 1 downto 0);
  ---------------------------------------------------------------------------------						   
  signal CORE_OUT_TVALID : std_logic;
  signal CORE_OUT_TREADY : std_logic;
  signal CORE_OUT_TDATA  : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal CORE_OUT_TKEEP  : std_logic_vector(DATA_WIDTH/8 - 1 downto 0);
  signal CORE_OUT_TLAST  : std_logic;
  ---------------------------------------------------------------------------------						   
  signal RSTN_CNT      : integer range 0 to COUNTER_LIMIT_RST := 0;
  signal RESETN_BUTTON : std_logic;
  ---------------------------------------------------------------------------------						   
  signal CLK125B       : std_logic;
  signal CLK125B_D2n   : std_logic;
  signal GLBL_RST_INTN : std_logic;
  signal VECTOR_RESETN : std_logic;
  signal RESETN_AXI    : std_logic;
  signal RX_RESET      : std_logic;
  signal TX_RESET      : std_logic;
  signal RX_RESETN     : std_logic;
  signal TX_RESETN     : std_logic;
  signal SYNC_RESET    : std_logic := '0';
  ---------------------------------------------------------------------------------						   
  signal RESET_PHY   : std_logic;
  signal CLOCK_SPEED : std_logic_vector(1 downto 0);
  signal CORE_RESET  : std_logic;
  signal CORE_RESETN : std_logic;
  ---------------------------------------------------------------------------------						   
  signal TX_MAC_ACLK        : std_logic; -- clock of tx_mac
  signal TX_AXIS_MAC_TDATA  : std_logic_vector(7 downto 0); -- data of tx_mac
  signal TX_AXIS_MAC_TVALID : std_logic; -- valid of tx_mac
  signal TX_AXIS_MAC_TLAST  : std_logic; -- last of tx_mac
  signal TX_AXIS_MAC_TREADY : std_logic; -- ready of tx_mac when tx ready to receive data
  signal TX_AXIS_MAC_TUSER  : std_logic_vector(0 downto 0); -- allow MAC send an error to PHY
  signal TX_AXIS_MAC_TKEEP  : std_logic_vector(0 downto 0); -- allow MAC send an error to PHY
  --------------------------------------------------------------------------------- 																	               
  signal RX_MAC_ACLK        : std_logic; -- clock of rx_mac
  signal RX_AXIS_MAC_TDATA  : std_logic_vector(7 downto 0); -- data of rx_mac
  signal RX_AXIS_MAC_TVALID : std_logic; -- valid of rx_mac
  signal RX_AXIS_MAC_TREADY : std_logic; -- ready of rx_mac
  signal RX_AXIS_MAC_TLAST  : std_logic; -- last of rx_mac
  signal RX_AXIS_MAC_TUSER  : std_logic_vector(0 downto 0);
  signal RX_AXIS_MAC_TKEEP  : std_logic_vector(0 downto 0);
  ---------------------------------------------------------------------------------
  -- signal ram_read_dout : std_logic_vector(7 downto 0);
  -- signal ram_read_en   : std_logic;
  -- signal ram_read_addr : std_logic_vector(5 downto 0);
  signal fifo_wr_en : std_logic;
  signal fifo_full  : std_logic;
  signal fifo_empty : std_logic;
  signal fifo_rd_en : std_logic;
  signal fifo_dout  : std_logic_vector(9 downto 0);
  ---------------------------------------------------------------------------------					   
  component axis_interconnect_8_512
    port (
      ACLK                : in std_logic;
      ARESETN             : in std_logic;
      S00_AXIS_ACLK       : in std_logic;
      S00_AXIS_ARESETN    : in std_logic;
      S00_AXIS_TVALID     : in std_logic;
      S00_AXIS_TREADY     : out std_logic;
      S00_AXIS_TDATA      : in std_logic_vector(7 downto 0);
      S00_AXIS_TKEEP      : in std_logic_vector(0 downto 0);
      S00_AXIS_TLAST      : in std_logic;
      M00_AXIS_ACLK       : in std_logic;
      M00_AXIS_ARESETN    : in std_logic;
      M00_AXIS_TVALID     : out std_logic;
      M00_AXIS_TREADY     : in std_logic;
      M00_AXIS_TDATA      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      M00_AXIS_TKEEP      : out std_logic_vector(DATA_WIDTH/8 - 1 downto 0);
      M00_AXIS_TLAST      : out std_logic;
      S00_FIFO_DATA_COUNT : out std_logic_vector(31 downto 0)
    );
  end component;
  ---------------------------------------------------------------------------------
  component axis_interconnect_512_8
    port (
      ACLK                : in std_logic;
      ARESETN             : in std_logic;
      S00_AXIS_ACLK       : in std_logic;
      S00_AXIS_ARESETN    : in std_logic;
      S00_AXIS_TVALID     : in std_logic;
      S00_AXIS_TREADY     : out std_logic;
      S00_AXIS_TDATA      : in std_logic_vector(DATA_WIDTH - 1 downto 0);
      S00_AXIS_TKEEP      : in std_logic_vector(DATA_WIDTH/8 - 1 downto 0);
      S00_AXIS_TLAST      : in std_logic;
      M00_AXIS_ACLK       : in std_logic;
      M00_AXIS_ARESETN    : in std_logic;
      M00_AXIS_TVALID     : out std_logic;
      M00_AXIS_TREADY     : in std_logic;
      M00_AXIS_TDATA      : out std_logic_vector(7 downto 0);
      M00_AXIS_TKEEP      : out std_logic_vector(0 downto 0);
      M00_AXIS_TLAST      : out std_logic;
      M00_FIFO_DATA_COUNT : out std_logic_vector(31 downto 0)
    );
  end component;
  ---------------------------------------------------------------------------------
  component GLOBAL_CLOCK_RESET is
    generic (
      CLOCK_SELECT  : std_logic := '0'; -- 0 select differential clock/1 single-ended    
      COUNTER_LIMIT : integer   := 50; -- simmulation = 50, implement = 100_000_000 * 5 - 1
      RECOVER_LIMIT : integer   := 20 -- simmulation = 20, implement = 100_000_000 / 1_000 - 1
    );
    port (
      CLK_IN      : in std_logic; -- single_ended clock in N
      CLK125B     : out std_logic;
      CLK125B_D2n : out std_logic; -- delayed-2ns CLK125
      CORE_RESET  : out std_logic;
      -- hard reset -----------------------------------------------------------
      RESETN_BUTTON : in std_logic;
      RESETN_ERROR  : in std_logic;
      --  output reset signals ------------------------------------------------
      GLBL_RST_INTN : out std_logic;
      VECTOR_RESETN : out std_logic;
      PHY_RESETN    : out std_logic;
      RESETN_AXI    : out std_logic;
      RESET_COM     : out std_logic
    );
  end component;
  ---------------------------------------------------------------------------------
  component TEMAC_WRAPPER is
    port (
      CLK125B       : in std_logic; -- Global CLK_125Mhz tuong ung voi gtx_clk
      CLK125B_D2n   : in std_logic; -- CLK_125Mhz with delay 2ns, tuong ung voi gtx_clk90
      GLBL_RST_INTN : in std_logic; -- Reset active 0, tuong ung voi glbl_rstn
      VECTOR_RESETN : in std_logic; -- Reset active 0
      RGMII_TXD     : out std_logic_vector(3 downto 0); -- tx data
      RGMII_TX_CTL  : out std_logic; -- tx valid
      RGMII_TXC     : out std_logic; -- tx clock
      RGMII_RXD     : in std_logic_vector(3 downto 0); -- rx data
      RGMII_RX_CTL  : in std_logic; -- rx valid
      RGMII_RXC     : in std_logic; -- rx clock
      -- transmit side, sync with TX_MAC_ACLK ---------------------------------                                    
      TX_MAC_ACLK        : out std_logic; -- clock of tx_mac
      TX_RESET           : out std_logic;
      TX_AXIS_MAC_TDATA  : in std_logic_vector(7 downto 0); -- data of tx_mac
      TX_AXIS_MAC_TVALID : in std_logic; -- valid of tx_mac
      TX_AXIS_MAC_TLAST  : in std_logic; -- last of tx_mac
      TX_AXIS_MAC_TREADY : out std_logic; -- ready of tx_mac when tx ready to receive data
      TX_AXIS_MAC_TUSER  : in std_logic_vector(0 downto 0); -- allow MAC send an error to PHY
      -- Receive side, sync with RX_MAC_ACLK ----------------------------------                                     
      RX_MAC_ACLK        : out std_logic; -- clock of rx_mac
      RX_RESET           : out std_logic;
      RX_AXIS_MAC_TDATA  : out std_logic_vector(7 downto 0); -- data of rx_mac
      RX_AXIS_MAC_TVALID : out std_logic; -- valid of rx_mac
      RX_AXIS_MAC_TLAST  : out std_logic; -- last of rx_mac
      RX_AXIS_MAC_TUSER  : out std_logic; -- frame error tuser = 1, assert with RX_AXIS_MAC_TLAST
      LINK_STATUS        : out std_logic; -- Link Status from the Temac
      CLOCK_SPEED        : out std_logic_vector (1 downto 0); -- Link Speed from the Temac
      SIM_MAC_SPEED      : in std_logic_vector (1 downto 0);
      SIM_UPDATE_SPEED   : in std_logic;
      SIMULATION         : in std_logic -- '1' : simulation 
      -- '0' : implementation
    );
  end component;
  --------------------------------------------------
  -- component CORE is
  --   generic (
  --     DATA_WIDTH : integer := 512);
  --   port (
  --     CORE_CLK   : in std_logic;
  --     CORE_RESET : in std_logic;
  --     ----------------------------------
  --     CORE_IN_TVALID : in std_logic;
  --     CORE_IN_TDATA  : in std_logic_vector(DATA_WIDTH - 1 downto 0);
  --     CORE_IN_TKEEP  : in std_logic_vector(DATA_WIDTH/8 - 1 downto 0);
  --     CORE_IN_TREADY : out std_logic;
  --     CORE_IN_TLAST  : in std_logic;
  --     ----------------------------------
  --     CORE_OUT_TVALID : out std_logic;
  --     CORE_OUT_TDATA  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
  --     CORE_OUT_TKEEP  : out std_logic_vector(DATA_WIDTH/8 - 1 downto 0);
  --     CORE_OUT_TREADY : in std_logic;
  --     CORE_OUT_TLAST  : out std_logic
  --   );
  -- end component;
  component CORE is
    generic (
      DATA_WIDTH : integer := 512 -- độ rộng bus AXI-Stream (bit)
    );
    port (
      CORE_CLK    : in std_logic;
      CORE_RESET  : in std_logic;
      CORE_ENABLE : in std_logic;

      -- FIFO interface
      fifo_wr_en : out std_logic;
      fifo_full  : in std_logic;
      fifo_empty : in std_logic;
      fifo_rd_en : out std_logic;
      fifo_dout  : in std_logic_vector(9 downto 0);

      -- AXI-Stream to TEMAC (CORE_OUT interface)
      CORE_OUT_TDATA  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      CORE_OUT_TVALID : out std_logic;
      CORE_OUT_TLAST  : out std_logic;
      CORE_OUT_TKEEP  : out std_logic_vector((DATA_WIDTH / 8) - 1 downto 0);
      CORE_OUT_TREADY : in std_logic
    );
  end component;
  ---------------------------------------------------------------------------------
  -- component blk_mem_gen_0
  --   port (
  --     -- Port A (write)
  --     clka  : in std_logic;
  --     ena   : in std_logic;
  --     wea   : in std_logic_vector(0 downto 0);
  --     addra : in std_logic_vector(5 downto 0);
  --     dina  : in std_logic_vector(7 downto 0);

  --     -- Port B (read)
  --     clkb  : in std_logic;
  --     enb   : in std_logic;
  --     addrb : in std_logic_vector(5 downto 0);
  --     doutb : out std_logic_vector(7 downto 0)
  --   );
  -- end component;
  component fifo_generator_0
    port (
      clk  : in std_logic;
      srst : in std_logic;

      din   : in std_logic_vector(9 downto 0);
      wr_en : in std_logic;
      full  : out std_logic;

      dout  : out std_logic_vector(9 downto 0);
      rd_en : in std_logic;
      empty : out std_logic
    );
  end component;
  -------------------------------------------------------------------------------------
begin
  RX_RESETN   <= not RX_RESET;
  TX_RESETN   <= not TX_RESET;
  CORE_RESETN <= not CORE_RESET;
  SYS_RESET   <= not SYS_RESET_N;
  --ADC clock
  ADC1_CLK <= CLK_50M;
  ---------------------------------------------------------------------------------
  CLOCK_RESET : GLOBAL_CLOCK_RESET
  generic map(
    COUNTER_LIMIT => COUNTER_LIMIT, -- simmulation = 50, implement = 100_000_000 * 5 - 1
    RECOVER_LIMIT => RECOVER_LIMIT) -- simmulation = 20, implement = 100_000_000 / 1_000 - 1
  port map
  (
    CLK_IN => CLK_50M,
    -----------------------------------------------------------------------------				      
    CLK125B     => CLK125B,
    CLK125B_D2n => CLK125B_D2n, -- delayed-2ns CLK125
    -- hard reset ---------------------------------------------------------------  
    CORE_RESET    => CORE_RESET,
    RESETN_BUTTON => RESETN_BUTTON,
    RESETN_ERROR  => '1',
    --  output reset signals ----------------------------------------------------
    GLBL_RST_INTN => GLBL_RST_INTN,
    VECTOR_RESETN => VECTOR_RESETN,
    PHY_RESETN    => RTL1_RGMII_RESETN,
    RESETN_AXI    => RESETN_AXI,
    RESET_COM     => open
  );
  ---------------------------------------------------------------------------------	  
  TEMAC_BLOCK : TEMAC_WRAPPER
  port map
  (
    CLK125B            => CLK125B, -- Global CLK_125Mhz tuong ung voi gtx_clk
    CLK125B_D2n        => CLK125B_D2n, -- CLK_125Mhz with delay 2ns, tuong ung voi gtx_clk90
    GLBL_RST_INTN      => GLBL_RST_INTN, -- Reset active 0, tuong ung voi glbl_rstn
    VECTOR_RESETN      => VECTOR_RESETN, -- Reset active 0
    RGMII_TXD          => RTL1_RGMII_TXD, -- tx data
    RGMII_TX_CTL       => RTL1_RGMII_TXCTL, -- tx valid
    RGMII_TXC          => RTL1_RGMII_TXC, -- tx clock
    RGMII_RXD          => RTL1_RGMII_RXD, -- rx data
    RGMII_RX_CTL       => RTL1_RGMII_RXCTL, -- rx valid
    RGMII_RXC          => RTL1_RGMII_RXC, -- rx clock
    TX_MAC_ACLK        => TX_MAC_ACLK, -- clock of tx_mac
    TX_RESET           => TX_RESET,
    TX_AXIS_MAC_TDATA  => TX_AXIS_MAC_TDATA, -- data of tx_mac
    TX_AXIS_MAC_TVALID => TX_AXIS_MAC_TVALID, -- valid of tx_mac
    TX_AXIS_MAC_TLAST  => TX_AXIS_MAC_TLAST, -- last of tx_mac
    TX_AXIS_MAC_TREADY => TX_AXIS_MAC_TREADY, -- ready of tx_mac when tx ready to receive data
    TX_AXIS_MAC_TUSER  => TX_AXIS_MAC_TUSER, -- allow MAC send an error to PHY
    RX_MAC_ACLK        => RX_MAC_ACLK, -- clock of rx_mac
    RX_RESET           => RX_RESET,
    RX_AXIS_MAC_TDATA  => RX_AXIS_MAC_TDATA, -- data of rx_mac
    RX_AXIS_MAC_TVALID => RX_AXIS_MAC_TVALID, -- valid of rx_mac
    RX_AXIS_MAC_TLAST  => RX_AXIS_MAC_TLAST, -- last of rx_mac
    RX_AXIS_MAC_TUSER  => RX_AXIS_MAC_TUSER(0), -- frame error tuser = 1, assert with RX_AXIS_MAC_TLAST
    LINK_STATUS        => open, -- Link Status from the Temac
    CLOCK_SPEED        => CLOCK_SPEED, -- Link Speed from the Temac
    SIM_MAC_SPEED      => "10",
    SIM_UPDATE_SPEED   => '0',
    SIMULATION         => SIMULATION
  );
  ---------------------------------------------------------------------------------
  RX_AXIS_MAC_TREADY <= '1';
  RX_AXIS_MAC_TKEEP  <= (others => RX_AXIS_MAC_TVALID);
  ---------------------------------------------------------------------------------
  axis_8_512_inst : axis_interconnect_8_512
  port map
  (
    ACLK                => CLK125B,
    ARESETN             => RESETN_AXI,
    S00_AXIS_ACLK       => RX_MAC_ACLK,
    S00_AXIS_ARESETN    => RX_RESETN,
    S00_AXIS_TVALID     => RX_AXIS_MAC_TVALID,
    S00_AXIS_TREADY     => RX_AXIS_MAC_TREADY,
    S00_AXIS_TDATA      => RX_AXIS_MAC_TDATA,
    S00_AXIS_TLAST      => RX_AXIS_MAC_TLAST,
    S00_AXIS_TKEEP      => RX_AXIS_MAC_TKEEP,
    M00_AXIS_ACLK       => CLK125B,
    M00_AXIS_ARESETN    => RESETN_AXI,
    M00_AXIS_TVALID     => CORE_IN_TVALID,
    M00_AXIS_TREADY     => CORE_IN_TREADY,
    M00_AXIS_TDATA      => CORE_IN_TDATA,
    M00_AXIS_TKEEP      => CORE_IN_TKEEP,
    M00_AXIS_TLAST      => CORE_IN_TLAST,
    S00_FIFO_DATA_COUNT => open
  );
  TX_AXIS_MAC_TKEEP(0) <= '1'; -- TX_AXIS_DATA is 8 bit so all TKEEP is 1
  ---------------------------------------------------------------------------------
  axis_512_8_inst : component axis_interconnect_512_8
    port map
    (
      ACLK                => CLK125B,
      ARESETN             => RESETN_AXI,
      S00_AXIS_ACLK       => CLK125B,
      S00_AXIS_ARESETN    => CORE_RESETN,
      S00_AXIS_TVALID     => CORE_OUT_TVALID,
      S00_AXIS_TREADY     => CORE_OUT_TREADY,
      S00_AXIS_TDATA      => CORE_OUT_TDATA,
      S00_AXIS_TKEEP      => CORE_OUT_TKEEP,
      S00_AXIS_TLAST      => CORE_OUT_TLAST,
      M00_AXIS_ACLK       => TX_MAC_ACLK,
      M00_AXIS_ARESETN    => TX_RESETN,
      M00_AXIS_TVALID     => TX_AXIS_MAC_TVALID,
      M00_AXIS_TREADY     => TX_AXIS_MAC_TREADY,
      M00_AXIS_TDATA      => TX_AXIS_MAC_TDATA,
      M00_AXIS_TKEEP      => TX_AXIS_MAC_TKEEP,
      M00_AXIS_TLAST      => TX_AXIS_MAC_TLAST,
      M00_FIFO_DATA_COUNT => open);

    -----------------------------------------------------------------------------
    -- inst_blk_ram : blk_mem_gen_0
    -- port map
    -- (
    --   -- Port A: không dùng → ràng buộc mặc định
    --   clka => '0',
    --   ena  => '0',
    --   wea => (others => '0'),
    --   addra => (others => '0'),
    --   dina => (others => '0'),

    --   -- Port B: dùng để đọc
    --   clkb  => CLK125B,
    --   enb   => ram_read_en,
    --   addrb => ram_read_addr,
    --   doutb => ram_read_dout
    -- );

    fifo_inst : fifo_generator_0
    port map
    (
      clk  => CLK125B,
      srst => CORE_RESET,

      din   => ADC1_DATA,
      wr_en => fifo_wr_en,
      full  => fifo_full,

      dout  => fifo_dout,
      rd_en => fifo_rd_en,
      empty => fifo_empty
    );
    -------------------------------------------------------
    SYS_CORE : component CORE
      generic map(
        DATA_WIDTH => 512)
      port map
      (
        CORE_CLK    => CLK125B,
        CORE_RESET  => CORE_RESET,
        CORE_ENABLE => BUTTON(3),
        ----------------------------------
        fifo_wr_en => fifo_wr_en,
        fifo_full  => fifo_full,
        fifo_empty => fifo_empty,
        fifo_rd_en => fifo_rd_en,
        fifo_dout  => fifo_dout,
        ----------------------------------
        CORE_OUT_TVALID => CORE_OUT_TVALID,
        CORE_OUT_TDATA  => CORE_OUT_TDATA,
        CORE_OUT_TKEEP  => CORE_OUT_TKEEP,
        CORE_OUT_TREADY => CORE_OUT_TREADY,
        CORE_OUT_TLAST  => CORE_OUT_TLAST
      );
      ---------------------------------------------------------------------------------
      -- RSTN_CNT_pr describe a free runing CNT
      ---------------------------------------------------------------------------------
      RSTN_CNT_pr : process (CLK125B)
      begin
        if rising_edge(CLK125B) then
          if RSTN_CNT < COUNTER_LIMIT_RST - 1 then
            RSTN_CNT <= RSTN_CNT + 1;
          end if;
        end if;
      end process;
      ---------------------------------------------------------------------------------
      -- RSTN_gen_pr creat a soft n reset for the syste
      ---------------------------------------------------------------------------------
      RSTN_gen_pr : process (CLK125B)
      begin
        if rising_edge(CLK125B) then
          if RSTN_CNT < COUNTER_LIMIT_RST - 1 then
            RESETN_BUTTON <= '0';
          else
            RESETN_BUTTON <= '1';
          end if;
        end if;
      end process;
      -------------------------------------------------------------------------------
      -- BLINKING THE LED_CORE AT 1Hz to test the free-runing clock
      -------------------------------------------------------------------------------
      resetn_gen_pr : process (CLK125B)
      begin
        if rising_edge(CLK125B) then
          if SYS_RESET_N = '0' or TEST_CNT = CLK_FREQ/2 - 1 then
            TEST_CNT       <= 0;
            LED_CORE_local <= not LED_CORE_local;
          else
            TEST_CNT <= TEST_CNT + 1;
          end if;
          -- if BUTTON(3) = '1' then
          --   LED_local <= "11111111";
          -- else
          --   LED_local <= (others => '0');
          -- end if;
        end if;
      end process;
      LED_CORE <= LED_CORE_local;

      ---------------------       
    end behavioral;
