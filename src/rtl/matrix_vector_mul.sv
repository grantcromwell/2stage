module matrix_vector_mul #(
  parameter int DIM = 24,
  parameter int FRAC_BITS = 16
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    start,
  input  logic [4:0]              dim,        // Actual dimension (1-24)
  input  q16_16_pkg::q16_16_t     matrix [0:DIM-1][0:DIM-1],  // A matrix
  input  q16_16_pkg::q16_16_t     vector [0:DIM-1],            // x vector
  output logic                    done,
  output logic                    saturated,
  output q16_16_pkg::q16_16_t     result [0:DIM-1]              // y = A*x
);

  import q16_16_pkg::*;

  typedef enum logic [1:0] {
    IDLE    = 2'b00,
    COMPUTE = 2'b01,
    OUTPUT  = 2'b10
  } state_t;

  state_t state, next_state;
  logic [4:0] row_idx, col_idx;
  logic [4:0] dim_reg;
  q48_16_t acc [0:DIM-1];
  logic row_done;

  // Sequential logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= IDLE;
      row_idx    <= 5'd0;
      col_idx    <= 5'd0;
      dim_reg    <= 5'd0;
      done       <= 1'b0;
      saturated  <= 1'b0;
      row_done   <= 1'b0;
      for (int i = 0; i < DIM; i++) begin
        acc[i]   <= '0;
        result[i] <= '0;
      end
    end else begin
      state <= next_state;

      case (state)
        IDLE: begin
          done      <= 1'b0;
          saturated <= 1'b0;
          row_idx   <= 5'd0;
          col_idx   <= 5'd0;
          dim_reg   <= dim;
          for (int i = 0; i < DIM; i++) acc[i] <= '0;
          if (start) begin
            row_done <= 1'b0;
          end
        end

        COMPUTE: begin
          if (col_idx < dim_reg) begin
            // Multiply-accumulate: acc[row] += matrix[row][col] * vector[col]
            acc[row_idx] <= mac_q48(acc[row_idx], matrix[row_idx][col_idx], vector[col_idx]);
            col_idx <= col_idx + 1'b1;
          end else begin
            // Row complete, saturate and store
            if (acc[row_idx] > Q16_MAX) begin
              result[row_idx] <= Q16_MAX;
              saturated       <= 1'b1;
            end else if (acc[row_idx] < Q16_MIN) begin
              result[row_idx] <= Q16_MIN;
              saturated       <= 1'b1;
            end else begin
              result[row_idx] <= acc[row_idx][31:0];
            end
            row_done <= 1'b1;
          end
        end

        OUTPUT: begin
          row_done <= 1'b0;
          if (row_idx < dim_reg - 1) begin
            row_idx <= row_idx + 1'b1;
            col_idx <= 5'd0;
          end else begin
            done <= 1'b1;
          end
        end
      endcase
    end
  end

  // Next state logic
  always_comb begin
    next_state = state;
    case (state)
      IDLE:    if (start)           next_state = COMPUTE;
      COMPUTE: if (row_done)        next_state = OUTPUT;
      OUTPUT:  if (row_idx == dim_reg-1) next_state = IDLE;
               else                 next_state = COMPUTE;
    endcase
  end

endmodule