module poly1305_core (
  input  logic         clk_i,
  input  logic         rst_ni,

  // Control
  input  logic         init_i,           // Pulse: load key, clear accumulator
  input  logic         block_valid_i,    // Pulse: process one message block
  input  logic         finalize_i,       // Pulse: generate tag

  // Key  (256-bit one-time key: r || s, little-endian)
  input  logic [127:0] key_r_i,          // r part  (will be clamped)
  input  logic [127:0] key_s_i,          // s part

  // Message block
  input  logic [127:0] block_i,          // Current 16-byte block (LE)
  input  logic [4:0]   block_len_i,      // Bytes in this block (1–16)

  // Output
  output logic         busy_o,           // 1 = processing
  output logic         done_o,           // 1-cycle pulse: block / finalize done
  output logic         valid_o,          // tag_o is valid
  output logic [127:0] tag_o             // 128-bit MAC tag
);

  
  //  Constants
  localparam [130:0] PRIME = (131'h4 << 128) - 131'd5;  // 2^130 - 5

  
  //  FSM
  typedef enum logic [2:0] {
    S_IDLE    = 3'd0,
    S_MULT    = 3'd2,   // 4-cycle multiply (mult_cnt 0..3)
    S_REDUCE  = 3'd3,   // modular reduction cycle 1: register reduce_step1
    S_REDUCE2 = 3'd6,   // modular reduction cycle 2: compute reduce_step2 -> acc
    S_FINAL   = 3'd4,   // canonical reduce + add s
    S_VALID   = 3'd5    // hold tag
  } state_e;

  state_e      state_q;
  logic [1:0]  mult_cnt_q;

  
  //  Internal registers
  logic [130:0] acc_q;          // Accumulator  (up to ~131 bits)
  logic [127:0] r_q;            // Clamped r
  logic [127:0] s_q;            // s key part
  logic [131:0] sum_q;          // acc + block_with_hibit
  logic [259:0] product_q;      // Product accumulator
  logic [127:0] tag_q;          // Output tag
  logic         valid_q;        // Tag valid flag
  logic         done_q;         // Done pulse

  
  //  Clamp function  (RFC 8439 §2.5)
  //
  //  r[3]  &= 0x0f   →  byte  3 top nibble = 0  →  bits [31:28]  = 0
  //  r[7]  &= 0x0f   →  byte  7 top nibble = 0  →  bits [63:60]  = 0
  //  r[11] &= 0x0f   →  byte 11 top nibble = 0  →  bits [95:92]  = 0
  //  r[15] &= 0x0f   →  byte 15 top nibble = 0  →  bits [127:124]= 0
  //  r[4]  &= 0xfc   →  byte  4 low 2 bits = 0  →  bits [33:32]  = 0
  //  r[8]  &= 0xfc   →  byte  8 low 2 bits = 0  →  bits [65:64]  = 0
  //  r[12] &= 0xfc   →  byte 12 low 2 bits = 0  →  bits [97:96]  = 0
  
  //  Inline clamp: zero specific bits of key_r_i per RFC 8439 §2.5
  
  wire [127:0] clamped_r;
  assign clamped_r = { 4'b0,              // [127:124]  r[15] &= 0x0f
                       key_r_i[123:98],   // [123:98]   passthrough
                       2'b0,              // [97:96]    r[12] &= 0xfc
                       4'b0,              // [95:92]    r[11] &= 0x0f
                       key_r_i[91:66],    // [91:66]    passthrough
                       2'b0,              // [65:64]    r[8]  &= 0xfc
                       4'b0,              // [63:60]    r[7]  &= 0x0f
                       key_r_i[59:34],    // [59:34]    passthrough
                       2'b0,              // [33:32]    r[4]  &= 0xfc
                       4'b0,              // [31:28]    r[3]  &= 0x0f
                       key_r_i[27:0]      // [27:0]     passthrough
                     };

  
  //  Hibit insertion
  //
  //  For a full 16-byte block:  block_with_hibit = {1'b1, block}    (bit 128)
  //  For a partial n-byte block: 0x01 byte at position n → bit 8*n
  
  logic [128:0] block_with_hibit;

  always_comb begin
    case (block_len_i)
      5'd1:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<   8);
      5'd2:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  16);
      5'd3:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  24);
      5'd4:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  32);
      5'd5:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  40);
      5'd6:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  48);
      5'd7:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  56);
      5'd8:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  64);
      5'd9:    block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  72);
      5'd10:   block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  80);
      5'd11:   block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  88);
      5'd12:   block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 <<  96);
      5'd13:   block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 << 104);
      5'd14:   block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 << 112);
      5'd15:   block_with_hibit = {1'b0, block_i[127:0]} | (129'd1 << 120);
      default: block_with_hibit = {1'b1, block_i[127:0]};  // 16 bytes
    endcase
  end

  
  //  Multiply — 4-cycle sequential   (one 32-bit limb of r per cycle)
  //
  //  product = sum × r = Σ_{k=0}^{3}  sum × r_limb[k] × 2^{32k}
  
  logic [31:0]  r_limb;
  logic [163:0] partial_product;     // 132 × 32 = 164 bits max
  logic [259:0] shifted_partial;

  always_comb begin
    case (mult_cnt_q)
      2'd0: r_limb = r_q[ 31:  0];
      2'd1: r_limb = r_q[ 63: 32];
      2'd2: r_limb = r_q[ 95: 64];
      2'd3: r_limb = r_q[127: 96];
    endcase
  end

  // DSP-friendly decomposition: split 132×32 into 4×(32×32) + 1×(4×32)
  // Each 32×32 maps to Cyclone V DSP blocks (27×27 mode)
  (* multstyle = "dsp" *) logic [63:0] pp_m0, pp_m1, pp_m2, pp_m3;
  logic [35:0] pp_m4;

  assign pp_m0 = {32'b0, sum_q[ 31:  0]} * {32'b0, r_limb};
  assign pp_m1 = {32'b0, sum_q[ 63: 32]} * {32'b0, r_limb};
  assign pp_m2 = {32'b0, sum_q[ 95: 64]} * {32'b0, r_limb};
  assign pp_m3 = {32'b0, sum_q[127: 96]} * {32'b0, r_limb};
  assign pp_m4 = {32'b0, sum_q[131:128]} * {4'b0,  r_limb};

  assign partial_product = {100'b0, pp_m0}
                         + { 68'b0, pp_m1, 32'b0}
                         + { 36'b0, pp_m2, 64'b0}
                         + {  4'b0, pp_m3, 96'b0}
                         + {pp_m4, 128'b0};

  always_comb begin
    shifted_partial = 260'd0;
    case (mult_cnt_q)
      2'd0: shifted_partial[163:  0] = partial_product;
      2'd1: shifted_partial[195: 32] = partial_product;
      2'd2: shifted_partial[227: 64] = partial_product;
      2'd3: shifted_partial[259: 96] = partial_product;
    endcase
  end

  
  //  Reduction  mod P = 2^130 − 5
  //
  //  Split product at bit 130:  product = hi·2^130 + lo
  //  Since 2^130 ≡ 5 (mod P):  result  ≡ lo + 5·hi
  //  Two steps to bring result below ~2^131:
  //    step1 = lo + 5·hi                    (≤ ~133 bits)
  //    step2 = lo2 + 5·hi2                  (≤  131 bits)
  
  // --- Reduction pipeline stage 1 (runs in S_REDUCE) ---
  logic [129:0] reduce_lo;
  logic [129:0] reduce_hi;
  logic [132:0] hi_times_5;
  logic [132:0] reduce_step1_comb;   // combinational
  logic [132:0] reduce_step1_q;      // registered at end of S_REDUCE

  assign reduce_lo         = product_q[129:0];
  assign reduce_hi         = product_q[259:130];
  assign hi_times_5        = {1'b0, reduce_hi, 2'b0} + {3'b0, reduce_hi};
  assign reduce_step1_comb = {3'b0, reduce_lo} + hi_times_5;

  // --- Reduction pipeline stage 2 (runs in S_REDUCE2) ---
  logic [129:0] reduce_lo2;
  logic [2:0]   reduce_hi2;
  logic [5:0]   hi2_times_5;
  logic [130:0] reduce_step2;

  assign reduce_lo2   = reduce_step1_q[129:0];
  assign reduce_hi2   = reduce_step1_q[132:130];
  assign hi2_times_5  = {reduce_hi2, 2'b0} + {3'b0, reduce_hi2};
  assign reduce_step2 = {1'b0, reduce_lo2} + {125'b0, hi2_times_5};

  
  //  Canonical reduction for finalization
  //
  //  acc might be slightly >= P.  One subtraction suffices because
  //  after the 2-step reduction acc ≤ 2^130 + 34 ≈ P + 39.
  
  logic [131:0] acc_minus_p;
  logic [130:0] canon_acc;
  assign acc_minus_p = {1'b0, acc_q} - {1'b0, PRIME};
  assign canon_acc   = acc_minus_p[131] ? acc_q : acc_minus_p[130:0];

  // tag = (canonical_acc + s) mod 2^128
  logic [131:0] tag_full;
  assign tag_full = {1'b0, canon_acc} + {4'b0, s_q};

  
  //  FSM + Datapath
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= S_IDLE;
      mult_cnt_q <= 2'd0;
      acc_q            <= 131'd0;
      r_q              <= 128'd0;
      s_q              <= 128'd0;
      sum_q            <= 132'd0;
      product_q        <= 260'd0;
      reduce_step1_q   <= 133'd0;
      tag_q            <= 128'd0;
      valid_q          <= 1'b0;
      done_q           <= 1'b0;
    end else begin
      done_q <= 1'b0;                   // default: clear pulse

      case (state_q)

        // ---- IDLE: wait for command ------------------------------------
        S_IDLE: begin
          if (init_i) begin
            r_q     <= clamped_r;
            s_q     <= key_s_i;
            acc_q   <= 131'd0;
            valid_q <= 1'b0;
          end
          if (block_valid_i && !init_i) begin
            // Absorb: sum = acc + block (with hibit)
            sum_q      <= {3'b0, block_with_hibit} + {1'b0, acc_q};
            product_q  <= 260'd0;
            mult_cnt_q <= 2'd0;
            state_q    <= S_MULT;
          end else if (finalize_i && !init_i) begin
            state_q <= S_FINAL;
          end
        end

        // ---- MULT: accumulate partial products (4 cycles) ---------------
        S_MULT: begin
          product_q  <= product_q + shifted_partial;
          mult_cnt_q <= mult_cnt_q + 2'd1;
          if (mult_cnt_q == 2'd3)
            state_q <= S_REDUCE;
        end

        // ---- REDUCE: cycle 1 — compute and register reduce_step1 --------
        S_REDUCE: begin
          reduce_step1_q <= reduce_step1_comb;
          state_q        <= S_REDUCE2;
        end

        // ---- REDUCE2: cycle 2 — compute reduce_step2, write acc ---------
        S_REDUCE2: begin
          acc_q   <= reduce_step2;
          done_q  <= 1'b1;
          state_q <= S_IDLE;
        end

        // ---- FINAL: canonical reduce + add s ----------------------------
        S_FINAL: begin
          tag_q   <= tag_full[127:0];
          valid_q <= 1'b1;
          done_q  <= 1'b1;
          state_q <= S_VALID;
        end

        // ---- VALID: hold tag until next init ----------------------------
        S_VALID: begin
          if (init_i) begin
            r_q     <= clamped_r;
            s_q     <= key_s_i;
            acc_q   <= 131'd0;
            valid_q <= 1'b0;
            state_q <= S_IDLE;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  
  //  Outputs
  
  assign busy_o  = (state_q != S_IDLE) && (state_q != S_VALID);
  assign done_o  = done_q;
  assign valid_o = valid_q;
  assign tag_o   = tag_q;

endmodule
