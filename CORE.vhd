library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity CORE is
  generic (
    DATA_WIDTH : integer := 512
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
    -- AXI-Stream to TEMAC
    CORE_OUT_TDATA  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    CORE_OUT_TVALID : out std_logic;
    CORE_OUT_TLAST  : out std_logic;
    CORE_OUT_TKEEP  : out std_logic_vector((DATA_WIDTH / 8) - 1 downto 0);
    CORE_OUT_TREADY : in std_logic
  );
end CORE;

architecture Behavioral of CORE is
  -- Constants
  constant HEADER_SIZE_BYTES  : integer := 42;
  constant PAYLOAD_SAMPLES    : integer := 1024;
  constant PAYLOAD_SIZE_BYTES : integer := (PAYLOAD_SAMPLES * 10 + 7) / 8;
  constant FRAME_SIZE_BYTES   : integer := HEADER_SIZE_BYTES + PAYLOAD_SIZE_BYTES;
  constant BLOCK_SIZE_BYTES   : integer := DATA_WIDTH / 8;
  constant TOTAL_BLOCKS       : integer := (FRAME_SIZE_BYTES + BLOCK_SIZE_BYTES - 1) / BLOCK_SIZE_BYTES;
  constant CLK_FREQ           : integer := 125_000_000;
  constant DELAY_15SEC_CYCLES : integer := 15 * CLK_FREQ;

  -- Ethernet header (42 bytes = 336 bits) - Thứ tự đúng theo chuẩn AXI
  constant header : std_logic_vector(335 downto 0) :=
  x"00" & x"00" & x"1A" & x"00" & x"91" & x"1F" & x"90" & x"1F" &
  x"02" & x"00" & x"00" & x"0A" & x"01" & x"00" & x"00" & x"0A" &
  x"00" & x"00" & x"11" & x"40" & x"00" & x"00" & x"00" & x"01" &
  x"2E" & x"00" & x"00" & x"45" & x"00" & x"08" &
  x"D0" & x"D0" & x"D0" & x"D0" & x"D0" & x"D0" &
  x"11" & x"CF" & x"A8" & x"13" & x"D7" & x"74";

  -- FSM states
  type state_type is (IDLE, WAIT_FULL, PREPARE_HEADER, SEND_HEADER, PREPARE_PAYLOAD, SEND_PAYLOAD, READ_FIFO, WAIT_DELAY);
  signal current_state, next_state : state_type;

  -- Counters and registers
  signal sample_count  : integer range 0 to PAYLOAD_SAMPLES    := 0;
  signal block_count   : integer range 0 to TOTAL_BLOCKS       := 0;
  signal byte_count    : integer range 0 to FRAME_SIZE_BYTES   := 0;
  signal delay_counter : integer range 0 to DELAY_15SEC_CYCLES := 0;
  signal read_counter  : integer range 0 to 63                 := 0;

  -- Data buffers
  signal data_buffer   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal sample_buffer : std_logic_vector(9 downto 0)              := (others => '0');

  -- Buffer cho 4 mẫu 10-bit
  type sample_array is array (0 to 3) of std_logic_vector(9 downto 0);
  signal samples_buffer     : sample_array         := (others => (others => '0'));
  signal sample_buffer_idx  : integer range 0 to 3 := 0;
  signal sample_buffer_full : boolean              := false;

  -- Control signals
  signal tvalid_i            : std_logic                                       := '0';
  signal tlast_i             : std_logic                                       := '0';
  signal tkeep_i             : std_logic_vector((DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
  signal read_fifo_ready     : std_logic                                       := '0';
  signal packing_position    : integer range 0 to 4                            := 0;
  signal bytes_in_last_block : integer range 0 to BLOCK_SIZE_BYTES             := 0;

  -- Internal signals
  signal fifo_rd_en_i : std_logic := '0';
  signal fifo_rd_en_d : std_logic := '0';

begin
  -- FSM state register process
  process (CORE_CLK, CORE_RESET)
  begin
    if CORE_RESET = '1' then
      current_state <= IDLE;
    elsif rising_edge(CORE_CLK) then
      if CORE_ENABLE = '1' then
        current_state <= next_state;
      else
        current_state <= IDLE;
      end if;
    end if;
  end process;

  -- FSM next state logic
  process (current_state, fifo_full, fifo_empty, CORE_ENABLE, block_count, delay_counter,
    sample_count, CORE_OUT_TREADY, tvalid_i, byte_count, read_fifo_ready, sample_buffer_full)
  begin
    next_state <= current_state;

    case current_state is
      when IDLE =>
        if CORE_ENABLE = '1' then
          next_state <= WAIT_FULL;
        end if;

      when WAIT_FULL =>
        if fifo_full = '1' then
          next_state <= PREPARE_HEADER;
        end if;
        if CORE_ENABLE = '0' then
          next_state <= IDLE;
        end if;

      when PREPARE_HEADER =>
        next_state <= SEND_HEADER;

      when SEND_HEADER =>
        if tvalid_i = '1' and CORE_OUT_TREADY = '1' then
          if block_count = 0 then
            next_state <= READ_FIFO;
          else
            next_state <= PREPARE_PAYLOAD;
          end if;
        end if;

      when READ_FIFO =>
        if read_fifo_ready = '1' or sample_count >= PAYLOAD_SAMPLES or sample_buffer_full then
          next_state <= PREPARE_PAYLOAD;
        end if;

      when PREPARE_PAYLOAD =>
        next_state <= SEND_PAYLOAD;

      when SEND_PAYLOAD =>
        if tvalid_i = '1' and CORE_OUT_TREADY = '1' then
          if block_count = TOTAL_BLOCKS - 1 or sample_count >= PAYLOAD_SAMPLES then
            next_state <= WAIT_DELAY;
          else
            next_state <= READ_FIFO;
          end if;
        end if;

      when WAIT_DELAY =>
        if delay_counter = DELAY_15SEC_CYCLES then
          next_state <= IDLE;
        end if;

      when others =>
        next_state <= IDLE;
    end case;
  end process;

  -- Main control process
  process (CORE_CLK, CORE_RESET)
  begin
    if CORE_RESET = '1' then
      sample_count        <= 0;
      block_count         <= 0;
      byte_count          <= 0;
      delay_counter       <= 0;
      read_counter        <= 0;
      tvalid_i            <= '0';
      tlast_i             <= '0';
      tkeep_i             <= (others => '0');
      data_buffer         <= (others => '0');
      fifo_rd_en_i        <= '0';
      fifo_rd_en_d        <= '0';
      read_fifo_ready     <= '0';
      sample_buffer       <= (others => '0');
      bytes_in_last_block <= 0;
      fifo_wr_en          <= '0';
      samples_buffer      <= (others => (others => '0'));
      sample_buffer_idx   <= 0;
      sample_buffer_full  <= false;
      packing_position    <= 0;

    elsif rising_edge(CORE_CLK) then
      fifo_rd_en_i <= '0';
      fifo_rd_en_d <= fifo_rd_en_i;

      if CORE_ENABLE = '1' then
        case current_state is
          when IDLE =>
            sample_count        <= 0;
            block_count         <= 0;
            byte_count          <= 0;
            delay_counter       <= 0;
            read_counter        <= 0;
            tvalid_i            <= '0';
            tlast_i             <= '0';
            tkeep_i             <= (others => '0');
            data_buffer         <= (others => '0');
            read_fifo_ready     <= '0';
            bytes_in_last_block <= FRAME_SIZE_BYTES - (TOTAL_BLOCKS - 1) * BLOCK_SIZE_BYTES;
            fifo_wr_en          <= '1';
            samples_buffer      <= (others => (others => '0'));
            sample_buffer_idx   <= 0;
            sample_buffer_full  <= false;
            packing_position    <= 0;

          when WAIT_FULL =>
            if fifo_full = '1' then
              fifo_wr_en <= '0';
            else
              fifo_wr_en <= '1';
            end if;

          when PREPARE_HEADER =>
            fifo_wr_en  <= '0';
            data_buffer <= (others => '0');

            -- Sao chép header vào data_buffer theo đúng thứ tự AXI (LSB first)
            for i in 0 to HEADER_SIZE_BYTES - 1 loop
              for j in 0 to 7 loop
                data_buffer(i * 8 + j) <= header(i * 8 + j);
              end loop;
            end loop;

            tvalid_i    <= '1';
            tkeep_i     <= (others => '1');
            tlast_i     <= '0';
            block_count <= 0;
            byte_count  <= HEADER_SIZE_BYTES;

          when SEND_HEADER =>
            if tvalid_i = '1' and CORE_OUT_TREADY = '1' then
              tvalid_i    <= '0';
              block_count <= block_count + 1;
            end if;

          when READ_FIFO =>
            fifo_wr_en <= '0';

            if fifo_empty = '0' and sample_count < PAYLOAD_SAMPLES and not sample_buffer_full then
              fifo_rd_en_i <= '1';
            end if;

            if fifo_rd_en_d = '1' then
              samples_buffer(sample_buffer_idx) <= fifo_dout;

              if sample_buffer_idx = 3 then
                sample_buffer_idx  <= 0;
                sample_buffer_full <= true;
              else
                sample_buffer_idx <= sample_buffer_idx + 1;
              end if;

              sample_count <= sample_count + 1;

              if sample_buffer_idx = 3 or sample_count = PAYLOAD_SAMPLES - 1 then
                read_fifo_ready <= '1';
              end if;
            else
              if sample_count >= PAYLOAD_SAMPLES then
                read_fifo_ready <= '1';
              end if;
            end if;

          when PREPARE_PAYLOAD =>
            fifo_wr_en      <= '0';
            read_fifo_ready <= '0';
            data_buffer     <= (others => '0');

            -- Đóng gói 4 mẫu 10-bit thành 5 byte theo thứ tự LSB first
            if sample_count > 0 and byte_count < FRAME_SIZE_BYTES then
              if sample_buffer_idx > 0 or sample_buffer_full then
                case packing_position is
                  when 0 =>
                    -- Byte 0: 8 bit đầu của mẫu 0
                    for j in 0 to 7 loop
                      data_buffer(read_counter * 8 + j) <= samples_buffer(0)(j);
                    end loop;
                    read_counter     <= (read_counter + 1) mod BLOCK_SIZE_BYTES;
                    packing_position <= 1;

                  when 1 =>
                    if (sample_buffer_full) or (sample_buffer_idx >= 2) then
                      -- Byte 1: 2 bit cuối của mẫu 0 + 6 bit đầu của mẫu 1
                      data_buffer(read_counter * 8)     <= samples_buffer(0)(8);
                      data_buffer(read_counter * 8 + 1) <= samples_buffer(0)(9);
                      for j in 0 to 5 loop
                        data_buffer(read_counter * 8 + 2 + j) <= samples_buffer(1)(j);
                      end loop;
                      read_counter     <= (read_counter + 1) mod BLOCK_SIZE_BYTES;
                      packing_position <= 2;
                    end if;

                  when 2 =>
                    if (sample_buffer_full) or (sample_buffer_idx >= 3) then
                      -- Byte 2: 4 bit cuối của mẫu 1 + 4 bit đầu của mẫu 2
                      for j in 0 to 3 loop
                        data_buffer(read_counter * 8 + j) <= samples_buffer(1)(6 + j);
                      end loop;
                      for j in 0 to 3 loop
                        data_buffer(read_counter * 8 + 4 + j) <= samples_buffer(2)(j);
                      end loop;
                      read_counter     <= (read_counter + 1) mod BLOCK_SIZE_BYTES;
                      packing_position <= 3;
                    end if;

                  when 3 =>
                    if sample_buffer_full then
                      -- Byte 3: 6 bit cuối của mẫu 2 + 2 bit đầu của mẫu 3
                      for j in 0 to 5 loop
                        data_buffer(read_counter * 8 + j) <= samples_buffer(2)(4 + j);
                      end loop;
                      for j in 0 to 1 loop
                        data_buffer(read_counter * 8 + 6 + j) <= samples_buffer(3)(j);
                      end loop;
                      read_counter     <= (read_counter + 1) mod BLOCK_SIZE_BYTES;
                      packing_position <= 4;
                    end if;

                  when 4 =>
                    if sample_buffer_full then
                      -- Byte 4: 8 bit cuối của mẫu 3
                      for j in 0 to 7 loop
                        data_buffer(read_counter * 8 + j) <= samples_buffer(3)(2 + j);
                      end loop;
                      read_counter <= (read_counter + 1) mod BLOCK_SIZE_BYTES;
                    end if;

                    packing_position   <= 0;
                    byte_count         <= byte_count + 5;
                    sample_buffer_full <= false;

                  when others =>
                    packing_position <= 0;
                end case;
              end if;
            end if;

            tvalid_i <= '1';

            if block_count = TOTAL_BLOCKS - 1 or sample_count >= PAYLOAD_SAMPLES then
              tlast_i <= '1';
              -- Thiết lập tkeep cho block cuối theo thứ tự LSB first
              for i in 0 to BLOCK_SIZE_BYTES - 1 loop
                if i < bytes_in_last_block then
                  tkeep_i(i) <= '1';
                else
                  tkeep_i(i) <= '0';
                end if;
              end loop;
            else
              tlast_i <= '0';
              tkeep_i <= (others => '1');
            end if;

          when SEND_PAYLOAD =>
            if tvalid_i = '1' and CORE_OUT_TREADY = '1' then
              tvalid_i <= '0';
              if tlast_i = '0' then
                block_count <= block_count + 1;
              end if;
            end if;

          when WAIT_DELAY =>
            tvalid_i <= '0';
            tlast_i  <= '0';
            tkeep_i  <= (others => '0');

            if delay_counter < DELAY_15SEC_CYCLES then
              delay_counter <= delay_counter + 1;
            else
              sample_count       <= 0;
              block_count        <= 0;
              byte_count         <= 0;
              read_counter       <= 0;
              sample_buffer_idx  <= 0;
              sample_buffer_full <= false;
              packing_position   <= 0;
            end if;

          when others =>
            null;
        end case;
      else
        tvalid_i     <= '0';
        tlast_i      <= '0';
        fifo_rd_en_i <= '0';
        fifo_wr_en   <= '0';
      end if;
    end if;
  end process;

  -- Output assignments
  CORE_OUT_TDATA  <= data_buffer;
  CORE_OUT_TVALID <= tvalid_i;
  CORE_OUT_TLAST  <= tlast_i;
  CORE_OUT_TKEEP  <= tkeep_i;
  fifo_rd_en      <= fifo_rd_en_i;

end Behavioral;