------------------------------------------------------------------------------------
-- File       : ETH_PCB_HTP_config_vector_sm.vhd
-- Author     : Xilinx Inc.
------------------------------------------------------------------------------------
-- (c) Copyright 2010 Xilinx, Inc. All rights reserved.
--
-- This file contains confidential and proprietary information
-- of Xilinx, Inc. and is protected under U.S. and
-- international copyright and other intellectual property
-- laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Xilinx, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Xilinx shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- Xilinx products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of Xilinx products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
------------------------------------------------------------------------------------
-- Description:  This module is reponsible for bringing up the MAC 
-- to enable basic packet transfer in both directions.
-- Due to the lack of a management interface the PHy cannot be
-- accessed and therefore this solution will not work when
-- targeted to a demo platform unless some other method of enabing the PHY
-- is used.
--
------------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
library UNISIM;
use UNISIM.VCOMPONENTS.all;
------------------------------------------------------------------------------------
-- The entity declaration for the block level example design.
------------------------------------------------------------------------------------
entity TEMAC_config_vector_sm is
	port(
		GTX_CLK                   : in  std_logic;
		GTX_RESETN                : in  std_logic;		
		MAC_SPEED                 : in  std_logic_vector(1  downto 0);
		UPDATE_SPEED              : in  std_logic;		
		RX_CONFIGURATION_VECTOR   : out std_logic_vector(79 downto 0);
		TX_CONFIGURATION_VECTOR   : out std_logic_vector(79 downto 0)
	);
end TEMAC_config_vector_sm;

architecture rtl of TEMAC_config_vector_sm is
	constant RUN_HALF_DUPLEX      : std_logic:= '0';
	--------------------------------------------------------------------------------
	-- Component declaration for the synchroniser
	--------------------------------------------------------------------------------
	component TEMAC_sync_block
	port(
		CLK                       : in  std_logic; 
		DATA_IN                   : in  std_logic;
		DATA_OUT                  : out std_logic
	);
	end component;
	--------------------------------------------------------------------------------
	-- main state machine ----------------------------------------------------------
	--------------------------------------------------------------------------------	
	type STATE_TYP is(STARTUP, RESET_MAC, CHECK_SPEED);
	--------------------------------------------------------------------------------
	-- Signal declarations ---------------------------------------------------------
	--------------------------------------------------------------------------------	
	signal CONTROL_STATUS         : STATE_TYP;
	signal UPDATE_SPEED_REG       : std_logic;
	signal UPDATE_SPEED_REG2      : std_logic; 
	signal UPDATE_SPEED_SYNC      : std_logic;
	--------------------------------------------------------------------------------
	signal COUNT_SHIFT            : std_logic_vector(20 downto 0):= (others => '0');
	--------------------------------------------------------------------------------
	signal TX_RESET               : std_logic;
	signal TX_ENABLE              : std_logic;
	signal TX_VLAN_ENABLE         : std_logic;
	signal TX_FCS_ENABLE          : std_logic;
	signal TX_JUMBO_ENABLE        : std_logic;
	signal TX_FC_ENABLE           : std_logic;
	signal TX_HD_ENABLE           : std_logic;
	signal TX_IFG_ADJUST          : std_logic;
	signal TX_SPEED               : std_logic_vector(1  downto 0):= (others => '0');
	signal TX_MAX_FRAME_ENABLE    : std_logic;
	signal TX_MAX_FRAME_LENGTH    : std_logic_vector(14 downto 0);
	signal TX_PAUSE_ADDR          : std_logic_vector(47 downto 0);
	--------------------------------------------------------------------------------
	signal RX_RESET               : std_logic;
	signal RX_ENABLE              : std_logic;
	signal RX_VLAN_ENABLE         : std_logic;
	signal RX_FCS_ENABLE          : std_logic;
	signal RX_JUMBO_ENABLE        : std_logic;
	signal RX_FC_ENABLE           : std_logic;
	signal RX_HD_ENABLE           : std_logic;
	signal RX_LEN_TYPE_CHK_DISABLE: std_logic;
	signal RX_CONTROL_LEN_CHK_DIS : std_logic;
	signal RX_PROMISCUOUS         : std_logic;
	signal RX_SPEED               : std_logic_vector(1 downto 0);
	signal RX_MAX_FRAME_ENABLE    : std_logic;
	signal RX_MAX_FRAME_LENGTH    : std_logic_vector(14 downto 0);
	signal RX_PAUSE_ADDR          : std_logic_vector(47 downto 0);
	--------------------------------------------------------------------------------
	signal GTX_RESET              : std_logic;  
------------------------------------------------------------------------------------
BEGIN
	GTX_RESET <= NOT GTX_RESETN;	
	RX_CONFIGURATION_VECTOR <= RX_PAUSE_ADDR & 
								'0' & RX_MAX_FRAME_LENGTH &
								'0' & RX_MAX_FRAME_ENABLE &
								RX_SPEED &
								RX_PROMISCUOUS &
								'0' & RX_CONTROL_LEN_CHK_DIS &
								RX_LEN_TYPE_CHK_DISABLE &
								'0' & RX_HD_ENABLE &
								RX_FC_ENABLE &
								RX_JUMBO_ENABLE &
								RX_FCS_ENABLE &
								RX_VLAN_ENABLE &
								RX_ENABLE &
								RX_RESET;
	--------------------------------------------------------------------------------
	TX_CONFIGURATION_VECTOR <= TX_PAUSE_ADDR &
								'0' & TX_MAX_FRAME_LENGTH &
								'0' & TX_MAX_FRAME_ENABLE &
								TX_SPEED &
								"000" & TX_IFG_ADJUST &
								'0' & TX_HD_ENABLE &
								TX_FC_ENABLE &
								TX_JUMBO_ENABLE &
								TX_FCS_ENABLE &
								TX_VLAN_ENABLE &
								TX_ENABLE &
								TX_RESET;
	--------------------------------------------------------------------------------
	-- don't reset this: it will always be updated before it is used.. -------------
	-- it does need an init value (zero) -------------------------------------------
	--------------------------------------------------------------------------------
	gen_count: process(GTX_CLK)
	begin
		if GTX_CLK'event and GTX_CLK = '1' then
			COUNT_SHIFT <= COUNT_SHIFT(19 downto 0) & (GTX_RESET or TX_RESET);
		end if;
	end process gen_count;
	--------------------------------------------------------------------------------
	upspeed_sync: TEMAC_sync_block  
	port map(
		CLK      => GTX_CLK,
		DATA_IN  => UPDATE_SPEED,
		DATA_OUT => UPDATE_SPEED_SYNC
	);
	--------------------------------------------------------------------------------
	-- capture update_spped as only want to react to one edge ----------------------
	--------------------------------------------------------------------------------
	capture_update: process (GTX_CLK)
	begin
		if GTX_CLK'event and GTX_CLK = '1' then
			if GTX_RESET = '1' then
				UPDATE_SPEED_REG  <= '0';
				UPDATE_SPEED_REG2 <= '0';
			else
				UPDATE_SPEED_REG  <= UPDATE_SPEED_SYNC;
				UPDATE_SPEED_REG2 <= UPDATE_SPEED_REG;
			end if;
		end if;
	end process capture_update;	
	--------------------------------------------------------------------------------
	-- Management process. This process sets up the configuration by
	-- turning off flow control
	--------------------------------------------------------------------------------
	gen_state: process(GTX_CLK)
	begin
		if GTX_CLK'event and GTX_CLK = '1' then
			if GTX_RESET = '1' then
			------------------------------------------------------------------------
				TX_RESET                <= '0';
				TX_ENABLE               <= '1';
				TX_VLAN_ENABLE          <= '0';
				TX_FCS_ENABLE           <= '0';
				TX_JUMBO_ENABLE         <= '0';
				TX_FC_ENABLE            <= '1';
				TX_HD_ENABLE            <= RUN_HALF_DUPLEX;
				TX_IFG_ADJUST           <= '0';
				TX_SPEED                <= MAC_SPEED;
				TX_MAX_FRAME_ENABLE     <= '0';
				TX_MAX_FRAME_LENGTH     <= (others => '0');
				TX_PAUSE_ADDR           <= X"0605040302DA";
				--------------------------------------------------------------------
				RX_RESET                <= '0';
				RX_ENABLE               <= '1';
				RX_VLAN_ENABLE          <= '0';
				RX_FCS_ENABLE           <= '0';
				RX_JUMBO_ENABLE         <= '0';
				RX_FC_ENABLE            <= '1';
				RX_HD_ENABLE            <= RUN_HALF_DUPLEX;
				RX_LEN_TYPE_CHK_DISABLE <= '0';
				RX_CONTROL_LEN_CHK_DIS  <= '0';				
				RX_PROMISCUOUS          <= '0';				
				RX_SPEED                <= MAC_SPEED;
				RX_MAX_FRAME_ENABLE     <= '0';
				RX_MAX_FRAME_LENGTH     <= (others => '0');
				RX_PAUSE_ADDR           <= X"0605040302DA";
				CONTROL_STATUS          <= STARTUP;
			------------------------------------------------------------------------
			-- main state machine is kicking off multi cycle accesses in each state 
			-- so has to stall while they take place
			------------------------------------------------------------------------
			else 
				case CONTROL_STATUS is
				--------------------------------------------------------------------
				when STARTUP =>
					-- this state will be ran after reset to wait for count_shift --
					if COUNT_SHIFT(20) = '0' then
						CONTROL_STATUS <= RESET_MAC;
					end if;
				--------------------------------------------------------------------
				when RESET_MAC =>
					assert false
					report "RESETING MAC" & CR
					severity note;
						TX_RESET       <= '1';
						RX_RESET       <= '1';
						RX_SPEED       <= MAC_SPEED;
						TX_SPEED       <= MAC_SPEED;
						CONTROL_STATUS <= CHECK_SPEED;
				--------------------------------------------------------------------
				when CHECK_SPEED =>
					-- hold the local resets for 20 gtx cycles to ensure -----------
					-- the tx is captured by the mac -------------------------------
					if COUNT_SHIFT(20) = '1' then               
						TX_RESET       <= '0';
						RX_RESET       <= '0';
					end if;
					if UPDATE_SPEED_REG = '1' and UPDATE_SPEED_REG2 = '0' then
						CONTROL_STATUS <= RESET_MAC;
					end if;
				--------------------------------------------------------------------
				when others =>
					CONTROL_STATUS     <= STARTUP;
				end case;				
			end if;
		end if;
	end process gen_state;
END rtl;  
------------------------------------------------------------------------------------
