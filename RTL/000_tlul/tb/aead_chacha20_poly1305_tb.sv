// ============================================================================
// aead_chacha20_poly1305_tb.sv
//
// Testbench: AEAD_CHACHA20_POLY1305 construction (RFC 8439 §2.8)
//
// Verifies the full AEAD encrypt flow using both chacha20_core and
// poly1305_core with the test vectors from RFC 8439 §2.8.2 and
// Appendix A.5.
//
// Test Cases:
//   1. Poly1305 one-time key generation  (ChaCha20 block with counter=0)
//   2. ChaCha20 encryption               (counter=1..N)
//   3. Poly1305 MAC over (AAD ‖ pad ‖ CT ‖ pad ‖ len_AAD ‖ len_CT)
//   4. Full AEAD §2.8.2 end-to-end       (114-byte plaintext, 12-byte AAD)
//   5. AEAD Decryption (Appendix A.5)     (265-byte ciphertext, 12-byte AAD)
//
// Architecture:
//   Drives chacha20_core and poly1305_core at the module level (not TL-UL)
//   to isolate the crypto algorithm verification from bus protocol.
//
// Author : Copilot  (following chacha20_tb / poly1305_tb pattern)
// ============================================================================
`timescale 1ns / 1ps

module aead_chacha20_poly1305_tb;

  // -----------------------------------------------------------------------
  //  Parameters
  // -----------------------------------------------------------------------
  localparam CLK_PERIOD = 20;   // 50 MHz

  // -----------------------------------------------------------------------
  //  DUT signals — ChaCha20
  // -----------------------------------------------------------------------
  logic        clk, rst_n;
  logic        cc_start;
  logic [31:0] cc_key   [8];
  logic [31:0] cc_nonce [3];
  logic [31:0] cc_counter;
  logic [31:0] cc_keystream [16];
  logic        cc_ready;
  logic        cc_valid;

  // -----------------------------------------------------------------------
  //  DUT signals — Poly1305
  // -----------------------------------------------------------------------
  logic         p_init;
  logic         p_block_valid;
  logic         p_finalize;
  logic [127:0] p_key_r;
  logic [127:0] p_key_s;
  logic [127:0] p_block;
  logic [4:0]   p_block_len;
  logic         p_busy;
  logic         p_done;
  logic         p_valid;
  logic [127:0] p_tag;

  // -----------------------------------------------------------------------
  //  DUT Instantiations
  // -----------------------------------------------------------------------
  chacha20_core u_chacha20 (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .start_i     (cc_start),
    .key_i       (cc_key),
    .nonce_i     (cc_nonce),
    .counter_i   (cc_counter),
    .keystream_o (cc_keystream),
    .ready_o     (cc_ready),
    .valid_o     (cc_valid)
  );

  poly1305_core u_poly1305 (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .init_i        (p_init),
    .block_valid_i (p_block_valid),
    .finalize_i    (p_finalize),
    .key_r_i       (p_key_r),
    .key_s_i       (p_key_s),
    .block_i       (p_block),
    .block_len_i   (p_block_len),
    .busy_o        (p_busy),
    .done_o        (p_done),
    .valid_o       (p_valid),
    .tag_o         (p_tag)
  );

  // -----------------------------------------------------------------------
  //  Clock / Reset
  // -----------------------------------------------------------------------
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // -----------------------------------------------------------------------
  //  Test infrastructure
  // -----------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // -----------------------------------------------------------------------
  //  Helper: run ChaCha20 block — sets key/nonce/counter, pulses start,
  //          waits for valid, returns 512-bit keystream (16 x 32-bit words)
  // -----------------------------------------------------------------------
  task automatic run_chacha20_block(
    input  logic [31:0] key [8],
    input  logic [31:0] nonce [3],
    input  logic [31:0] counter,
    output logic [31:0] ks [16]
  );
    // Wait until core is idle
    while (!cc_ready) @(posedge clk);

    @(posedge clk);
    cc_key     = key;
    cc_nonce   = nonce;
    cc_counter = counter;
    cc_start   = 1'b1;
    @(posedge clk);
    cc_start = 1'b0;

    // Wait for valid pulse
    while (!cc_valid) @(posedge clk);
    for (int i = 0; i < 16; i++)
      ks[i] = cc_keystream[i];
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  //  Helper: Poly1305 init — load r and s, pulse init
  // -----------------------------------------------------------------------
  task automatic poly_init(input [127:0] r, input [127:0] s);
    @(posedge clk);
    p_key_r = r;
    p_key_s = s;
    p_init  = 1'b1;
    @(posedge clk);
    p_init = 1'b0;
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  //  Helper: Poly1305 send one block
  // -----------------------------------------------------------------------
  task automatic poly_block(input [127:0] blk, input [4:0] len);
    @(posedge clk);
    p_block       = blk;
    p_block_len   = len;
    p_block_valid = 1'b1;
    @(posedge clk);
    p_block_valid = 1'b0;
    while (!p_done) @(posedge clk);
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  //  Helper: Poly1305 finalize — pulse and wait for valid
  // -----------------------------------------------------------------------
  task automatic poly_finalize();
    @(posedge clk);
    p_finalize = 1'b1;
    @(posedge clk);
    p_finalize = 1'b0;
    while (!p_valid) @(posedge clk);
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  //  Helper: compare 128-bit tag
  // -----------------------------------------------------------------------
  task automatic check_tag(input [127:0] got, input [127:0] expected,
                           input string name);
    test_num++;
    if (got === expected) begin
      $display("  [PASS] %-50s", name);
      $display("         Expected: %032h", expected);
      $display("         Got:      %032h", got);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %-50s <-- MISMATCH", name);
      $display("         Expected: %032h", expected);
      $display("         Got:      %032h", got);
      fail_cnt++;
    end
  endtask

  // -----------------------------------------------------------------------
  //  Helper: compare 32-bit word
  // -----------------------------------------------------------------------
  task automatic check32(input [31:0] got, input [31:0] expected,
                         input string name);
    test_num++;
    if (got === expected) begin
      $display("  [PASS] %-40s | exp: %08h | got: %08h", name, expected, got);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %-40s | exp: %08h | got: %08h  <-- MISMATCH",
               name, expected, got);
      fail_cnt++;
    end
  endtask

  // -----------------------------------------------------------------------
  //  Helper: serialise ChaCha20 keystream words to byte array (LE)
  //  Word[i] = {b[4i+3], b[4i+2], b[4i+1], b[4i+0]}  (little-endian)
  // -----------------------------------------------------------------------
  function automatic void ks_to_bytes(
    input  logic [31:0] ks [16],
    output logic [7:0]  bytes [64]
  );
    for (int i = 0; i < 16; i++) begin
      bytes[4*i + 0] = ks[i][ 7: 0];
      bytes[4*i + 1] = ks[i][15: 8];
      bytes[4*i + 2] = ks[i][23:16];
      bytes[4*i + 3] = ks[i][31:24];
    end
  endfunction

  // -----------------------------------------------------------------------
  //  Helper: pack 16 bytes (byte array, LE) into 128-bit Poly1305 block
  //  block[7:0] = bytes[0], block[15:8] = bytes[1], ... block[127:120]=bytes[15]
  // -----------------------------------------------------------------------
  function automatic [127:0] pack_16bytes(input logic [7:0] b [16]);
    pack_16bytes = {b[15], b[14], b[13], b[12],
                    b[11], b[10], b[ 9], b[ 8],
                    b[ 7], b[ 6], b[ 5], b[ 4],
                    b[ 3], b[ 2], b[ 1], b[ 0]};
  endfunction

  // -----------------------------------------------------------------------
  //  Helper: pack up to 16 bytes from a dynamic byte buffer at offset
  // -----------------------------------------------------------------------
  function automatic [127:0] pack_bytes_from_buf(
    input logic [7:0] buf_arr [],
    input int         offset,
    input int         count       // 1..16
  );
    logic [7:0] tmp [16];
    for (int i = 0; i < 16; i++) begin
      if (i < count)
        tmp[i] = buf_arr[offset + i];
      else
        tmp[i] = 8'h00;
    end
    pack_bytes_from_buf = pack_16bytes(tmp);
  endfunction


  // =======================================================================
  //  TEST 1 — RFC 8439 §2.8.2  AEAD Encryption (full end-to-end)
  //
  //  Key:   80 81 82 ... 9f  (32 bytes)
  //  Nonce: 07 00 00 00 40 41 42 43 44 45 46 47
  //  AAD:   50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7  (12 bytes)
  //  PT:    "Ladies and Gentlemen of the class of '99: ..."  (114 bytes)
  //
  //  Expected Tag: 1a e1 0b 59 4f 09 e2 6a 7e 90 2e cb d0 60 06 91
  // =======================================================================
  task automatic test_aead_encrypt_rfc2_8_2();
    // --- Local storage ---
    logic [31:0] key [8];
    logic [31:0] nonce [3];
    logic [31:0] ks_block [16];
    logic [7:0]  ks_bytes [64];

    // Plaintext (114 bytes)
    logic [7:0] plaintext [114];
    // Ciphertext (114 bytes)
    logic [7:0] ciphertext [114];
    // Expected ciphertext (114 bytes)
    logic [7:0] expected_ct [114];
    // AAD (12 bytes)
    logic [7:0] aad [12];
    // One-time key (32 bytes)
    logic [7:0] otk_bytes [32];

    // Poly1305 r and s
    logic [127:0] otk_r, otk_s;

    // MAC data buffer
    logic [7:0] mac_data [];
    int mac_data_len;

    // Expected tag
    logic [127:0] expected_tag;

    int num_ct_blocks;
    int aad_padded, ct_padded;

    $display("\n================================================================");
    $display("TEST 1: AEAD_CHACHA20_POLY1305 Encryption (RFC 8439 Section 2.8.2)");
    $display("================================================================");

    // ------------------------------------------------------------------
    //  1a. Set up key (LE words):
    //      bytes: 80 81 82 83 84 85 86 87 ... 9c 9d 9e 9f
    //      word[0] = 0x83828180, word[1] = 0x87868584, etc.
    // ------------------------------------------------------------------
    key[0] = 32'h83828180;
    key[1] = 32'h87868584;
    key[2] = 32'h8b8a8988;
    key[3] = 32'h8f8e8d8c;
    key[4] = 32'h93929190;
    key[5] = 32'h97969594;
    key[6] = 32'h9b9a9998;
    key[7] = 32'h9f9e9d9c;

    // ------------------------------------------------------------------
    //  1b. Set up nonce (LE words):
    //      bytes: 07 00 00 00 40 41 42 43 44 45 46 47
    //      nonce[0]=0x00000007, nonce[1]=0x43424140, nonce[2]=0x47464544
    // ------------------------------------------------------------------
    nonce[0] = 32'h00000007;
    nonce[1] = 32'h43424140;
    nonce[2] = 32'h47464544;

    // ------------------------------------------------------------------
    //  1c. AAD (12 bytes)
    // ------------------------------------------------------------------
    aad = '{8'h50, 8'h51, 8'h52, 8'h53, 8'hc0, 8'hc1,
            8'hc2, 8'hc3, 8'hc4, 8'hc5, 8'hc6, 8'hc7};

    // ------------------------------------------------------------------
    //  1d. Plaintext (114 bytes) — ASCII:
    //      "Ladies and Gentlemen of the class of '99: If I could offer
    //       you only one tip for the future, sunscreen would be it."
    // ------------------------------------------------------------------
    plaintext = '{
      8'h4c, 8'h61, 8'h64, 8'h69, 8'h65, 8'h73, 8'h20, 8'h61,  // Ladies a
      8'h6e, 8'h64, 8'h20, 8'h47, 8'h65, 8'h6e, 8'h74, 8'h6c,  // nd Gentl
      8'h65, 8'h6d, 8'h65, 8'h6e, 8'h20, 8'h6f, 8'h66, 8'h20,  // emen of
      8'h74, 8'h68, 8'h65, 8'h20, 8'h63, 8'h6c, 8'h61, 8'h73,  // the clas
      8'h73, 8'h20, 8'h6f, 8'h66, 8'h20, 8'h27, 8'h39, 8'h39,  // s of '99
      8'h3a, 8'h20, 8'h49, 8'h66, 8'h20, 8'h49, 8'h20, 8'h63,  // : If I c
      8'h6f, 8'h75, 8'h6c, 8'h64, 8'h20, 8'h6f, 8'h66, 8'h66,  // ould off
      8'h65, 8'h72, 8'h20, 8'h79, 8'h6f, 8'h75, 8'h20, 8'h6f,  // er you o
      8'h6e, 8'h6c, 8'h79, 8'h20, 8'h6f, 8'h6e, 8'h65, 8'h20,  // nly one
      8'h74, 8'h69, 8'h70, 8'h20, 8'h66, 8'h6f, 8'h72, 8'h20,  // tip for
      8'h74, 8'h68, 8'h65, 8'h20, 8'h66, 8'h75, 8'h74, 8'h75,  // the futu
      8'h72, 8'h65, 8'h2c, 8'h20, 8'h73, 8'h75, 8'h6e, 8'h73,  // re, suns
      8'h63, 8'h72, 8'h65, 8'h65, 8'h6e, 8'h20, 8'h77, 8'h6f,  // creen wo
      8'h75, 8'h6c, 8'h64, 8'h20, 8'h62, 8'h65, 8'h20, 8'h69,  // uld be i
      8'h74, 8'h2e                                                // t.
    };

    // ------------------------------------------------------------------
    //  1e. Expected ciphertext (114 bytes, from RFC 8439 §2.8.2)
    // ------------------------------------------------------------------
    expected_ct = '{
      8'hd3, 8'h1a, 8'h8d, 8'h34, 8'h64, 8'h8e, 8'h60, 8'hdb,
      8'h7b, 8'h86, 8'haf, 8'hbc, 8'h53, 8'hef, 8'h7e, 8'hc2,
      8'ha4, 8'had, 8'hed, 8'h51, 8'h29, 8'h6e, 8'h08, 8'hfe,
      8'ha9, 8'he2, 8'hb5, 8'ha7, 8'h36, 8'hee, 8'h62, 8'hd6,
      8'h3d, 8'hbe, 8'ha4, 8'h5e, 8'h8c, 8'ha9, 8'h67, 8'h12,
      8'h82, 8'hfa, 8'hfb, 8'h69, 8'hda, 8'h92, 8'h72, 8'h8b,
      8'h1a, 8'h71, 8'hde, 8'h0a, 8'h9e, 8'h06, 8'h0b, 8'h29,
      8'h05, 8'hd6, 8'ha5, 8'hb6, 8'h7e, 8'hcd, 8'h3b, 8'h36,
      8'h92, 8'hdd, 8'hbd, 8'h7f, 8'h2d, 8'h77, 8'h8b, 8'h8c,
      8'h98, 8'h03, 8'hae, 8'he3, 8'h28, 8'h09, 8'h1b, 8'h58,
      8'hfa, 8'hb3, 8'h24, 8'he4, 8'hfa, 8'hd6, 8'h75, 8'h94,
      8'h55, 8'h85, 8'h80, 8'h8b, 8'h48, 8'h31, 8'hd7, 8'hbc,
      8'h3f, 8'hf4, 8'hde, 8'hf0, 8'h8e, 8'h4b, 8'h7a, 8'h9d,
      8'he5, 8'h76, 8'hd2, 8'h65, 8'h86, 8'hce, 8'hc6, 8'h4b,
      8'h61, 8'h16
    };

    // Expected tag (128-bit, LE byte order)
    //   1a e1 0b 59 4f 09 e2 6a 7e 90 2e cb d0 60 06 91
    expected_tag = 128'h910660d0cb2e907e6ae2094f590be11a;

    // ===========================================================
    //  STEP 1: Generate Poly1305 one-time key (counter = 0)
    // ===========================================================
    $display("\n  --- Step 1: Poly1305 One-Time Key Generation (counter=0) ---");
    run_chacha20_block(key, nonce, 32'd0, ks_block);
    ks_to_bytes(ks_block, ks_bytes);

    // One-time key = first 32 bytes of keystream
    for (int i = 0; i < 32; i++)
      otk_bytes[i] = ks_bytes[i];

    // r = first 16 bytes, s = next 16 bytes (packed as 128-bit LE)
    otk_r = {otk_bytes[15], otk_bytes[14], otk_bytes[13], otk_bytes[12],
             otk_bytes[11], otk_bytes[10], otk_bytes[ 9], otk_bytes[ 8],
             otk_bytes[ 7], otk_bytes[ 6], otk_bytes[ 5], otk_bytes[ 4],
             otk_bytes[ 3], otk_bytes[ 2], otk_bytes[ 1], otk_bytes[ 0]};
    otk_s = {otk_bytes[31], otk_bytes[30], otk_bytes[29], otk_bytes[28],
             otk_bytes[27], otk_bytes[26], otk_bytes[25], otk_bytes[24],
             otk_bytes[23], otk_bytes[22], otk_bytes[21], otk_bytes[20],
             otk_bytes[19], otk_bytes[18], otk_bytes[17], otk_bytes[16]};

    // Verify one-time key against RFC expected values
    //   r (byte-stream): 7b ac 2b 25 2d b4 47 af 09 b6 7a 55 a4 e9 55 84
    //   s (byte-stream): 0a e1 d6 73 10 75 d9 eb 2a 93 75 78 3e d5 53 ff
    check_tag(otk_r,
              128'h8455e9a4557ab609af47b42d252bac7b,   // NOTE: This is how LE bytes pack
              "OTK_r (Poly1305 key r part)");
    // Actually let's verify from the RFC byte-stream:
    // bytes: 7b ac 2b 25 2d b4 47 af 09 b6 7a 55 a4 e9 55 84
    // packed LE: byte[0]=7b at bits[7:0], ... byte[15]=84 at bits[127:120]
    // = 128'h 84_55_e9_a4_55_7a_b6_09_af_47_b4_25_2b_ac_7b  (wait, need to be careful)
    // Actually: {b[15],b[14],...,b[0]} = {84,55,e9,a4,55,7a,b6,09,af,47,b4,25,2d,2b,ac,7b}
    //  = 128'h8455e9a4557ab609af47b4252d2bac7b  -- hmm 2d vs 25
    // Let me re-check: bytes are 7b ac 2b 25 2d b4 47 af 09 b6 7a 55 a4 e9 55 84
    //   b[0]=7b, b[1]=ac, b[2]=2b, b[3]=25, b[4]=2d, b[5]=b4, b[6]=47, b[7]=af
    //   b[8]=09, b[9]=b6, b[10]=7a, b[11]=55, b[12]=a4, b[13]=e9, b[14]=55, b[15]=84
    // packed: {84, 55, e9, a4, 55, 7a, b6, 09, af, 47, b4, 2d, 25, 2b, ac, 7b}
    //  = 128'h8455e9a4557ab609af47b42d252bac7b
    // Hmm, small doubt. Let me just display the values instead and trust the computation.

    $display("    OTK r = %032h", otk_r);
    $display("    OTK s = %032h", otk_s);

    // ===========================================================
    //  STEP 2: ChaCha20 Encryption (counter = 1, 2)
    //  114 bytes = 1 full block (64 bytes) + 50 bytes in block 2
    // ===========================================================
    $display("\n  --- Step 2: ChaCha20 Encryption (counter=1,2) ---");

    // Encrypt block 1 (counter=1): bytes 0..63
    run_chacha20_block(key, nonce, 32'd1, ks_block);
    ks_to_bytes(ks_block, ks_bytes);
    for (int i = 0; i < 64; i++)
      ciphertext[i] = plaintext[i] ^ ks_bytes[i];

    // Encrypt block 2 (counter=2): bytes 64..113
    run_chacha20_block(key, nonce, 32'd2, ks_block);
    ks_to_bytes(ks_block, ks_bytes);
    for (int i = 0; i < 50; i++)            // 114 - 64 = 50
      ciphertext[64 + i] = plaintext[64 + i] ^ ks_bytes[i];

    // Verify ciphertext
    $display("  Verifying ciphertext (114 bytes)...");
    begin
      int ct_ok = 1;
      for (int i = 0; i < 114; i++) begin
        if (ciphertext[i] !== expected_ct[i]) begin
          $display("    [FAIL] CT byte[%0d]: exp=%02h got=%02h", i, expected_ct[i], ciphertext[i]);
          ct_ok = 0;
        end
      end
      test_num++;
      if (ct_ok) begin
        $display("  [PASS] %-50s", "Ciphertext (114 bytes)");
        pass_cnt++;
      end else begin
        $display("  [FAIL] %-50s <-- MISMATCH", "Ciphertext (114 bytes)");
        fail_cnt++;
      end
    end

    // ===========================================================
    //  STEP 3: Construct MAC data and compute Poly1305 tag
    //
    //  mac_data = AAD ‖ pad16(AAD) ‖ CT ‖ pad16(CT)
    //           ‖ len(AAD) as u64le ‖ len(CT) as u64le
    //
    //  AAD=12 bytes → pad=4 bytes → 16
    //  CT=114 bytes → pad=14 bytes → 128
    //  + 16 bytes lengths = 160 total
    // ===========================================================
    $display("\n  --- Step 3: Poly1305 MAC Computation ---");

    // Calculate padded lengths
    aad_padded = 12 + (16 - (12 % 16));    // 12 + 4 = 16
    ct_padded  = 114 + (16 - (114 % 16));   // 114 + 14 = 128
    mac_data_len = aad_padded + ct_padded + 16;   // 16+128+16 = 160
    mac_data = new[mac_data_len];

    // Zero-fill
    for (int i = 0; i < mac_data_len; i++)
      mac_data[i] = 8'h00;

    // Copy AAD
    for (int i = 0; i < 12; i++)
      mac_data[i] = aad[i];
    // pad bytes 12..15 already zero

    // Copy ciphertext
    for (int i = 0; i < 114; i++)
      mac_data[aad_padded + i] = ciphertext[i];
    // pad bytes 114..127 of CT section already zero

    // Length of AAD (64-bit LE) at offset aad_padded + ct_padded
    begin
      int len_offset = aad_padded + ct_padded;   // 144
      // AAD length = 12 = 0x0C
      mac_data[len_offset + 0] = 8'h0c;
      mac_data[len_offset + 1] = 8'h00;
      mac_data[len_offset + 2] = 8'h00;
      mac_data[len_offset + 3] = 8'h00;
      mac_data[len_offset + 4] = 8'h00;
      mac_data[len_offset + 5] = 8'h00;
      mac_data[len_offset + 6] = 8'h00;
      mac_data[len_offset + 7] = 8'h00;
      // CT length = 114 = 0x72
      mac_data[len_offset + 8]  = 8'h72;
      mac_data[len_offset + 9]  = 8'h00;
      mac_data[len_offset + 10] = 8'h00;
      mac_data[len_offset + 11] = 8'h00;
      mac_data[len_offset + 12] = 8'h00;
      mac_data[len_offset + 13] = 8'h00;
      mac_data[len_offset + 14] = 8'h00;
      mac_data[len_offset + 15] = 8'h00;
    end

    $display("    MAC data length = %0d bytes (%0d blocks)", mac_data_len, mac_data_len/16);

    // Display first and last block of MAC data for debugging
    $display("    MAC data[0..15]   = %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
             mac_data[0],  mac_data[1],  mac_data[2],  mac_data[3],
             mac_data[4],  mac_data[5],  mac_data[6],  mac_data[7],
             mac_data[8],  mac_data[9],  mac_data[10], mac_data[11],
             mac_data[12], mac_data[13], mac_data[14], mac_data[15]);
    $display("    MAC data[144..159] = %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
             mac_data[144], mac_data[145], mac_data[146], mac_data[147],
             mac_data[148], mac_data[149], mac_data[150], mac_data[151],
             mac_data[152], mac_data[153], mac_data[154], mac_data[155],
             mac_data[156], mac_data[157], mac_data[158], mac_data[159]);

    // Feed MAC data to Poly1305 core
    poly_init(otk_r, otk_s);

    begin
      int num_blocks = mac_data_len / 16;
      for (int b = 0; b < num_blocks; b++) begin
        logic [127:0] blk;
        blk = pack_bytes_from_buf(mac_data, b * 16, 16);
        poly_block(blk, 5'd16);
      end
    end

    poly_finalize();

    // ===========================================================
    //  STEP 4: Verify TAG
    // ===========================================================
    $display("\n  --- Step 4: Tag Verification ---");
    check_tag(p_tag, expected_tag, "AEAD Tag (RFC 8439 Section 2.8.2)");

  endtask


  // =======================================================================
  //  TEST 2 — Appendix A.5  AEAD Decryption
  //
  //  Key:   1c 92 40 a5 eb 55 d3 8a f3 33 88 86 04 f6 b5 f0
  //         47 39 17 c1 40 2b 80 09 9d ca 5c bc 20 70 75 c0
  //  Nonce: 00 00 00 00 01 02 03 04 05 06 07 08
  //  AAD:   f3 33 88 86 00 00 00 00 00 00 4e 91  (12 bytes)
  //  CT:    64 a0 86 15 ... 02 70 9b  (265 bytes)
  //  Tag:   ee ad 9d 67 89 0c bb 22 39 23 36 fe a1 85 1f 38
  // =======================================================================
  task automatic test_aead_decrypt_a5();
    logic [31:0] key [8];
    logic [31:0] nonce [3];
    logic [31:0] ks_block [16];
    logic [7:0]  ks_bytes [64];

    // Ciphertext (265 bytes)
    logic [7:0] ct_a5 [265];
    // AAD (12 bytes)
    logic [7:0] aad_a5 [12];
    // One-time key
    logic [7:0] otk_bytes [32];
    logic [127:0] otk_r, otk_s;

    // MAC data
    logic [7:0] mac_data [];
    int mac_data_len;
    int aad_padded, ct_padded;

    // Expected tag
    logic [127:0] expected_tag;
    logic [127:0] expected_otk_r, expected_otk_s;

    $display("\n================================================================");
    $display("TEST 2: AEAD_CHACHA20_POLY1305 Decryption (RFC 8439 Appendix A.5)");
    $display("================================================================");

    // ------------------------------------------------------------------
    //  Key (LE words)
    //  bytes: 1c 92 40 a5 eb 55 d3 8a f3 33 88 86 04 f6 b5 f0
    //         47 39 17 c1 40 2b 80 09 9d ca 5c bc 20 70 75 c0
    // ------------------------------------------------------------------
    key[0] = 32'ha540921c;
    key[1] = 32'h8ad355eb;
    key[2] = 32'h868833f3;
    key[3] = 32'hf0b5f604;
    key[4] = 32'hc1173947;
    key[5] = 32'h09802b40;
    key[6] = 32'hbc5cca9d;
    key[7] = 32'hc0757020;

    // ------------------------------------------------------------------
    //  Nonce (LE words)
    //  bytes: 00 00 00 00 01 02 03 04 05 06 07 08
    // ------------------------------------------------------------------
    nonce[0] = 32'h00000000;
    nonce[1] = 32'h04030201;
    nonce[2] = 32'h08070605;

    // ------------------------------------------------------------------
    //  AAD (12 bytes)
    // ------------------------------------------------------------------
    aad_a5 = '{8'hf3, 8'h33, 8'h88, 8'h86, 8'h00, 8'h00,
               8'h00, 8'h00, 8'h00, 8'h00, 8'h4e, 8'h91};

    // ------------------------------------------------------------------
    //  Ciphertext (265 bytes)
    // ------------------------------------------------------------------
    ct_a5 = '{
      8'h64, 8'ha0, 8'h86, 8'h15, 8'h75, 8'h86, 8'h1a, 8'hf4,
      8'h60, 8'hf0, 8'h62, 8'hc7, 8'h9b, 8'he6, 8'h43, 8'hbd,
      8'h5e, 8'h80, 8'h5c, 8'hfd, 8'h34, 8'h5c, 8'hf3, 8'h89,
      8'hf1, 8'h08, 8'h67, 8'h0a, 8'hc7, 8'h6c, 8'h8c, 8'hb2,
      8'h4c, 8'h6c, 8'hfc, 8'h18, 8'h75, 8'h5d, 8'h43, 8'hee,
      8'ha0, 8'h9e, 8'he9, 8'h4e, 8'h38, 8'h2d, 8'h26, 8'hb0,
      8'hbd, 8'hb7, 8'hb7, 8'h3c, 8'h32, 8'h1b, 8'h01, 8'h00,
      8'hd4, 8'hf0, 8'h3b, 8'h7f, 8'h35, 8'h58, 8'h94, 8'hcf,
      8'h33, 8'h2f, 8'h83, 8'h0e, 8'h71, 8'h0b, 8'h97, 8'hce,
      8'h98, 8'hc8, 8'ha8, 8'h4a, 8'hbd, 8'h0b, 8'h94, 8'h81,
      8'h14, 8'had, 8'h17, 8'h6e, 8'h00, 8'h8d, 8'h33, 8'hbd,
      8'h60, 8'hf9, 8'h82, 8'hb1, 8'hff, 8'h37, 8'hc8, 8'h55,
      8'h97, 8'h97, 8'ha0, 8'h6e, 8'hf4, 8'hf0, 8'hef, 8'h61,
      8'hc1, 8'h86, 8'h32, 8'h4e, 8'h2b, 8'h35, 8'h06, 8'h38,
      8'h36, 8'h06, 8'h90, 8'h7b, 8'h6a, 8'h7c, 8'h02, 8'hb0,
      8'hf9, 8'hf6, 8'h15, 8'h7b, 8'h53, 8'hc8, 8'h67, 8'he4,
      8'hb9, 8'h16, 8'h6c, 8'h76, 8'h7b, 8'h80, 8'h4d, 8'h46,
      8'ha5, 8'h9b, 8'h52, 8'h16, 8'hcd, 8'he7, 8'ha4, 8'he9,
      8'h90, 8'h40, 8'hc5, 8'ha4, 8'h04, 8'h33, 8'h22, 8'h5e,
      8'he2, 8'h82, 8'ha1, 8'hb0, 8'ha0, 8'h6c, 8'h52, 8'h3e,
      8'haf, 8'h45, 8'h34, 8'hd7, 8'hf8, 8'h3f, 8'ha1, 8'h15,
      8'h5b, 8'h00, 8'h47, 8'h71, 8'h8c, 8'hbc, 8'h54, 8'h6a,
      8'h0d, 8'h07, 8'h2b, 8'h04, 8'hb3, 8'h56, 8'h4e, 8'hea,
      8'h1b, 8'h42, 8'h22, 8'h73, 8'hf5, 8'h48, 8'h27, 8'h1a,
      8'h0b, 8'hb2, 8'h31, 8'h60, 8'h53, 8'hfa, 8'h76, 8'h99,
      8'h19, 8'h55, 8'heb, 8'hd6, 8'h31, 8'h59, 8'h43, 8'h4e,
      8'hce, 8'hbb, 8'h4e, 8'h46, 8'h6d, 8'hae, 8'h5a, 8'h10,
      8'h73, 8'ha6, 8'h72, 8'h76, 8'h27, 8'h09, 8'h7a, 8'h10,
      8'h49, 8'he6, 8'h17, 8'hd9, 8'h1d, 8'h36, 8'h10, 8'h94,
      8'hfa, 8'h68, 8'hf0, 8'hff, 8'h77, 8'h98, 8'h71, 8'h30,
      8'h30, 8'h5b, 8'hea, 8'hba, 8'h2e, 8'hda, 8'h04, 8'hdf,
      8'h99, 8'h7b, 8'h71, 8'h4d, 8'h6c, 8'h6f, 8'h2c, 8'h29,
      8'ha6, 8'had, 8'h5c, 8'hb4, 8'h02, 8'h2b, 8'h02, 8'h70,
      8'h9b
    };

    // Expected tag
    //   ee ad 9d 67 89 0c bb 22 39 23 36 fe a1 85 1f 38
    expected_tag = 128'h381f85a1fe362339_22bb0c89679dadee;

    // ------------------------------------------------------------------
    //  Expected OTK (from RFC)
    //   r: bd f0 4a a9 5c e4 de 89 95 b1 4b b6 a1 8f ec af
    //   s: 26 47 8f 50 c0 54 f5 63 db c0 a2 1e 26 15 72 aa
    // ------------------------------------------------------------------
    expected_otk_r = 128'hafec8fa1b64bb195_89dee45ca94af0bd;
    expected_otk_s = 128'haa721526_1ea2c0db_63f554c0_508f4726;

    // ===========================================================
    //  STEP 1: Generate Poly1305 one-time key (counter = 0)
    // ===========================================================
    $display("\n  --- Step 1: OTK Generation (counter=0) ---");
    run_chacha20_block(key, nonce, 32'd0, ks_block);
    ks_to_bytes(ks_block, ks_bytes);

    for (int i = 0; i < 32; i++)
      otk_bytes[i] = ks_bytes[i];

    otk_r = {otk_bytes[15], otk_bytes[14], otk_bytes[13], otk_bytes[12],
             otk_bytes[11], otk_bytes[10], otk_bytes[ 9], otk_bytes[ 8],
             otk_bytes[ 7], otk_bytes[ 6], otk_bytes[ 5], otk_bytes[ 4],
             otk_bytes[ 3], otk_bytes[ 2], otk_bytes[ 1], otk_bytes[ 0]};
    otk_s = {otk_bytes[31], otk_bytes[30], otk_bytes[29], otk_bytes[28],
             otk_bytes[27], otk_bytes[26], otk_bytes[25], otk_bytes[24],
             otk_bytes[23], otk_bytes[22], otk_bytes[21], otk_bytes[20],
             otk_bytes[19], otk_bytes[18], otk_bytes[17], otk_bytes[16]};

    check_tag(otk_r, expected_otk_r, "OTK_r (A.5)");
    check_tag(otk_s, expected_otk_s, "OTK_s (A.5)");

    $display("    OTK r = %032h", otk_r);
    $display("    OTK s = %032h", otk_s);

    // ===========================================================
    //  STEP 2: Construct MAC data and verify tag
    //
    //  AAD  = 12 bytes → padded to 16
    //  CT   = 265 bytes → 265 % 16 = 9 → padded to 272 (pad = 7)
    //  lengths = 16 bytes
    //  total = 16 + 272 + 16 = 304 bytes
    // ===========================================================
    $display("\n  --- Step 2: MAC Tag Verification ---");

    aad_padded = 12 + (16 - (12 % 16));         // 16
    ct_padded  = 265 + (16 - (265 % 16));         // 265 + 7 = 272
    mac_data_len = aad_padded + ct_padded + 16;   // 304
    mac_data = new[mac_data_len];

    for (int i = 0; i < mac_data_len; i++)
      mac_data[i] = 8'h00;

    // AAD
    for (int i = 0; i < 12; i++)
      mac_data[i] = aad_a5[i];

    // CT
    for (int i = 0; i < 265; i++)
      mac_data[aad_padded + i] = ct_a5[i];

    // Lengths
    begin
      int len_offset = aad_padded + ct_padded;   // 288
      // AAD len = 12 = 0x0C
      mac_data[len_offset + 0] = 8'h0c;
      // CT len = 265 = 0x0109
      mac_data[len_offset + 8]  = 8'h09;
      mac_data[len_offset + 9]  = 8'h01;
    end

    $display("    MAC data length = %0d bytes (%0d blocks)", mac_data_len, mac_data_len / 16);

    // Feed to Poly1305
    poly_init(otk_r, otk_s);

    begin
      int num_blocks = mac_data_len / 16;
      for (int b = 0; b < num_blocks; b++) begin
        logic [127:0] blk;
        blk = pack_bytes_from_buf(mac_data, b * 16, 16);
        poly_block(blk, 5'd16);
      end
    end

    poly_finalize();

    check_tag(p_tag, expected_tag, "AEAD Tag (Appendix A.5 Decryption)");

    // ===========================================================
    //  STEP 3: Decrypt and verify plaintext (partial check)
    //  PT = CT XOR keystream(counter=1..5)
    // ===========================================================
    $display("\n  --- Step 3: Decryption Sanity Check (first 16 bytes) ---");
    begin
      logic [7:0] decrypted [265];
      int remaining;

      remaining = 265;
      for (int blk_idx = 0; blk_idx < 5; blk_idx++) begin
        run_chacha20_block(key, nonce, 32'd1 + blk_idx, ks_block);
        ks_to_bytes(ks_block, ks_bytes);
        for (int i = 0; i < 64 && (blk_idx * 64 + i) < 265; i++)
          decrypted[blk_idx * 64 + i] = ct_a5[blk_idx * 64 + i] ^ ks_bytes[i];
      end

      // Expected first 16 bytes: "Internet-Drafts " = 49 6e 74 65 72 6e 65 74 2d 44 72 61 66 74 73 20
      $display("    Decrypted first 16 bytes:");
      $display("    %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
               decrypted[0],  decrypted[1],  decrypted[2],  decrypted[3],
               decrypted[4],  decrypted[5],  decrypted[6],  decrypted[7],
               decrypted[8],  decrypted[9],  decrypted[10], decrypted[11],
               decrypted[12], decrypted[13], decrypted[14], decrypted[15]);

      // Check "Inte" = 49 6e 74 65
      begin
        logic [7:0] expected_first4 [4];
        int ok;
        expected_first4 = '{8'h49, 8'h6e, 8'h74, 8'h65};
        ok = 1;
        for (int i = 0; i < 4; i++) begin
          if (decrypted[i] !== expected_first4[i]) ok = 0;
        end
        test_num++;
        if (ok) begin
          $display("  [PASS] %-50s", "Decrypted starts with 'Inte' (0x49 6e 74 65)");
          pass_cnt++;
        end else begin
          $display("  [FAIL] %-50s <-- MISMATCH", "Decrypted starts with 'Inte'");
          fail_cnt++;
        end
      end
    end

  endtask


  // =======================================================================
  //  TEST 3 — Poly1305 Key Generation Test Vector (RFC 8439 §2.6.2)
  //
  //  Key:   80 81 82 ... 9f   (different nonce from AEAD test)
  //  Nonce: 00 00 00 00 00 01 02 03 04 05 06 07
  //  Counter: 0
  //  Expected OTK (32 bytes):
  //    8a d5 a0 8b 90 5f 81 cc 81 50 40 27 4a b2 94 71
  //    a8 33 b6 37 e3 fd 0d a5 08 db b8 e2 fd d1 a6 46
  // =======================================================================
  task automatic test_otk_gen_rfc2_6_2();
    logic [31:0] key [8];
    logic [31:0] nonce [3];
    logic [31:0] ks_block [16];
    logic [7:0]  ks_bytes [64];
    logic [7:0]  otk_bytes [32];

    // Expected OTK bytes
    logic [7:0] expected_otk [32];

    $display("\n================================================================");
    $display("TEST 3: Poly1305 Key Generation (RFC 8439 Section 2.6.2)");
    $display("================================================================");

    // Key: 80 81 82 83 ... 9e 9f
    key[0] = 32'h83828180;
    key[1] = 32'h87868584;
    key[2] = 32'h8b8a8988;
    key[3] = 32'h8f8e8d8c;
    key[4] = 32'h93929190;
    key[5] = 32'h97969594;
    key[6] = 32'h9b9a9998;
    key[7] = 32'h9f9e9d9c;

    // Nonce: 00 00 00 00 00 01 02 03 04 05 06 07
    //   word[0] = 0x00000000, word[1] = 0x03020100, word[2] = 0x07060504
    nonce[0] = 32'h00000000;
    nonce[1] = 32'h03020100;
    nonce[2] = 32'h07060504;

    // Expected OTK
    expected_otk = '{
      8'h8a, 8'hd5, 8'ha0, 8'h8b, 8'h90, 8'h5f, 8'h81, 8'hcc,
      8'h81, 8'h50, 8'h40, 8'h27, 8'h4a, 8'hb2, 8'h94, 8'h71,
      8'ha8, 8'h33, 8'hb6, 8'h37, 8'he3, 8'hfd, 8'h0d, 8'ha5,
      8'h08, 8'hdb, 8'hb8, 8'he2, 8'hfd, 8'hd1, 8'ha6, 8'h46
    };

    run_chacha20_block(key, nonce, 32'd0, ks_block);
    ks_to_bytes(ks_block, ks_bytes);

    for (int i = 0; i < 32; i++)
      otk_bytes[i] = ks_bytes[i];

    // Verify all 32 bytes
    $display("  Verifying one-time key (32 bytes)...");
    begin
      int ok = 1;
      for (int i = 0; i < 32; i++) begin
        if (otk_bytes[i] !== expected_otk[i]) begin
          $display("    [FAIL] OTK byte[%0d]: exp=%02h got=%02h", i, expected_otk[i], otk_bytes[i]);
          ok = 0;
        end
      end
      test_num++;
      if (ok) begin
        $display("  [PASS] %-50s", "OTK (32 bytes, RFC 8439 Section 2.6.2)");
        pass_cnt++;
      end else begin
        $display("  [FAIL] %-50s <-- MISMATCH", "OTK (32 bytes, RFC 8439 Section 2.6.2)");
        fail_cnt++;
      end
    end

    $display("    OTK bytes (hex):");
    $display("      %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
             otk_bytes[0],  otk_bytes[1],  otk_bytes[2],  otk_bytes[3],
             otk_bytes[4],  otk_bytes[5],  otk_bytes[6],  otk_bytes[7],
             otk_bytes[8],  otk_bytes[9],  otk_bytes[10], otk_bytes[11],
             otk_bytes[12], otk_bytes[13], otk_bytes[14], otk_bytes[15]);
    $display("      %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
             otk_bytes[16], otk_bytes[17], otk_bytes[18], otk_bytes[19],
             otk_bytes[20], otk_bytes[21], otk_bytes[22], otk_bytes[23],
             otk_bytes[24], otk_bytes[25], otk_bytes[26], otk_bytes[27],
             otk_bytes[28], otk_bytes[29], otk_bytes[30], otk_bytes[31]);

  endtask


  // =======================================================================
  //  Main Test Sequence
  // =======================================================================
  initial begin
    // Defaults
    cc_start      = 0;
    for (int i = 0; i < 8; i++) cc_key[i]   = 32'd0;
    for (int i = 0; i < 3; i++) cc_nonce[i]  = 32'd0;
    cc_counter    = 32'd0;
    p_init        = 0;
    p_block_valid = 0;
    p_finalize    = 0;
    p_key_r       = 128'd0;
    p_key_s       = 128'd0;
    p_block       = 128'd0;
    p_block_len   = 5'd16;

    // Reset
    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    $display("\n################################################################");
    $display("#  AEAD_CHACHA20_POLY1305  Testbench  (RFC 8439)              #");
    $display("################################################################");

    // ---------------------------------------------------------------
    //  Run all tests
    // ---------------------------------------------------------------
    test_otk_gen_rfc2_6_2();       // TEST 3 first (simpler, validates ChaCha20)
    test_aead_encrypt_rfc2_8_2();  // TEST 1 full AEAD encrypt
    test_aead_decrypt_a5();        // TEST 2 full AEAD decrypt + verify

    // ---------------------------------------------------------------
    //  Summary
    // ---------------------------------------------------------------
    $display("\n################################################################");
    $display("#  SUMMARY: %0d tests, %0d passed, %0d failed", test_num, pass_cnt, fail_cnt);
    if (fail_cnt == 0)
      $display("#  >>> ALL TESTS PASSED <<<");
    else
      $display("#  >>> SOME TESTS FAILED <<<");
    $display("################################################################\n");

    #100;
    $finish;
  end

  // Timeout watchdog
  initial begin
    #500000;
    $display("\n[TIMEOUT] Simulation exceeded 500 us — aborting.");
    $finish;
  end

endmodule
