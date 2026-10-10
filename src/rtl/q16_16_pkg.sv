package q16_16_pkg;
  // Q16.16 Fixed-Point Package
  // 1 sign bit, 15 integer bits, 16 fractional bits
  // Range: -32768.0 to +32767.9999847412109375
  // Resolution: 1/65536 ≈ 1.5259e-5

  parameter int Q_FRAC_BITS = 16;
  parameter int Q_INT_BITS  = 15;
  parameter int Q_TOTAL_BITS = 32;
  parameter int Q_SIGN_BIT = 31;

  // Q16.16 value type
  typedef logic signed [Q_TOTAL_BITS-1:0] q16_16_t;

  // Extended precision for accumulation (48 bits: 1 sign, 31 integer, 16 fractional)
  parameter int ACC_FRAC_BITS = 16;
  parameter int ACC_INT_BITS  = 31;
  parameter int ACC_TOTAL_BITS = 48;
  typedef logic signed [ACC_TOTAL_BITS-1:0] q48_16_t;

  // Double extended for quadratic form (64 bits)
  parameter int Q64_FRAC_BITS = 16;
  parameter int Q64_INT_BITS  = 47;
  parameter int Q64_TOTAL_BITS = 64;
  typedef logic signed [Q64_TOTAL_BITS-1:0] q64_16_t;

  // Saturation constants
  localparam q16_16_t Q16_MAX  = 32'sh7FFF_FFFF;  // +32767.99998
  localparam q16_16_t Q16_MIN  = 32'sh8000_0000;  // -32768.0
  localparam q48_16_t Q48_MAX  = 48'sh7FFF_FFFF_FFFF;
  localparam q48_16_t Q48_MIN  = 48'sh8000_0000_0000;
  localparam q64_16_t Q64_MAX  = 64'sh7FFF_FFFF_FFFF_FFFF;
  localparam q64_16_t Q64_MIN  = 64'sh8000_0000_0000_0000;

  // Convert double to Q16.16
  function automatic q16_16_t double_to_q16(input real val);
    logic signed [63:0] temp;
    begin
      temp = $signed(val * 65536.0);
      if (temp > Q16_MAX) return Q16_MAX;
      if (temp < Q16_MIN) return Q16_MIN;
      return temp[31:0];
    end
  endfunction

  // Convert Q16.16 to double
  function automatic real q16_to_double(input q16_16_t val);
    begin
      return $signed(val) / 65536.0;
    end
  endfunction

  // Saturating addition for Q16.16
  function automatic q16_16_t sat_add_q16(input q16_16_t a, input q16_16_t b);
    q48_16_t sum;
    begin
      sum = $signed({{16{a[31]}}, a}) + $signed({{16{b[31]}}, b});
      if (sum > Q16_MAX) return Q16_MAX;
      if (sum < Q16_MIN) return Q16_MIN;
      return sum[31:0];
    end
  endfunction

  // Saturating multiplication Q16.16 x Q16.16 -> Q16.16
  function automatic q16_16_t sat_mul_q16(input q16_16_t a, input q16_16_t b);
    q64_16_t prod;
    begin
      prod = $signed({{32{a[31]}}, a}) * $signed({{32{b[31]}}, b});
      prod = prod >>> 16;  // Adjust for Q16.16 x Q16.16 = Q32.32 -> Q16.16
      if (prod > Q16_MAX) return Q16_MAX;
      if (prod < Q16_MIN) return Q16_MIN;
      return prod[31:0];
    end
  endfunction

  // Multiply-accumulate for Q16.16 x Q16.16 -> Q48.16
  function automatic q64_16_t mac_q64(input q64_16_t acc, input q16_16_t a, input q16_16_t b);
    q64_16_t prod;
    begin
      prod = $signed({{32{a[31]}}, a}) * $signed({{32{b[31]}}, b});
      prod = prod >>> 16;
      acc = acc + prod;
      return acc;
    end
  endfunction

  // Maximum dimension supported
  parameter int MAX_DIM = 24;

endpackage
