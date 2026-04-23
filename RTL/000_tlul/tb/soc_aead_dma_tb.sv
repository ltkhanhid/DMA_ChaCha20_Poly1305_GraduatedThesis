`timescale 1ns/1ps

// ============================================================
// soc_aead_dma_tb.sv — AEAD Performance Comparison Testbench
//
// Instantiates TWO SoC instances running simultaneously:
//   SoC A: demo_aead.hex     (CPU-only data movement)
//   SoC B: demo_aead_dma.hex (DMA-assisted data movement)
//
// Both receive identical 64-byte plaintext via UART, process
// AEAD ChaCha20-Poly1305, and transmit 80 bytes (CT+TAG).
//
// Verification:
//   - Both SoCs produce identical ciphertext
//   - Both SoCs produce identical tag
//   - Ciphertext matches RFC 8439 §2.8.2 expected values
//
// Performance Metrics (Phase 2 → Phase 6 = crypto processing):
//   - Total clock cycles
//   - CPU instructions retired (insn_vld)
//   - IPC (Instructions Per Cycle)
//   - Per-phase breakdown
// ============================================================

module soc_aead_dma_tb;
  import tlul_pkg::*;

  // ─── Parameters ─────────────────────────────────────────
  parameter CLK_PERIOD    = 20;               // 50 MHz
  parameter MEM_DEPTH     = 65536;
  parameter BIT_PERIOD    = 50_000_000 / 115_200;  // ~434 cycles/bit
  parameter NUM_TX_BYTES  = 80;               // 64 CT + 16 TAG

  // ─── Shared Signals ─────────────────────────────────────
  logic        clk, rst_n;
  logic [9:0]  sw_i;
  logic        uart_tx_to_soc;  // shared UART input for both SoCs

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ─── Test Data ──────────────────────────────────────────
  logic [7:0] PTEXT [0:63];
  logic [7:0] EXP_CT [0:63];

  // ═══════════════════════════════════════════════════════
  //  SoC A — CPU-only (demo_aead.hex)
  // ═══════════════════════════════════════════════════════
  logic [9:0]  a_ledr;
  logic [31:0] a_ledg;
  logic [6:0]  a_hex0, a_hex1, a_hex2, a_hex3;
  logic [6:0]  a_hex4, a_hex5, a_hex6, a_hex7;
  logic        a_uart_tx;
  logic        a_irq_dma, a_irq_chacha, a_irq_poly;
  logic [31:0] a_pc_debug, a_pc_wb, a_pc_mem;
  logic        a_insn_vld, a_ctrl, a_mispred;

  soc_top_2m6s #(
    .MEM_DEPTH(MEM_DEPTH),
    .MEM_FILE("demo_aead.hex")
  ) u_soc_a (
    .clk       (clk),
    .rst_n     (rst_n),
    .sw_i      (sw_i),
    .ledr_o    (a_ledr),
    .ledg_o    (a_ledg),
    .hex0_o    (a_hex0),  .hex1_o    (a_hex1),
    .hex2_o    (a_hex2),  .hex3_o    (a_hex3),
    .hex4_o    (a_hex4),  .hex5_o    (a_hex5),
    .hex6_o    (a_hex6),  .hex7_o    (a_hex7),
    .uart_rx_i (uart_tx_to_soc),
    .uart_tx_o (a_uart_tx),
    .irq_dma_o (a_irq_dma),
    .irq_chacha_o(a_irq_chacha),
    .irq_poly_o(a_irq_poly),
    .pc_debug_o(a_pc_debug),
    .pc_wb_o   (a_pc_wb),
    .pc_mem_o  (a_pc_mem),
    .insn_vld_o(a_insn_vld),
    .ctrl_o    (a_ctrl),
    .mispred_o (a_mispred)
  );

  // ═══════════════════════════════════════════════════════
  //  SoC B — DMA-assisted (demo_aead_dma.hex)
  // ═══════════════════════════════════════════════════════
  logic [9:0]  b_ledr;
  logic [31:0] b_ledg;
  logic [6:0]  b_hex0, b_hex1, b_hex2, b_hex3;
  logic [6:0]  b_hex4, b_hex5, b_hex6, b_hex7;
  logic        b_uart_tx;
  logic        b_irq_dma, b_irq_chacha, b_irq_poly;
  logic [31:0] b_pc_debug, b_pc_wb, b_pc_mem;
  logic        b_insn_vld, b_ctrl, b_mispred;

  soc_top_2m6s #(
    .MEM_DEPTH(MEM_DEPTH),
    .MEM_FILE("demo_aead_dma.hex")
  ) u_soc_b (
    .clk       (clk),
    .rst_n     (rst_n),
    .sw_i      (sw_i),
    .ledr_o    (b_ledr),
    .ledg_o    (b_ledg),
    .hex0_o    (b_hex0),  .hex1_o    (b_hex1),
    .hex2_o    (b_hex2),  .hex3_o    (b_hex3),
    .hex4_o    (b_hex4),  .hex5_o    (b_hex5),
    .hex6_o    (b_hex6),  .hex7_o    (b_hex7),
    .uart_rx_i (uart_tx_to_soc),
    .uart_tx_o (b_uart_tx),
    .irq_dma_o (b_irq_dma),
    .irq_chacha_o(b_irq_chacha),
    .irq_poly_o(b_irq_poly),
    .pc_debug_o(b_pc_debug),
    .pc_wb_o   (b_pc_wb),
    .pc_mem_o  (b_pc_mem),
    .insn_vld_o(b_insn_vld),
    .ctrl_o    (b_ctrl),
    .mispred_o (b_mispred)
  );

  // ═══════════════════════════════════════════════════════
  //  UART Captured Data
  // ═══════════════════════════════════════════════════════
  logic [7:0] a_received [0:NUM_TX_BYTES-1];
  logic [7:0] b_received [0:NUM_TX_BYTES-1];
  int         a_rx_count, b_rx_count;
  logic       a_capture_done, b_capture_done;

  // ═══════════════════════════════════════════════════════
  //  Helper Functions
  // ═══════════════════════════════════════════════════════

  // Decode 7-segment pattern to digit (0-15), returns -1 if unknown
  function automatic int seg_to_digit(input [6:0] seg);
    case(seg)
      7'b1000000: return 0;
      7'b1111001: return 1;
      7'b0100100: return 2;
      7'b0110000: return 3;
      7'b0011001: return 4;
      7'b0010010: return 5;
      7'b0000010: return 6;
      7'b1111000: return 7;
      7'b0000000: return 8;
      7'b0010000: return 9;
      7'b0001000: return 10; // A
      7'b0000011: return 11; // b
      7'b1000110: return 12; // C
      7'b0100001: return 13; // d
      7'b0000110: return 14; // E
      7'b0001110: return 15; // F
      default:    return -1;
    endcase
  endfunction

  function automatic string seg_to_char(input [6:0] seg);
    int d;
    d = seg_to_digit(seg);
    case(d)
      0:  return "0";  1:  return "1";  2:  return "2";  3:  return "3";
      4:  return "4";  5:  return "5";  6:  return "6";  7:  return "7";
      8:  return "8";  9:  return "9";  10: return "A";  11: return "b";
      12: return "C";  13: return "d";  14: return "E";  15: return "F";
      default: return "?";
    endcase
  endfunction

  task wait_cycles(int n);
    repeat(n) @(posedge clk);
  endtask

  // ═══════════════════════════════════════════════════════
  //  Phase Detection + Performance Counters
  // ═══════════════════════════════════════════════════════

  // --- SoC A ---
  int  a_phase;
  int  a_prev_phase;
  longint a_phase_time [0:8];   // $time when phase starts
  int  a_insn_cnt;              // CPU instructions during crypto (Phase 2-5)
  int  a_phase_insn [0:8];     // per-phase instruction count
  int  a_crypto_measuring;

  initial begin
    a_phase = 0; a_prev_phase = -1;
    a_insn_cnt = 0; a_crypto_measuring = 0;
    for (int i = 0; i <= 8; i++) begin a_phase_time[i] = 0; a_phase_insn[i] = 0; end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      int d;
      d = seg_to_digit(a_hex0);
      if (d >= 1 && d <= 7 && d != a_prev_phase) begin
        a_phase = d;
        a_phase_time[d] = $time;
        a_prev_phase = d;
      end

      // Count instructions for crypto phases (2-5)
      if (a_phase >= 2 && a_phase <= 5) begin
        if (a_insn_vld) begin
          a_insn_cnt = a_insn_cnt + 1;
          a_phase_insn[a_phase] = a_phase_insn[a_phase] + 1;
        end
      end
    end
  end

  // --- SoC B ---
  int  b_phase;
  int  b_prev_phase;
  longint b_phase_time [0:8];
  int  b_insn_cnt;
  int  b_phase_insn [0:8];
  int  b_crypto_measuring;

  initial begin
    b_phase = 0; b_prev_phase = -1;
    b_insn_cnt = 0; b_crypto_measuring = 0;
    for (int i = 0; i <= 8; i++) begin b_phase_time[i] = 0; b_phase_insn[i] = 0; end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      int d;
      d = seg_to_digit(b_hex0);
      if (d >= 1 && d <= 7 && d != b_prev_phase) begin
        b_phase = d;
        b_phase_time[d] = $time;
        b_prev_phase = d;
      end

      if (b_phase >= 2 && b_phase <= 5) begin
        if (b_insn_vld) begin
          b_insn_cnt = b_insn_cnt + 1;
          b_phase_insn[b_phase] = b_phase_insn[b_phase] + 1;
        end
      end
    end
  end

  // ═══════════════════════════════════════════════════════
  //  UART Tasks
  // ═══════════════════════════════════════════════════════

  task automatic uart_send_byte(input [7:0] data);
    integer i;
    uart_tx_to_soc = 1'b0;                   // Start bit
    repeat(BIT_PERIOD) @(posedge clk);
    for (i = 0; i < 8; i++) begin
      uart_tx_to_soc = data[i];
      repeat(BIT_PERIOD) @(posedge clk);
    end
    uart_tx_to_soc = 1'b1;                   // Stop bit
    repeat(BIT_PERIOD) @(posedge clk);
    repeat(BIT_PERIOD) @(posedge clk);        // inter-byte gap
  endtask

  // SoC A UART capture
  task automatic uart_recv_a(output logic [7:0] data);
    integer i;
    @(negedge a_uart_tx);
    repeat(BIT_PERIOD / 2) @(posedge clk);
    for (i = 0; i < 8; i++) begin
      repeat(BIT_PERIOD) @(posedge clk);
      data[i] = a_uart_tx;
    end
    repeat(BIT_PERIOD) @(posedge clk);
  endtask

  // SoC B UART capture
  task automatic uart_recv_b(output logic [7:0] data);
    integer i;
    @(negedge b_uart_tx);
    repeat(BIT_PERIOD / 2) @(posedge clk);
    for (i = 0; i < 8; i++) begin
      repeat(BIT_PERIOD) @(posedge clk);
      data[i] = b_uart_tx;
    end
    repeat(BIT_PERIOD) @(posedge clk);
  endtask

  // ═══════════════════════════════════════════════════════
  //  UART TX Capture Processes (parallel)
  // ═══════════════════════════════════════════════════════
  initial begin : a_capture_proc
    logic [7:0] byte_data;
    a_rx_count     = 0;
    a_capture_done = 0;
    wait(rst_n === 1'b1);

    while (a_rx_count < NUM_TX_BYTES) begin
      uart_recv_a(byte_data);
      a_received[a_rx_count] = byte_data;
      a_rx_count = a_rx_count + 1;
    end
    a_capture_done = 1;
  end

  initial begin : b_capture_proc
    logic [7:0] byte_data;
    b_rx_count     = 0;
    b_capture_done = 0;
    wait(rst_n === 1'b1);

    while (b_rx_count < NUM_TX_BYTES) begin
      uart_recv_b(byte_data);
      b_received[b_rx_count] = byte_data;
      b_rx_count = b_rx_count + 1;
    end
    b_capture_done = 1;
  end

  // ═══════════════════════════════════════════════════════
  //  MAIN TEST SEQUENCE
  // ═══════════════════════════════════════════════════════
  initial begin
    integer i;
    int a_ct_pass, a_ct_fail, b_ct_pass, b_ct_fail;
    int ab_ct_match, ab_tag_match;
    longint a_crypto_cycles, b_crypto_cycles;
    real a_ipc, b_ipc;
    real insn_reduction, cycle_diff;

    // ── Initialize Test Data ────────────────────────────
    // Plaintext: first 64 bytes of RFC 8439 §2.8.2
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

    // Expected ciphertext (RFC 8439 §2.8.2)
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

    // ══════════════════════════════════════════════════════
    //  BANNER
    // ══════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    $display(" AEAD CHACHA20-POLY1305  Performance Comparison: CPU vs DMA");
    $display("================================================================");
    $display("");
    $display(" PARAMETERS (RFC 8439 Section 2.8.2):");
    $display("   Key   : 80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f");
    $display("           90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f");
    $display("   Nonce : 07 00 00 00 40 41 42 43 44 45 46 47");
    $display("   AAD   : 50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7  (12 bytes)");
    $display("   PT    : \"Ladies and Gentlemen of the class of '99: If I co\"");
    $display("           \"uld offer you o\"  (64 bytes)");
    $display("");
    $display(" SoC A: CPU-only   (demo_aead.hex)");
    $display(" SoC B: DMA-assist (demo_aead_dma.hex)");
    $display("================================================================");
    $display("");

    // ── Reset ────────────────────────────────────────────
    rst_n          = 0;
    sw_i           = 0;
    uart_tx_to_soc = 1;
    wait_cycles(20);
    rst_n = 1;
    $display("[%0t] Reset released — both SoCs running in parallel.", $time);

    // Wait for firmware initialization
    wait_cycles(2000);

    // ══════════════════════════════════════════════════════
    //  Send 64 plaintext bytes to BOTH SoCs (shared UART)
    // ══════════════════════════════════════════════════════
    $display("");
    $display("--- Sending 64 plaintext bytes via shared UART ---");
    for (i = 0; i < 64; i++) begin
      uart_send_byte(PTEXT[i]);
    end
    $display("[%0t] All 64 bytes sent.", $time);
    $display("");
    $display("--- Waiting for AEAD processing + UART TX ---");

    // ══════════════════════════════════════════════════════
    //  Wait for BOTH SoCs to complete UART TX
    // ══════════════════════════════════════════════════════
    fork
      wait(a_capture_done === 1'b1 && b_capture_done === 1'b1);
      begin
        wait_cycles(3_000_000);  // 60 ms timeout
        if (!a_capture_done || !b_capture_done) begin
          $display("");
          $display("*** TIMEOUT ***");
          $display("  SoC A: %0d/%0d bytes, Phase=%0d, PC=0x%08h",
                   a_rx_count, NUM_TX_BYTES, a_phase, a_pc_debug);
          $display("  SoC B: %0d/%0d bytes, Phase=%0d, PC=0x%08h",
                   b_rx_count, NUM_TX_BYTES, b_phase, b_pc_debug);
          $stop;
        end
      end
    join_any
    disable fork;

    // Let the firmware reach Phase 7 (AEAd display)
    wait_cycles(10000);

    $display("[%0t] Both SoCs completed.", $time);

    // ══════════════════════════════════════════════════════
    //  CORRECTNESS VERIFICATION
    // ══════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    $display(" CORRECTNESS VERIFICATION");
    $display("================================================================");

    // 1. Check SoC A ciphertext vs RFC expected
    a_ct_pass = 0; a_ct_fail = 0;
    for (i = 0; i < 64; i++) begin
      if (a_received[i] === EXP_CT[i]) a_ct_pass++;
      else begin
        a_ct_fail++;
        $display("  [A] CT byte[%2d]: got=%02h exp=%02h  FAIL", i, a_received[i], EXP_CT[i]);
      end
    end
    $display("  SoC A CT vs RFC 8439: %0d/64 PASS%s",
             a_ct_pass, a_ct_fail == 0 ? "" : $sformatf(" (%0d FAIL)", a_ct_fail));

    // 2. Check SoC B ciphertext vs RFC expected
    b_ct_pass = 0; b_ct_fail = 0;
    for (i = 0; i < 64; i++) begin
      if (b_received[i] === EXP_CT[i]) b_ct_pass++;
      else begin
        b_ct_fail++;
        $display("  [B] CT byte[%2d]: got=%02h exp=%02h  FAIL", i, b_received[i], EXP_CT[i]);
      end
    end
    $display("  SoC B CT vs RFC 8439: %0d/64 PASS%s",
             b_ct_pass, b_ct_fail == 0 ? "" : $sformatf(" (%0d FAIL)", b_ct_fail));

    // 3. Check A vs B ciphertext match
    ab_ct_match = 1;
    for (i = 0; i < 64; i++)
      if (a_received[i] !== b_received[i]) ab_ct_match = 0;
    $display("  A vs B CT:  %s", ab_ct_match ? "MATCH" : "MISMATCH");

    // 4. Check tags
    begin
      logic [127:0] a_tag, b_tag;
      a_tag = {a_received[79], a_received[78], a_received[77], a_received[76],
               a_received[75], a_received[74], a_received[73], a_received[72],
               a_received[71], a_received[70], a_received[69], a_received[68],
               a_received[67], a_received[66], a_received[65], a_received[64]};
      b_tag = {b_received[79], b_received[78], b_received[77], b_received[76],
               b_received[75], b_received[74], b_received[73], b_received[72],
               b_received[71], b_received[70], b_received[69], b_received[68],
               b_received[67], b_received[66], b_received[65], b_received[64]};

      $display("  SoC A Tag: %032h", a_tag);
      $display("  SoC B Tag: %032h", b_tag);
      ab_tag_match = (a_tag === b_tag);
      $display("  A vs B Tag: %s", ab_tag_match ? "MATCH" : "MISMATCH");
    end

    // ══════════════════════════════════════════════════════
    //  PERFORMANCE ANALYSIS
    // ══════════════════════════════════════════════════════
    a_crypto_cycles = (a_phase_time[6] - a_phase_time[2]) / CLK_PERIOD;
    b_crypto_cycles = (b_phase_time[6] - b_phase_time[2]) / CLK_PERIOD;

    if (a_crypto_cycles > 0)
      a_ipc = real'(a_insn_cnt) / real'(a_crypto_cycles);
    else
      a_ipc = 0.0;

    if (b_crypto_cycles > 0)
      b_ipc = real'(b_insn_cnt) / real'(b_crypto_cycles);
    else
      b_ipc = 0.0;

    insn_reduction = (a_insn_cnt > 0) ?
      100.0 * real'(a_insn_cnt - b_insn_cnt) / real'(a_insn_cnt) : 0.0;
    cycle_diff = (a_crypto_cycles > 0) ?
      100.0 * real'(a_crypto_cycles - b_crypto_cycles) / real'(a_crypto_cycles) : 0.0;

    $display("");
    $display("================================================================");
    $display(" PERFORMANCE COMPARISON  (Phase 2-5: Crypto Processing Only)");
    $display("================================================================");
    $display("");
    $display("  Phase Breakdown (clock cycles):");
    $display("  +----------+----------------------------+----------------------------+");
    $display("  |  Phase   |  SoC A (CPU-only)          |  SoC B (DMA-assisted)      |");
    $display("  +----------+----------------------------+----------------------------+");

    for (int p = 2; p <= 5; p++) begin
      longint a_pc, b_pc;
      int a_pi, b_pi;
      a_pc = (a_phase_time[p+1] > 0 && a_phase_time[p] > 0) ?
             (a_phase_time[p+1] - a_phase_time[p]) / CLK_PERIOD : 0;
      b_pc = (b_phase_time[p+1] > 0 && b_phase_time[p] > 0) ?
             (b_phase_time[p+1] - b_phase_time[p]) / CLK_PERIOD : 0;
      a_pi = a_phase_insn[p];
      b_pi = b_phase_insn[p];

      case(p)
        2: $display("  |  P2 OTK  | %6d cyc / %5d insn   | %6d cyc / %5d insn   |",
                    a_pc, a_pi, b_pc, b_pi);
        3: $display("  |  P3 Init | %6d cyc / %5d insn   | %6d cyc / %5d insn   |",
                    a_pc, a_pi, b_pc, b_pi);
        4: $display("  |  P4 Enc  | %6d cyc / %5d insn   | %6d cyc / %5d insn   |",
                    a_pc, a_pi, b_pc, b_pi);
        5: $display("  |  P5 MAC  | %6d cyc / %5d insn   | %6d cyc / %5d insn   |",
                    a_pc, a_pi, b_pc, b_pi);
      endcase
    end

    $display("  +----------+----------------------------+----------------------------+");
    $display("");
    $display("  Summary (Phase 2 → Phase 6):");
    $display("  +---------------------+-----------+-----------+---------------+");
    $display("  |  Metric             |  CPU-only | DMA-assist| Change        |");
    $display("  +---------------------+-----------+-----------+---------------+");
    $display("  |  Total Cycles       | %9d | %9d | %6.1f%%       |",
             a_crypto_cycles, b_crypto_cycles, cycle_diff);
    $display("  |  CPU Instructions   | %9d | %9d | -%4.1f%% saved  |",
             a_insn_cnt, b_insn_cnt, insn_reduction);
    $display("  |  IPC                |     %5.3f |     %5.3f |               |",
             a_ipc, b_ipc);
    $display("  +---------------------+-----------+-----------+---------------+");
    $display("");

    // Interpretation
    if (insn_reduction > 0) begin
      $display("  Analysis:");
      $display("    - DMA saved %0d CPU instructions (%.1f%% reduction)",
               a_insn_cnt - b_insn_cnt, insn_reduction);
      if (b_crypto_cycles < a_crypto_cycles)
        $display("    - DMA also reduced total cycles by %.1f%%", cycle_diff);
      else if (b_crypto_cycles > a_crypto_cycles)
        $display("    - DMA added %.1f%% cycle overhead (bus arbitration latency)", -cycle_diff);
      else
        $display("    - Total cycle count unchanged");
      $display("    - Lower IPC for DMA = CPU idle during DMA transfers");
      $display("      (CPU freed for other tasks in real applications)");
    end

    // ══════════════════════════════════════════════════════
    //  FINAL RESULT
    // ══════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    if (a_ct_fail == 0 && b_ct_fail == 0 && ab_ct_match && ab_tag_match) begin
      $display(" RESULT: ALL CORRECT");
      $display("   Both SoCs produce identical, RFC-compliant output.");
      $display("   CPU instructions saved with DMA: %0d (%.1f%%)",
               a_insn_cnt - b_insn_cnt, insn_reduction);
    end else begin
      $display(" RESULT: FAILURES DETECTED");
      if (a_ct_fail > 0) $display("   SoC A: %0d CT bytes failed", a_ct_fail);
      if (b_ct_fail > 0) $display("   SoC B: %0d CT bytes failed", b_ct_fail);
      if (!ab_ct_match)  $display("   A/B ciphertext mismatch");
      if (!ab_tag_match) $display("   A/B tag mismatch");
    end
    $display("================================================================");
    $display("");

    $stop;
  end

  // ── Timeout watchdog ──
  initial begin
    #100_000_000;           // 100 ms
    $display("\n[TIMEOUT] Simulation exceeded 100 ms — aborting.");
    $finish;
  end

endmodule
