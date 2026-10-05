library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity shadow_core is
  port (
    clk         : in  std_logic;
    rst_n       : in  std_logic;
    start       : in  std_logic;
    cancel      : in  std_logic;
    dim         : in  std_logic_vector(4 downto 0);
    mem_we      : in  std_logic;
    mem_addr    : in  std_logic_vector(11 downto 0);
    mem_data    : in  std_logic_vector(31 downto 0);
    mem_strb    : in  std_logic_vector(3 downto 0);
    result_addr : in  std_logic_vector(4 downto 0);
    result_data : out std_logic_vector(31 downto 0);
    quadratic   : out std_logic_vector(63 downto 0);
    busy        : out std_logic;
    done        : out std_logic;
    saturated   : out std_logic;
    error       : out std_logic;
    cycles      : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of shadow_core is
  constant LANES : positive := 24;
  type bank_t is array (0 to 23) of signed(31 downto 0);
  type matrix_banks_t is array (0 to 23) of bank_t;
  type vector_t is array (0 to 23) of signed(31 downto 0);
  type product_t is array (0 to 23) of signed(63 downto 0);
  type sum12_t is array (0 to 11) of signed(63 downto 0);
  type sum6_t is array (0 to 5) of signed(63 downto 0);
  type sum3_t is array (0 to 2) of signed(63 downto 0);
  type sum2_t is array (0 to 1) of signed(63 downto 0);

  function reduce_products(values : product_t) return signed is
    variable level12 : sum12_t;
    variable level6 : sum6_t;
    variable level3 : sum3_t;
    variable level2 : sum2_t;
  begin
    for i in 0 to 11 loop
      level12(i) := shift_right(values(2*i), 16) + shift_right(values(2*i+1), 16);
    end loop;
    for i in 0 to 5 loop level6(i) := level12(2*i) + level12(2*i+1); end loop;
    for i in 0 to 1 loop level3(i) := level6(2*i) + level6(2*i+1); end loop;
    level3(2) := level6(4) + level6(5);
    level2(0) := level3(0) + level3(1);
    level2(1) := level3(2);
    return level2(0) + level2(1);
  end function;

  signal matrix_banks : matrix_banks_t;
  signal vector_mem   : vector_t;
  signal y_mem        : vector_t := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of matrix_banks : signal is "distributed";

  type state_t is (IDLE, MATRIX, QDOT_ISSUE, QDOT_DRAIN, FINISH);
  signal state : state_t := IDLE;
  signal n, issue_row : natural range 0 to 24 := 0;

  signal product_pipe : product_t := (others => (others => '0'));
  signal operand_a, operand_b : vector_t := (others => (others => '0'));
  signal valid_pipe : std_logic := '0';
  signal kind_pipe : std_logic := '0';
  signal row_pipe : natural range 0 to 23 := 0;

  signal done_i, saturated_i, error_i : std_logic := '0';
  signal quadratic_i : signed(63 downto 0) := (others => '0');
  signal cycles_i : unsigned(31 downto 0) := (others => '0');
  constant MAX_Q16 : signed(63 downto 0) := resize(signed'(x"7FFFFFFF"), 64);
  constant MIN_Q16 : signed(63 downto 0) := resize(signed'(x"80000000"), 64);
begin
  busy      <= '1' when state /= IDLE else '0';
  done      <= done_i;
  saturated <= saturated_i;
  error     <= error_i;
  quadratic <= std_logic_vector(quadratic_i);
  cycles    <= std_logic_vector(cycles_i);

  process(all)
    variable index_v : natural;
  begin
    index_v := to_integer(unsigned(result_addr));
    if index_v < LANES then result_data <= std_logic_vector(y_mem(index_v));
    else result_data <= (others => '0'); end if;
  end process;

  process(all)
  begin
    for col in 0 to LANES-1 loop
      operand_a(col) <= (others => '0');
      operand_b(col) <= (others => '0');
      if col < n then
        if state = MATRIX and issue_row < n then
          operand_a(col) <= matrix_banks(col)(issue_row);
          operand_b(col) <= vector_mem(col);
        elsif state = QDOT_ISSUE then
          operand_a(col) <= y_mem(col);
          operand_b(col) <= vector_mem(col);
        end if;
      end if;
    end loop;
  end process;

  process(clk)
    variable address_v : natural;
  begin
    if rising_edge(clk) then
      if mem_we = '1' and state = IDLE then
        address_v := to_integer(unsigned(mem_addr));
        for row_idx in 0 to 23 loop
          for col_idx in 0 to 23 loop
            if address_v = 16#100# + 4*(row_idx*24 + col_idx) then
              for byte_idx in 0 to 3 loop
                if mem_strb(byte_idx) = '1' then
                  matrix_banks(col_idx)(row_idx)(8*byte_idx+7 downto 8*byte_idx) <=
                    signed(mem_data(8*byte_idx+7 downto 8*byte_idx));
                end if;
              end loop;
            end if;
          end loop;
        end loop;
        for vector_idx in 0 to 23 loop
          if address_v = 16#A00# + 4*vector_idx then
            for byte_idx in 0 to 3 loop
              if mem_strb(byte_idx) = '1' then
                vector_mem(vector_idx)(8*byte_idx+7 downto 8*byte_idx) <=
                  signed(mem_data(8*byte_idx+7 downto 8*byte_idx));
              end if;
            end loop;
          end if;
        end loop;
      end if;
    end if;
  end process;

  process(clk)
    variable dim_v : natural;
    variable total_v : signed(63 downto 0);
    variable row_v : natural;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state <= IDLE;
        n <= 0;
        issue_row <= 0;
        valid_pipe <= '0';
        kind_pipe <= '0';
        done_i <= '0';
        saturated_i <= '0';
        error_i <= '0';
        quadratic_i <= (others => '0');
        cycles_i <= (others => '0');
      elsif cancel = '1' then
        state <= IDLE;
        valid_pipe <= '0';
        done_i <= '0';
        saturated_i <= '0';
        error_i <= '0';
        quadratic_i <= (others => '0');
        cycles_i <= (others => '0');
      else
        done_i <= '0';
        if state /= IDLE then cycles_i <= cycles_i + 1; end if;

        if valid_pipe = '1' then
          total_v := reduce_products(product_pipe);
          if kind_pipe = '0' then
            row_v := row_pipe;
            if total_v > MAX_Q16 then
              y_mem(row_v) <= signed'(x"7FFFFFFF"); saturated_i <= '1';
            elsif total_v < MIN_Q16 then
              y_mem(row_v) <= signed'(x"80000000"); saturated_i <= '1';
            else
              y_mem(row_v) <= total_v(31 downto 0);
            end if;
            if row_v + 1 = n then state <= QDOT_ISSUE; end if;
          else
            quadratic_i <= total_v;
            state <= FINISH;
          end if;
        end if;

        valid_pipe <= '0';
        if (state = MATRIX and issue_row < n) or state = QDOT_ISSUE then
          for col in 0 to LANES-1 loop
            product_pipe(col) <= operand_a(col) * operand_b(col);
          end loop;
          valid_pipe <= '1';
          if state = MATRIX then
            row_pipe <= issue_row;
            kind_pipe <= '0';
            issue_row <= issue_row + 1;
          else
            row_pipe <= 0;
            kind_pipe <= '1';
            state <= QDOT_DRAIN;
          end if;
        end if;
        case state is
          when IDLE =>
            if start = '1' then
              dim_v := to_integer(unsigned(dim));
              n <= dim_v;
              issue_row <= 0;
              cycles_i <= (others => '0');
              saturated_i <= '0';
              quadratic_i <= (others => '0');
              for i in 0 to 23 loop y_mem(i) <= (others => '0'); end loop;
              if dim_v = 0 or dim_v > LANES then
                error_i <= '1'; state <= FINISH;
              else
                error_i <= '0'; state <= MATRIX;
              end if;
            end if;

          when MATRIX =>
            null;

          when QDOT_ISSUE =>
            null;

          when QDOT_DRAIN => null;
          when FINISH => done_i <= '1'; state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
