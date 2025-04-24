------------------------------------------------------------------------
-- Title      : Reset synchroniser
-- Project    : Tri-Mode Ethernet MAC
------------------------------------------------------------------------
-- File       : ETH_PCB_HTP_reset_sync.vhd
-- Author     : Xilinx Inc.
------------------------------------------------------------------------
-- Description: Both flip-flops have the same asynchronous reset signal.
--              Together the flops create a minimum of a 1 clock period
--              duration pulse which is used for synchronous reset.
--
--              The flops are placed, using RLOCs, into the same slice.
------------------------------------------------------------------------
-- (c) Copyright 2001-2008 Xilinx, Inc. All rights reserved.
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
------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
library UNISIM;
use UNISIM.VCOMPONENTS.all;
------------------------------------------------------------------------
entity TEMAC_reset_sync is
	generic(
		INITIALISE    : bit:= '1';
		DEPTH         : integer:= 5
    );                
	port(             
		RESET_IN      : in  std_logic; -- Active high asynchronous reset
		ENABLE        : in  std_logic;                                    
		CLK           : in  std_logic; -- clock to be sync'ed to
		RESET_OUT     : out std_logic  -- "Synchronised" reset signal
    );
  attribute DONT_TOUCH: string;
  attribute DONT_TOUCH of TEMAC_reset_sync: entity is "yes";
end TEMAC_reset_sync;
------------------------------------------------------------------------
architecture rtl of TEMAC_reset_sync is
	signal RESET_SYNC_REG0                : std_logic;
	signal RESET_SYNC_REG1                : std_logic;
	signal RESET_SYNC_REG2                : std_logic;
	signal RESET_SYNC_REG3                : std_logic;
	signal RESET_SYNC_REG4                : std_logic;
	attribute ASYNC_REG                   : string;
	attribute ASYNC_REG of RESET_SYNC0    : label is "true";
	attribute ASYNC_REG of RESET_SYNC1    : label is "true";
	attribute ASYNC_REG of RESET_SYNC2    : label is "true";
	attribute ASYNC_REG of RESET_SYNC3    : label is "true";
	attribute ASYNC_REG of RESET_SYNC4    : label is "true";
	attribute SHREG_EXTRACT               : string;
	attribute SHREG_EXTRACT of RESET_SYNC0: label is "no";
	attribute SHREG_EXTRACT of RESET_SYNC1: label is "no";
	attribute SHREG_EXTRACT of RESET_SYNC2: label is "no";
	attribute SHREG_EXTRACT of RESET_SYNC3: label is "no";
	attribute SHREG_EXTRACT of RESET_SYNC4: label is "no";
------------------------------------------------------------------------
BEGIN
	RESET_SYNC0: FDPE
	generic map(
		INIT  => INITIALISE
	)
	port map(
		C     => CLK,
		CE    => ENABLE,
		PRE   => RESET_IN,
		D     => '0',
		Q     => RESET_SYNC_REG0
	);	
	--------------------------------------------------------------------
	RESET_SYNC1: FDPE
	generic map(
		INIT => INITIALISE
	)
	port map(
		C     => CLK,
		CE    => ENABLE,
		PRE   => RESET_IN,
		D     => RESET_SYNC_REG0,
		Q     => RESET_SYNC_REG1
	);	
	--------------------------------------------------------------------
	RESET_SYNC2: FDPE
	generic map(
		INIT => INITIALISE
	)
	port map (
		C     => CLK,
		CE    => ENABLE,
		PRE   => RESET_IN,
		D     => RESET_SYNC_REG1,
		Q     => RESET_SYNC_REG2
	);	
	--------------------------------------------------------------------
	RESET_SYNC3: FDPE
	generic map(
		INIT => INITIALISE
	)
	port map(
		C     => CLK,
		CE    => ENABLE,
		PRE   => RESET_IN,
		D     => RESET_SYNC_REG2,
		Q     => RESET_SYNC_REG3
	);	
	--------------------------------------------------------------------
	RESET_SYNC4: FDPE
	generic map(
		INIT => INITIALISE
	)
	port map(
		C     => CLK,
		CE    => ENABLE,
		PRE   => RESET_IN,
		D     => RESET_SYNC_REG3,
		Q     => RESET_SYNC_REG4
	);	
	RESET_OUT <= RESET_SYNC_REG4;
END rtl;
------------------------------------------------------------------------
