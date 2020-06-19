----------------------------------------------------------------------------------
-- Company: SAL-Virginia Tech
-- Engineer: Behnaz Rezvani
-- 
-- Create Date: 01/31/2020
-- Module Name: COMET_Datapath - Behavioral 
-- Tool Versions: 2019.1
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.Design_pkg.all;
use work.SomeFunction.all;

-- Entity
----------------------------------------------------------------------------------
entity COMET_Datapath is
  Port (
    clk, rst        : in  std_logic;
    bdi             : in  std_logic_vector(CCW-1 downto 0);
    bdi_size        : in  std_logic_vector(2 downto 0);
    key             : in  std_logic_vector(CCSW-1 downto 0);
    bdo             : out std_logic_vector(CCW-1 downto 0);
    msg_auth        : out std_logic;
    CHAM_start      : in  std_logic;
    CHAM_done       : out std_logic;
    ctr_words       : in  std_logic_vector(2 downto 0);
    ctr_bytes       : in  std_logic_vector(4 downto 0);
    KeyReg128_rst   : in  std_logic;
    KeyReg128_en    : in  std_logic;
    ZstateReg_rst   : in  std_logic; 
    ZstateReg_en    : in  std_logic;
    Zstate_mux_sel  : in  std_logic_vector(2 downto 0);
    Z_ctrl_mux_sel  : in  std_logic_vector(2 downto 0);
    YstateReg_rst   : in  std_logic; 
    YstateReg_en    : in  std_logic;
    Ystate_mux_sel  : in  std_logic_vector(1 downto 0);
    iDataReg_rst    : in  std_logic;
    iDataReg_en     : in  std_logic;
    iData_mux_sel   : in  std_logic;
    bdo_t_mux_sel   : in std_logic
  );
end COMET_Datapath;

-- Architecture
----------------------------------------------------------------------------------
architecture Behavioral of COMET_Datapath is

    -- All zero constant
    constant zero123         : std_logic_vector(122 downto 0) := (others => '0');
    constant zero115         : std_logic_vector(114 downto 0) := (others => '0');

    -- Signals -------------------------------------------------------------------
    signal Ek_key           : std_logic_vector(127 downto 0);
    signal Ek_in            : std_logic_vector(127 downto 0);
    signal Ek_out           : std_logic_vector(127 downto 0);
    
    signal KeyReg128_in     : std_logic_vector(127 downto 0);
    signal secret_key_reg   : std_logic_vector(127 downto 0);
    
    signal ZstateReg_in     : std_logic_vector(127 downto 0);
    signal ZstateReg_out    : std_logic_vector(127 downto 0);
    signal Zstate_ctrl      : std_logic_vector(4 downto 0);
    
    signal YstateReg_in     : std_logic_vector(127 downto 0);
    signal YstateReg_out    : std_logic_vector(127 downto 0);

    signal iDataReg_in      : std_logic_vector(127 downto 0);
    signal iDataReg_out     : std_logic_vector(127 downto 0);
    
    signal CT               : std_logic_vector(127 downto 0);
    
    signal Ek_out_32        : std_logic_vector(31 downto 0);
    signal CT_32            : std_logic_vector(31 downto 0);
    signal bdo_t            : std_logic_vector(31 downto 0);

----------------------------------------------------------------------------------   
begin
    
    -- CHAM
    
    Ek_key <= ZstateReg_out(31 downto 0)  & ZstateReg_out(63 downto 32) &
              ZstateReg_out(95 downto 64) & ZstateReg_out(127 downto 96);
              
    Ek_in  <= YstateReg_out(31 downto 0)  & YstateReg_out(63 downto 32) &
              YstateReg_out(95 downto 64) & YstateReg_out(127 downto 96);
              
    Ek: entity work.CHAM128
    Port map(
        clk         => clk,
        rst         => rst,
        start       => CHAM_start,
        Key         => Ek_key,
        CHAM_in     => Ek_in,
        CHAM_out    => Ek_out,
        done        => CHAM_done
    );

    -- Registers
    
    KeyReg128_in <= secret_key_reg(95 downto 0) & key(7 downto 0)   & key(15 downto 8) &
                                                  key(23 downto 16) & key(31 downto 24);
    KeyReg128: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => KeyReg128_rst,
        en      => KeyReg128_en,
        D_in    => KeyReg128_in,
        D_out   => secret_key_reg
    );
    
    ZstateReg: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => ZstateReg_rst,
        en      => ZstateReg_en,
        D_in    => ZstateReg_in,
        D_out   => ZstateReg_out
    );
    
    YstateReg: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => YstateReg_rst,
        en      => YstateReg_en,
        D_in    => YstateReg_in,
        D_out   => YstateReg_out
    );

    iDataReg: entity work.myReg
    generic map( b => 128)
    Port map(
        clk     => clk,
        rst     => iDataReg_rst,
        en      => iDataReg_en,
        D_in    => iDataReg_in,
        D_out   => iDataReg_out
    );
    
    -- Multiplexres
    
    with Z_ctrl_mux_sel select
        Zstate_ctrl <= "00001" when "001", -- First AD
                       "00010" when "010", -- Partial AD
                       "00011" when "011", -- Partial first AD
--                       "00100" when "100", -- First M
                       "01000" when "101", -- Partial M
--                       "01100" when "110", -- Partial first M
                       "10000" when "111", -- Tag
                       "00000" when others; -- Nothing
    
    with Zstate_mux_sel select
        ZstateReg_in    <= secret_key_reg(31 downto 0)  & secret_key_reg(63 downto 32) &
                           secret_key_reg(95 downto 64) & secret_key_reg(127 downto 96) when "000", -- Z = Key
                           Ek_out                                                       when "001", -- Z = Ek(K, N)
                           phi(Ek_out xor (Zstate_ctrl & zero123))                      when "010", -- Z = phi(Ek(K, N))
                           phi(ZstateReg_out xor (Zstate_ctrl & zero115 & "00100000"))  when "011",
                           phi(ZstateReg_out xor (Zstate_ctrl & zero123))               when others;
                           
    with Ystate_mux_sel select
        YstateReg_in    <= iDataReg_in(31 downto 0)  & iDataReg_in(63  downto 32) & 
                           iDataReg_in(95 downto 64) & iDataReg_in(127 downto 96)                      when "00",   -- Y = Nonce
                           secret_key_reg(31 downto 0)  & secret_key_reg(63  downto 32) & 
                           secret_key_reg(95 downto 64) & secret_key_reg(127 downto 96)                when "01",   -- Y = key
                           Ek_out xor pad(CT, conv_integer(ctr_bytes))                                 when "10",   -- Y = CT 
                           Ek_out xor pad(iDataReg_out, conv_integer(ctr_bytes))                       when others; -- Y = Ek_out xor AD/PT 
                        
    with iData_mux_sel select
        iDataReg_in <=  iDataReg_out(95 downto 0) & bdi(7  downto 0)  & bdi(15 downto 8) &
                                                    bdi(23 downto 16) & bdi(31 downto 24)              when '0',    -- Nonce/ Expected tag
                        myMux(iDataReg_out,        (bdi(7  downto 0)  & bdi(15 downto 8)
                                                  & bdi(23 downto 16) & bdi(31 downto 24)), ctr_words) when others; -- AD/PT/CT 
                                         
    Ek_out_32 <=  Ek_out(((conv_integer(ctr_words)+1)*32 - 1) downto (conv_integer(ctr_words)*32)); 

    CT <= shuffle(Ek_out) xor iDataReg_out; -- Enc: CT = shuffle(Ek_out) xor M
    CT_32 <= CT(((conv_integer(ctr_words)+1)*32 - 1) downto (conv_integer(ctr_words)*32));   
        
    with bdo_t_mux_sel select 
    bdo_t <=  chop(BE2LE(CT_32), ctr_bytes) when '0', -- CT(PT) =  Y xor PT(CT)
              Ek_out_32(7  downto 0)  & Ek_out_32(15 downto 8) &
              Ek_out_32(23 downto 16) & Ek_out_32(31 downto 24) when others; -- Computed tag
              
    bdo   <= bdo_t;

    msg_auth <=  '1' when (iDataReg_out = (Ek_out(31 downto 0) & Ek_out(63 downto 32) & Ek_out(95 downto 64) & Ek_out(127 downto 96))) else '0';
    
end Behavioral;
