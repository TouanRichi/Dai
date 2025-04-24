---------------------------------------------------------------------------------------------
-- Author: Trinh Quang Kien, BMKTVXL 2020
-- Module: GLOBAL_CLOCK_RESET entity
-- Project: Artix-7 XC7A35T board demo
-- Begin Date: 
-- Revision History Date Author Comments
--   29/11/20 manhdq changed the coding style
-- Purpose:
-- 
---------------------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;
library UNISIM;
use UNISIM.VComponents.all;
---------------------------------------------------------------------------------------------
entity GLOBAL_CLOCK_RESET is
	generic(
	   CLOCK_SELECT        : std_logic:= '0';                                                  -- 0 select differential clock/1 single-ended    
	   COUNTER_LIMIT       : integer  := 50;                                                   -- simmulation = 50, implement = 100_000_000 * 5 - 1
	   RECOVER_LIMIT       : integer  := 20                                                    -- simmulation = 20, implement = 100_000_000 / 1_000 - 1
	);                                                                                         
	port( 
	   CLK_IN              : in  std_logic;                                                    -- single_ended clock in N
	   CLK125B             : out std_logic;                                                    
	   CLK125B_D2N         : out std_logic;                                                    -- delayed-2ns CLK125
	   CORE_RESET          : out std_logic;
	   -- hard reset ------------------------------------------------------------------------
	   RESETN_BUTTON       : in  std_logic;
	   RESETN_ERROR        : in  std_logic;	   
	   -- output reset signals --------------------------------------------------------------
	   GLBL_RST_INTN       : out std_logic;
	   VECTOR_RESETN       : out std_logic;
	   PHY_RESETN          : out std_logic;
	   RESETN_AXI          : out std_logic;
	   RESET_COM           : out std_logic
	);
end GLOBAL_CLOCK_RESET;
---------------------------------------------------------------------------------------------
architecture behavior of GLOBAL_CLOCK_RESET is
	signal CLK_LOCKED      : std_logic:= '0';
	signal CLK125_BUFG     : std_logic:= '0';
	signal CLK200_BUFG     : std_logic:= '0';
	signal RESETN_AXI_LOCAL: std_logic:= '0';
	signal RESET_COM_LOCAL : std_logic:= '1';
	signal RESET_CONTROL   : integer range 0 to 3:= 0;
	signal CNT_RST         : integer range 0 to COUNTER_LIMIT:= 0;
	signal GLBL_RST        : std_logic:= '0';
	signal RESETN_PHY      : std_logic:= '0';
	signal CLK125_D2n_LOCAL: std_logic:= '0';
	signal RESET_STATE     : integer range 0 to 1:= 0;
	signal VECTOR_RSTN     : std_logic;
	-----------------------------------------------------------------------------------------
	component clk_wiz_master
		port(		  
			CLK_IN1        : in  std_logic;
			CLK_125        : out std_logic;
			CLK_125_D2NS   : out std_logic;
			CLK_200        : out std_logic;
			--CLK_100        : out std_logic;
			--CLK_SYS        : out std_logic;		    
			LOCKED         : out std_logic                                                    -- Status and control signals	  
		);                                                                                     
	end component;                                                                             
	-----------------------------------------------------------------------------------------  
	component RESET_TEMAC_cfg_vector is                                                        
	    port(                                                                                  
			-- clocks -----------------------------------------------------------------------  
			DCM_LOCKED     : in std_logic;                                                     -- locked from MMCM (PLL)
			GTX_CLK        : in std_logic;                                                     -- 125 MHz not delay
			REFCLK         : in std_logic;                                                     -- 200Mhz
			-- asynchronous resets ----------------------------------------------------------                                                                   
			GLBL_RST       : in std_logic;                                                     -- active 1
			GLBL_RST_INTN  : out std_logic;                                                    -- reset active 0
			VECTOR_RESETN  : out std_logic;                                                    -- reset active 0 ,reset of axi_lite
			PHY_RESETN     : out std_logic                                                     -- reset phy active 0
	);
	end component;
---------------------------------------------------------------------------------------------
BEGIN
	CLK_gen: clk_wiz_master
	port map( 
	    -- Clock in ports -------------------------------------------------------------------
	    CLK_IN1           => CLK_IN,
		-- Clock out ports ------------------------------------------------------------------ 
		CLK_125           => CLK125_BUFG,
		CLK_125_D2NS      => CLK125B_D2N,
		CLK_200           => CLK200_BUFG,
	    -- Status and control signals -------------------------------------------------------
	    LOCKED            => CLK_LOCKED
	);	
	-----------------------------------------------------------------------------------------
	CREAT_TEMAC_RESET: RESET_TEMAC_cfg_vector
	port map( 
		DCM_LOCKED        => CLK_LOCKED,                                                       -- locked from MMCM (PLL)
		GTX_CLK           => CLK125_BUFG,                                                      -- 125 MHz not delay
		REFCLK            => CLK200_BUFG,                                                      -- 200Mhz
		-- asynchronous resets --------------------------------------------------------------
		GLBL_RST          => GLBL_RST,                                                         -- active 1
		GLBL_RST_INTN     => GLBL_RST_INTN,                                                    -- reset active 0
		VECTOR_RESETN     => VECTOR_RSTN,                                                      -- reset active 0 ,reset of axi_lite
		PHY_RESETN        => RESETN_PHY                                                        -- reset phy active 0
	);
	-----------------------------------------------------------------------------------------
	RST_PROC: process(CLK125_BUFG)
	begin
		if rising_edge(CLK125_BUFG) THEN
			if RESETN_BUTTON = '0' or CLK_LOCKED = '0' then
				CNT_RST <= 0;
				RESET_CONTROL <= 0;
			else
				case RESET_CONTROL is
				-----------------------------------------------------------------------------
				when 0 =>
					if CNT_RST < COUNTER_LIMIT - 1 then
					   CNT_RST <= CNT_RST + 1;
					else
						CNT_RST <= 0;
						RESET_CONTROL <= 1;
					end if;
				-----------------------------------------------------------------------------
				when 1 =>
					if CNT_RST < COUNTER_LIMIT - 1 then
						CNT_RST <= CNT_RST + 1;
					elsif RESETN_ERROR = '0' then
						CNT_RST <= 0;
						RESET_CONTROL <= 2;
					end if;
				-----------------------------------------------------------------------------
				when 2 =>
					if CNT_RST < RECOVER_LIMIT - 1 then
						CNT_RST <= CNT_RST + 1;
					else
						CNT_RST <= COUNTER_LIMIT - RECOVER_LIMIT;
						RESET_CONTROL <= 1;
					end if;
				-----------------------------------------------------------------------------
				when others =>
					RESET_CONTROL <= 0;
				end case;
			end if;
		end if;
	end process;
	-----------------------------------------------------------------------------------------
 	CLK125B          <= CLK125_BUFG;
	VECTOR_RESETN    <= VECTOR_RSTN;
	GLBL_RST         <= RESET_COM_LOCAL;
	CORE_RESET       <= RESET_COM_LOCAL;
	PHY_RESETN       <= RESETN_PHY;
	RESET_COM_LOCAL  <= '0' when RESET_CONTROL = 1 and CNT_RST >= COUNTER_LIMIT - 1 else '1';	
	RESETN_AXI_LOCAL <= '1' when RESET_CONTROL = 1 and CNT_RST >= COUNTER_LIMIT - 1 else '0';
    RESETN_AXI       <= RESETN_AXI_LOCAL;
    RESET_COM        <= RESET_COM_LOCAL;
END behavior;
---------------------------------------------------------------------------------------------
