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
  type row_pipe_t is array (0 to 5) of natural range 0 to 23;

  signal matrix_banks : matrix_banks_t;
  signal vector_mem   : vector_t;
  signal y_mem        : vector_t := (others => (others => '0'));

  
  
  attribute ram_style : string;
  attribute ram_style of matrix_banks : signal is "distributed";

  type state_t is (IDLE, MATRIX, QDOT_ISSUE, QDOT_DRAIN, FINISH);
  signal state : state_t := IDLE;
  signal n, issue_row : natural range 0 to 31 := 0;

  signal product0, product1 : product_t := (others => (others => '0'));
  signal operand_a0, operand_b0 : vector_t := (others => (others => '0'));
  signal operand_a1, operand_b1 : vector_t := (others => (others => '0'));
  signal sum12_0, sum12_1   : sum12_t := (others => (others => '0'));
  signal sum6_0, sum6_1     : sum6_t := (others => (others => '0'));
  signal sum3_0, sum3_1     : sum3_t := (others => (others => '0'));
  signal sum2_0, sum2_1     : sum2_t := (others => (others => '0'));
  signal total0, total1     : signed(63 downto 0) := (others => '0');

  signal valid0_pipe, valid1_pipe : std_logic_vector(0 to 5) := (others => '0');
  signal kind_pipe                : std_logic_vector(0 to 5) := (others => '0');
  signal row0_pipe, row1_pipe     : row_pipe_t := (others => 0);
  signal issue0_valid, issue1_valid, issue_kind : std_logic := '0';
  signal issue_row0, issue_row1 : natural range 0 to 23 := 0;

  signal done_i, saturated_i, error_i : std_logic := '0';
  signal quadratic_i : signed(63 downto 0) := (others => '0');
  signal cycles_i    : unsigned(31 downto 0) := (others => '0');

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
    if index_v < 24 then
      result_data <= std_logic_vector(y_mem(index_v));
    else
      result_data <= (others => '0');
    end if;
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
    variable row0_v, row1_v : natural;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state <= IDLE;
        n <= 0;
        issue_row <= 0;
        valid0_pipe <= (others => '0');
        valid1_pipe <= (others => '0');
        kind_pipe <= (others => '0');
        issue0_valid <= '0';
        issue1_valid <= '0';
        done_i <= '0';
        saturated_i <= '0';
        error_i <= '0';
        quadratic_i <= (others => '0');
        cycles_i <= (others => '0');
      elsif cancel = '1' then
        state <= IDLE;
        valid0_pipe <= (others => '0');
        valid1_pipe <= (others => '0');
        kind_pipe <= (others => '0');
        issue0_valid <= '0';
        issue1_valid <= '0';
        done_i <= '0';
        saturated_i <= '0';
        error_i <= '0';
        quadratic_i <= (others => '0');
        cycles_i <= (others => '0');
      else
        done_i <= '0';
        issue0_valid <= '0';
        issue1_valid <= '0';

        if state /= IDLE then
          cycles_i <= cycles_i + 1;
        end if;

        
        
        for i in 0 to LANES-1 loop
          product0(i) <= operand_a0(i) * operand_b0(i);
          product1(i) <= operand_a1(i) * operand_b1(i);
        end loop;
        valid0_pipe(0) <= issue0_valid;
        valid1_pipe(0) <= issue1_valid;
        kind_pipe(0) <= issue_kind;
        row0_pipe(0) <= issue_row0;
        row1_pipe(0) <= issue_row1;

        
        for i in 0 to 11 loop
          sum12_0(i) <= shift_right(product0(2*i), 16) + shift_right(product0(2*i+1), 16);
          sum12_1(i) <= shift_right(product1(2*i), 16) + shift_right(product1(2*i+1), 16);
        end loop;
        for i in 0 to 5 loop
          sum6_0(i) <= sum12_0(2*i) + sum12_0(2*i+1);
          sum6_1(i) <= sum12_1(2*i) + sum12_1(2*i+1);
        end loop;
        for i in 0 to 2 loop
          sum3_0(i) <= sum6_0(2*i) + sum6_0(2*i+1);
          sum3_1(i) <= sum6_1(2*i) + sum6_1(2*i+1);
        end loop;
        sum2_0(0) <= sum3_0(0) + sum3_0(1);
        sum2_0(1) <= sum3_0(2);
        sum2_1(0) <= sum3_1(0) + sum3_1(1);
        sum2_1(1) <= sum3_1(2);
        total0 <= sum2_0(0) + sum2_0(1);
        total1 <= sum2_1(0) + sum2_1(1);

        for stage in 1 to 5 loop
          valid0_pipe(stage) <= valid0_pipe(stage-1);
          valid1_pipe(stage) <= valid1_pipe(stage-1);
          kind_pipe(stage) <= kind_pipe(stage-1);
          row0_pipe(stage) <= row0_pipe(stage-1);
          row1_pipe(stage) <= row1_pipe(stage-1);
        end loop;

        
        if valid0_pipe(5) = '1' then
          if kind_pipe(5) = '0' then
            row0_v := row0_pipe(5);
            if total0 > MAX_Q16 then
              y_mem(row0_v) <= signed'(x"7FFFFFFF");
              saturated_i <= '1';
            elsif total0 < MIN_Q16 then
              y_mem(row0_v) <= signed'(x"80000000");
              saturated_i <= '1';
            else
              y_mem(row0_v) <= total0(31 downto 0);
            end if;
            if row0_v + 1 = n then
              state <= QDOT_ISSUE;
            end if;
          else
            quadratic_i <= total0;
            state <= FINISH;
          end if;
        end if;
        if valid1_pipe(5) = '1' and kind_pipe(5) = '0' then
          row1_v := row1_pipe(5);
          if total1 > MAX_Q16 then
            y_mem(row1_v) <= signed'(x"7FFFFFFF");
            saturated_i <= '1';
          elsif total1 < MIN_Q16 then
            y_mem(row1_v) <= signed'(x"80000000");
            saturated_i <= '1';
          else
            y_mem(row1_v) <= total1(31 downto 0);
          end if;
          if row1_v + 1 = n then
            state <= QDOT_ISSUE;
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
              valid0_pipe <= (others => '0');
              valid1_pipe <= (others => '0');
              kind_pipe <= (others => '0');
              issue0_valid <= '0';
              issue1_valid <= '0';
              for i in 0 to 23 loop
                y_mem(i) <= (others => '0');
              end loop;
              if dim_v = 0 or dim_v > 24 then
                error_i <= '1';
                state <= FINISH;
              else
                error_i <= '0';
                state <= MATRIX;
              end if;
            end if;

          when MATRIX =>
            if issue_row < n then
              issue0_valid <= '1';
              issue_kind <= '0';
              issue_row0 <= issue_row;
              for col in 0 to LANES-1 loop
                if col < n then
                  operand_a0(col) <= matrix_banks(col)(issue_row);
                  operand_b0(col) <= vector_mem(col);
                else
                  operand_a0(col) <= (others => '0');
                  operand_b0(col) <= (others => '0');
                end if;
              end loop;

              if issue_row + 1 < n then
                issue1_valid <= '1';
                issue_row1 <= issue_row + 1;
                for col in 0 to LANES-1 loop
                  if col < n then
                    operand_a1(col) <= matrix_banks(col)(issue_row + 1);
                    operand_b1(col) <= vector_mem(col);
                  else
                    operand_a1(col) <= (others => '0');
                    operand_b1(col) <= (others => '0');
                  end if;
                end loop;
              end if;
              issue_row <= issue_row + 2;
            end if;

          when QDOT_ISSUE =>
            issue0_valid <= '1';
            issue_kind <= '1';
            issue_row0 <= 0;
            for col in 0 to LANES-1 loop
              if col < n then
                operand_a0(col) <= y_mem(col);
                operand_b0(col) <= vector_mem(col);
              else
                operand_a0(col) <= (others => '0');
                operand_b0(col) <= (others => '0');
              end if;
            end loop;
            state <= QDOT_DRAIN;

          when QDOT_DRAIN =>
            null;

          when FINISH =>
            done_i <= '1';
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
