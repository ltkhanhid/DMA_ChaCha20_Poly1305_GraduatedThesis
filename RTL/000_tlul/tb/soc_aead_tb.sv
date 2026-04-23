`timescale 1ns/1ps

// ============================================================
// soc_aead_tb.sv — SoC AEAD ChaCha20-Poly1305 Demo Testbench
//
// Full end-to-end AEAD verification through the SoC:
//   UART TX → SoC UART RX → Firmware AEAD → SoC UART TX → Capture
//
// AEAD Flow (RFC 8439 §2.8):
//   1. OTK Generation: ChaCha20(key,nonce,counter=0) → r||s
//   2. Encryption:     CT = ChaCha20(key,nonce,counter=1) XOR PT
//   3. MAC Input:      AAD | pad16 | CT | pad16 | len_aad | len_ct
//   4. Tag:            Poly1305(otk, mac_input)
//
// Verification:
//   - Ciphertext:  Compared against RFC 8439 §2.8.2 expected CT
//   - Tag:         Computed by reference chacha20_core + poly1305_core
//
// Parameters: RFC 8439 §2.8.2 (64-byte subset)
//   Key   : 80 81 82 ... 9e 9f  (32 bytes)
//   Nonce : 07 00 00 00 40 41 42 43 44 45 46 47  (12 bytes)
//   AAD   : 50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7  (12 bytes)
//   PT    : "Ladies and Gentlemen of the class of '99: If I could offer you o"
// ============================================================

module soc_aead_tb;
  import tlul_pkg::*;

  // ─── Parameters ───────────────────────────────────────────
  parameter CLK_PERIOD = 20;              // 50 MHz
  parameter MEM_DEPTH  = 65536;
  parameter BIT_PERIOD = 50_000_000 / 115_200;  // ~434 cycles/bit
  parameter NUM_TX_BYTES = 80;            // 64 CT + 16 TAG

  // ─── DUT Signals ──────────────────────────────────────────
  logic        clk, rst_n;
  logic [9:0]  sw_i, ledr_o;
  logic [31:0] ledg_o;
  logic [6:0]  hex0_o, hex1_o, hex2_o, hex3_o;
  logic [6:0]  hex4_o, hex5_o, hex6_o, hex7_o;
  logic        uart_rx_i, uart_tx_o;
  logic        irq_dma, irq_chacha, irq_poly;
  logic [31:0] pc_debug, pc_wb, pc_mem;
  logic        insn_vld, ctrl, mispred;

  // ─── Test Data ────────────────────────────────────────────
  logic [7:0] PTEXT [0:63];
  logic [7:0] EXP_CT [0:63];                // RFC8439 expected ciphertext
  logic [7:0] received [0:NUM_TX_BYTES-1];   // Captured UART TX
  logic [127:0] ref_tag;                     // Reference-computed tag

  int  rx_count;
  logic capture_done;

  // ─── Clock ────────────────────────────────────────────────
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ─── DUT Instantiation ───────────────────────────────────
  soc_top_2m6s #(
    .MEM_DEPTH (MEM_DEPTH),
    .MEM_FILE  ("demo_aead.hex")
  ) u_soc (
    .clk       (clk),
    .rst_n     (rst_n),
    .sw_i      (sw_i),
    .ledr_o    (ledr_o),
    .ledg_o    (ledg_o),
    .hex0_o    (hex0_o),
    .hex1_o    (hex1_o),
    .hex2_o    (hex2_o),
    .hex3_o    (hex3_o),
    .hex4_o    (hex4_o),
    .hex5_o    (hex5_o),
    .hex6_o    (hex6_o),
    .hex7_o    (hex7_o),
    .uart_rx_i (uart_rx_i),
    .uart_tx_o (uart_tx_o),
    .irq_dma_o (irq_dma),
    .irq_chacha_o(irq_chacha),
    .irq_poly_o(irq_poly),
    .pc_debug_o(pc_debug),
    .pc_wb_o   (pc_wb),
    .pc_mem_o  (pc_mem),
    .insn_vld_o(insn_vld),
    .ctrl_o    (ctrl),
    .mispred_o (mispred)
  );

  // ═════════════════════════════════════════════════════════
  //  REFERENCE MODEL — ChaCha20 + Poly1305 for expected values
  // ═════════════════════════════════════════════════════════

  // ── Reference ChaCha20 ──
  logic        ref_cc_start;
  logic [31:0] ref_cc_key   [8];
  logic [31:0] ref_cc_nonce [3];
  logic [31:0] ref_cc_counter;
  logic [31:0] ref_cc_keystream [16];
  logic        ref_cc_ready, ref_cc_valid;

  chacha20_core ref_chacha20 (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .start_i     (ref_cc_start),
    .key_i       (ref_cc_key),
    .nonce_i     (ref_cc_nonce),
    .counter_i   (ref_cc_counter),
    .keystream_o (ref_cc_keystream),
    .ready_o     (ref_cc_ready),
    .valid_o     (ref_cc_valid)
  );

  // ── Reference Poly1305 ──
  logic         ref_p_init;
  logic         ref_p_block_valid;
  logic         ref_p_finalize;
  logic [127:0] ref_p_key_r, ref_p_key_s;
  logic [127:0] ref_p_block;
  logic [4:0]   ref_p_block_len;
  logic         ref_p_busy, ref_p_done, ref_p_valid;
  logic [127:0] ref_p_tag;

  poly1305_core ref_poly1305 (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .init_i        (ref_p_init),
    .block_valid_i (ref_p_block_valid),
    .finalize_i    (ref_p_finalize),
    .key_r_i       (ref_p_key_r),
    .key_s_i       (ref_p_key_s),
    .block_i       (ref_p_block),
    .block_len_i   (ref_p_block_len),
    .busy_o        (ref_p_busy),
    .done_o        (ref_p_done),
    .valid_o       (ref_p_valid),
    .tag_o         (ref_p_tag)
  );

  // ═════════════════════════════════════════════════════════
  //  Helper Functions
  // ═════════════════════════════════════════════════════════

  function string hex_to_char(input [6:0] seg);
    case(seg)
      7'b1000000: hex_to_char = "0";
      7'b1111001: hex_to_char = "1";
      7'b0100100: hex_to_char = "2";
      7'b0110000: hex_to_char = "3";
      7'b0011001: hex_to_char = "4";
      7'b0010010: hex_to_char = "5";
      7'b0000010: hex_to_char = "6";
      7'b1111000: hex_to_char = "7";
      7'b0000000: hex_to_char = "8";
      7'b0010000: hex_to_char = "9";
      7'b0001000: hex_to_char = "A";
      7'b0000011: hex_to_char = "b";
      7'b1000110: hex_to_char = "C";
      7'b0100001: hex_to_char = "d";
      7'b0000110: hex_to_char = "E";
      7'b0001110: hex_to_char = "F";
      7'b1111111: hex_to_char = " ";
      7'b0111111: hex_to_char = "-";
      default:    hex_to_char = "?";
    endcase
  endfunction

  function string ascii_to_char(input [7:0] c);
    if (c >= 32 && c <= 126)
      ascii_to_char = $sformatf("%c", c);
    else
      ascii_to_char = ".";
  endfunction

  task display_hex();
    $display("  7-SEG: [ %s | %s | %s | %s | %s | %s | %s | %s ]",
      hex_to_char(hex7_o), hex_to_char(hex6_o),
      hex_to_char(hex5_o), hex_to_char(hex4_o),
      hex_to_char(hex3_o), hex_to_char(hex2_o),
      hex_to_char(hex1_o), hex_to_char(hex0_o));
  endtask

  task wait_cycles(int n);
    repeat(n) @(posedge clk);
  endtask

  // ═════════════════════════════════════════════════════════
  //  UART Tasks
  // ═════════════════════════════════════════════════════════

  task uart_send_byte(input [7:0] data);
    integer i;
    uart_rx_i = 1'b0;                          // Start bit
    repeat(BIT_PERIOD) @(posedge clk);
    for (i = 0; i < 8; i++) begin
      uart_rx_i = data[i];
      repeat(BIT_PERIOD) @(posedge clk);
    end
    uart_rx_i = 1'b1;                          // Stop bit
    repeat(BIT_PERIOD) @(posedge clk);
    repeat(BIT_PERIOD) @(posedge clk);         // inter-byte gap
  endtask

  task automatic uart_recv_byte(output logic [7:0] data);
    integer i;
    @(negedge uart_tx_o);
    repeat(BIT_PERIOD / 2) @(posedge clk);
    for (i = 0; i < 8; i++) begin
      repeat(BIT_PERIOD) @(posedge clk);
      data[i] = uart_tx_o;
    end
    repeat(BIT_PERIOD) @(posedge clk);
  endtask

  // ═════════════════════════════════════════════════════════
  //  Reference Model Helper Tasks
  // ═════════════════════════════════════════════════════════

  task automatic ref_chacha20_block(
    input  logic [31:0] key [8],
    input  logic [31:0] nonce [3],
    input  logic [31:0] counter,
    output logic [31:0] ks [16]
  );
    while (!ref_cc_ready) @(posedge clk);
    @(posedge clk);
    ref_cc_key     = key;
    ref_cc_nonce   = nonce;
    ref_cc_counter = counter;
    ref_cc_start   = 1'b1;
    @(posedge clk);
    ref_cc_start   = 1'b0;
    while (!ref_cc_valid) @(posedge clk);
    for (int i = 0; i < 16; i++) ks[i] = ref_cc_keystream[i];
    @(posedge clk);
  endtask

  task automatic ref_poly_init(input [127:0] r, input [127:0] s);
    @(posedge clk);
    ref_p_key_r = r;
    ref_p_key_s = s;
    ref_p_init  = 1'b1;
    @(posedge clk);
    ref_p_init  = 1'b0;
    @(posedge clk);
  endtask

  task automatic ref_poly_block(input [127:0] blk, input [4:0] len);
    @(posedge clk);
    ref_p_block       = blk;
    ref_p_block_len   = len;
    ref_p_block_valid = 1'b1;
    @(posedge clk);
    ref_p_block_valid = 1'b0;
    while (!ref_p_done) @(posedge clk);
    @(posedge clk);
  endtask

  task automatic ref_poly_finalize();
    @(posedge clk);
    ref_p_finalize = 1'b1;
    @(posedge clk);
    ref_p_finalize = 1'b0;
    while (!ref_p_valid) @(posedge clk);
    @(posedge clk);
  endtask

  // Helper: pack 16 bytes (LE array) into 128-bit block
  function automatic [127:0] pack_16bytes(input logic [7:0] b [16]);
    pack_16bytes = {b[15], b[14], b[13], b[12],
                    b[11], b[10], b[ 9], b[ 8],
                    b[ 7], b[ 6], b[ 5], b[ 4],
                    b[ 3], b[ 2], b[ 1], b[ 0]};
  endfunction

  // Helper: serialize keystream words to bytes (LE)
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

  // ═════════════════════════════════════════════════════════
  //  Reference AEAD Computation
  //
  //  Computes expected ciphertext and tag independently
  //  using reference ChaCha20 + Poly1305 cores.
  // ═════════════════════════════════════════════════════════
  logic [7:0] ref_ct [64];
  logic       ref_computed;

  task automatic compute_reference();
    logic [31:0] key [8];
    logic [31:0] nonce [3];
    logic [31:0] ks_block [16];
    logic [7:0]  ks_bytes [64];
    logic [7:0]  otk_bytes [32];
    logic [127:0] otk_r, otk_s;
    logic [7:0]  mac_data [96];  // 16+64+16 = 96 bytes
    logic [7:0]  blk16 [16];

    // Key
    key[0] = 32'h83828180;  key[1] = 32'h87868584;
    key[2] = 32'h8b8a8988;  key[3] = 32'h8f8e8d8c;
    key[4] = 32'h93929190;  key[5] = 32'h97969594;
    key[6] = 32'h9b9a9998;  key[7] = 32'h9f9e9d9c;
    // Nonce
    nonce[0] = 32'h00000007;
    nonce[1] = 32'h43424140;
    nonce[2] = 32'h47464544;

    $display("  [REF] Computing reference AEAD values...");

    // ── Step 1: OTK Generation (counter=0) ──
    ref_chacha20_block(key, nonce, 32'd0, ks_block);
    ks_to_bytes(ks_block, ks_bytes);
    for (int i = 0; i < 32; i++) otk_bytes[i] = ks_bytes[i];

    otk_r = {otk_bytes[15], otk_bytes[14], otk_bytes[13], otk_bytes[12],
             otk_bytes[11], otk_bytes[10], otk_bytes[ 9], otk_bytes[ 8],
             otk_bytes[ 7], otk_bytes[ 6], otk_bytes[ 5], otk_bytes[ 4],
             otk_bytes[ 3], otk_bytes[ 2], otk_bytes[ 1], otk_bytes[ 0]};
    otk_s = {otk_bytes[31], otk_bytes[30], otk_bytes[29], otk_bytes[28],
             otk_bytes[27], otk_bytes[26], otk_bytes[25], otk_bytes[24],
             otk_bytes[23], otk_bytes[22], otk_bytes[21], otk_bytes[20],
             otk_bytes[19], otk_bytes[18], otk_bytes[17], otk_bytes[16]};

    $display("  [REF] OTK r = %032h", otk_r);
    $display("  [REF] OTK s = %032h", otk_s);

    // ── Step 2: Encryption (counter=1) ──
    ref_chacha20_block(key, nonce, 32'd1, ks_block);
    ks_to_bytes(ks_block, ks_bytes);
    for (int i = 0; i < 64; i++)
      ref_ct[i] = PTEXT[i] ^ ks_bytes[i];

    $display("  [REF] Ciphertext computed (64 bytes)");

    // ── Step 3: Poly1305 MAC ──
    // Build MAC data: AAD|pad|CT|len_aad|len_ct = 96 bytes
    for (int i = 0; i < 96; i++) mac_data[i] = 8'h00;

    // AAD (12 bytes) + pad (4 zeros)
    mac_data[ 0] = 8'h50; mac_data[ 1] = 8'h51;
    mac_data[ 2] = 8'h52; mac_data[ 3] = 8'h53;
    mac_data[ 4] = 8'hc0; mac_data[ 5] = 8'hc1;
    mac_data[ 6] = 8'hc2; mac_data[ 7] = 8'hc3;
    mac_data[ 8] = 8'hc4; mac_data[ 9] = 8'hc5;
    mac_data[10] = 8'hc6; mac_data[11] = 8'hc7;
    // 12..15 = zero (padding)

    // CT (64 bytes at offset 16)
    for (int i = 0; i < 64; i++)
      mac_data[16 + i] = ref_ct[i];

    // Lengths at offset 80
    mac_data[80] = 8'h0c;   // aad_len = 12 (u64 LE)
    // 81..87 = 0
    mac_data[88] = 8'h40;   // ct_len = 64 (u64 LE)
    // 89..95 = 0

    // Feed to Poly1305
    ref_poly_init(otk_r, otk_s);
    for (int b = 0; b < 6; b++) begin
      for (int j = 0; j < 16; j++) blk16[j] = mac_data[b*16 + j];
      ref_poly_block(pack_16bytes(blk16), 5'd16);
    end
    ref_poly_finalize();
    ref_tag = ref_p_tag;

    $display("  [REF] Tag = %032h", ref_tag);
    $display("  [REF] Reference computation complete.");
    ref_computed = 1;
  endtask

  // ═════════════════════════════════════════════════════════
  //  7-Segment Phase Change Monitor
  // ═════════════════════════════════════════════════════════
  logic [6:0] prev_hex0 = 7'h7f;
  logic [6:0] prev_hex1 = 7'h7f;

  always @(posedge clk) begin
    if (rst_n && ({hex1_o, hex0_o} !== {prev_hex1, prev_hex0})) begin
      prev_hex0 <= hex0_o;
      prev_hex1 <= hex1_o;
      $display("[%0t] Phase update:", $time);
      display_hex();
    end
  end

  // ═════════════════════════════════════════════════════════
  //  UART TX Capture Process (runs in parallel)
  // ═════════════════════════════════════════════════════════
  initial begin : uart_capture_proc
    logic [7:0] byte_data;
    rx_count     = 0;
    capture_done = 0;

    wait(rst_n === 1'b1);

    while (rx_count < NUM_TX_BYTES) begin
      uart_recv_byte(byte_data);
      received[rx_count] = byte_data;

      if (rx_count < 4 || rx_count >= 60 && rx_count < 64 ||
          rx_count >= 64 || (rx_count % 16 == 0))
        $display("  [UART-CAP] byte[%2d]: 0x%02h%s",
                 rx_count, byte_data,
                 (rx_count >= 64) ? "  (TAG)" : "  (CT)");
      else if (rx_count == 4)
        $display("  [UART-CAP] ... capturing CT bytes 4-59 ...");

      rx_count = rx_count + 1;
    end

    capture_done = 1;
    $display("[%0t] All %0d bytes captured from UART TX.", $time, NUM_TX_BYTES);
  end

  // ═════════════════════════════════════════════════════════
  //  MAIN TEST SEQUENCE
  // ═════════════════════════════════════════════════════════
  initial begin
    integer i;
    int pass_ct, fail_ct, pass_tag, fail_tag;
    int t_start, t_end;

    // ── Initialize Test Data ────────────────────────────────
    // Plaintext: first 64 bytes of "Sunscreen" (RFC 8439 §2.8.2)
    PTEXT[ 0] = 8'h4c; PTEXT[ 1] = 8'h61; PTEXT[ 2] = 8'h64; PTEXT[ 3] = 8'h69;
    PTEXT[ 4] = 8'h65; PTEXT[ 5] = 8'h73; PTEXT[ 6] = 8'h20; PTEXT[ 7] = 8'h61;
    PTEXT[ 8] = 8'h6e; PTEXT[ 9] = 8'h64; PTEXT[10] = 8'h20; PTEXT[11] = 8'h47;
    PTEXT[12] = 8'h65; PTEXT[13] = 8'h6e; PTEXT[14] = 8'h74; PTEXT[15] = 8'h6c;
    PTEXT[16] = 8'h65; PTEXT[17] = 8'h6d; PTEXT[18] = 8'h65; PTEXT[19] = 8'h6e;
    PTEXT[20] = 8'h20; PTEXT[21] = 8'h6f; PTEXT[22] = 8'h66; PTEXT[23] = 8'h20;
    PTEXT[24] = 8'h74; PTEXT[25] = 8'h68; PTEXT[26] = 8'h65; PTEXT[27] = 8'h20;
    PTEXT[28] = 8'h63; PTEXT[29] = 8'h6c; PTEXT[30] = 8'h61; PTEXT[31] = 8'h73;
    PTEXT[32] = 8'h73; PTEXT[33] = 8'h20; PTEXT[34] = 8'h6f; PTEXT[35] = 8'h66;
    PTEXT[36] = 8'h20; PTEXT[37] = 8'h27; PTEXT[38] = 8'h39; PTEXT[39] = 8'h39;
    PTEXT[40] = 8'h3a; PTEXT[41] = 8'h20; PTEXT[42] = 8'h49; PTEXT[43] = 8'h66;
    PTEXT[44] = 8'h20; PTEXT[45] = 8'h49; PTEXT[46] = 8'h20; PTEXT[47] = 8'h63;
    PTEXT[48] = 8'h6f; PTEXT[49] = 8'h75; PTEXT[50] = 8'h6c; PTEXT[51] = 8'h64;
    PTEXT[52] = 8'h20; PTEXT[53] = 8'h6f; PTEXT[54] = 8'h66; PTEXT[55] = 8'h66;
    PTEXT[56] = 8'h65; PTEXT[57] = 8'h72; PTEXT[58] = 8'h20; PTEXT[59] = 8'h79;
    PTEXT[60] = 8'h6f; PTEXT[61] = 8'h75; PTEXT[62] = 8'h20; PTEXT[63] = 8'h6f;

    // Expected ciphertext (first 64 bytes of RFC 8439 §2.8.2)
    EXP_CT[ 0] = 8'hd3; EXP_CT[ 1] = 8'h1a; EXP_CT[ 2] = 8'h8d; EXP_CT[ 3] = 8'h34;
    EXP_CT[ 4] = 8'h64; EXP_CT[ 5] = 8'h8e; EXP_CT[ 6] = 8'h60; EXP_CT[ 7] = 8'hdb;
    EXP_CT[ 8] = 8'h7b; EXP_CT[ 9] = 8'h86; EXP_CT[10] = 8'haf; EXP_CT[11] = 8'hbc;
    EXP_CT[12] = 8'h53; EXP_CT[13] = 8'hef; EXP_CT[14] = 8'h7e; EXP_CT[15] = 8'hc2;
    EXP_CT[16] = 8'ha4; EXP_CT[17] = 8'had; EXP_CT[18] = 8'hed; EXP_CT[19] = 8'h51;
    EXP_CT[20] = 8'h29; EXP_CT[21] = 8'h6e; EXP_CT[22] = 8'h08; EXP_CT[23] = 8'hfe;
    EXP_CT[24] = 8'ha9; EXP_CT[25] = 8'he2; EXP_CT[26] = 8'hb5; EXP_CT[27] = 8'ha7;
    EXP_CT[28] = 8'h36; EXP_CT[29] = 8'hee; EXP_CT[30] = 8'h62; EXP_CT[31] = 8'hd6;
    EXP_CT[32] = 8'h3d; EXP_CT[33] = 8'hbe; EXP_CT[34] = 8'ha4; EXP_CT[35] = 8'h5e;
    EXP_CT[36] = 8'h8c; EXP_CT[37] = 8'ha9; EXP_CT[38] = 8'h67; EXP_CT[39] = 8'h12;
    EXP_CT[40] = 8'h82; EXP_CT[41] = 8'hfa; EXP_CT[42] = 8'hfb; EXP_CT[43] = 8'h69;
    EXP_CT[44] = 8'hda; EXP_CT[45] = 8'h92; EXP_CT[46] = 8'h72; EXP_CT[47] = 8'h8b;
    EXP_CT[48] = 8'h1a; EXP_CT[49] = 8'h71; EXP_CT[50] = 8'hde; EXP_CT[51] = 8'h0a;
    EXP_CT[52] = 8'h9e; EXP_CT[53] = 8'h06; EXP_CT[54] = 8'h0b; EXP_CT[55] = 8'h29;
    EXP_CT[56] = 8'h05; EXP_CT[57] = 8'hd6; EXP_CT[58] = 8'ha5; EXP_CT[59] = 8'hb6;
    EXP_CT[60] = 8'h7e; EXP_CT[61] = 8'hcd; EXP_CT[62] = 8'h3b; EXP_CT[63] = 8'h36;

    // ── Init reference signals ──────────────────────────────
    ref_cc_start      = 0;
    for (int j = 0; j < 8; j++) ref_cc_key[j]   = 0;
    for (int j = 0; j < 3; j++) ref_cc_nonce[j]  = 0;
    ref_cc_counter    = 0;
    ref_p_init        = 0;
    ref_p_block_valid = 0;
    ref_p_finalize    = 0;
    ref_p_key_r       = 0;
    ref_p_key_s       = 0;
    ref_p_block       = 0;
    ref_p_block_len   = 16;
    ref_computed      = 0;

    // ══════════════════════════════════════════════════════════
    //  BANNER
    // ══════════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    $display(" AEAD CHACHA20-POLY1305  SoC Demo  (RFC 8439 Section 2.8)");
    $display("================================================================");
    $display("");
    $display(" INPUT PARAMETERS:");
    $display("   Key   : 80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f");
    $display("           90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f");
    $display("   Nonce : 07 00 00 00 40 41 42 43 44 45 46 47");
    $display("   AAD   : 50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7  (12 bytes)");
    $display("");
    $display(" PLAINTEXT (64 bytes):");
    for (i = 0; i < 4; i++) begin
      string line_hex, line_asc;
      line_hex = "";
      line_asc = "";
      for (int j = 0; j < 16; j++) begin
        line_hex = {line_hex, $sformatf("%02h ", PTEXT[i*16+j])};
        line_asc = {line_asc, ascii_to_char(PTEXT[i*16+j])};
      end
      $display("   %03d: %s |%s|", i*16, line_hex, line_asc);
    end
    $display("");
    $display(" AEAD Flow: OTK(ctr=0) -> Encrypt(ctr=1) -> MAC(6 blocks) -> Tag");
    $display(" UART: 115200 baud | TX: 80 bytes (64 CT + 16 TAG)");
    $display("================================================================");

    // ── Reset ───────────────────────────────────────────────
    rst_n    = 0;
    sw_i     = 0;
    uart_rx_i = 1;
    wait_cycles(20);
    rst_n = 1;
    $display("");
    $display("[%0t] Reset released.", $time);

    // Wait for firmware to init
    wait_cycles(2000);

    // ══════════════════════════════════════════════════════════
    //  Compute Reference (while firmware waits for UART data)
    // ══════════════════════════════════════════════════════════
    $display("");
    $display("--- Computing reference AEAD values (parallel with DUT) ---");
    compute_reference();
    $display("");

    // ══════════════════════════════════════════════════════════
    //  Send 64 plaintext bytes via UART
    // ══════════════════════════════════════════════════════════
    $display("--- Sending 64 plaintext bytes via UART (115200 baud) ---");
    t_start = $time;

    for (i = 0; i < 64; i++) begin
      if (i < 4 || i >= 60)
        $display("  [UART-TX] byte[%2d]: 0x%02h  '%s'",
                 i, PTEXT[i], ascii_to_char(PTEXT[i]));
      else if (i == 4)
        $display("  [UART-TX] ... sending bytes 4-59 ...");
      uart_send_byte(PTEXT[i]);
    end

    t_end = $time;
    $display("[%0t] All 64 plaintext bytes sent. Duration: %0d ns", $time, t_end - t_start);
    $display("");

    // ══════════════════════════════════════════════════════════
    //  Wait for firmware processing + UART TX capture
    // ══════════════════════════════════════════════════════════
    $display("--- Waiting for firmware AEAD processing + UART TX output ---");
    t_start = $time;

    fork
      wait(capture_done === 1'b1);
      begin
        wait_cycles(2_000_000);       // 40ms timeout
        if (!capture_done) begin
          $display("");
          $display("*** TIMEOUT: Only captured %0d of %0d bytes ***", rx_count, NUM_TX_BYTES);
          display_hex();
          $display("  PC = 0x%08h", pc_debug);
          $stop;
        end
      end
    join_any
    disable fork;

    t_end = $time;
    wait_cycles(5000);

    $display("[%0t] Processing + UART TX duration: %0d ns", $time, t_end - t_start);
    $display("");
    display_hex();

    // ══════════════════════════════════════════════════════════
    //  DISPLAY OUTPUT
    // ══════════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    $display(" SoC OUTPUT (captured from UART TX):");
    $display("================================================================");

    $display("");
    $display(" CIPHERTEXT (64 bytes):");
    for (i = 0; i < 4; i++) begin
      $display("   %03d: %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
        i*16,
        received[i*16+ 0], received[i*16+ 1], received[i*16+ 2], received[i*16+ 3],
        received[i*16+ 4], received[i*16+ 5], received[i*16+ 6], received[i*16+ 7],
        received[i*16+ 8], received[i*16+ 9], received[i*16+10], received[i*16+11],
        received[i*16+12], received[i*16+13], received[i*16+14], received[i*16+15]);
    end

    $display("");
    $display(" TAG (16 bytes):");
    $display("   %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
      received[64], received[65], received[66], received[67],
      received[68], received[69], received[70], received[71],
      received[72], received[73], received[74], received[75],
      received[76], received[77], received[78], received[79]);

    // ══════════════════════════════════════════════════════════
    //  VERIFICATION
    // ══════════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    $display(" VERIFICATION");
    $display("================================================================");

    // ── Ciphertext check (vs RFC 8439 + reference) ──────────
    pass_ct  = 0;
    fail_ct  = 0;
    $display("");
    $display(" Ciphertext vs RFC 8439 Section 2.8.2 expected (first 64 bytes):");
    for (i = 0; i < 64; i++) begin
      if (received[i] === EXP_CT[i]) begin
        pass_ct++;
      end else begin
        fail_ct++;
        $display("   Byte[%2d]: got=0x%02h  exp=0x%02h  **FAIL**", i, received[i], EXP_CT[i]);
      end
    end
    if (fail_ct == 0)
      $display("   All 64 ciphertext bytes match RFC expected values.");

    // Also cross-check with reference
    begin
      int ref_fail = 0;
      for (i = 0; i < 64; i++) begin
        if (received[i] !== ref_ct[i]) ref_fail++;
      end
      if (ref_fail > 0)
        $display("   WARNING: %0d bytes differ from reference model!", ref_fail);
    end

    // ── Tag check (vs reference model) ──────────────────────
    pass_tag = 0;
    fail_tag = 0;
    $display("");
    $display(" Tag vs reference model:");
    begin
      logic [127:0] soc_tag;
      soc_tag = {received[79], received[78], received[77], received[76],
                 received[75], received[74], received[73], received[72],
                 received[71], received[70], received[69], received[68],
                 received[67], received[66], received[65], received[64]};
      $display("   SoC tag = %032h", soc_tag);
      $display("   Ref tag = %032h", ref_tag);
      if (soc_tag === ref_tag) begin
        $display("   Tag MATCH!");
        pass_tag = 1;
      end else begin
        $display("   Tag MISMATCH!");
        fail_tag = 1;
        // Show byte-level diff
        for (i = 0; i < 16; i++) begin
          logic [7:0] exp_byte;
          exp_byte = ref_tag[i*8 +: 8];
          if (received[64+i] !== exp_byte)
            $display("     Tag byte[%0d]: got=0x%02h ref=0x%02h **FAIL**",
                     i, received[64+i], exp_byte);
        end
      end
    end

    // ── Detailed comparison print ───────────────────────────
    $display("");
    $display(" Side-by-side (first 16 bytes):");
    $display("   Plaintext : %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
      PTEXT[ 0], PTEXT[ 1], PTEXT[ 2], PTEXT[ 3],
      PTEXT[ 4], PTEXT[ 5], PTEXT[ 6], PTEXT[ 7],
      PTEXT[ 8], PTEXT[ 9], PTEXT[10], PTEXT[11],
      PTEXT[12], PTEXT[13], PTEXT[14], PTEXT[15]);
    $display("   Ciphertext: %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
      received[ 0], received[ 1], received[ 2], received[ 3],
      received[ 4], received[ 5], received[ 6], received[ 7],
      received[ 8], received[ 9], received[10], received[11],
      received[12], received[13], received[14], received[15]);
    $display("   Expected  : %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
      EXP_CT[ 0], EXP_CT[ 1], EXP_CT[ 2], EXP_CT[ 3],
      EXP_CT[ 4], EXP_CT[ 5], EXP_CT[ 6], EXP_CT[ 7],
      EXP_CT[ 8], EXP_CT[ 9], EXP_CT[10], EXP_CT[11],
      EXP_CT[12], EXP_CT[13], EXP_CT[14], EXP_CT[15]);

    // ══════════════════════════════════════════════════════════
    //  FINAL RESULT
    // ══════════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    if (fail_ct == 0 && fail_tag == 0) begin
      $display(" RESULT: CT %0d/64 PASS  |  TAG %0d/1 PASS  >>> ALL CORRECT <<<",
               pass_ct, pass_tag);
      $display("");
      $display(" Full AEAD pipeline verified end-to-end:");
      $display("   Host -> UART RX -> Firmware AEAD:");
      $display("     1. ChaCha20(key,nonce,ctr=0) -> OTK generation");
      $display("     2. Poly1305 init with OTK (r,s)");
      $display("     3. ChaCha20(key,nonce,ctr=1) XOR PT -> ciphertext");
      $display("     4. Poly1305 MAC(AAD|pad|CT|lengths) -> finalize -> tag");
      $display("   Firmware -> UART TX -> Host (64B CT + 16B TAG)");
      $display("");
      $display(" Peripherals exercised: UART, ChaCha20, Poly1305, 7-Segment");
    end else begin
      $display(" RESULT: CT %0d PASS %0d FAIL | TAG %0d PASS %0d FAIL",
               pass_ct, fail_ct, pass_tag, fail_tag);
    end
    $display("================================================================");
    $display("");

    $stop;
  end

  // ── Timeout watchdog ──
  initial begin
    #100_000_000;           // 100ms timeout
    $display("\n[TIMEOUT] Simulation exceeded 100 ms — aborting.");
    $finish;
  end

endmodule
