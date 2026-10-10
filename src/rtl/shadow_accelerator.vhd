library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity shadow_accelerator is
  generic (
    DIM        : positive := 24;
    ADDR_WIDTH : positive := 12;
    DATA_WIDTH : positive := 32;
    FRAC_BITS  : positive := 16
  );
  port (
    s_axi_aclk    : in  std_logic;
    s_axi_aresetn : in  std_logic;
    s_axi_awaddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    s_axi_wstrb   : in  std_logic_vector(DATA_WIDTH/8-1 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    irq           : out std_logic
  );
end entity;

architecture rtl of shadow_accelerator is
  type hash_t is array (0 to 7) of std_logic_vector(31 downto 0);

  function merge_bytes(
    old_value : std_logic_vector(31 downto 0);
    new_value : std_logic_vector(31 downto 0);
    strobes   : std_logic_vector(3 downto 0)
  ) return std_logic_vector is
    variable result_v : std_logic_vector(31 downto 0) := old_value;
  begin
    for byte_idx in 0 to 3 loop
      if strobes(byte_idx) = '1' then
        result_v(8*byte_idx+7 downto 8*byte_idx) := new_value(8*byte_idx+7 downto 8*byte_idx);
      end if;
    end loop;
    return result_v;
  end function;

  signal aw_pending, w_pending : std_logic := '0';
  signal awaddr_i              : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
  signal wdata_i               : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb_i               : std_logic_vector(3 downto 0) := (others => '0');
  signal ctrl, dimension, sequence_reg, epoch, deadline_reg : std_logic_vector(31 downto 0) := (others => '0');
  signal model_hash, config_hash : hash_t := (others => (others => '0'));
  signal done_latched, error_latched, sat_latched : std_logic := '0';
  signal core_start, core_cancel, core_busy, core_done, core_sat, core_error : std_logic := '0';
  signal core_q : std_logic_vector(63 downto 0);
  signal core_y, core_cycles : std_logic_vector(31 downto 0);
  signal core_dim : std_logic_vector(4 downto 0);
  signal core_mem_we : std_logic;
  signal commit_write : std_logic;
  signal cancel_pending : std_logic;
  signal bvalid_i, rvalid_i : std_logic := '0';
  signal bresp_i, rresp_i : std_logic_vector(1 downto 0) := (others => '0');
  signal rdata_i : std_logic_vector(31 downto 0) := (others => '0');
  signal result_index : std_logic_vector(4 downto 0);
begin
  assert DATA_WIDTH = 32 report "shadow_accelerator requires 32-bit AXI data" severity failure;
  assert ADDR_WIDTH = 12 report "shadow_accelerator requires a 4 KiB aperture" severity failure;
  assert DIM = 24 report "shadow_accelerator storage is fixed at dimension 24" severity failure;
  assert FRAC_BITS = 16 report "shadow_accelerator arithmetic is fixed at Q16.16" severity failure;

  s_axi_awready <= '1' when aw_pending = '0' and bvalid_i = '0' else '0';
  s_axi_wready  <= '1' when w_pending = '0' and bvalid_i = '0' else '0';
  s_axi_arready <= not rvalid_i;
  s_axi_bvalid  <= bvalid_i;
  s_axi_bresp   <= bresp_i;
  s_axi_rvalid  <= rvalid_i;
  s_axi_rresp   <= rresp_i;
  s_axi_rdata   <= rdata_i;
  irq <= ctrl(2) and done_latched;

  commit_write <= aw_pending and w_pending and not bvalid_i;
  cancel_pending <= '1' when commit_write = '1' and awaddr_i = std_logic_vector(to_unsigned(0, ADDR_WIDTH)) and
                    ((wstrb_i(0) = '1' and wdata_i(1) = '1') or (wstrb_i(0) = '0' and ctrl(1) = '1')) else '0';
  core_dim <= dimension(4 downto 0) when unsigned(dimension) <= 24 else (others => '0');
  core_mem_we <= '1' when commit_write = '1' and core_start = '0' and awaddr_i(1 downto 0) = "00" else '0';
  result_index <= std_logic_vector(resize(shift_right(unsigned(s_axi_araddr) - to_unsigned(16#A80#, ADDR_WIDTH), 2), 5));

  core_inst : entity work.shadow_core
    port map (
      clk => s_axi_aclk, rst_n => s_axi_aresetn, start => core_start, cancel => core_cancel,
      dim => core_dim, mem_we => core_mem_we, mem_addr => awaddr_i,
      mem_data => wdata_i, mem_strb => wstrb_i, result_addr => result_index,
      result_data => core_y, quadratic => core_q, busy => core_busy, done => core_done,
      saturated => core_sat, error => core_error, cycles => core_cycles
    );

  process(s_axi_aclk)
    variable addr_v, index_v : natural;
    variable next_ctrl_v, read_v : std_logic_vector(31 downto 0);
  begin
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn = '0' then
        aw_pending <= '0'; w_pending <= '0';
        awaddr_i <= (others => '0'); wdata_i <= (others => '0'); wstrb_i <= (others => '0');
        bvalid_i <= '0'; bresp_i <= (others => '0');
        rvalid_i <= '0'; rdata_i <= (others => '0'); rresp_i <= (others => '0');
        ctrl <= (others => '0'); dimension <= std_logic_vector(to_unsigned(24, 32));
        sequence_reg <= (others => '0'); epoch <= (others => '0'); deadline_reg <= (others => '0');
        model_hash <= (others => (others => '0')); config_hash <= (others => (others => '0'));
        core_start <= '0'; core_cancel <= '0';
        done_latched <= '0'; error_latched <= '0'; sat_latched <= '0';
      else
        core_start <= '0';
        core_cancel <= '0';

        if core_done = '1' and core_cancel = '0' and cancel_pending = '0' then
          done_latched <= '1';
          error_latched <= core_error;
          sat_latched <= core_sat;
        end if;

        if s_axi_awvalid = '1' and aw_pending = '0' and bvalid_i = '0' then
          awaddr_i <= s_axi_awaddr;
          aw_pending <= '1';
        end if;
        if s_axi_wvalid = '1' and w_pending = '0' and bvalid_i = '0' then
          wdata_i <= s_axi_wdata;
          wstrb_i <= s_axi_wstrb;
          w_pending <= '1';
        end if;
        if bvalid_i = '1' and s_axi_bready = '1' then bvalid_i <= '0'; end if;

        if commit_write = '1' then
          aw_pending <= '0'; w_pending <= '0'; bvalid_i <= '1'; bresp_i <= "00";
          addr_v := to_integer(unsigned(awaddr_i));
          if awaddr_i(1 downto 0) /= "00" then
            bresp_i <= "10";
          elsif addr_v = 16#000# then
            next_ctrl_v := merge_bytes(ctrl, wdata_i, wstrb_i);
            ctrl <= next_ctrl_v and x"00000005";
            if next_ctrl_v(1) = '1' then
              core_cancel <= '1'; ctrl <= (others => '0');
              done_latched <= '0'; error_latched <= '0'; sat_latched <= '0';
            elsif next_ctrl_v(0) = '1' and ctrl(0) = '0' then
              if core_busy = '1' or core_start = '1' then
                bresp_i <= "10";
                ctrl <= next_ctrl_v and x"00000004";
              else
                core_start <= '1';
                done_latched <= '0'; error_latched <= '0'; sat_latched <= '0';
              end if;
            elsif next_ctrl_v(0) = '0' then
              done_latched <= '0';
            end if;
          elsif core_busy = '1' or core_start = '1' then
            bresp_i <= "10";
          else
            case addr_v is
              when 16#008# => dimension <= merge_bytes(dimension, wdata_i, wstrb_i);
              when 16#00C# => sequence_reg <= merge_bytes(sequence_reg, wdata_i, wstrb_i);
              when 16#010# => model_hash(0) <= merge_bytes(model_hash(0), wdata_i, wstrb_i);
              when 16#014# => model_hash(1) <= merge_bytes(model_hash(1), wdata_i, wstrb_i);
              when 16#018# => model_hash(2) <= merge_bytes(model_hash(2), wdata_i, wstrb_i);
              when 16#01C# => model_hash(3) <= merge_bytes(model_hash(3), wdata_i, wstrb_i);
              when 16#020# => model_hash(4) <= merge_bytes(model_hash(4), wdata_i, wstrb_i);
              when 16#024# => model_hash(5) <= merge_bytes(model_hash(5), wdata_i, wstrb_i);
              when 16#028# => model_hash(6) <= merge_bytes(model_hash(6), wdata_i, wstrb_i);
              when 16#02C# => model_hash(7) <= merge_bytes(model_hash(7), wdata_i, wstrb_i);
              when 16#030# => config_hash(0) <= merge_bytes(config_hash(0), wdata_i, wstrb_i);
              when 16#034# => config_hash(1) <= merge_bytes(config_hash(1), wdata_i, wstrb_i);
              when 16#038# => config_hash(2) <= merge_bytes(config_hash(2), wdata_i, wstrb_i);
              when 16#03C# => config_hash(3) <= merge_bytes(config_hash(3), wdata_i, wstrb_i);
              when 16#040# => config_hash(4) <= merge_bytes(config_hash(4), wdata_i, wstrb_i);
              when 16#044# => config_hash(5) <= merge_bytes(config_hash(5), wdata_i, wstrb_i);
              when 16#048# => config_hash(6) <= merge_bytes(config_hash(6), wdata_i, wstrb_i);
              when 16#04C# => config_hash(7) <= merge_bytes(config_hash(7), wdata_i, wstrb_i);
              when 16#050# => epoch <= merge_bytes(epoch, wdata_i, wstrb_i);
              when 16#054# => deadline_reg <= merge_bytes(deadline_reg, wdata_i, wstrb_i);
              when others =>
                if not ((addr_v >= 16#100# and addr_v < 16#A00#) or
                           (addr_v >= 16#A00# and addr_v < 16#A60#)) then
                  bresp_i <= "10";
                end if;
            end case;
          end if;
        end if;

        if rvalid_i = '1' and s_axi_rready = '1' then rvalid_i <= '0'; end if;
        if s_axi_arvalid = '1' and rvalid_i = '0' then
          rvalid_i <= '1'; rresp_i <= "00"; read_v := (others => '0');
          addr_v := to_integer(unsigned(s_axi_araddr));
          if s_axi_araddr(1 downto 0) /= "00" then
            rresp_i <= "10";
          else
            case addr_v is
              when 16#000# => read_v := ctrl;
              when 16#004# =>
                read_v(0) := not (core_busy or core_start);
                read_v(1) := core_busy or core_start;
                read_v(2) := done_latched;
                read_v(3) := error_latched;
                read_v(4) := sat_latched;
              when 16#008# => read_v := dimension;
              when 16#00C# => read_v := sequence_reg;
              when 16#010# => read_v := model_hash(0);
              when 16#014# => read_v := model_hash(1);
              when 16#018# => read_v := model_hash(2);
              when 16#01C# => read_v := model_hash(3);
              when 16#020# => read_v := model_hash(4);
              when 16#024# => read_v := model_hash(5);
              when 16#028# => read_v := model_hash(6);
              when 16#02C# => read_v := model_hash(7);
              when 16#030# => read_v := config_hash(0);
              when 16#034# => read_v := config_hash(1);
              when 16#038# => read_v := config_hash(2);
              when 16#03C# => read_v := config_hash(3);
              when 16#040# => read_v := config_hash(4);
              when 16#044# => read_v := config_hash(5);
              when 16#048# => read_v := config_hash(6);
              when 16#04C# => read_v := config_hash(7);
              when 16#050# => read_v := epoch;
              when 16#054# => read_v := deadline_reg;
              when 16#058# => read_v := core_cycles;
              when 16#05C# => read_v := x"53484431";
              when 16#B00# =>
                if done_latched = '1' then read_v := core_q(31 downto 0); else rresp_i <= "10"; end if;
              when 16#B04# =>
                if done_latched = '1' then read_v := core_q(63 downto 32); else rresp_i <= "10"; end if;
              when 16#B08# =>
                if done_latched = '1' then read_v(0) := sat_latched; else rresp_i <= "10"; end if;
              when others =>
                if addr_v >= 16#A80# and addr_v < 16#AE0# then
                  if done_latched = '1' then read_v := core_y; else rresp_i <= "10"; end if;
                else
                  rresp_i <= "10";
                end if;
            end case;
          end if;
          rdata_i <= read_v;
        end if;
      end if;
    end if;
  end process;
end architecture;
