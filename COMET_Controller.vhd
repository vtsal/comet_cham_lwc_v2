----------------------------------------------------------------------------------
-- Company: SAL- Virginia Tech
-- Engineer: Behnaz Rezvani
-- 
-- Create Date: 09/09/2019
-- Module Name: COMET_Cnotroller - Behavioral - Version 2
-- Tool Versions: 2019.1
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.SomeFunction.all;
--use work.design_pkg.all;

-- Entity
----------------------------------------------------------------------------------
entity COMET_Controller is
    Port(
        clk             : in std_logic;
        rst             : in std_logic;
        -- Data Input
        key             : in std_logic_vector(31 downto 0); -- SW = 32
        bdi             : in std_logic_vector(31 downto 0); -- W = 32
        -- Key Control
        key_valid       : in std_logic;
        key_ready       : out std_logic;
        key_update      : in std_logic;
        -- BDI Control
        bdi_valid       : in std_logic;
        bdi_ready       : out std_logic;
        bdi_size        : in std_logic_vector(2 downto 0); -- W/(8+1) = 3
        bdi_eot         : in std_logic;
        bdi_eoi         : in std_logic;
        bdi_type        : in std_logic_vector(3 downto 0);
        decrypt_in      : in std_logic;
        -- BDO Control
        bdo_valid       : out std_logic;
        bdo_ready       : in std_logic;
        bdo_valid_bytes : out std_logic_vector(3 downto 0); -- W/8 = 4
        end_of_block    : out std_logic;
        bdo_type        : out std_logic_vector(3 downto 0);
        -- Tag Verification
        msg_auth_valid  : out std_logic;
        msg_auth_ready  : in std_logic;
        -- CHAM
        CHAM_start      : out std_logic;
        CHAM_done       : in std_logic;
        -- Control
        ctr_words       : inout std_logic_vector(2 downto 0);
        ctr_bytes       : inout std_logic_vector(4 downto 0);
        KeyReg128_rst   : out std_logic;
        KeyReg128_en    : out std_logic;
        ZstateReg_rst   : out std_logic;
        ZstateReg_en    : out std_logic;
        Zstate_mux_sel  : out std_logic_vector(2 downto 0);
        Z_ctrl_mux_sel  : out std_logic_vector(2 downto 0);
        YstateReg_rst   : out std_logic;
        YstateReg_en    : out std_logic;
        Ystate_mux_sel  : out std_logic_vector(1 downto 0);
        iDataReg_rst    : out std_logic;
        iDataReg_en     : out std_logic;
        iData_mux_sel   : out std_logic;
        bdo_t_mux_sel   : out std_logic       
    );
end COMET_Controller;

-- Architecture
----------------------------------------------------------------------------------
architecture Behavioral of COMET_Controller is

    -- Constants -----------------------------------------------------------------
    --bdi_type and bdo_type encoding
    constant HDR_AD         : std_logic_vector(3 downto 0) := "0001";
    constant HDR_MSG        : std_logic_vector(3 downto 0) := "0100";
    constant HDR_CT         : std_logic_vector(3 downto 0) := "0101";
    constant HDR_TAG        : std_logic_vector(3 downto 0) := "1000";
    constant HDR_KEY        : std_logic_vector(3 downto 0) := "1100";
    constant HDR_NPUB       : std_logic_vector(3 downto 0) := "1101";
    
    -- Types ---------------------------------------------------------------------
    type fsm is (idle, load_key, wait_Npub, load_Npub, process_Npub, load_AD,
                 process_AD, load_data, process_data, output_data, process_tag,
                 output_tag, load_tag, verify_tag);

    -- Signals -------------------------------------------------------------------
    -- Control Signals  
    signal decrypt_rst      : std_logic;
    signal decrypt_set      : std_logic;
    signal decrypt_reg      : std_logic;
    
    signal bdi_eoi_reg      : std_logic;
    signal bdi_eoi_rst      : std_logic;
    signal bdi_eoi_set      : std_logic;
    
    signal bdi_eot_reg      : std_logic;
    signal bdi_eot_rst      : std_logic;
    signal bdi_eot_set      : std_logic;
    
    signal first_ADM_reg    : std_logic;
    signal first_ADM_rst    : std_logic;
    signal first_ADM_set    : std_logic;

    -- Counter signals
    signal ctr_words_rst    : std_logic;
    signal ctr_words_inc    : std_logic;
    
    signal ctr_bytes_rst    : std_logic;
    signal ctr_bytes_inc    : std_logic;
    signal ctr_bytes_dec    : std_logic;
    
    -- State machine signals
    signal state            : fsm;
    signal next_state       : fsm;

----------------------------------------------------------------------------------    
begin
    
    bdo_valid_bytes <= "1111"; -- Since we truncate the CT, bdo_valid_bytes can be always "1111"
    
    ---------------------------------------------------------------------------------
    Sync: process(clk)
    begin
        if rising_edge(clk) then
            if (rst = '1') then
                state   <= idle;
            else
                state   <= next_state;
            
                if (ctr_words_rst = '1') then
                    ctr_words   <= "000";
                elsif (ctr_words_inc = '1') then
                    ctr_words   <= ctr_words + 1;
                end if;
                
                if (ctr_bytes_rst = '1') then
                    ctr_bytes   <= "00000";
                elsif (ctr_bytes_inc = '1') then
                    ctr_bytes   <= ctr_bytes + bdi_size;
                elsif (ctr_bytes_dec = '1') then
                    ctr_bytes   <= ctr_bytes - 4;
                end if;

                if (decrypt_rst = '1') then
                    decrypt_reg <= '0';
                elsif (decrypt_set = '1') then
                    decrypt_reg <= '1';
                end if;
                
                if (bdi_eoi_rst = '1') then
                    bdi_eoi_reg   <= '0';
                elsif (bdi_eoi_set = '1') then
                    bdi_eoi_reg   <= '1';
                end if;
                
                if (bdi_eot_rst = '1') then
                    bdi_eot_reg   <= '0';
                elsif (bdi_eot_set = '1') then
                    bdi_eot_reg   <= '1';
                end if;
                
                if (first_ADM_rst = '1') then
                    first_ADM_reg <= '0';
                elsif (first_ADM_set = '1') then
                    first_ADM_reg <= '1';
                end if;
                
            end if;
        end if;
    end process;
    
    Controller: process(state, key, key_valid, key_update, bdi, bdi_valid, bdi_eot, bdi_eoi,
                        bdi_type, ctr_words, CHAM_done, bdo_ready, msg_auth_ready)
                       
    begin
        next_state          <= idle;
        key_ready           <= '0';
        bdi_ready           <= '0'; 
        bdo_valid           <= '0';                   
        end_of_block        <= '0';        
        msg_auth_valid      <= '0';  
        KeyReg128_rst       <= '0';
        KeyReg128_en        <= '0';
        iDataReg_rst        <= '0';
        iDataReg_en         <= '0';
        ZstateReg_rst       <= '0';
        ZstateReg_en        <= '0';
        YstateReg_rst       <= '0';
        YstateReg_en        <= '0';
        ctr_words_rst       <= '0';
        ctr_words_inc       <= '0';
        ctr_bytes_rst       <= '0';
        ctr_bytes_inc       <= '0';
        ctr_bytes_dec       <= '0';
        decrypt_rst         <= '0';
        decrypt_set         <= '0';
        bdi_eoi_rst         <= '0';
        bdi_eoi_set         <= '0';
        bdi_eot_rst         <= '0';
        bdi_eot_set         <= '0';
        first_ADM_rst       <= '0';
        first_ADM_set       <= '0';
        Z_ctrl_mux_sel      <= "000"; -- All zeros 
        Zstate_mux_sel      <= "111"; -- Z = phi(Z xor Ctrl)  
        Ystate_mux_sel      <= "11";  -- Y = Ek_out xor AD/PT
        iData_mux_sel       <= '1';   -- AD/PT/CT
        bdo_t_mux_sel       <= '0';
        CHAM_start          <= '0';
        
        case state is
            when idle =>
                ctr_words_rst       <= '1';
                ctr_bytes_rst       <= '1';
                iDataReg_rst        <= '1';
                ZstateReg_rst       <= '1';
                YstateReg_rst       <= '1';
                decrypt_rst         <= '1';
                bdi_eoi_rst         <= '1';
                bdi_eot_rst         <= '1';
                first_ADM_rst       <= '1';
                if (key_valid = '1' and key_update = '1') then -- Get a new key
                    KeyReg128_rst   <= '1'; -- No need to keep the previous key
                    next_state      <= load_key;
                elsif (bdi_valid = '1') then -- In decryption, skip loading the key and goto load the nonce
                    next_state      <= load_Npub;
                else
                    next_state      <= idle;
                end if;
                
            when load_key =>
                key_ready           <= '1';
                KeyReg128_en        <= '1'; -- We need to register the key for decryption
                ctr_words_inc       <= '1';
                if (ctr_words = 3) then
                    ctr_words_rst   <= '1'; 
                    next_state      <= wait_Npub;
                else
                    next_state      <= load_key;
                end if;
                
            when wait_Npub =>
                if (bdi_valid = '1') then
                    next_state      <= load_Npub;
                else
                    next_state      <= wait_Npub;
                end if;
                
            when load_Npub =>
                bdi_ready           <= '1';                
                ctr_words_inc       <= '1';
                iDataReg_en         <= '1'; 
                iData_mux_sel       <= '0'; -- Nonce
                Zstate_mux_sel      <= "000"; -- Z = Key
                Ystate_mux_sel      <= "00";  -- Y = Nonce
                if (decrypt_in = '1') then -- Decryption
                    decrypt_set     <= '1';
                end if;
                if (bdi_eoi = '1') then -- No AD and no data
                    bdi_eoi_set     <= '1';
                end if;
                if (ctr_words = 3) then 
                    ctr_words_rst   <= '1';
                    ZstateReg_en    <= '1';                      
                    YstateReg_en    <= '1';                   
                    next_state      <= process_Npub;
                else
                    next_state      <= load_Npub;
                end if;
                
            when process_Npub =>
                CHAM_start              <= '1';
                Zstate_mux_sel          <= "001"; -- Z = Ek(K, N)
                Ystate_mux_sel          <= "01"; -- Y = Key
                if (CHAM_done = '1') then
                    CHAM_start          <= '0';
                    iDataReg_rst        <= '1';
                    ZstateReg_en        <= '1';
                    YstateReg_en        <= '1'; 
                    first_ADM_set       <= '1';                   
                    if (bdi_eoi_reg = '1') then   -- No AD and no M, go to process tag
                        Z_ctrl_mux_sel  <= "111"; -- Ctrl_tg
                        Zstate_mux_sel  <= "010"; -- Z = phi(Ek(K, N) xor Ctrl) 
                        next_state      <= process_tag;
                    elsif (bdi_type = HDR_AD) then -- Start of loading AD                      
                        next_state      <= load_AD;
                    else                           -- No AD, go to load M
                        next_state      <= load_data; 
                    end if;
                else
                    next_state          <= process_Npub;
                end if;

            when load_AD =>
                bdi_ready               <= '1';
                ctr_words_inc           <= '1';
                ctr_bytes_inc           <= '1';
                iDataReg_en             <= '1'; 
                if (bdi_eot = '1') then -- Last block of AD
                    bdi_eot_set         <= '1';
                end if;
                if (bdi_eoi = '1') then -- No block of M
                    bdi_eoi_set         <= '1';
                end if;
                if (first_ADM_reg = '1' and (bdi_eot = '1' or ctr_words = 3)) then --First block of AD
                    first_ADM_rst        <= '1';
                    Z_ctrl_mux_sel      <= "001"; -- Ctrl_ad
                    if (bdi_size /= "100" or ctr_words /= 3) then -- First and partial last block of AD 
                        Z_ctrl_mux_sel  <= "011"; -- Ctrl_ad + Ctrl_p_ad
                    end if;
                elsif (bdi_eot = '1') then -- Last block of AD
                    if (bdi_size /= "100" or ctr_words /= 3) then -- Partial last block
                        Z_ctrl_mux_sel  <= "010"; -- Ctrl_p_ad
                    end if;                  
                end if;               
                if (bdi_eot = '1' or ctr_words = 3) then -- Have gotten a full block of AD
                    ctr_words_rst       <= '1';
                    ZstateReg_en        <= '1';
                    next_state          <= process_AD;
                else
                    next_state          <= load_AD;
                end if;                   
            
            when process_AD =>
                CHAM_start              <= '1';
                if (CHAM_done = '1') then
                    CHAM_start          <= '0';
                    ctr_bytes_rst       <= '1';
                    iDataReg_rst        <= '1';
                    YstateReg_en        <= '1';
                    if (bdi_eoi_reg = '1') then    -- No block of M and last block of AD, go to process tag                       
                        ZstateReg_en    <= '1';
                        Z_ctrl_mux_sel  <= "111";  -- Ctrl_tg
                        next_state      <= process_tag;
                    elsif (bdi_eot_reg = '0') then -- Still loading AD
                        next_state      <= load_AD;
                    else                           -- No more AD, start loading M 
                        first_ADM_set   <= '1';
                        next_state      <= load_data;
                    end if;
                else
                    next_state          <= process_AD;
                end if;
                
            when load_data =>
                bdi_ready               <= '1'; 
                ctr_words_inc           <= '1';
                ctr_bytes_inc           <= '1';
                iDataReg_en             <= '1';  
                if (bdi_eot = '1') then -- Last block of M
                    bdi_eot_set         <= '1';
                else
                    bdi_eot_rst         <= '1';
                end if;  
                if (first_ADM_reg = '1' and (bdi_eot = '1' or ctr_words = 3)) then --First block of M
                    first_ADM_rst       <= '1';
                    Zstate_mux_sel      <= "011"; -- Ctrl_m
                    if (bdi_size /= "100" or ctr_words /= 3) then -- First and partial last block of M  
                        Z_ctrl_mux_sel  <= "101"; -- Ctrl_p_m
                    end if;
                elsif (bdi_eot = '1') then -- Last block of m
                    if (bdi_size /= "100" or ctr_words /= 3) then -- Partial last block
                        Z_ctrl_mux_sel  <= "101"; -- Ctrl_p_m
                    end if;                  
                end if;         
                if (bdi_eot = '1' or ctr_words = 3) then -- Have gotten a block of M
                    ctr_words_rst       <= '1';
                    ZstateReg_en        <= '1';
                    next_state          <= process_data;
                else
                    next_state          <= load_data;
                end if;
            
            when process_data =>
                CHAM_start              <= '1';
                if (CHAM_done = '1') then
                    CHAM_start          <= '0';
                    YstateReg_en        <= '1';
                    if (decrypt_reg = '1') then -- Decryption 
                        Ystate_mux_sel  <= "10";
                    end if;
                    next_state          <= output_data;
                else
                    next_state          <= process_data;
                end if;
                
            when output_data =>
                bdo_valid               <= '1';
                ctr_words_inc           <= '1';
                ctr_bytes_dec           <= '1';               
                if (ctr_bytes <= 4) then -- Last 4 bytes of M
                    end_of_block        <= bdi_eot_reg; -- Indicates the last block of M
                end if;
                if (ctr_words = 3 or ctr_bytes <= 4) then -- One block of CT is extracted
                    ctr_words_rst       <= '1';
                    ctr_bytes_rst       <= '1';
                    iDataReg_rst        <= '1';
                    if (bdi_eot_reg = '1') then -- No more M, go to process tag
                        ZstateReg_en    <= '1';
                        Z_ctrl_mux_sel  <= "111"; -- Ctrl_tg
                        next_state      <= process_tag;
                    else
                        next_state      <= load_data;
                    end if;
                else
                    next_state          <= output_data;
                end if;

            when process_tag =>
                CHAM_start          <= '1';
                if (CHAM_done = '1') then
                    CHAM_start      <= '0';
                    if (decrypt_reg = '0') then -- Encryption
                        next_state  <= output_tag;
                    else                        -- Decryption
                        next_state  <= load_tag;   
                    end if;
                else
                    next_state      <= process_tag;
                end if;
                
            when output_tag =>              
                bdo_valid           <= '1';
                bdo_t_mux_sel       <= '1';
                ctr_words_inc       <= '1';
                if (ctr_words = 3) then
                    end_of_block    <= '1'; -- Last word of Tag
                    ctr_words_rst   <= '1';
                    next_state      <= idle;
                else
                    next_state      <= output_tag;
                end if; 
             
            when load_tag =>
                bdi_ready           <= '1';
                iDataReg_en         <= '1';
                iData_mux_sel       <= '0';
                ctr_words_inc       <= '1';
                if (ctr_words = 3) then
                    ctr_words_rst   <= '1';
                    next_state      <= verify_tag;
                else
                    next_state      <= load_tag;
                end if;   
            
            when verify_tag =>
                if (msg_auth_ready = '1') then
                    msg_auth_valid  <= '1';
                    next_state      <= idle; 
                else
                    next_state      <= verify_tag;
                end if;
                
            when others => 
                next_state  <= idle;                     
        end case;
    end process Controller;
    
end Behavioral;
