
module chacha20_core (
  input  logic        clk_i,
  input  logic        rst_ni,

  //  Control 
  input  logic        start_i,          // Pulse: load key/nonce/counter, begin

  //  Parameters (from register bridge) 
  input  logic [31:0] key_i    [8],     // 256-bit key   (8 words)
  input  logic [31:0] nonce_i  [3],     // 96-bit nonce  (3 words)
  input  logic [31:0] counter_i,        // 32-bit block counter

  //  Output 
  output logic [31:0] keystream_o [16], // 512-bit keystream block
  output logic        ready_o,          // 1 = idle, keystream valid
  output logic        valid_o           // 1-cycle pulse on new keystream
);

  // Constants
  localparam logic [31:0] SIGMA0 = 32'h61707865;  // "expa"
  localparam logic [31:0] SIGMA1 = 32'h3320646e;  // "nd 3"
  localparam logic [31:0] SIGMA2 = 32'h79622d32;  // "2-by"
  localparam logic [31:0] SIGMA3 = 32'h6b206574;  // "te k"

  
  // FSM
  typedef enum logic [1:0] {
    S_IDLE  = 2'd0,
    S_ROUND = 2'd1,
    S_ADD   = 2'd2,
    S_VALID = 2'd3
  } state_t;

  state_t      fsm_q, fsm_d;
  logic [4:0]  round_q;                // 0–19


  // State registers
  logic [31:0] wk_q  [16];             // Working state  (mutated by QR)
  logic [31:0] ini_q [16];             // Initial state   (for final add)

  
  // QR wiring
  logic [31:0] qr_a_in [4], qr_b_in [4], qr_c_in [4], qr_d_in [4];
  logic [31:0] qr_a_out[4], qr_b_out[4], qr_c_out[4], qr_d_out[4];

  // Even round_q = column round,  Odd round_q = diagonal round
  wire is_col = ~round_q[0];

  // 4× QR instances  (Serrano Figure 3: QR_0 … QR_3)
  genvar gi;
  generate
    for (gi = 0; gi < 4; gi++) begin : gen_qr
      chacha20_qr u_qr (
        .a_i (qr_a_in[gi]),  .b_i (qr_b_in[gi]),
        .c_i (qr_c_in[gi]),  .d_i (qr_d_in[gi]),
        .a_o (qr_a_out[gi]), .b_o (qr_b_out[gi]),
        .c_o (qr_c_out[gi]), .d_o (qr_d_out[gi])
      );
    end
  endgenerate


  // QR input multiplexing  (RFC 8439 §2.3)
  //
  //  Column round  (even):
  //    QR0(0, 4, 8,12)  QR1(1, 5, 9,13)  QR2(2, 6,10,14)  QR3(3, 7,11,15)
  //  Diagonal round (odd):
  //    QR0(0, 5,10,15)  QR1(1, 6,11,12)  QR2(2, 7, 8,13)  QR3(3, 4, 9,14)
  always_comb begin
    // Defaults
    for (int i = 0; i < 4; i++) begin
      qr_a_in[i] = 32'd0;  qr_b_in[i] = 32'd0;
      qr_c_in[i] = 32'd0;  qr_d_in[i] = 32'd0;
    end

    if (is_col) begin
      //  Column round 
      qr_a_in[0] = wk_q[ 0]; qr_b_in[0] = wk_q[ 4]; qr_c_in[0] = wk_q[ 8]; qr_d_in[0] = wk_q[12];
      qr_a_in[1] = wk_q[ 1]; qr_b_in[1] = wk_q[ 5]; qr_c_in[1] = wk_q[ 9]; qr_d_in[1] = wk_q[13];
      qr_a_in[2] = wk_q[ 2]; qr_b_in[2] = wk_q[ 6]; qr_c_in[2] = wk_q[10]; qr_d_in[2] = wk_q[14];
      qr_a_in[3] = wk_q[ 3]; qr_b_in[3] = wk_q[ 7]; qr_c_in[3] = wk_q[11]; qr_d_in[3] = wk_q[15];
    end else begin
      //  Diagonal round 
      qr_a_in[0] = wk_q[ 0]; qr_b_in[0] = wk_q[ 5]; qr_c_in[0] = wk_q[10]; qr_d_in[0] = wk_q[15];
      qr_a_in[1] = wk_q[ 1]; qr_b_in[1] = wk_q[ 6]; qr_c_in[1] = wk_q[11]; qr_d_in[1] = wk_q[12];
      qr_a_in[2] = wk_q[ 2]; qr_b_in[2] = wk_q[ 7]; qr_c_in[2] = wk_q[ 8]; qr_d_in[2] = wk_q[13];
      qr_a_in[3] = wk_q[ 3]; qr_b_in[3] = wk_q[ 4]; qr_c_in[3] = wk_q[ 9]; qr_d_in[3] = wk_q[14];
    end
  end

  
  // FSM next-state
  always_comb begin
    fsm_d = fsm_q;
    case (fsm_q)
      S_IDLE:  if (start_i)           fsm_d = S_ROUND;
      S_ROUND: if (round_q == 5'd19)  fsm_d = S_ADD;
      S_ADD:                           fsm_d = S_VALID;
      S_VALID:                         fsm_d = S_IDLE;
      default:                         fsm_d = S_IDLE;
    endcase
  end

  
  // FSM sequential + state update
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fsm_q   <= S_IDLE;
      round_q <= 5'd0;
      for (int i = 0; i < 16; i++) begin
        wk_q[i]  <= 32'd0;
        ini_q[i] <= 32'd0;
      end
    end else begin
      fsm_q <= fsm_d;

      case (fsm_q)

        // IDLE: latch initial matrix on start pulse
        S_IDLE: begin
          if (start_i) begin
            // Build initial matrix
            ini_q[ 0] <= SIGMA0;       wk_q[ 0] <= SIGMA0;
            ini_q[ 1] <= SIGMA1;       wk_q[ 1] <= SIGMA1;
            ini_q[ 2] <= SIGMA2;       wk_q[ 2] <= SIGMA2;
            ini_q[ 3] <= SIGMA3;       wk_q[ 3] <= SIGMA3;
            ini_q[ 4] <= key_i[0];     wk_q[ 4] <= key_i[0];
            ini_q[ 5] <= key_i[1];     wk_q[ 5] <= key_i[1];
            ini_q[ 6] <= key_i[2];     wk_q[ 6] <= key_i[2];
            ini_q[ 7] <= key_i[3];     wk_q[ 7] <= key_i[3];
            ini_q[ 8] <= key_i[4];     wk_q[ 8] <= key_i[4];
            ini_q[ 9] <= key_i[5];     wk_q[ 9] <= key_i[5];
            ini_q[10] <= key_i[6];     wk_q[10] <= key_i[6];
            ini_q[11] <= key_i[7];     wk_q[11] <= key_i[7];
            ini_q[12] <= counter_i;    wk_q[12] <= counter_i;
            ini_q[13] <= nonce_i[0];   wk_q[13] <= nonce_i[0];
            ini_q[14] <= nonce_i[1];   wk_q[14] <= nonce_i[1];
            ini_q[15] <= nonce_i[2];   wk_q[15] <= nonce_i[2];
            round_q   <= 5'd0;
          end
        end

        // ROUND: apply 4× QR per cycle (column / diagonal)      
        S_ROUND: begin
          round_q <= round_q + 5'd1;

          if (is_col) begin
            // Column round: QR outputs map to same indices as inputs
            wk_q[ 0] <= qr_a_out[0]; wk_q[ 4] <= qr_b_out[0];
            wk_q[ 8] <= qr_c_out[0]; wk_q[12] <= qr_d_out[0];
            wk_q[ 1] <= qr_a_out[1]; wk_q[ 5] <= qr_b_out[1];
            wk_q[ 9] <= qr_c_out[1]; wk_q[13] <= qr_d_out[1];
            wk_q[ 2] <= qr_a_out[2]; wk_q[ 6] <= qr_b_out[2];
            wk_q[10] <= qr_c_out[2]; wk_q[14] <= qr_d_out[2];
            wk_q[ 3] <= qr_a_out[3]; wk_q[ 7] <= qr_b_out[3];
            wk_q[11] <= qr_c_out[3]; wk_q[15] <= qr_d_out[3];
          end else begin
            // Diagonal round: QR outputs map to shuffled indices
            wk_q[ 0] <= qr_a_out[0]; wk_q[ 5] <= qr_b_out[0];
            wk_q[10] <= qr_c_out[0]; wk_q[15] <= qr_d_out[0];
            wk_q[ 1] <= qr_a_out[1]; wk_q[ 6] <= qr_b_out[1];
            wk_q[11] <= qr_c_out[1]; wk_q[12] <= qr_d_out[1];
            wk_q[ 2] <= qr_a_out[2]; wk_q[ 7] <= qr_b_out[2];
            wk_q[ 8] <= qr_c_out[2]; wk_q[13] <= qr_d_out[2];
            wk_q[ 3] <= qr_a_out[3]; wk_q[ 4] <= qr_b_out[3];
            wk_q[ 9] <= qr_c_out[3]; wk_q[14] <= qr_d_out[3];
          end
        end

        
        // ADD: final addition  (working + initial)
        S_ADD: begin
          for (int i = 0; i < 16; i++)
            wk_q[i] <= wk_q[i] + ini_q[i];
        end

        
        // VALID: keystream is ready in wk_q — 1-cycle pulse
        S_VALID: begin
          // Nothing to do — wk_q holds the final keystream
        end

        default: ;
      endcase
    end
  end

  
  // Outputs
  assign ready_o = (fsm_q == S_IDLE);
  assign valid_o = (fsm_q == S_VALID);

  // Keystream output: valid when ready_o or valid_o is asserted
  genvar i;
  generate
    for (i = 0; i < 16; i++) begin : gen_ks
      assign keystream_o[i] = wk_q[i];
    end
  endgenerate

endmodule
