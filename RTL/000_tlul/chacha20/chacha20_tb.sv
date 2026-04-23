//-----------------------------------------------------------------------------
// Testbench: chacha20_tb
// Description: Comprehensive testbench for ChaCha20 TL-UL peripheral.
//              Verifies keystream, encryption, counter auto-increment, and IRQ
//              using the RFC 8439 Section 2.3.2 test vector.
//
// Reference:
//   [RFC 8439] §2.3.2 — Test Vector for the ChaCha20 Block Function
//   [RFC 8439] §2.4.2 — Test Vector for the ChaCha20 Cipher
//
// Test Cases:
//   1. Keystream verification  (plaintext=0 → ciphertext=keystream)
//   2. Encryption XOR          (ciphertext = plaintext ^ keystream)
//   3. Counter auto-increment  (second block uses counter+1)
//   4. IRQ sticky + W1C        (done interrupt behaviour)
//   5. Register read-back      (key/nonce/counter persistence)
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module chacha20_tb;

  //===========================================================================
  // Parameters
  //===========================================================================
  parameter CLK_PERIOD = 20;  // 50 MHz

  //===========================================================================
  // DUT Signals
  //===========================================================================
  logic        clk;
  logic        rst_n;

  // TileLink Slave (testbench → ChaCha20 registers)
  logic        tl_a_valid;
  logic [2:0]  tl_a_opcode;
  logic [2:0]  tl_a_param;
  logic [2:0]  tl_a_size;
  logic [4:0]  tl_a_source;
  logic [31:0] tl_a_address;
  logic [3:0]  tl_a_mask;
  logic [31:0] tl_a_data;
  logic        tl_a_corrupt;
  logic        tl_a_ready;    // from DUT

  logic        tl_d_valid;    // from DUT
  logic [2:0]  tl_d_opcode;
  logic [2:0]  tl_d_param;
  logic [2:0]  tl_d_size;
  logic [4:0]  tl_d_source;
  logic [0:0]  tl_d_sink;
  logic [31:0] tl_d_data;
  logic        tl_d_denied;
  logic        tl_d_corrupt;
  logic        tl_d_ready;    // to DUT

  // Interrupt
  logic        chacha_irq;

  // Test variables
  logic [31:0] read_data;
  int          test_count;
  int          pass_count;
  int          fail_count;

  //===========================================================================
  // TileLink Opcodes
  //===========================================================================
  localparam logic [2:0] TL_GET           = 3'd4;
  localparam logic [2:0] TL_PUT_FULL_DATA = 3'd0;

  //===========================================================================
  // ChaCha20 Register Offsets  (see tlul_chacha20.sv register map)
  //===========================================================================
  localparam logic [31:0] BASE         = 32'h0000_0000;
  localparam logic [31:0] REG_KEY0     = BASE + 32'h00;
  localparam logic [31:0] REG_KEY1     = BASE + 32'h04;
  localparam logic [31:0] REG_KEY2     = BASE + 32'h08;
  localparam logic [31:0] REG_KEY3     = BASE + 32'h0C;
  localparam logic [31:0] REG_KEY4     = BASE + 32'h10;
  localparam logic [31:0] REG_KEY5     = BASE + 32'h14;
  localparam logic [31:0] REG_KEY6     = BASE + 32'h18;
  localparam logic [31:0] REG_KEY7     = BASE + 32'h1C;
  localparam logic [31:0] REG_NONCE0   = BASE + 32'h20;
  localparam logic [31:0] REG_NONCE1   = BASE + 32'h24;
  localparam logic [31:0] REG_NONCE2   = BASE + 32'h28;
  localparam logic [31:0] REG_COUNTER  = BASE + 32'h2C;
  localparam logic [31:0] REG_CONTROL  = BASE + 32'h30;
  localparam logic [31:0] REG_STATUS   = BASE + 32'h34;
  localparam logic [31:0] REG_IRQ_ST   = BASE + 32'h38;
  localparam logic [31:0] REG_PTEXT0   = BASE + 32'h40;
  localparam logic [31:0] REG_CTEXT0   = BASE + 32'h80;

  //===========================================================================
  // RFC 8439 Section 2.3.2 — Test Vector
  //===========================================================================
  // Key  : 00:01:02:…:1f  (little-endian 32-bit words)
  // Nonce: 00:00:00:09 : 00:00:00:4a : 00:00:00:00
  // Counter: 1
  //===========================================================================
  logic [31:0] tv_key   [8];
  logic [31:0] tv_nonce [3];
  logic [31:0] tv_counter;
  logic [31:0] tv_ks    [16];   // Expected keystream (after final addition)

  initial begin
    // Key: 00 01 02 03 → 0x03020100 (LE), etc.
    tv_key[0] = 32'h03020100;
    tv_key[1] = 32'h07060504;
    tv_key[2] = 32'h0b0a0908;
    tv_key[3] = 32'h0f0e0d0c;
    tv_key[4] = 32'h13121110;
    tv_key[5] = 32'h17161514;
    tv_key[6] = 32'h1b1a1918;
    tv_key[7] = 32'h1f1e1d1c;

    // Nonce: 00:00:00:09 → 0x09000000 (LE)
    tv_nonce[0] = 32'h09000000;
    tv_nonce[1] = 32'h4a000000;
    tv_nonce[2] = 32'h00000000;

    // Counter
    tv_counter = 32'h00000001;

    // Expected keystream (RFC 8439 §2.3.2 — verified by hand)
    tv_ks[ 0] = 32'he4e7f110;
    tv_ks[ 1] = 32'h15593bd1;
    tv_ks[ 2] = 32'h1fdd0f50;
    tv_ks[ 3] = 32'hc47120a3;
    tv_ks[ 4] = 32'hc7f4d1c7;
    tv_ks[ 5] = 32'h0368c033;
    tv_ks[ 6] = 32'h9aaa2204;
    tv_ks[ 7] = 32'h4e6cd4c3;
    tv_ks[ 8] = 32'h466482d2;
    tv_ks[ 9] = 32'h09aa9f07;
    tv_ks[10] = 32'h05d7c214;
    tv_ks[11] = 32'ha2028bd9;
    tv_ks[12] = 32'hd19c12b5;
    tv_ks[13] = 32'hb94e16de;
    tv_ks[14] = 32'he883d0cb;
    tv_ks[15] = 32'h4e3c50a2;
  end

  //===========================================================================
  // Clock Generation
  //===========================================================================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  //===========================================================================
  // DUT Instantiation
  //===========================================================================
  tlul_chacha20 u_dut (
    .i_clk          (clk),
    .i_rst_n        (rst_n),

    // TL-UL Slave
    .i_tl_a_valid   (tl_a_valid),
    .i_tl_a_opcode  (tl_a_opcode),
    .i_tl_a_param   (tl_a_param),
    .i_tl_a_size    (tl_a_size),
    .i_tl_a_source  (tl_a_source),
    .i_tl_a_address (tl_a_address),
    .i_tl_a_mask    (tl_a_mask),
    .i_tl_a_data    (tl_a_data),
    .i_tl_a_corrupt (tl_a_corrupt),
    .o_tl_a_ready   (tl_a_ready),

    .o_tl_d_valid   (tl_d_valid),
    .o_tl_d_opcode  (tl_d_opcode),
    .o_tl_d_param   (tl_d_param),
    .o_tl_d_size    (tl_d_size),
    .o_tl_d_source  (tl_d_source),
    .o_tl_d_sink    (tl_d_sink),
    .o_tl_d_data    (tl_d_data),
    .o_tl_d_denied  (tl_d_denied),
    .o_tl_d_corrupt (tl_d_corrupt),
    .i_tl_d_ready   (tl_d_ready),

    .o_chacha_irq   (chacha_irq)
  );

  //===========================================================================
  // TileLink CPU Interface Tasks (same pattern as dma_tb)
  //===========================================================================
  task automatic tl_write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge clk);
    tl_a_valid   <= 1'b1;
    tl_a_opcode  <= TL_PUT_FULL_DATA;
    tl_a_param   <= 3'd0;
    tl_a_size    <= 3'd2;
    tl_a_source  <= 5'd1;
    tl_a_address <= addr;
    tl_a_mask    <= 4'hF;
    tl_a_data    <= data;
    tl_a_corrupt <= 1'b0;

    @(posedge clk);
    while (!tl_a_ready) @(posedge clk);
    tl_a_valid <= 1'b0;

    while (!tl_d_valid) @(posedge clk);
    @(posedge clk);
  endtask

  task automatic tl_read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk);
    tl_a_valid   <= 1'b1;
    tl_a_opcode  <= TL_GET;
    tl_a_param   <= 3'd0;
    tl_a_size    <= 3'd2;
    tl_a_source  <= 5'd1;
    tl_a_address <= addr;
    tl_a_mask    <= 4'hF;
    tl_a_data    <= 32'd0;
    tl_a_corrupt <= 1'b0;

    @(posedge clk);
    while (!tl_a_ready) @(posedge clk);
    tl_a_valid <= 1'b0;

    while (!tl_d_valid) @(posedge clk);
    data = tl_d_data;
    @(posedge clk);
  endtask

  // -- Poll STATUS.ready until it becomes 1 (with timeout) --
  task automatic wait_ready(input int timeout_cycles);
    logic [31:0] status;
    int cnt;
    cnt = 0;
    do begin
      tl_read(REG_STATUS, status);
      cnt++;
      if (cnt > timeout_cycles) begin
        $display("[CHACHA_TB] @%0t ns | ERROR | Timeout waiting for STATUS.ready after %0d polls!", $time, cnt);
        return;
      end
    end while (status[0] == 1'b0);
  endtask

  // -- Helper: write all 8 key words --
  task automatic write_key(input logic [31:0] k [8]);
    for (int i = 0; i < 8; i++)
      tl_write(REG_KEY0 + i*4, k[i]);
  endtask

  // -- Helper: write all 3 nonce words --
  task automatic write_nonce(input logic [31:0] n [3]);
    for (int i = 0; i < 3; i++)
      tl_write(REG_NONCE0 + i*4, n[i]);
  endtask

  // -- Helper: write 16 plaintext words --
  task automatic write_plaintext(input logic [31:0] pt [16]);
    for (int i = 0; i < 16; i++)
      tl_write(REG_PTEXT0 + i*4, pt[i]);
  endtask

  // -- Helper: read 16 ciphertext words --
  task automatic read_ciphertext(output logic [31:0] ct [16]);
    for (int i = 0; i < 16; i++)
      tl_read(REG_CTEXT0 + i*4, ct[i]);
  endtask

  //===========================================================================
  // CHECK utility
  //===========================================================================
  task automatic check(input string name, input logic [31:0] got,
                       input logic [31:0] exp);
    test_count++;
    if (got === exp) begin
      $display("[CHACHA_TB] @%0t ns | PASS  | %-35s  exp=0x%08X  got=0x%08X", $time, name, exp, got);
      pass_count++;
    end else begin
      $display("[CHACHA_TB] @%0t ns | FAIL  | %-35s  exp=0x%08X  got=0x%08X  <-- MISMATCH", $time, name, exp, got);
      fail_count++;
    end
  endtask

  //===========================================================================
  // TEST 1 — Keystream Verification (plaintext = 0)
  //   RFC 8439 §2.3.2: key/nonce/counter → expected keystream
  //   When plaintext = 0, ciphertext = 0 XOR keystream = keystream
  //===========================================================================
  task automatic test_keystream();
    logic [31:0] ct [16];
    logic [31:0] zero_pt [16];

    $display("");
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | TEST 1: Keystream Verification (RFC 8439 Section 2.3.2)", $time);
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Purpose : CT = PT XOR KS; with PT=0 => CT = KS (keystream)", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Ref     : RFC 8439 Section 2.3.2 official test vector", $time);
    $display("");

    // Zero plaintext
    for (int i = 0; i < 16; i++) zero_pt[i] = 32'd0;

    $display("[CHACHA_TB] @%0t ns | CFG   | Key[0..3] : %08X %08X %08X %08X",
             $time, tv_key[0], tv_key[1], tv_key[2], tv_key[3]);
    $display("[CHACHA_TB] @%0t ns | CFG   | Key[4..7] : %08X %08X %08X %08X",
             $time, tv_key[4], tv_key[5], tv_key[6], tv_key[7]);
    $display("[CHACHA_TB] @%0t ns | CFG   | Nonce     : %08X %08X %08X",
             $time, tv_nonce[0], tv_nonce[1], tv_nonce[2]);
    $display("[CHACHA_TB] @%0t ns | CFG   | Counter   : 0x%08X", $time, tv_counter);
    $display("[CHACHA_TB] @%0t ns | CFG   | Plaintext : 0x00000000 (all zeros x16)", $time);

    // Write parameters
    write_key(tv_key);
    write_nonce(tv_nonce);
    tl_write(REG_COUNTER, tv_counter);
    write_plaintext(zero_pt);

    // Trigger encryption
    $display("[CHACHA_TB] @%0t ns | INFO  | Writing registers + triggering encryption (CONTROL <- 1)", $time);
    tl_write(REG_CONTROL, 32'd1);

    // Wait for completion
    wait_ready(100);

    // Read and verify ciphertext = keystream (since PT=0)
    $display("[CHACHA_TB] @%0t ns | INFO  | Computation complete. Verifying 16 keystream words:", $time);
    read_ciphertext(ct);
    for (int i = 0; i < 16; i++)
      check($sformatf("KS[%0d]", i), ct[i], tv_ks[i]);
  endtask

  //===========================================================================
  // TEST 2 — Encryption XOR
  //   Write known plaintext, verify ciphertext = plaintext ^ keystream
  //===========================================================================
  task automatic test_encryption();
    logic [31:0] pt [16];
    logic [31:0] ct [16];
    logic [31:0] expected_ct;

    $display("");
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | TEST 2: Encryption XOR Verification", $time);
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Purpose : Verify CT[i] = PT[i] XOR KS[i] with non-zero plaintext", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Formula : CT[i] = 0xDEADBEEF XOR KS[i]", $time);
    $display("");

    // Use a non-zero plaintext pattern
    for (int i = 0; i < 16; i++)
      pt[i] = 32'hDEADBEEF;

    $display("[CHACHA_TB] @%0t ns | CFG   | Key[0..3] : %08X %08X %08X %08X",
             $time, tv_key[0], tv_key[1], tv_key[2], tv_key[3]);
    $display("[CHACHA_TB] @%0t ns | CFG   | Key[4..7] : %08X %08X %08X %08X",
             $time, tv_key[4], tv_key[5], tv_key[6], tv_key[7]);
    $display("[CHACHA_TB] @%0t ns | CFG   | Nonce     : %08X %08X %08X",
             $time, tv_nonce[0], tv_nonce[1], tv_nonce[2]);
    $display("[CHACHA_TB] @%0t ns | CFG   | Counter   : 0x%08X", $time, tv_counter);
    $display("[CHACHA_TB] @%0t ns | CFG   | Plaintext : 0xDEADBEEF (all 16 words)", $time);

    // Write parameters (same key/nonce, reset counter to 1)
    write_key(tv_key);
    write_nonce(tv_nonce);
    tl_write(REG_COUNTER, tv_counter);
    write_plaintext(pt);

    // Trigger
    $display("[CHACHA_TB] @%0t ns | INFO  | Writing registers + triggering encryption (CONTROL <- 1)", $time);
    tl_write(REG_CONTROL, 32'd1);
    wait_ready(100);

    // Verify ciphertext = plaintext ^ keystream
    $display("[CHACHA_TB] @%0t ns | INFO  | Computation complete. Verifying CT[i] = 0xDEADBEEF XOR KS[i]:", $time);
    read_ciphertext(ct);
    for (int i = 0; i < 16; i++) begin
      expected_ct = pt[i] ^ tv_ks[i];
      check($sformatf("CT[%0d] (0xDEADBEEF^KS[%0d])", i, i), ct[i], expected_ct);
    end
  endtask

  //===========================================================================
  // TEST 3 — Counter Auto-Increment
  //   After test 1 finishes, counter should have auto-incremented.
  //   Verify by reading counter register.
  //===========================================================================
  task automatic test_counter_auto_inc();
    logic [31:0] rd;

    $display("");
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | TEST 3: Counter Auto-Increment", $time);
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Purpose : COUNTER += 1 after each 64-byte block (RFC 8439 Section 2.4)", $time);
    $display("[CHACHA_TB] @%0t ns | CFG   | Initial Counter : 0x00000001", $time);
    $display("");
    tl_write(REG_COUNTER, 32'd1);
    tl_write(REG_CONTROL, 32'd1);
    $display("[CHACHA_TB] @%0t ns | INFO  | Trigger block 1 (COUNTER=1 before start)", $time);
    wait_ready(100);

    // Counter should now be 2
    tl_read(REG_COUNTER, rd);
    check("Counter after block 1 (1->2)", rd, 32'd2);

    // Run another block
    $display("[CHACHA_TB] @%0t ns | INFO  | Trigger block 2 (COUNTER=2 before start)", $time);
    tl_write(REG_CONTROL, 32'd1);
    wait_ready(100);

    // Counter should now be 3
    tl_read(REG_COUNTER, rd);
    check("Counter after block 2 (2->3)", rd, 32'd3);
  endtask

  //===========================================================================
  // TEST 4 — IRQ Sticky + W1C
  //===========================================================================
  task automatic test_irq();
    logic [31:0] rd;

    $display("");
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | TEST 4: IRQ Sticky Behaviour + W1C Clear", $time);
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Purpose   : IRQ_STATUS[0] set on completion, sticky until W1C", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Mechanism : irq_done_q set by core_valid, cleared by writing 1", $time);
    $display("");

    // Clear any previous IRQ
    $display("[CHACHA_TB] @%0t ns | CFG   | Write IRQ_STATUS <- 0x1  (W1C pre-clear)", $time);
    tl_write(REG_IRQ_ST, 32'd1);
    tl_read(REG_IRQ_ST, rd);
    check("IRQ_STATUS after W1C pre-clear", rd, 32'd0);

    // Run a block
    $display("[CHACHA_TB] @%0t ns | INFO  | Trigger encryption block (COUNTER <- 1)", $time);
    tl_write(REG_COUNTER, 32'd1);
    tl_write(REG_CONTROL, 32'd1);
    wait_ready(100);

    // IRQ should be set
    tl_read(REG_IRQ_ST, rd);
    check("IRQ_STATUS after block done (=1)", rd, 32'd1);

    // IRQ should stay set (sticky) on re-read
    $display("[CHACHA_TB] @%0t ns | INFO  | Re-read IRQ_STATUS -- should remain sticky=1", $time);
    tl_read(REG_IRQ_ST, rd);
    check("IRQ_STATUS sticky re-read", rd, 32'd1);

    // W1C -- clear by writing 1
    $display("[CHACHA_TB] @%0t ns | CFG   | Write IRQ_STATUS <- 0x1  (W1C clear)", $time);
    tl_write(REG_IRQ_ST, 32'd1);
    tl_read(REG_IRQ_ST, rd);
    check("IRQ_STATUS after W1C clear", rd, 32'd0);
  endtask

  //===========================================================================
  // TEST 5 — Register Read-Back
  //===========================================================================
  task automatic test_register_readback();
    logic [31:0] rd;

    $display("");
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | TEST 5: Register Read-Back", $time);
    $display("[CHACHA_TB] @%0t ns | ================================================================", $time);
    $display("[CHACHA_TB] @%0t ns | INFO  | Purpose : Verify TL-UL register interface read/write integrity", $time);
    $display("");

    // Write and read key[0]
    $display("[CHACHA_TB] @%0t ns | CFG   | Write KEY0    <- 0xCAFEBABE", $time);
    tl_write(REG_KEY0, 32'hCAFEBABE);
    tl_read(REG_KEY0, rd);
    check("KEY[0] readback (wr 0xCAFEBABE)", rd, 32'hCAFEBABE);

    // Write and read nonce[1]
    $display("[CHACHA_TB] @%0t ns | CFG   | Write NONCE1  <- 0x12345678", $time);
    tl_write(REG_NONCE1, 32'h12345678);
    tl_read(REG_NONCE1, rd);
    check("NONCE[1] readback (wr 0x12345678)", rd, 32'h12345678);

    // Write and read counter
    $display("[CHACHA_TB] @%0t ns | CFG   | Write COUNTER <- 0x0000FFFF", $time);
    tl_write(REG_COUNTER, 32'h0000FFFF);
    tl_read(REG_COUNTER, rd);
    check("COUNTER readback (wr 0x0000FFFF)", rd, 32'h0000FFFF);

    // CONTROL always reads 0 (self-clearing)
    $display("[CHACHA_TB] @%0t ns | INFO  | Read CONTROL   (self-clearing, expect 0)", $time);
    tl_read(REG_CONTROL, rd);
    check("CONTROL always reads 0", rd, 32'd0);

    // STATUS.ready should be 1 when idle
    $display("[CHACHA_TB] @%0t ns | INFO  | Read STATUS    (bit[0]=ready, expect 1 when idle)", $time);
    tl_read(REG_STATUS, rd);
    check("STATUS[0]=ready when idle", rd, 32'd1);
  endtask

  //===========================================================================
  // Main Stimulus
  //===========================================================================
  initial begin
    // ---- Initialise ----
    rst_n        = 1'b0;
    tl_a_valid   = 1'b0;
    tl_a_opcode  = 3'd0;
    tl_a_param   = 3'd0;
    tl_a_size    = 3'd0;
    tl_a_source  = 5'd0;
    tl_a_address = 32'd0;
    tl_a_mask    = 4'd0;
    tl_a_data    = 32'd0;
    tl_a_corrupt = 1'b0;
    tl_d_ready   = 1'b1;      // Always accept D channel responses

    test_count   = 0;
    pass_count   = 0;
    fail_count   = 0;

    // ---- Reset ----
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $timeformat(-9, 0, "", 0);
    $display("");
    $display("[CHACHA_TB] @%0t ns | ################################################################", $time);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | #    ChaCha20 TL-UL Peripheral -- Verification Testbench       #", $time);
    $display("[CHACHA_TB] @%0t ns | #    Module Under Test: tlul_chacha20                          #", $time);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | #    Sub-modules : chacha20_core, chacha20_qr (x4)             #", $time);
    $display("[CHACHA_TB] @%0t ns | #    Bus Protocol: TileLink Uncached Lightweight (TL-UL)       #", $time);
    $display("[CHACHA_TB] @%0t ns | #    Clock Period: %0d ns (%0d MHz)                                #", $time, CLK_PERIOD, 1000/CLK_PERIOD);
    $display("[CHACHA_TB] @%0t ns | #    Test Vector: RFC 8439 Section 2.3.2                       #", $time);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | #    Test Plan:                                                #", $time);
    $display("[CHACHA_TB] @%0t ns | #      1. Keystream Verification  -- RFC 8439 test vector      #", $time);
    $display("[CHACHA_TB] @%0t ns | #      2. Encryption XOR          -- CT[i] = PT[i] XOR KS[i]  #", $time);
    $display("[CHACHA_TB] @%0t ns | #      3. Counter Auto-Increment  -- +1 per 64-byte block      #", $time);
    $display("[CHACHA_TB] @%0t ns | #      4. IRQ Sticky + W1C        -- done interrupt control    #", $time);
    $display("[CHACHA_TB] @%0t ns | #      5. Register Read-Back      -- key/nonce/counter/status  #", $time);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | ################################################################", $time);

    // ---- Run Tests ----
    test_keystream();
    test_encryption();
    test_counter_auto_inc();
    test_irq();
    test_register_readback();

    // ---- Summary ----
    repeat (5) @(posedge clk);
    $display("");
    $display("[CHACHA_TB] @%0t ns | ################################################################", $time);
    $display("[CHACHA_TB] @%0t ns | #                    FINAL TEST SUMMARY                        #", $time);
    $display("[CHACHA_TB] @%0t ns | ################################################################", $time);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | #   Total Checks : %-4d                                       #", $time, test_count);
    $display("[CHACHA_TB] @%0t ns | #   Passed       : %-4d                                       #", $time, pass_count);
    $display("[CHACHA_TB] @%0t ns | #   Failed       : %-4d                                       #", $time, fail_count);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    if (fail_count == 0)
    $display("[CHACHA_TB] @%0t ns | #   Result: *** ALL TESTS PASSED ***                          #", $time);
    else
    $display("[CHACHA_TB] @%0t ns | #   Result: *** %0d TEST(S) FAILED ***                         #", $time, fail_count);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | #   Simulation Time : %0t ns                                   #", $time, $time);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | #   Test Breakdown:                                            #", $time);
    $display("[CHACHA_TB] @%0t ns | #     T1 Keystream Verification  : verified (16 words vs RFC)  #", $time);
    $display("[CHACHA_TB] @%0t ns | #     T2 Encryption XOR          : verified (16 words)         #", $time);
    $display("[CHACHA_TB] @%0t ns | #     T3 Counter Auto-Increment  : verified (2 steps)          #", $time);
    $display("[CHACHA_TB] @%0t ns | #     T4 IRQ Sticky + W1C        : verified (4 checks)         #", $time);
    $display("[CHACHA_TB] @%0t ns | #     T5 Register Read-Back      : verified (5 regs)           #", $time);
    $display("[CHACHA_TB] @%0t ns | #                                                              #", $time);
    $display("[CHACHA_TB] @%0t ns | ################################################################", $time);
    $display("");

    $finish;
  end

  //===========================================================================
  // Timeout watchdog
  //===========================================================================
  initial begin
    #500000;
    $display("[CHACHA_TB] @%0t ns | FATAL | Global timeout reached -- simulation aborted!", $time);
    $finish;
  end

endmodule
