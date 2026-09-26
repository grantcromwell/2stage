library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;



entity hls_shadow_core is
  port (clk:in std_logic; rst_n:in std_logic; start:in std_logic; cancel:in std_logic;
        dim:in std_logic_vector(4 downto 0); mem_we:in std_logic;
        mem_addr:in std_logic_vector(11 downto 0); mem_data:in std_logic_vector(31 downto 0);
        mem_strb:in std_logic_vector(3 downto 0); result_addr:in std_logic_vector(4 downto 0);
        result_data:out std_logic_vector(31 downto 0); quadratic:out std_logic_vector(63 downto 0);
        busy:out std_logic; done:out std_logic; saturated:out std_logic; error:out std_logic;
        cycles:out std_logic_vector(31 downto 0));
end entity;

architecture rtl of hls_shadow_core is
  type matrix_t is array (0 to 575) of std_logic_vector(31 downto 0);
  type vector_t is array (0 to 23) of std_logic_vector(31 downto 0);
  signal matrix_mem : matrix_t := (others => (others => '0'));
  signal vector_mem, direction_mem : vector_t := (others => (others => '0'));
  signal ap_start_i, ap_done_i, ap_idle_i, ap_ready_i : std_logic := '0';
  signal matrix_addr : std_logic_vector(9 downto 0); signal matrix_ce : std_logic;
  signal vector_addr, direction_addr : std_logic_vector(4 downto 0);
  signal vector_ce, direction_ce, direction_we : std_logic;
  signal matrix_q, vector_q : std_logic_vector(31 downto 0) := (others => '0');
  signal direction_d : std_logic_vector(31 downto 0);
  signal q_i : std_logic_vector(63 downto 0); signal q_vld : std_logic;
  signal sat_i, err_i : std_logic_vector(0 downto 0);
  signal sat_vld, err_vld : std_logic;
  signal busy_i, done_i, saturated_i, error_i : std_logic := '0';
  signal q_latched : std_logic_vector(63 downto 0) := (others => '0');
  signal cycle_i : unsigned(31 downto 0) := (others => '0');
begin
  u_hls: entity work.shadow_hls
    port map (ap_clk=>clk, ap_rst=>not rst_n, ap_start=>ap_start_i, ap_done=>ap_done_i,
      ap_idle=>ap_idle_i, ap_ready=>ap_ready_i, matrix_address0=>matrix_addr,
      matrix_ce0=>matrix_ce, matrix_q0=>matrix_q,
      vector_address0=>vector_addr, vector_ce0=>vector_ce,
      vector_q0=>vector_q, dim=>dim,
      direction_address0=>direction_addr, direction_ce0=>direction_ce,
      direction_we0=>direction_we, direction_d0=>direction_d, quadratic=>q_i,
      quadratic_ap_vld=>q_vld, saturated=>sat_i, saturated_ap_vld=>sat_vld,
      error=>err_i, error_ap_vld=>err_vld);
  result_data <= direction_mem(to_integer(unsigned(result_addr))) when unsigned(result_addr) < 24 else (others=>'0');
  busy <= busy_i; done <= done_i; saturated <= saturated_i; error <= error_i;
  quadratic <= q_latched; cycles <= std_logic_vector(cycle_i);
  process(clk)
    variable a : natural; variable old : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if matrix_ce='1' and unsigned(matrix_addr)<576 then
        matrix_q<=matrix_mem(to_integer(unsigned(matrix_addr)));
      end if;
      if vector_ce='1' and unsigned(vector_addr)<24 then
        vector_q<=vector_mem(to_integer(unsigned(vector_addr)));
      end if;
      ap_start_i <= '0'; done_i <= '0';
      if rst_n='0' then busy_i<='0'; saturated_i<='0'; error_i<='0'; q_latched<=(others=>'0'); cycle_i<=(others=>'0');
      else
        if mem_we='1' and busy_i='0' then
          a:=to_integer(unsigned(mem_addr)); old:=mem_data;
          if a>=16#100# and a<16#A00# then
            old:=matrix_mem((a-16#100#)/4); for b in 0 to 3 loop if mem_strb(b)='1' then old(8*b+7 downto 8*b):=mem_data(8*b+7 downto 8*b); end if; end loop; matrix_mem((a-16#100#)/4)<=old;
          elsif a>=16#A00# and a<16#A60# then
            old:=vector_mem((a-16#A00#)/4); for b in 0 to 3 loop if mem_strb(b)='1' then old(8*b+7 downto 8*b):=mem_data(8*b+7 downto 8*b); end if; end loop; vector_mem((a-16#A00#)/4)<=old;
          end if;
        end if;
        if cancel='1' then busy_i<='0';
        elsif start='1' and busy_i='0' then busy_i<='1'; ap_start_i<='1'; saturated_i<='0'; error_i<='0'; q_latched<=(others=>'0'); cycle_i<=(others=>'0'); direction_mem<=(others=>(others=>'0'));
        elsif busy_i='1' then cycle_i<=cycle_i+1; if ap_done_i='1' then busy_i<='0'; done_i<='1'; end if;
        end if;
        if direction_we='1' then direction_mem(to_integer(unsigned(direction_addr)))<=direction_d; end if;
        if q_vld='1' then q_latched<=q_i; end if;
        if sat_vld='1' then saturated_i<=sat_i(0); end if;
        if err_vld='1' then error_i<=err_i(0); end if;
      end if;
    end if;
  end process;
end architecture;
