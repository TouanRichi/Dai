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
  constant HEADER_SIZE_BYTES       : integer := 44; -- Header size (44 bytes)
  constant PAYLOAD_SAMPLES         : integer := 1024; -- Số mẫu trong mỗi frame
  constant SAMPLES_PER_BLOCK       : integer := 48; -- 48 mẫu / block (60 bytes)
  constant BLOCK_SIZE_BYTES        : integer := DATA_WIDTH / 8; -- 64 bytes per block
  constant PAYLOAD_BYTES_PER_BLOCK : integer := 60; -- 60 bytes payload per block
  constant CLK_FREQ                : integer := 125_000_000;
  constant DELAY_15SEC_CYCLES      : integer := 15 * CLK_FREQ;
  constant MAX_PACKS_PER_BLOCK     : integer := SAMPLES_PER_BLOCK / 4; -- Maximum number of 4-sample packs per block

  -- Số block cần thiết cho tất cả các mẫu (tính cả header và block cuối)
  constant NUM_PAYLOAD_BLOCKS : integer := (PAYLOAD_SAMPLES + SAMPLES_PER_BLOCK - 1) / SAMPLES_PER_BLOCK;
  constant TOTAL_BLOCKS       : integer := NUM_PAYLOAD_BLOCKS + 1; -- +1 cho header block
  constant SAMPLES_LAST_BLOCK : integer := PAYLOAD_SAMPLES - (NUM_PAYLOAD_BLOCKS - 1) * SAMPLES_PER_BLOCK;
  -- Số byte trong block cuối
  constant BYTES_LAST_BLOCK : integer := (SAMPLES_LAST_BLOCK * 10 + 7) / 8;

  -- Ethernet header (44 bytes = 352 bits) - LSB first theo AXI
  constant header : std_logic_vector(351 downto 0) :=
  x"00" & x"00" & x"1A" & x"00" & x"91" & x"1F" & x"90" & x"1F" &
  x"02" & x"00" & x"00" & x"0A" & x"01" & x"00" & x"00" & x"0A" &
  x"00" & x"00" & x"11" & x"40" & x"00" & x"00" & x"00" & x"01" &
  x"2E" & x"00" & x"00" & x"45" & x"00" & x"08" &
  x"D0" & x"D0" & x"D0" & x"D0" & x"D0" & x"D0" &
  x"11" & x"CF" & x"A8" & x"13" & x"D7" & x"74" & x"00" & x"00";

  -- FSM states
  type state_type is (IDLE, WAIT_DELAY, WAIT_FULL, PREPARE_HEADER, SEND_HEADER,
    READ_FIFO, PREPARE_PAYLOAD, SEND_PAYLOAD);
  signal current_state, next_state : state_type;

  -- Counters and registers
  signal sample_count     : integer range 0 to PAYLOAD_SAMPLES    := 0;
  signal block_count      : integer range 0 to TOTAL_BLOCKS       := 0;
  signal delay_counter    : integer range 0 to DELAY_15SEC_CYCLES := 0;
  signal bytes_in_block   : integer range 0 to BLOCK_SIZE_BYTES   := 0;
  signal samples_in_block : integer range 0 to SAMPLES_PER_BLOCK  := 0;

  -- Data buffers
  signal data_buffer   : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
  signal sample_buffer : std_logic_vector(9 downto 0)              := (others => '0');

  -- Buffer cho 4 mẫu 10-bit
  type sample_array is array (0 to SAMPLES_PER_BLOCK - 1) of std_logic_vector(9 downto 0);
  signal samples_buffer    : sample_array                             := (others => (others => '0'));
  signal sample_buffer_idx : integer range 0 to SAMPLES_PER_BLOCK - 1 := 0;
  signal rem_samples       : integer range 0 to 3                     := 0; -- Số lượng mẫu dư trong nhóm cuối cùng

  -- Control signals
  signal tvalid_i               : std_logic                                       := '0';
  signal tlast_i                : std_logic                                       := '0';
  signal tkeep_i                : std_logic_vector((DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
  signal read_fifo_ready        : std_logic                                       := '0';
  signal is_last_block          : boolean                                         := false;
  signal remaining_samples      : integer range 0 to PAYLOAD_SAMPLES              := 0;
  signal valid_bytes_last_block : integer range 0 to BLOCK_SIZE_BYTES             := 0;

  -- Internal signals
  signal fifo_rd_en_i : std_logic := '0';
  signal fifo_rd_en_d : std_logic := '0';
  signal first_boot   : boolean   := true; -- Flag cho lần khởi động đầu tiên

begin
  -- FSM state register process
  process (CORE_CLK, CORE_RESET)
  begin
    if CORE_RESET = '1' then
      current_state <= IDLE;
      first_boot    <= true;
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
    sample_count, CORE_OUT_TREADY, tvalid_i, read_fifo_ready, first_boot)
  begin
    next_state <= current_state;

    case current_state is
      when IDLE =>
        if CORE_ENABLE = '1' then
          if first_boot then
            -- Chỉ vào WAIT_DELAY ở lần khởi động đầu tiên
            next_state <= WAIT_DELAY;
          else
            next_state <= WAIT_FULL;
          end if;
        end if;

      when WAIT_DELAY =>
        if delay_counter = DELAY_15SEC_CYCLES then
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
          next_state <= READ_FIFO;
        end if;

      when READ_FIFO =>
        if read_fifo_ready = '1' or sample_count >= PAYLOAD_SAMPLES then
          next_state <= PREPARE_PAYLOAD;
        end if;

      when PREPARE_PAYLOAD =>
        next_state <= SEND_PAYLOAD;

      when SEND_PAYLOAD =>
        if tvalid_i = '1' and CORE_OUT_TREADY = '1' then
          if block_count >= TOTAL_BLOCKS - 1 or sample_count >= PAYLOAD_SAMPLES then
            -- Nếu đã gửi đủ số block hoặc đã gửi đủ số mẫu, quay lại IDLE
            next_state <= IDLE;
          else
            -- Tiếp tục đọc FIFO cho block tiếp theo
            next_state <= READ_FIFO;
          end if;
        end if;

      when others =>
        next_state <= IDLE;
    end case;
  end process;

  -- Main control process
  process (CORE_CLK, CORE_RESET)
  begin
    if CORE_RESET = '1' then
      sample_count           <= 0;
      block_count            <= 0;
      delay_counter          <= 0;
      bytes_in_block         <= 0;
      samples_in_block       <= 0;
      tvalid_i               <= '0';
      tlast_i                <= '0';
      tkeep_i                <= (others => '0');
      data_buffer            <= (others => '0');
      fifo_rd_en_i           <= '0';
      fifo_rd_en_d           <= '0';
      read_fifo_ready        <= '0';
      sample_buffer          <= (others => '0');
      fifo_wr_en             <= '0';
      samples_buffer         <= (others => (others => '0'));
      sample_buffer_idx      <= 0;
      is_last_block          <= false;
      first_boot             <= true;
      remaining_samples      <= 0;
      valid_bytes_last_block <= 0;
      rem_samples            <= 0;

    elsif rising_edge(CORE_CLK) then
      fifo_rd_en_i <= '0';
      fifo_rd_en_d <= fifo_rd_en_i;

      if CORE_ENABLE = '1' then
        case current_state is
          when IDLE =>
            sample_count           <= 0;
            block_count            <= 0;
            bytes_in_block         <= 0;
            samples_in_block       <= 0;
            tvalid_i               <= '0';
            tlast_i                <= '0';
            tkeep_i                <= (others => '0');
            data_buffer            <= (others => '0');
            read_fifo_ready        <= '0';
            fifo_wr_en             <= '1';
            samples_buffer         <= (others => (others => '0'));
            sample_buffer_idx      <= 0;
            is_last_block          <= false;
            remaining_samples      <= PAYLOAD_SAMPLES;
            valid_bytes_last_block <= 0;
            rem_samples            <= 0;
            -- Không reset first_boot ở đây

          when WAIT_DELAY =>
            fifo_wr_en <= '0';
            tvalid_i   <= '0';
            tlast_i    <= '0';
            tkeep_i    <= (others => '0');

            if delay_counter < DELAY_15SEC_CYCLES then
              delay_counter <= delay_counter + 1;
            else
              delay_counter <= 0;
              first_boot    <= false; -- Đánh dấu đã qua giai đoạn khởi động
            end if;

          when WAIT_FULL =>
            if fifo_full = '1' then
              fifo_wr_en <= '0';
            else
              fifo_wr_en <= '1';
            end if;

          when PREPARE_HEADER =>
            fifo_wr_en     <= '0';
            data_buffer    <= (others => '0');
            bytes_in_block <= HEADER_SIZE_BYTES;

            -- Sao chép header vào data_buffer theo đúng thứ tự LSB first
            -- Header được định nghĩa với byte thấp nhất (LSB) ở vị trí 0
            for i in 0 to HEADER_SIZE_BYTES - 1 loop
              for j in 0 to 7 loop
                data_buffer(i * 8 + j) <= header(i * 8 + j);
              end loop;
            end loop;

            tvalid_i <= '1';

            -- Thiết lập tkeep cho header block (chỉ 44 byte đầu tiên là hợp lệ)
            for i in 0 to BLOCK_SIZE_BYTES - 1 loop
              if i < HEADER_SIZE_BYTES then
                tkeep_i(i) <= '1';
              else
                tkeep_i(i) <= '0';
              end if;
            end loop;

            tlast_i     <= '0'; -- Header không phải là block cuối
            block_count <= 0;

          when SEND_HEADER =>
            if tvalid_i = '1' and CORE_OUT_TREADY = '1' then
              tvalid_i    <= '0';
              block_count <= block_count + 1;
            end if;

          when READ_FIFO =>
            fifo_wr_en       <= '0';
            read_fifo_ready  <= '0';
            bytes_in_block   <= 0;
            samples_in_block <= 0;
            data_buffer      <= (others => '0');

            -- Xác định số mẫu còn lại phải gửi
            remaining_samples <= PAYLOAD_SAMPLES - sample_count;

            -- Xác định đây có phải là block cuối không
            is_last_block <= (block_count = TOTAL_BLOCKS - 1) or
              (sample_count + SAMPLES_PER_BLOCK >= PAYLOAD_SAMPLES);

            -- Tính số byte hợp lệ trong block cuối
            if is_last_block then
              -- Số mẫu trong block cuối
              if remaining_samples < SAMPLES_PER_BLOCK then
                -- Số byte cần cho các mẫu còn lại (4 mẫu 10-bit = 5 byte)
                valid_bytes_last_block <= (remaining_samples * 10 + 7) / 8;
              else
                valid_bytes_last_block <= PAYLOAD_BYTES_PER_BLOCK;
              end if;
            end if;

            -- Đọc mẫu từ FIFO
            if fifo_empty = '0' and sample_count < PAYLOAD_SAMPLES then
              if samples_in_block < SAMPLES_PER_BLOCK and
                (not is_last_block or samples_in_block < remaining_samples) then
                fifo_rd_en_i <= '1';
              end if;
            end if;

            if fifo_rd_en_d = '1' then
              samples_buffer(sample_buffer_idx) <= fifo_dout;
              sample_buffer_idx                 <= sample_buffer_idx + 1;
              samples_in_block                  <= samples_in_block + 1;
              sample_count                      <= sample_count + 1;

              -- Sẵn sàng chuẩn bị payload khi:
              -- 1. Đạt đủ số mẫu cho mỗi block (48 mẫu) hoặc
              -- 2. Đã đọc đủ tổng số mẫu cho block cuối hoặc
              -- 3. Đã đọc hết FIFO
              if samples_in_block + 1 >= SAMPLES_PER_BLOCK or
                sample_count + 1 >= PAYLOAD_SAMPLES or
                (fifo_empty = '1' and sample_count > 0) then
                read_fifo_ready <= '1';
              end if;
            end if;

          when PREPARE_PAYLOAD =>
            fifo_wr_en  <= '0';
            data_buffer <= (others => '0');

            -- Đóng gói các mẫu 10-bit thành các byte theo thứ tự LSB first
            -- Mỗi 4 mẫu 10-bit được đóng gói thành 5 byte
            -- Công thức: [AAAAAAAA] [AABBBBBB] [BBBBCCCC] [CCCCCCDD] [DDDDDDDD]

            -- Xử lý các nhóm đầy đủ 4 mẫu
            for i in 0 to MAX_PACKS_PER_BLOCK - 1 loop
              if i * 4 < samples_in_block then
                -- Byte 0: 8 bit đầu của mẫu 0
                for j in 0 to 7 loop
                  data_buffer(i * 40 + j) <= samples_buffer(i * 4)(j);
                end loop;

                -- Byte 1: 2 bit cuối của mẫu 0 + 6 bit đầu của mẫu 1
                data_buffer(i * 40 + 8) <= samples_buffer(i * 4)(8);
                data_buffer(i * 40 + 9) <= samples_buffer(i * 4)(9);

                -- Chỉ thêm mẫu thứ 2 nếu có đủ mẫu
                if i * 4 + 1 < samples_in_block then
                  for j in 0 to 5 loop
                    data_buffer(i * 40 + 10 + j) <= samples_buffer(i * 4 + 1)(j);
                  end loop;

                  -- Byte 2: 4 bit cuối của mẫu 1 + 4 bit đầu của mẫu 2
                  for j in 0 to 3 loop
                    data_buffer(i * 40 + 16 + j) <= samples_buffer(i * 4 + 1)(j + 6);
                  end loop;

                  -- Chỉ thêm mẫu thứ 3 nếu có đủ mẫu
                  if i * 4 + 2 < samples_in_block then
                    for j in 0 to 3 loop
                      data_buffer(i * 40 + 20 + j) <= samples_buffer(i * 4 + 2)(j);
                    end loop;

                    -- Byte 3: 6 bit cuối của mẫu 2 + 2 bit đầu của mẫu 3
                    for j in 0 to 5 loop
                      data_buffer(i * 40 + 24 + j) <= samples_buffer(i * 4 + 2)(j + 4);
                    end loop;

                    -- Chỉ thêm mẫu thứ 4 nếu đây là nhóm đầy đủ
                    if i * 4 + 3 < samples_in_block then
                      for j in 0 to 1 loop
                        data_buffer(i * 40 + 30 + j) <= samples_buffer(i * 4 + 3)(j);
                      end loop;

                      -- Byte 4: 8 bit cuối của mẫu 3
                      for j in 0 to 7 loop
                        data_buffer(i * 40 + 32 + j) <= samples_buffer(i * 4 + 3)(j + 2);
                      end loop;
                    end if;
                  end if;
                end if;
              end if;
            end loop;

            -- Xác định số mẫu dư trong nhóm cuối
            rem_samples <= samples_in_block mod 4;

            tvalid_i <= '1';

            -- Thiết lập tkeep cho payload block
            if is_last_block then
              -- Nếu là block cuối, chỉ set tkeep cho số byte thực tế sử dụng
              tlast_i <= '1';
              for i in 0 to BLOCK_SIZE_BYTES - 1 loop
                if i < valid_bytes_last_block then
                  tkeep_i(i) <= '1';
                else
                  tkeep_i(i) <= '0';
                end if;
              end loop;
            else
              -- Nếu không phải block cuối, set 60 byte đầu là hợp lệ
              tlast_i <= '0';
              for i in 0 to BLOCK_SIZE_BYTES - 1 loop
                if i < PAYLOAD_BYTES_PER_BLOCK then
                  tkeep_i(i) <= '1';
                else
                  tkeep_i(i) <= '0';
                end if;
              end loop;
            end if;

          when SEND_PAYLOAD =>
            if tvalid_i = '1' and CORE_OUT_TREADY = '1' then
              tvalid_i <= '0';
              if tlast_i = '0' then
                block_count <= block_count + 1;
              end if;
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