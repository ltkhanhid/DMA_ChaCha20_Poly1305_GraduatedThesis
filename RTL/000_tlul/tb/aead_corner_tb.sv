// ============================================================================
// aead_corner_tb.sv — Corner-Case Tests for AEAD_CHACHA20_POLY1305
//
// Tests edge conditions of the AEAD construction (RFC 8439 §2.8):
//
//  TC  | PT len | AAD len | Description
//  ----|--------|---------|------------------------------------------
//   1  |    0   |   12    | Empty plaintext, only AAD → tag-only
//   2  |   64   |    0    | No AAD, one full ChaCha20 block
//   3  |    0   |    0    | Both empty → tag from lengths block only
//   4  |    1   |    1    | Minimal single-byte PT and AAD
//   5  |   15   |   15    | Just under one Poly1305 block (partial)
//   6  |   16   |   16    | Exact one Poly1305 block (no padding)
//   7  |   17   |   17    | One byte over a block boundary
//   8  |   64   |   12    | Full ChaCha20 block (encrypt-decrypt trip)
//   9  |   65   |   12    | Crosses into 2nd ChaCha20 block
//  10  |  128   |   32    | Two full ChaCha20 blocks, 2x Poly AAD blk
//  11  |   --   |   --    | Tag sensitivity: flip 1 CT bit → tag change
//  12  |   --   |   --    | Re-init: double init resets accumulator
//
// Methodology:
//   • Each test runs a full AEAD encrypt, then AEAD decrypt round-trip
//   • Verifies: decrypted_PT == original_PT, encrypt_tag == decrypt_tag
//   • Test 11 verifies tag changes if ciphertext is tampered
//   • Test 12 verifies Poly1305 re-init correctness
//
// Author : Copilot
// ============================================================================
`timescale 1ns / 1ps

module aead_corner_tb;

  // -----------------------------------------------------------------------
  //  Clock / Parameters
  // -----------------------------------------------------------------------
  localparam CLK_PERIOD = 20;   // 50 MHz

  logic clk, rst_n;
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // -----------------------------------------------------------------------
  //  DUT — ChaCha20
  // -----------------------------------------------------------------------
  logic        cc_start;
  logic [31:0] cc_key     [8];
  logic [31:0] cc_nonce   [3];
  logic [31:0] cc_counter;
  logic [31:0] cc_keystream [16];
  logic        cc_ready, cc_valid;

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

  // -----------------------------------------------------------------------
  //  DUT — Poly1305
  // -----------------------------------------------------------------------
  logic         p_init, p_block_valid, p_finalize;
  logic [127:0] p_key_r, p_key_s, p_block;
  logic [4:0]   p_block_len;
  logic         p_busy, p_done, p_valid;
  logic [127:0] p_tag;

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
  //  Counters
  // -----------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // =====================================================================
  //  Low-level helpers  (same as aead_chacha20_poly1305_tb)
  // =====================================================================

  task automatic run_chacha20_block(
    input  logic [31:0] key   [8],
    input  logic [31:0] nonce [3],
    input  logic [31:0] counter,
    output logic [31:0] ks    [16]
  );
    while (!cc_ready) @(posedge clk);
    @(posedge clk);
    cc_key     = key;
    cc_nonce   = nonce;
    cc_counter = counter;
    cc_start   = 1'b1;
    @(posedge clk);
    cc_start   = 1'b0;
    while (!cc_valid) @(posedge clk);
    for (int i = 0; i < 16; i++) ks[i] = cc_keystream[i];
    @(posedge clk);
  endtask

  task automatic poly_init(input [127:0] r, input [127:0] s);
    @(posedge clk);
    p_key_r = r;  p_key_s = s;  p_init = 1'b1;
    @(posedge clk);
    p_init = 1'b0;
    @(posedge clk);
  endtask

  task automatic poly_block(input [127:0] blk, input [4:0] len);
    @(posedge clk);
    p_block = blk;  p_block_len = len;  p_block_valid = 1'b1;
    @(posedge clk);
    p_block_valid = 1'b0;
    while (!p_done) @(posedge clk);
    @(posedge clk);
  endtask

  task automatic poly_finalize();
    @(posedge clk);
    p_finalize = 1'b1;
    @(posedge clk);
    p_finalize = 1'b0;
    while (!p_valid) @(posedge clk);
    @(posedge clk);
  endtask

  // ── Serialise keystream words → byte array (LE) ──
  function automatic void ks_to_bytes(
    input  logic [31:0] ks    [16],
    output logic [7:0]  bytes [64]
  );
    for (int i = 0; i < 16; i++) begin
      bytes[4*i+0] = ks[i][ 7: 0];
      bytes[4*i+1] = ks[i][15: 8];
      bytes[4*i+2] = ks[i][23:16];
      bytes[4*i+3] = ks[i][31:24];
    end
  endfunction

  // ── Pack up to 16 bytes (LE) into 128-bit Poly1305 block ──
  function automatic [127:0] pack_block(
    input logic [7:0] buf_arr [],
    input int         offset,
    input int         count       // 1..16
  );
    logic [7:0] tmp [16];
    for (int i = 0; i < 16; i++)
      tmp[i] = (i < count) ? buf_arr[offset + i] : 8'h00;
    pack_block = {tmp[15], tmp[14], tmp[13], tmp[12],
                  tmp[11], tmp[10], tmp[ 9], tmp[ 8],
                  tmp[ 7], tmp[ 6], tmp[ 5], tmp[ 4],
                  tmp[ 3], tmp[ 2], tmp[ 1], tmp[ 0]};
  endfunction

  // =====================================================================
  //  AEAD_ENCRYPT — generic, variable-length PT and AAD
  //
  //  Outputs: ct[] (same length as pt), tag (128-bit)
  // =====================================================================
  task automatic aead_encrypt(
    input  logic [31:0] key      [8],
    input  logic [31:0] nonce    [3],
    input  logic [7:0]  pt       [],
    input  logic [7:0]  aad      [],
    output logic [7:0]  ct       [],
    output logic [127:0] tag
  );
    int pt_len, aad_len;
    logic [31:0] ks_block [16];
    logic [7:0]  ks_bytes [64];
    logic [7:0]  otk [32];
    logic [127:0] otk_r, otk_s;
    int num_enc_blocks;

    // MAC construction buffer
    logic [7:0] mac_data [];
    int aad_padded, ct_padded, mac_len;

    pt_len  = pt.size();
    aad_len = aad.size();
    ct      = new[pt_len];

    // === Step 1: OTK generation (counter=0) ===
    run_chacha20_block(key, nonce, 32'd0, ks_block);
    ks_to_bytes(ks_block, ks_bytes);
    for (int i = 0; i < 32; i++) otk[i] = ks_bytes[i];

    otk_r = {otk[15], otk[14], otk[13], otk[12],
             otk[11], otk[10], otk[ 9], otk[ 8],
             otk[ 7], otk[ 6], otk[ 5], otk[ 4],
             otk[ 3], otk[ 2], otk[ 1], otk[ 0]};
    otk_s = {otk[31], otk[30], otk[29], otk[28],
             otk[27], otk[26], otk[25], otk[24],
             otk[23], otk[22], otk[21], otk[20],
             otk[19], otk[18], otk[17], otk[16]};

    // === Step 2: Encrypt (counter=1..N) ===
    num_enc_blocks = (pt_len + 63) / 64;
    for (int b = 0; b < num_enc_blocks; b++) begin
      int base, chunk;
      run_chacha20_block(key, nonce, 32'd1 + b, ks_block);
      ks_to_bytes(ks_block, ks_bytes);
      base  = b * 64;
      chunk = (pt_len - base > 64) ? 64 : (pt_len - base);
      for (int i = 0; i < chunk; i++)
        ct[base + i] = pt[base + i] ^ ks_bytes[i];
    end

    // === Step 3: Poly1305 MAC ===
    //  mac_data = AAD | pad16(AAD) | CT | pad16(CT) | len_aad_u64le | len_ct_u64le
    aad_padded = (aad_len == 0) ? 0 : (aad_len + ((16 - (aad_len % 16)) % 16));
    ct_padded  = (pt_len  == 0) ? 0 : (pt_len  + ((16 - (pt_len  % 16)) % 16));
    mac_len    = aad_padded + ct_padded + 16;  // +16 for two u64 lengths
    mac_data   = new[mac_len];

    for (int i = 0; i < mac_len; i++) mac_data[i] = 8'h00;

    // Copy AAD
    for (int i = 0; i < aad_len; i++) mac_data[i] = aad[i];

    // Copy CT
    for (int i = 0; i < pt_len; i++) mac_data[aad_padded + i] = ct[i];

    // Lengths (u64 LE): aad_len, ct_len
    begin
      int off = aad_padded + ct_padded;
      mac_data[off + 0] = aad_len[7:0];
      mac_data[off + 1] = aad_len[15:8];
      mac_data[off + 2] = aad_len[23:16];
      mac_data[off + 3] = aad_len[31:24];
      // off+4..+7 = 0  (high 32 bits)
      mac_data[off + 8]  = pt_len[7:0];
      mac_data[off + 9]  = pt_len[15:8];
      mac_data[off + 10] = pt_len[23:16];
      mac_data[off + 11] = pt_len[31:24];
      // off+12..+15 = 0
    end

    // Feed Poly1305
    poly_init(otk_r, otk_s);
    begin
      int num_mac_blocks = mac_len / 16;
      for (int b = 0; b < num_mac_blocks; b++)
        poly_block(pack_block(mac_data, b * 16, 16), 5'd16);
    end
    poly_finalize();
    tag = p_tag;
  endtask

  // =====================================================================
  //  AEAD_DECRYPT — same as encrypt (XOR is symmetric) + MAC verify
  //
  //  Outputs: pt[] (decrypted), tag (re-computed), tag_ok
  // =====================================================================
  task automatic aead_decrypt(
    input  logic [31:0]  key   [8],
    input  logic [31:0]  nonce [3],
    input  logic [7:0]   ct    [],
    input  logic [7:0]   aad   [],
    input  logic [127:0] exp_tag,
    output logic [7:0]   pt    [],
    output logic [127:0] dec_tag,
    output logic         tag_ok
  );
    int ct_len, aad_len;
    logic [31:0] ks_block [16];
    logic [7:0]  ks_bytes [64];
    logic [7:0]  otk [32];
    logic [127:0] otk_r, otk_s;
    int num_blocks;

    logic [7:0] mac_data [];
    int aad_padded, ct_padded, mac_len;

    ct_len  = ct.size();
    aad_len = aad.size();
    pt      = new[ct_len];

    // OTK (counter=0)
    run_chacha20_block(key, nonce, 32'd0, ks_block);
    ks_to_bytes(ks_block, ks_bytes);
    for (int i = 0; i < 32; i++) otk[i] = ks_bytes[i];

    otk_r = {otk[15], otk[14], otk[13], otk[12],
             otk[11], otk[10], otk[ 9], otk[ 8],
             otk[ 7], otk[ 6], otk[ 5], otk[ 4],
             otk[ 3], otk[ 2], otk[ 1], otk[ 0]};
    otk_s = {otk[31], otk[30], otk[29], otk[28],
             otk[27], otk[26], otk[25], otk[24],
             otk[23], otk[22], otk[21], otk[20],
             otk[19], otk[18], otk[17], otk[16]};

    // MAC verification (over ciphertext, before decryption per RFC 8439)
    aad_padded = (aad_len == 0) ? 0 : (aad_len + ((16 - (aad_len % 16)) % 16));
    ct_padded  = (ct_len  == 0) ? 0 : (ct_len  + ((16 - (ct_len  % 16)) % 16));
    mac_len    = aad_padded + ct_padded + 16;
    mac_data   = new[mac_len];

    for (int i = 0; i < mac_len; i++) mac_data[i] = 8'h00;
    for (int i = 0; i < aad_len; i++) mac_data[i] = aad[i];
    for (int i = 0; i < ct_len;  i++) mac_data[aad_padded + i] = ct[i];
    begin
      int off = aad_padded + ct_padded;
      mac_data[off + 0] = aad_len[7:0];   mac_data[off + 1] = aad_len[15:8];
      mac_data[off + 2] = aad_len[23:16]; mac_data[off + 3] = aad_len[31:24];
      mac_data[off + 8]  = ct_len[7:0];   mac_data[off + 9]  = ct_len[15:8];
      mac_data[off + 10] = ct_len[23:16]; mac_data[off + 11] = ct_len[31:24];
    end

    poly_init(otk_r, otk_s);
    begin
      int num_mac_blocks = mac_len / 16;
      for (int b = 0; b < num_mac_blocks; b++)
        poly_block(pack_block(mac_data, b * 16, 16), 5'd16);
    end
    poly_finalize();
    dec_tag = p_tag;
    tag_ok  = (dec_tag === exp_tag);

    // Decrypt (counter=1..N)
    num_blocks = (ct_len + 63) / 64;
    for (int b = 0; b < num_blocks; b++) begin
      int base, chunk;
      run_chacha20_block(key, nonce, 32'd1 + b, ks_block);
      ks_to_bytes(ks_block, ks_bytes);
      base  = b * 64;
      chunk = (ct_len - base > 64) ? 64 : (ct_len - base);
      for (int i = 0; i < chunk; i++)
        pt[base + i] = ct[base + i] ^ ks_bytes[i];
    end
  endtask

  // =====================================================================
  //  RESULT CHECKER — encrypt→decrypt round-trip
  // =====================================================================
  task automatic check_roundtrip(
    input string    test_name,
    input logic [7:0] orig_pt [],
    input logic [7:0] dec_pt  [],
    input logic [127:0] enc_tag,
    input logic [127:0] dec_tag,
    input logic         tag_ok
  );
    int pt_ok;
    pt_ok = 1;
    if (orig_pt.size() != dec_pt.size()) begin
      pt_ok = 0;
    end else begin
      for (int i = 0; i < orig_pt.size(); i++)
        if (orig_pt[i] !== dec_pt[i]) pt_ok = 0;
    end

    // Check 1: Plaintext round-trip
    test_num++;
    if (pt_ok) begin
      $display("  [PASS] %-55s", {test_name, " — PT round-trip"});
      pass_cnt++;
    end else begin
      $display("  [FAIL] %-55s <-- MISMATCH", {test_name, " — PT round-trip"});
      fail_cnt++;
      // Show diff
      for (int i = 0; i < orig_pt.size() && i < dec_pt.size(); i++)
        if (orig_pt[i] !== dec_pt[i])
          $display("         PT byte[%0d]: orig=%02h dec=%02h", i, orig_pt[i], dec_pt[i]);
    end

    // Check 2: Tag match
    test_num++;
    if (tag_ok) begin
      $display("  [PASS] %-55s", {test_name, " — Tag match"});
      $display("         Enc tag: %032h", enc_tag);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %-55s <-- MISMATCH", {test_name, " — Tag match"});
      $display("         Enc tag: %032h", enc_tag);
      $display("         Dec tag: %032h", dec_tag);
      fail_cnt++;
    end
  endtask

  // =====================================================================
  //  Generic test runner: encrypt → print → decrypt → verify
  // =====================================================================
  task automatic run_aead_test(
    input string       test_name,
    input logic [31:0] key   [8],
    input logic [31:0] nonce [3],
    input logic [7:0]  pt_in [],
    input logic [7:0]  aad   []
  );
    logic [7:0]   ct [];
    logic [7:0]   dec_pt [];
    logic [127:0] enc_tag, dec_tag;
    logic         tag_ok;
    int pt_len, aad_len;

    pt_len  = pt_in.size();
    aad_len = aad.size();

    $display("\n  --- %s (PT=%0d B, AAD=%0d B) ---", test_name, pt_len, aad_len);

    // Encrypt
    aead_encrypt(key, nonce, pt_in, aad, ct, enc_tag);

    // Print summary
    if (pt_len > 0) begin
      $display("    CT[0..%0d]:", (pt_len < 16 ? pt_len-1 : 15));
      begin
        string s; s = "      ";
        for (int i = 0; i < pt_len && i < 16; i++)
          s = {s, $sformatf("%02h ", ct[i])};
        $display("%s", s);
      end
      if (pt_len > 16)
        $display("      ... (%0d more bytes)", pt_len - 16);
    end else begin
      $display("    CT: (empty)");
    end
    $display("    Tag: %032h", enc_tag);

    // Decrypt + verify
    aead_decrypt(key, nonce, ct, aad, enc_tag, dec_pt, dec_tag, tag_ok);
    check_roundtrip(test_name, pt_in, dec_pt, enc_tag, dec_tag, tag_ok);
  endtask

  // =====================================================================
  //  Test Key & Nonce  (RFC 8439 §2.8.2)
  // =====================================================================
  logic [31:0] K [8];
  logic [31:0] N [3];

  task setup_key_nonce();
    K[0] = 32'h83828180;  K[1] = 32'h87868584;
    K[2] = 32'h8b8a8988;  K[3] = 32'h8f8e8d8c;
    K[4] = 32'h93929190;  K[5] = 32'h97969594;
    K[6] = 32'h9b9a9998;  K[7] = 32'h9f9e9d9c;
    N[0] = 32'h00000007;
    N[1] = 32'h43424140;
    N[2] = 32'h47464544;
  endtask

  // =====================================================================
  //  MAIN TEST SEQUENCE
  // =====================================================================
  initial begin
    // Defaults
    cc_start      = 0;
    for (int i = 0; i < 8; i++) cc_key[i]   = 0;
    for (int i = 0; i < 3; i++) cc_nonce[i]  = 0;
    cc_counter    = 0;
    p_init        = 0;
    p_block_valid = 0;
    p_finalize    = 0;
    p_key_r       = 0;
    p_key_s       = 0;
    p_block       = 0;
    p_block_len   = 16;

    // Reset
    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    setup_key_nonce();

    $display("\n################################################################");
    $display("#  AEAD_CHACHA20_POLY1305  Corner-Case Testbench               #");
    $display("################################################################");

    // ============================================================
    // TC1: Empty plaintext, 12-byte AAD
    // ============================================================
    begin
      logic [7:0] pt_empty [];
      logic [7:0] aad12 [];
      pt_empty = new[0];
      aad12 = new[12];
      aad12 = '{8'h50, 8'h51, 8'h52, 8'h53, 8'hc0, 8'hc1,
                8'hc2, 8'hc3, 8'hc4, 8'hc5, 8'hc6, 8'hc7};
      run_aead_test("TC1: Empty PT, 12B AAD", K, N, pt_empty, aad12);
    end

    // ============================================================
    // TC2: 64-byte PT, no AAD
    // ============================================================
    begin
      logic [7:0] pt64 [];
      logic [7:0] aad_empty [];
      pt64 = new[64];
      for (int i = 0; i < 64; i++) pt64[i] = i[7:0];
      aad_empty = new[0];
      run_aead_test("TC2: 64B PT, no AAD", K, N, pt64, aad_empty);
    end

    // ============================================================
    // TC3: Both empty
    // ============================================================
    begin
      logic [7:0] pt0 [];
      logic [7:0] aad0 [];
      pt0  = new[0];
      aad0 = new[0];
      run_aead_test("TC3: Empty PT, empty AAD", K, N, pt0, aad0);
    end

    // ============================================================
    // TC4: Single byte PT, single byte AAD
    // ============================================================
    begin
      logic [7:0] pt1 [];
      logic [7:0] aad1 [];
      pt1 = new[1];  pt1[0] = 8'hAB;
      aad1 = new[1]; aad1[0] = 8'hCD;
      run_aead_test("TC4: 1B PT, 1B AAD", K, N, pt1, aad1);
    end

    // ============================================================
    // TC5: 15 bytes PT, 15 bytes AAD (just under a block)
    // ============================================================
    begin
      logic [7:0] pt15 [];
      logic [7:0] aad15 [];
      pt15  = new[15];
      aad15 = new[15];
      for (int i = 0; i < 15; i++) begin
        pt15[i]  = 8'h10 + i[7:0];
        aad15[i] = 8'hA0 + i[7:0];
      end
      run_aead_test("TC5: 15B PT, 15B AAD (partial blocks)", K, N, pt15, aad15);
    end

    // ============================================================
    // TC6: 16 bytes PT, 16 bytes AAD (exact blocks, no padding)
    // ============================================================
    begin
      logic [7:0] pt16 [];
      logic [7:0] aad16 [];
      pt16  = new[16];
      aad16 = new[16];
      for (int i = 0; i < 16; i++) begin
        pt16[i]  = 8'h20 + i[7:0];
        aad16[i] = 8'hB0 + i[7:0];
      end
      run_aead_test("TC6: 16B PT, 16B AAD (exact, no padding)", K, N, pt16, aad16);
    end

    // ============================================================
    // TC7: 17 bytes PT, 17 bytes AAD (one byte over boundary)
    // ============================================================
    begin
      logic [7:0] pt17 [];
      logic [7:0] aad17 [];
      pt17  = new[17];
      aad17 = new[17];
      for (int i = 0; i < 17; i++) begin
        pt17[i]  = 8'h30 + i[7:0];
        aad17[i] = 8'hC0 + i[7:0];
      end
      run_aead_test("TC7: 17B PT, 17B AAD (1 over boundary)", K, N, pt17, aad17);
    end

    // ============================================================
    // TC8: 64-byte PT, 12-byte AAD (full ChaCha20 block)
    // ============================================================
    begin
      logic [7:0] pt64 [];
      logic [7:0] aad12 [];
      pt64  = new[64];
      aad12 = new[12];
      for (int i = 0; i < 64; i++) pt64[i]  = i[7:0] ^ 8'hFF;
      aad12 = '{8'h50, 8'h51, 8'h52, 8'h53, 8'hc0, 8'hc1,
                8'hc2, 8'hc3, 8'hc4, 8'hc5, 8'hc6, 8'hc7};
      run_aead_test("TC8: 64B PT, 12B AAD (full block)", K, N, pt64, aad12);
    end

    // ============================================================
    // TC9: 65-byte PT, 12-byte AAD (crosses into 2nd ChaCha block)
    // ============================================================
    begin
      logic [7:0] pt65 [];
      logic [7:0] aad12 [];
      pt65  = new[65];
      aad12 = new[12];
      for (int i = 0; i < 65; i++) pt65[i] = (i * 7 + 3) & 8'hFF;
      aad12 = '{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF,
                8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66};
      run_aead_test("TC9: 65B PT, 12B AAD (crosses ChaCha block)", K, N, pt65, aad12);
    end

    // ============================================================
    // TC10: 128-byte PT, 32-byte AAD (2 full ChaCha blocks, 2 AAD blocks)
    // ============================================================
    begin
      logic [7:0] pt128 [];
      logic [7:0] aad32 [];
      pt128 = new[128];
      aad32 = new[32];
      for (int i = 0; i < 128; i++) pt128[i] = (i * 13 + 7) & 8'hFF;
      for (int i = 0; i < 32;  i++) aad32[i] = (i * 5 + 11) & 8'hFF;
      run_aead_test("TC10: 128B PT, 32B AAD (2 ChaCha blocks)", K, N, pt128, aad32);
    end

    // ============================================================
    // TC11: Tag sensitivity — flip 1 bit in CT, tags must differ
    // ============================================================
    begin
      logic [7:0]   pt_ts [];
      logic [7:0]   aad_ts [];
      logic [7:0]   ct_good [];
      logic [7:0]   ct_bad  [];
      logic [127:0] tag_good, tag_bad;
      logic [7:0]   dec_pt [];
      logic [127:0] dec_tag;
      logic         tok;

      $display("\n  --- TC11: Tag sensitivity (flip 1 CT bit) ---");

      pt_ts  = new[32];
      aad_ts = new[8];
      for (int i = 0; i < 32; i++) pt_ts[i]  = i[7:0];
      for (int i = 0; i < 8;  i++) aad_ts[i] = 8'hF0 + i[7:0];

      // Encrypt normally
      aead_encrypt(K, N, pt_ts, aad_ts, ct_good, tag_good);
      $display("    Good tag: %032h", tag_good);

      // Tamper: flip bit 0 of CT byte[0]
      ct_bad = new[ct_good.size()];
      for (int i = 0; i < ct_good.size(); i++) ct_bad[i] = ct_good[i];
      ct_bad[0] = ct_bad[0] ^ 8'h01;

      // Re-MAC the tampered CT
      aead_decrypt(K, N, ct_bad, aad_ts, tag_good, dec_pt, dec_tag, tok);
      $display("    Bad  tag: %032h", dec_tag);

      test_num++;
      if (!tok && dec_tag !== tag_good) begin
        $display("  [PASS] %-55s", "TC11: Tag sensitivity — tags differ");
        pass_cnt++;
      end else begin
        $display("  [FAIL] %-55s <-- TAG NOT AFFECTED", "TC11: Tag sensitivity");
        fail_cnt++;
      end
    end

    // ============================================================
    // TC12: Poly1305 re-init — double init resets accumulator
    // ============================================================
    begin
      logic [7:0]   pt_a [], pt_b [];
      logic [7:0]   aad_a [], aad_b [];
      logic [7:0]   ct_a [], ct_b [];
      logic [127:0] tag_a, tag_b, tag_b2;
      logic [7:0]   ct_b2 [];

      $display("\n  --- TC12: Poly1305 re-init correctness ---");

      // Encrypt with data A
      pt_a  = new[16]; aad_a = new[4];
      for (int i = 0; i < 16; i++) pt_a[i]  = 8'hAA;
      for (int i = 0; i < 4;  i++) aad_a[i] = 8'h11;
      aead_encrypt(K, N, pt_a, aad_a, ct_a, tag_a);
      $display("    Tag A: %032h  (PT=16×0xAA, AAD=4×0x11)", tag_a);

      // Encrypt with data B (different data, same key/nonce)
      pt_b  = new[16]; aad_b = new[4];
      for (int i = 0; i < 16; i++) pt_b[i]  = 8'hBB;
      for (int i = 0; i < 4;  i++) aad_b[i] = 8'h22;
      aead_encrypt(K, N, pt_b, aad_b, ct_b, tag_b);
      $display("    Tag B: %032h  (PT=16×0xBB, AAD=4×0x22)", tag_b);

      // Encrypt B again — must match tag_b (proves re-init works)
      aead_encrypt(K, N, pt_b, aad_b, ct_b2, tag_b2);
      $display("    Tag B': %032h (re-run of B)", tag_b2);

      // Check: A != B, and B == B'
      test_num++;
      if (tag_a !== tag_b) begin
        $display("  [PASS] %-55s", "TC12a: Different data → different tags");
        pass_cnt++;
      end else begin
        $display("  [FAIL] %-55s <-- SAME TAG FOR DIFFERENT DATA", "TC12a");
        fail_cnt++;
      end

      test_num++;
      if (tag_b === tag_b2) begin
        $display("  [PASS] %-55s", "TC12b: Re-init gives identical tag");
        pass_cnt++;
      end else begin
        $display("  [FAIL] %-55s <-- TAG CHANGED ON RE-RUN", "TC12b");
        fail_cnt++;
      end
    end

    // ============================================================
    // TC13: All-zero key and nonce — degenerate but valid
    // ============================================================
    begin
      logic [31:0] K0 [8];
      logic [31:0] N0 [3];
      logic [7:0]  pt_z [];
      logic [7:0]  aad_z [];
      for (int i = 0; i < 8; i++) K0[i] = 32'd0;
      for (int i = 0; i < 3; i++) N0[i] = 32'd0;
      pt_z  = new[48];
      aad_z = new[8];
      for (int i = 0; i < 48; i++) pt_z[i]  = 8'h00;
      for (int i = 0; i < 8;  i++) aad_z[i] = 8'h00;
      run_aead_test("TC13: All-zero key/nonce/PT/AAD", K0, N0, pt_z, aad_z);
    end

    // ============================================================
    // TC14: 63-byte PT (one byte short of full ChaCha block)
    // ============================================================
    begin
      logic [7:0] pt63 [];
      logic [7:0] aad4 [];
      pt63 = new[63];
      aad4 = new[4];
      for (int i = 0; i < 63; i++) pt63[i] = (i + 100) & 8'hFF;
      aad4 = '{8'hDE, 8'hAD, 8'hBE, 8'hEF};
      run_aead_test("TC14: 63B PT (1 short of block)", K, N, pt63, aad4);
    end

    // ============================================================
    // TC15: 129 bytes PT, 1 byte AAD — large & minimal
    // ============================================================
    begin
      logic [7:0] pt129 [];
      logic [7:0] aad1  [];
      pt129 = new[129];
      aad1  = new[1];
      for (int i = 0; i < 129; i++) pt129[i] = (i * 3) & 8'hFF;
      aad1[0] = 8'hFF;
      run_aead_test("TC15: 129B PT, 1B AAD (3 ChaCha blks)", K, N, pt129, aad1);
    end

    // ============================================================
    //  SUMMARY
    // ============================================================
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
    #2_000_000;
    $display("\n[TIMEOUT] Simulation exceeded 2 ms — aborting.");
    $finish;
  end

endmodule
