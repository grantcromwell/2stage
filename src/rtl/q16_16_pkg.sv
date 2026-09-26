package q16_16_pkg;
  
  
  
  

  parameter int Q_FRAC_BITS = 16;
  parameter int Q_INT_BITS  = 15;
  parameter int Q_TOTAL_BITS = 32;
  parameter int Q_SIGN_BIT = 31;

  
  typedef logic signed [Q_TOTAL_BITS-1:0] q16_16_t;

  
  parameter int ACC_FRAC_BITS = 16;
  parameter int ACC_INT_BITS  = 31;
  parameter int ACC_TOTAL_BITS = 48;
  typedef logic signed [ACC_TOTAL_BITS-1:0] q48_16_t;

  
  parameter int Q64_FRAC_BITS = 16;
  parameter int Q64_INT_BITS  = 47;
  parameter int Q64_TOTAL_BITS = 64;
  typedef logic signed [Q64_TOTAL_BITS-1:0] q64_16_t;

  
  localparam q16_16_t Q16_MAX  = 32'sh7FFF_FFFF;  
  localparam q16_16_t Q16_MIN  = 32'sh8000_0000;  
  localparam q48_16_t Q48_MAX  = 48'sh7FFF_FFFF_FFFF;
  localparam q48_16_t Q48_MIN  = 48'sh8000_0000_0000;
  localparam q64_16_t Q64_MAX  = 64'sh7FFF_FFFF_FFFF_FFFF;
  localparam q64_16_t Q64_MIN  = 64'sh8000_0000_0000_0000;

  
  function automatic q16_16_t double_to_q16(input real val);
    logic signed [63:0] temp;
    begin
      temp = $signed(val * 65536.0);
      if (temp > Q16_MAX) return Q16_MAX;
      if (temp < Q16_MIN) return Q16_MIN;
      return temp[31:0];
    end
  endfunction

  
  function automatic real q16_to_double(input q16_16_t val);
    begin
      return $signed(val) / 65536.0;
    end
  endfunction

  
  function automatic q16_16_t sat_add_q16(input q16_16_t a, input q16_16_t b);
    q48_16_t sum;
    begin
      sum = $signed({{16{a[31]}}, a}) + $signed({{16{b[31]}}, b});
      if (sum > Q16_MAX) return Q16_MAX;
      if (sum < Q16_MIN) return Q16_MIN;
      return sum[31:0];
    end
  endfunction

  
  function automatic q16_16_t sat_mul_q16(input q16_16_t a, input q16_16_t b);
    q64_16_t prod;
    begin
      prod = $signed({{32{a[31]}}, a}) * $signed({{32{b[31]}}, b});
      prod = prod >>> 16;  
      if (prod > Q16_MAX) return Q16_MAX;
      if (prod < Q16_MIN) return Q16_MIN;
      return prod[31:0];
    end
  endfunction

  
  function automatic q48_16_t mac_q48(input q48_16_t acc, input q16_16_t a, input q16_16_t b);
    q64_16_t prod;
    begin
      prod = $signed({{32{a[31]}}, a}) * $signed({{32{b[31]}}, b});
      prod = prod >>> 16;
      acc = acc + prod;
      if (acc > Q48_MAX) return Q48_MAX;
      if (acc < Q48_MIN) return Q48_MIN;
      return acc;
    end
  endfunction

  
  parameter int MAX_DIM = 24;

endpackage