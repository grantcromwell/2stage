module quadratic_form #(
  parameter int DIM = 24,
  parameter int FRAC_BITS = 16
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    start,
  input  logic [4:0]              dim,        
  input  q16_16_pkg::q16_16_t     vector [0:DIM-1],   
  input  q16_16_pkg::q16_16_t     y_vector [0:DIM-1],  
  output logic                    done,
  output logic                    saturated,
  output q16_16_pkg::q64_16_t     result      
);

  import q16_16_pkg::*;

  typedef enum logic [1:0] {
    IDLE    = 2'b00,
    COMPUTE = 2'b01,
    OUTPUT  = 2'b10
  } state_t;

  state_t state, next_state;
  logic [4:0] idx;
  logic [4:0] dim_reg;
  q64_16_t acc;
  logic idx_done;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= IDLE;
      idx       <= 5'd0;
      dim_reg   <= 5'd0;
      acc       <= '0;
      done      <= 1'b0;
      saturated <= 1'b0;
      idx_done  <= 1'b0;
      result    <= '0;
    end else begin
      state <= next_state;

      case (state)
        IDLE: begin
          done      <= 1'b0;
          saturated <= 1'b0;
          idx       <= 5'd0;
          dim_reg   <= dim;
          acc       <= '0;
          if (start) idx_done <= 1'b0;
        end

        COMPUTE: begin
          if (idx < dim_reg) begin
            
            
            q64_16_t prod;
            prod = $signed({{32{vector[idx][31]}}, vector[idx]}) *
                   $signed({{32{y_vector[idx][31]}}, y_vector[idx]});
            prod = prod >>> 16;  
            acc = acc + prod;
            idx <= idx + 1'b1;
          end else begin
            idx_done <= 1'b1;
          end
        end

        OUTPUT: begin
          
          if (acc > Q64_MAX) begin
            result    <= Q64_MAX;
            saturated <= 1'b1;
          end else if (acc < Q64_MIN) begin
            result    <= Q64_MIN;
            saturated <= 1'b1;
          end else begin
            result <= acc;
          end
          done <= 1'b1;
        end
      endcase
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE:    if (start)           next_state = COMPUTE;
      COMPUTE: if (idx_done)        next_state = OUTPUT;
      OUTPUT:                      next_state = IDLE;
    endcase
  end

endmodule