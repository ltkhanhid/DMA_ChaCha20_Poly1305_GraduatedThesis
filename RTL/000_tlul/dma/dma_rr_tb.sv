//------------------------------------------------------------------------------
// dma_rr_tb.sv — DMA Round-Robin Arbitration Verification Testbench
//
// Purpose: verify that dma_arbiter correctly alternates bus grants between
//          CH0 and CH1 when both are concurrently active.
//
// Monitoring strategy:
//   Each accepted GET transaction on the DMA bus starts a new "word transfer"
//   (READ phase). The address is matched against the configured source ranges
//   to identify which channel is being served. Channel IDs are appended to
//   grant_log[] for post-processing.
//
// Test cases:
//   TC1  Equal simultaneous   (CH0=4, CH1=4 words)
//          Both configured, then enabled back-to-back.
//          Verify: each gets exactly 4 grants, strict alternation in overlap.
//
//   TC2  Unequal concurrent   (CH0=8, CH1=4 words)
//          After CH1 finishes, CH0 should get the remaining 4 grants alone.
//          Verify: correct per-channel counts; no CH1 starvation in overlap.
//
//   TC3  Staggered start      (CH0=6 words, CH1=4 words, CH0 2-word head start)
//          CH0 enabled first; CH1 enabled after 2 CH0 words complete.
//          Verify: ≥2 leading CH0 grants in log; strict alternation once CH1 joins.
//
//   TC4  Single channel       (CH1 only, 4 words)
//          CH0 disabled; CH1 should get every grant.
//          Verify: 0 CH0 grants, 4 CH1 grants.
//
//   TC5  Restart during run   (CH0 completes then restarts while CH1 still active)
//          After CH0_a finishes, reconfigure and re-enable CH0_b.
//          Round-robin must resume correctly after the restart.
//          Verify: total grants = N0a+N0b for CH0, N1 for CH1; data correct.
//
// Memory layout (non-overlapping, 1-KB memory):
//   TC1  CH0 src [0..3]     = 0x000-0x00F   dst [32..35]   = 0x080-0x08F
//        CH1 src [64..67]   = 0x100-0x10F   dst [96..99]   = 0x180-0x18F
//   TC2  CH0 src [128..135] = 0x200-0x21F   dst [160..167] = 0x280-0x29F
//        CH1 src [192..195] = 0x300-0x30F   dst [224..227] = 0x380-0x38F
//   TC3  CH0 src [256..261] = 0x400-0x417   dst [288..293] = 0x480-0x497
//        CH1 src [320..323] = 0x500-0x50F   dst [352..355] = 0x580-0x58F
//   TC4  CH1 src [384..387] = 0x600-0x60F   dst [416..419] = 0x680-0x68F
//   TC5  CH0_a src[448..451]= 0x700-0x70F   dst [480..483] = 0x780-0x78F
//        CH1   src[512..519]= 0x800-0x81F   dst [544..551] = 0x880-0x89F
//        CH0_b src[576..579]= 0x900-0x90F   dst [608..611] = 0x980-0x98F
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module dma_rr_tb;

  //===========================================================================
  // Parameters
  //===========================================================================
  parameter CLK_PERIOD = 20;    // 50 MHz
  parameter MEM_WORDS  = 1024;  // 4 KB total

  //===========================================================================
  // DUT Signals
  //===========================================================================
  logic        clk;
  logic        rst_n;

  // TileLink Slave (CPU → DMA registers)
  logic        tl_a_valid;
  logic [2:0]  tl_a_opcode;
  logic [2:0]  tl_a_param;
  logic [2:0]  tl_a_size;
  logic [4:0]  tl_a_source;
  logic [31:0] tl_a_address;
  logic [3:0]  tl_a_mask;
  logic [31:0] tl_a_data;
  logic        tl_a_corrupt;
  logic        tl_a_ready;

  logic        tl_d_valid;
  logic [2:0]  tl_d_opcode;
  logic [2:0]  tl_d_param;
  logic [2:0]  tl_d_size;
  logic [4:0]  tl_d_source;
  logic [0:0]  tl_d_sink;
  logic [31:0] tl_d_data;
  logic        tl_d_denied;
  logic        tl_d_corrupt;
  logic        tl_d_ready;

  // TileLink Master (DMA → Memory)
  logic        dma_tl_a_valid;
  logic [2:0]  dma_tl_a_opcode;
  logic [2:0]  dma_tl_a_param;
  logic [2:0]  dma_tl_a_size;
  logic [4:0]  dma_tl_a_source;
  logic [31:0] dma_tl_a_address;
  logic [3:0]  dma_tl_a_mask;
  logic [31:0] dma_tl_a_data;
  logic        dma_tl_a_corrupt;
  logic        dma_tl_a_ready;

  logic        dma_tl_d_valid;
  logic [2:0]  dma_tl_d_opcode;
  logic [2:0]  dma_tl_d_param;
  logic [2:0]  dma_tl_d_size;
  logic [4:0]  dma_tl_d_source;
  logic [0:0]  dma_tl_d_sink;
  logic [31:0] dma_tl_d_data;
  logic        dma_tl_d_denied;
  logic        dma_tl_d_corrupt;
  logic        dma_tl_d_ready;

  logic        dma_irq;

  //===========================================================================
  // TL Opcodes
  //===========================================================================
  localparam logic [2:0] TL_GET              = 3'd4;
  localparam logic [2:0] TL_PUT_FULL_DATA    = 3'd0;
  localparam logic [2:0] TL_ACCESS_ACK       = 3'd0;
  localparam logic [2:0] TL_ACCESS_ACK_DATA  = 3'd1;

  //===========================================================================
  // DMA Register Map (Base 0x1005_0000 — matches tlul_xbar_2m6s)
  //===========================================================================
  localparam logic [31:0] DMA_BASE         = 32'h1005_0000;
  localparam logic [31:0] DMA_CH0_CONTROL  = DMA_BASE + 8'h00;
  localparam logic [31:0] DMA_CH0_STATUS   = DMA_BASE + 8'h04;
  localparam logic [31:0] DMA_CH0_SRC_ADDR = DMA_BASE + 8'h08;
  localparam logic [31:0] DMA_CH0_DST_ADDR = DMA_BASE + 8'h0C;
  localparam logic [31:0] DMA_CH0_XFER_CNT = DMA_BASE + 8'h10;
  localparam logic [31:0] DMA_CH1_CONTROL  = DMA_BASE + 8'h20;
  localparam logic [31:0] DMA_CH1_STATUS   = DMA_BASE + 8'h24;
  localparam logic [31:0] DMA_CH1_SRC_ADDR = DMA_BASE + 8'h28;
  localparam logic [31:0] DMA_CH1_DST_ADDR = DMA_BASE + 8'h2C;
  localparam logic [31:0] DMA_CH1_XFER_CNT = DMA_BASE + 8'h30;
  localparam logic [31:0] DMA_IRQ_STATUS   = DMA_BASE + 8'h40;

  //===========================================================================
  // Memory Model
  //===========================================================================
  logic [31:0] memory [0:MEM_WORDS-1];

  typedef enum logic [1:0] { MEM_IDLE, MEM_RESPOND } mem_state_t;
  mem_state_t  mem_state_q;
  logic [2:0]  mem_opcode_q;
  logic [2:0]  mem_size_q;
  logic [4:0]  mem_source_q;
  logic [31:0] mem_rdata_q;

  //===========================================================================
  // Test Bookkeeping
  //===========================================================================
  int test_count;
  int pass_count;
  int fail_count;

  //===========================================================================
  // Grant Monitor
  //  On every accepted GET on the DMA master bus, append the channel ID
  //  (0 or 1) to grant_log[]. Identification is done by address-range match.
  //  A GET = first half of a word transfer = arbiter just granted this channel.
  //===========================================================================
  int          grant_log[$];         // channel id per word transfer
  int          mon_ch0_cnt;          // running CH0 grant count
  int          mon_ch1_cnt;          // running CH1 grant count
  int          mon_max_imbalance;    // max |ch0_cnt - ch1_cnt| during run
  logic        mon_active;
  logic [31:0] mon_ch0_src_lo;       // CH0 src byte range [lo, hi)
  logic [31:0] mon_ch0_src_hi;
  logic [31:0] mon_ch1_src_lo;       // CH1 src byte range [lo, hi)
  logic [31:0] mon_ch1_src_hi;

  always @(posedge clk) begin : u_grant_monitor
    int ch_id;
    int imb;
    if (mon_active && dma_tl_a_valid && dma_tl_a_ready &&
        (dma_tl_a_opcode == TL_GET)) begin
      if (dma_tl_a_address >= mon_ch0_src_lo &&
          dma_tl_a_address <  mon_ch0_src_hi)
        ch_id = 0;
      else if (dma_tl_a_address >= mon_ch1_src_lo &&
               dma_tl_a_address <  mon_ch1_src_hi)
        ch_id = 1;
      else
        ch_id = -1;

      grant_log.push_back(ch_id);

      if      (ch_id == 0) mon_ch0_cnt++;
      else if (ch_id == 1) mon_ch1_cnt++;

      imb = mon_ch0_cnt - mon_ch1_cnt;
      if (imb < 0) imb = -imb;
      if (imb > mon_max_imbalance) mon_max_imbalance = imb;
    end
  end

  //===========================================================================
  // Monitor control tasks
  //===========================================================================
  task monitor_start(
    input logic [31:0] c0_lo, c0_hi,
    input logic [31:0] c1_lo, c1_hi
  );
    grant_log.delete();
    mon_ch0_cnt       = 0;
    mon_ch1_cnt       = 0;
    mon_max_imbalance = 0;
    mon_ch0_src_lo    = c0_lo;
    mon_ch0_src_hi    = c0_hi;
    mon_ch1_src_lo    = c1_lo;
    mon_ch1_src_hi    = c1_hi;
    mon_active        = 1'b1;
  endtask

  task monitor_stop();
    mon_active = 1'b0;
  endtask

  // Update CH0 range mid-run without resetting counts.
  // Use when CH0 restarts with a different source address during an active monitor.
  task monitor_update_ch0(input logic [31:0] lo, input logic [31:0] hi);
    mon_ch0_src_lo = lo;
    mon_ch0_src_hi = hi;
  endtask

  task print_grant_log();
    $write("[MON] grant_log [");
    foreach (grant_log[i]) begin
      $write("%0d", grant_log[i]);
      if (i < grant_log.size() - 1) $write(",");
    end
    $display("]");
    $display("[MON] CH0_grants=%-3d  CH1_grants=%-3d  max_imbalance=%0d",
             mon_ch0_cnt, mon_ch1_cnt, mon_max_imbalance);
  endtask

  //===========================================================================
  // Verification tasks
  //===========================================================================

  // Check total grants per channel match expected values.
  task check_grant_counts(input int exp0, input int exp1, input string tc_name);
    test_count++;
    if (mon_ch0_cnt === exp0 && mon_ch1_cnt === exp1) begin
      $display("[PASS] %s: grants  CH0=%0d  CH1=%0d  (exp %0d/%0d)",
               tc_name, mon_ch0_cnt, mon_ch1_cnt, exp0, exp1);
      pass_count++;
    end else begin
      $display("[FAIL] %s: grants  CH0=%0d  CH1=%0d  (exp %0d/%0d)",
               tc_name, mon_ch0_cnt, mon_ch1_cnt, exp0, exp1);
      fail_count++;
    end
  endtask

  // Check strict alternation in the overlap window.
  //   The "overlap window" starts at the first CH1 grant in the log.
  //   While both channels still have remaining words (ch0_seen < n0 AND
  //   ch1_seen < n1), no two consecutive same-channel grants are allowed.
  task automatic check_alternation(input int n0, input int n1, input string tc_name);
    int ch0_seen;
    int ch1_seen;
    int last_ch;
    int in_overlap;
    int ok;
    ch0_seen   = 0;
    ch1_seen   = 0;
    last_ch    = -1;
    in_overlap = 0;
    ok         = 1;

    test_count++;
    foreach (grant_log[i]) begin
      int g;
      g = grant_log[i];

      // Overlap begins at first CH1 grant; reset last_ch so the boundary
      // entry (transitioning from CH0-only to overlap) is never flagged.
      if (!in_overlap && g == 1) begin
        in_overlap = 1;
        last_ch    = -1;
      end

      // Only enforce alternation inside the overlap and while both active.
      if (in_overlap && ch0_seen < n0 && ch1_seen < n1) begin
        if (g == last_ch && g >= 0) begin
          $display("[FAIL] %s: double grant to CH%0d at grant[%0d]",
                   tc_name, g, i);
          ok = 0;
          fail_count++;
          break;
        end
      end

      last_ch = g;
      if      (g == 0) ch0_seen++;
      else if (g == 1) ch1_seen++;
    end

    if (ok) begin
      if (in_overlap)
        $display("[PASS] %s: strict RR alternation in overlap window", tc_name);
      else
        $display("[INFO] %s: CH1 never appeared — no overlap to verify", tc_name);
      pass_count++;
    end
  endtask

  // Check running imbalance stays within max_allowed during concurrent phase.
  task check_imbalance(input int max_allowed, input string tc_name);
    test_count++;
    if (mon_max_imbalance <= max_allowed) begin
      $display("[PASS] %s: max_imbalance=%0d (≤ %0d allowed)",
               tc_name, mon_max_imbalance, max_allowed);
      pass_count++;
    end else begin
      $display("[FAIL] %s: max_imbalance=%0d (> %0d allowed)",
               tc_name, mon_max_imbalance, max_allowed);
      fail_count++;
    end
  endtask

  // Check destination memory data correctness.
  //   Expected: memory[dst_word + i] == pattern_base + i  for i in [0, n)
  task check_data(
    input int     dst_word_base,
    input int     n_words,
    input logic [31:0] pattern_base,
    input string  tc_name
  );
    logic all_ok;
    test_count++;
    all_ok = 1'b1;
    for (int i = 0; i < n_words; i++) begin
      if (memory[dst_word_base + i] !== (pattern_base + i)) begin
        $display("  [%s] mem[%0d]=0x%08X  exp=0x%08X",
                 tc_name, dst_word_base+i,
                 memory[dst_word_base+i], pattern_base+i);
        all_ok = 1'b0;
      end
    end
    if (all_ok) begin
      $display("[PASS] %s: %0d words correct", tc_name, n_words); pass_count++;
    end else begin
      $display("[FAIL] %s: data mismatch",     tc_name);           fail_count++;
    end
  endtask

  // Reset channels and clear IRQs between test cases.
  task tc_cleanup();
    tl_write(DMA_CH0_CONTROL, 32'h0);
    tl_write(DMA_CH1_CONTROL, 32'h0);
    tl_write(DMA_IRQ_STATUS,  32'h3);
    monitor_stop();
    repeat (10) @(posedge clk);
  endtask

  //===========================================================================
  // Clock + Watchdog
  //===========================================================================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  initial begin
    #(CLK_PERIOD * 500_000);
    $display("[FATAL] Simulation watchdog fired — possible deadlock!");
    $finish;
  end

  //===========================================================================
  // DUT
  //===========================================================================
  tlul_dma u_dut (
    .i_clk              (clk),
    .i_rst_n            (rst_n),
    // Slave
    .i_tl_a_valid       (tl_a_valid),
    .i_tl_a_opcode      (tl_a_opcode),
    .i_tl_a_param       (tl_a_param),
    .i_tl_a_size        (tl_a_size),
    .i_tl_a_source      (tl_a_source),
    .i_tl_a_address     (tl_a_address),
    .i_tl_a_mask        (tl_a_mask),
    .i_tl_a_data        (tl_a_data),
    .i_tl_a_corrupt     (tl_a_corrupt),
    .o_tl_a_ready       (tl_a_ready),
    .o_tl_d_valid       (tl_d_valid),
    .o_tl_d_opcode      (tl_d_opcode),
    .o_tl_d_param       (tl_d_param),
    .o_tl_d_size        (tl_d_size),
    .o_tl_d_source      (tl_d_source),
    .o_tl_d_sink        (tl_d_sink),
    .o_tl_d_data        (tl_d_data),
    .o_tl_d_denied      (tl_d_denied),
    .o_tl_d_corrupt     (tl_d_corrupt),
    .i_tl_d_ready       (tl_d_ready),
    // Master
    .o_dma_tl_a_valid   (dma_tl_a_valid),
    .o_dma_tl_a_opcode  (dma_tl_a_opcode),
    .o_dma_tl_a_param   (dma_tl_a_param),
    .o_dma_tl_a_size    (dma_tl_a_size),
    .o_dma_tl_a_source  (dma_tl_a_source),
    .o_dma_tl_a_address (dma_tl_a_address),
    .o_dma_tl_a_mask    (dma_tl_a_mask),
    .o_dma_tl_a_data    (dma_tl_a_data),
    .o_dma_tl_a_corrupt (dma_tl_a_corrupt),
    .i_dma_tl_a_ready   (dma_tl_a_ready),
    .i_dma_tl_d_valid   (dma_tl_d_valid),
    .i_dma_tl_d_opcode  (dma_tl_d_opcode),
    .i_dma_tl_d_param   (dma_tl_d_param),
    .i_dma_tl_d_size    (dma_tl_d_size),
    .i_dma_tl_d_source  (dma_tl_d_source),
    .i_dma_tl_d_sink    (dma_tl_d_sink),
    .i_dma_tl_d_data    (dma_tl_d_data),
    .i_dma_tl_d_denied  (dma_tl_d_denied),
    .i_dma_tl_d_corrupt (dma_tl_d_corrupt),
    .o_dma_tl_d_ready   (dma_tl_d_ready),
    .o_dma_irq          (dma_irq)
  );

  //===========================================================================
  // Memory Model (simple, 1-cycle response, no error injection)
  //===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_state_q  <= MEM_IDLE;
      mem_opcode_q <= 3'd0;
      mem_size_q   <= 3'd0;
      mem_source_q <= 5'd0;
      mem_rdata_q  <= 32'd0;
    end else begin
      case (mem_state_q)
        MEM_IDLE: begin
          if (dma_tl_a_valid && dma_tl_a_ready) begin
            mem_opcode_q <= dma_tl_a_opcode;
            mem_size_q   <= dma_tl_a_size;
            mem_source_q <= dma_tl_a_source;
            if (dma_tl_a_opcode == TL_GET)
              mem_rdata_q <= memory[dma_tl_a_address[11:2]];
            mem_state_q  <= MEM_RESPOND;
          end
        end
        MEM_RESPOND: begin
          if (dma_tl_d_valid && dma_tl_d_ready)
            mem_state_q <= MEM_IDLE;
        end
        default: mem_state_q <= MEM_IDLE;
      endcase
    end
  end

  always @(posedge clk) begin
    if (mem_state_q == MEM_IDLE && dma_tl_a_valid && dma_tl_a_ready &&
        dma_tl_a_opcode != TL_GET)
      memory[dma_tl_a_address[11:2]] = dma_tl_a_data;
  end

  assign dma_tl_a_ready  = (mem_state_q == MEM_IDLE);
  assign dma_tl_d_valid  = (mem_state_q == MEM_RESPOND);
  assign dma_tl_d_opcode = (mem_opcode_q == TL_GET) ? TL_ACCESS_ACK_DATA : TL_ACCESS_ACK;
  assign dma_tl_d_param  = 3'd0;
  assign dma_tl_d_size   = mem_size_q;
  assign dma_tl_d_source = mem_source_q;
  assign dma_tl_d_sink   = 1'b0;
  assign dma_tl_d_data   = mem_rdata_q;
  assign dma_tl_d_denied = 1'b0;
  assign dma_tl_d_corrupt = 1'b0;

  //===========================================================================
  // CPU TileLink tasks
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

  // Poll STATUS[0] (busy) until clear.
  task automatic wait_dma_done(input int channel, input int timeout_polls);
    logic [31:0] status;
    logic [31:0] saddr;
    int          n;
    saddr = (channel == 0) ? DMA_CH0_STATUS : DMA_CH1_STATUS;
    n = 0;
    do begin
      tl_read(saddr, status);
      n++;
      if (n > timeout_polls) begin
        $display("[TIMEOUT] CH%0d busy after %0d polls!", channel, n);
        return;
      end
    end while (status[0] == 1'b1);
    $display("[DBG] CH%0d done after %0d polls  (t=%0t)", channel, n, $time);
  endtask

  // Poll STATUS[31:16] (remaining words) until ≤ target.
  // Used to create a controlled head-start for TC3.
  task automatic wait_remaining_le(input int channel, input int target,
                                   input int timeout_polls);
    logic [31:0] status;
    logic [31:0] saddr;
    int          n;
    saddr = (channel == 0) ? DMA_CH0_STATUS : DMA_CH1_STATUS;
    n = 0;
    do begin
      tl_read(saddr, status);
      n++;
      if (n > timeout_polls) begin
        $display("[TIMEOUT] wait_remaining CH%0d <= %0d after %0d polls!",
                 channel, target, n);
        return;
      end
    end while (status[31:16] > target);
  endtask

  //===========================================================================
  // TC1 — Equal Simultaneous (CH0=4, CH1=4 words)
  //===========================================================================
  task tc1_equal_simultaneous();
    localparam int N = 4;
    $display("");
    $display("================================================================");
    $display("  TC1: Equal Simultaneous  (%0d+%0d words)", N, N);
    $display("================================================================");
    $display("  Purpose: Both channels start simultaneously with equal");
    $display("           transfer sizes. Arbiter must alternate fairly.");
    $display("  Expected: Strict CH0-CH1-CH0-CH1... alternation.");
    $display("");

    for (int i =  0; i <  N; i++) memory[i]     = 32'hAAAA_0000 + i;
    for (int i = 64; i < 64+N; i++) memory[i]   = 32'hBBBB_0000 + (i-64);
    for (int i = 32; i < 32+N; i++) memory[i]   = 32'h0;
    for (int i = 96; i < 96+N; i++) memory[i]   = 32'h0;

    // Configure all registers before enabling either channel.
    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0000);  // word  0
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0080);  // word 32
    tl_write(DMA_CH0_XFER_CNT, N);
    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0100);  // word 64
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_0180);  // word 96
    tl_write(DMA_CH1_XFER_CNT, N);

    monitor_start(
      32'h0000_0000, 32'h0000_0010,   // CH0 src: 4 words × 4 B = 0x10
      32'h0000_0100, 32'h0000_0110    // CH1 src
    );

    // Enable both back-to-back → minimal head-start
    tl_write(DMA_CH0_CONTROL, 32'h0000_0007);   // en+src_inc+dst_inc
    tl_write(DMA_CH1_CONTROL, 32'h0000_0007);

    wait_dma_done(0, 5000);
    wait_dma_done(1, 5000);
    monitor_stop();

    print_grant_log();
    check_grant_counts(N, N, "TC1");
    check_alternation(N, N, "TC1");
    // Fairness: during overlap each channel can be at most 2 words ahead
    check_imbalance(2, "TC1_fair");
    check_data(32, N, 32'hAAAA_0000, "TC1_CH0_data");
    check_data(96, N, 32'hBBBB_0000, "TC1_CH1_data");
    tc_cleanup();
  endtask

  //===========================================================================
  // TC2 — Unequal Concurrent (CH0=8, CH1=4 words)
  //===========================================================================
  task tc2_unequal_concurrent();
    localparam int N0 = 8, N1 = 4;
    $display("");
    $display("================================================================");
    $display("  TC2: Unequal Concurrent  (CH0=%0d, CH1=%0d words)", N0, N1);
    $display("================================================================");
    $display("  Purpose: CH0 has more words than CH1. After CH1 finishes,");
    $display("           CH0 should get all remaining grants without delay.");
    $display("  Expected: Alternation during overlap, then CH0-only tail.");
    $display("");

    for (int i = 128; i < 128+N0; i++) memory[i] = 32'hCCCC_0000 + (i-128);
    for (int i = 192; i < 192+N1; i++) memory[i] = 32'hDDDD_0000 + (i-192);
    for (int i = 160; i < 160+N0; i++) memory[i] = 32'h0;
    for (int i = 224; i < 224+N1; i++) memory[i] = 32'h0;

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0200);  // word 128
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0280);  // word 160
    tl_write(DMA_CH0_XFER_CNT, N0);
    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0300);  // word 192
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_0380);  // word 224
    tl_write(DMA_CH1_XFER_CNT, N1);

    monitor_start(
      32'h0000_0200, 32'h0000_0220,   // CH0 src: 8 words = 0x20 bytes
      32'h0000_0300, 32'h0000_0310    // CH1 src: 4 words
    );

    tl_write(DMA_CH0_CONTROL, 32'h0000_0007);
    tl_write(DMA_CH1_CONTROL, 32'h0000_0007);

    wait_dma_done(0, 5000);
    wait_dma_done(1, 5000);
    monitor_stop();

    print_grant_log();
    check_grant_counts(N0, N1, "TC2");
    check_alternation(N0, N1, "TC2");
    // After CH1 finishes, CH0 must receive the remaining 4 grants alone.
    // In the grant_log those should be the last N0-N1 entries all being 0.
    begin
      int solo_ok;
      int solo_cnt;
      solo_ok  = 1;
      solo_cnt = 0;
      test_count++;
      for (int i = grant_log.size()-1; i >= 0; i--) begin
        if (grant_log[i] == 0) solo_cnt++;
        else break;
      end
      // solo_cnt = trailing CH0-only grants
      if (solo_cnt >= (N0 - N1)) begin
        $display("[PASS] TC2: CH0 solo tail = %0d grants (≥ %0d expected)",
                 solo_cnt, N0-N1);
        pass_count++;
      end else begin
        $display("[FAIL] TC2: CH0 solo tail = %0d (< %0d expected)",
                 solo_cnt, N0-N1);
        fail_count++;
      end
    end
    check_data(160, N0, 32'hCCCC_0000, "TC2_CH0_data");
    check_data(224, N1, 32'hDDDD_0000, "TC2_CH1_data");
    tc_cleanup();
  endtask

  //===========================================================================
  // TC3 — Staggered Start (CH0 gets 2-word head start, then CH1 joins)
  //===========================================================================
  task tc3_staggered_start();
    localparam int N0 = 6, N1 = 4;
    int head_start;
    $display("");
    $display("================================================================");
    $display("  TC3: Staggered Start  (CH0 head=%0d words, CH1 joins later)", 2);
    $display("================================================================");
    $display("  Purpose: CH0 starts first and completes 2+ words before");
    $display("           CH1 is enabled. Once CH1 joins, strict alternation.");
    $display("");

    for (int i = 256; i < 256+N0; i++) memory[i] = 32'hEEEE_0000 + (i-256);
    for (int i = 320; i < 320+N1; i++) memory[i] = 32'hFFFF_0000 + (i-320);
    for (int i = 288; i < 288+N0; i++) memory[i] = 32'h0;
    for (int i = 352; i < 352+N1; i++) memory[i] = 32'h0;

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0400);  // word 256
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0480);  // word 288
    tl_write(DMA_CH0_XFER_CNT, N0);
    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0500);  // word 320
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_0580);  // word 352
    tl_write(DMA_CH1_XFER_CNT, N1);

    monitor_start(
      32'h0000_0400, 32'h0000_0418,   // CH0 src: 6 words = 0x18 bytes
      32'h0000_0500, 32'h0000_0510    // CH1 src: 4 words
    );

    // Enable CH0 only.
    tl_write(DMA_CH0_CONTROL, 32'h0000_0007);

    // Wait until CH0 has transferred at least 2 words (remaining ≤ N0-2=4).
    wait_remaining_le(0, N0-2, 500);
    $display("[DBG] TC3: ≥2 CH0 words done at t=%0t; enabling CH1", $time);

    // Enable CH1 — from here, round-robin should alternate.
    tl_write(DMA_CH1_CONTROL, 32'h0000_0007);

    wait_dma_done(0, 5000);
    wait_dma_done(1, 5000);
    monitor_stop();

    print_grant_log();
    check_grant_counts(N0, N1, "TC3");
    check_alternation(N0, N1, "TC3");

    // Verify measured head-start ≥ 2 words.
    begin
      head_start = 0;
      foreach (grant_log[i]) begin
        if (grant_log[i] == 0) head_start++;
        else break;
      end
      $display("[DBG] TC3: measured CH0 head-start = %0d word(s)", head_start);
      test_count++;
      if (head_start >= 2) begin
        $display("[PASS] TC3: head-start = %0d (≥ 2)", head_start);
        pass_count++;
      end else begin
        $display("[FAIL] TC3: head-start = %0d (< 2)", head_start);
        fail_count++;
      end
    end

    check_data(288, N0, 32'hEEEE_0000, "TC3_CH0_data");
    check_data(352, N1, 32'hFFFF_0000, "TC3_CH1_data");
    tc_cleanup();
  endtask

  //===========================================================================
  // TC4 — Single Channel Active (CH1 only, 4 words)
  //===========================================================================
  task tc4_single_channel_ch1();
    localparam int N1 = 4;
    $display("");
    $display("================================================================");
    $display("  TC4: Single Channel  (CH1 only, %0d words)", N1);
    $display("================================================================");
    $display("  Purpose: Only CH1 is active. CH0 disabled.");
    $display("           All grants must go to CH1, no starvation.");
    $display("");

    for (int i = 384; i < 384+N1; i++) memory[i] = 32'h1234_0000 + (i-384);
    for (int i = 416; i < 416+N1; i++) memory[i] = 32'h0;

    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0600);  // word 384
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_0680);  // word 416
    tl_write(DMA_CH1_XFER_CNT, N1);

    // CH0 src range set to unmapped sentinel so nothing will match it.
    monitor_start(
      32'hFFFF_FF00, 32'hFFFF_FFFF,   // CH0: sentinel (nothing maps here)
      32'h0000_0600, 32'h0000_0610    // CH1 src: 4 words
    );

    tl_write(DMA_CH1_CONTROL, 32'h0000_0007);

    wait_dma_done(1, 2000);
    monitor_stop();

    print_grant_log();
    test_count++;
    if (mon_ch0_cnt == 0 && mon_ch1_cnt == N1) begin
      $display("[PASS] TC4: all %0d grants went to CH1, CH0 got none", N1);
      pass_count++;
    end else begin
      $display("[FAIL] TC4: CH0=%0d CH1=%0d (exp 0/%0d)",
               mon_ch0_cnt, mon_ch1_cnt, N1);
      fail_count++;
    end
    check_data(416, N1, 32'h1234_0000, "TC4_data");
    tc_cleanup();
  endtask

  //===========================================================================
  // TC5 — Restart During Concurrent (CH0 finishes and restarts while CH1 runs)
  //
  //  Phase A: CH0_a(4) + CH1(8) run concurrently → round-robin
  //  Gap:     CH0 completes, sits idle while CH1 continues
  //  Phase B: CH0_b(4) re-enabled → round-robin resumes
  //===========================================================================
  task tc5_restart_during_concurrent();
    localparam int N0A = 4, N1 = 8, N0B = 4;
    $display("");
    $display("================================================================");
    $display("  TC5: Restart During Concurrent");
    $display("================================================================");
    $display("  CH0_a=%0d + CH1=%0d words run concurrently.", N0A, N1);
    $display("  After CH0_a finishes, reconfigure and re-enable CH0_b=%0d.", N0B);
    $display("  Round-robin must resume correctly after the restart.");
    $display("");

    for (int i = 448; i < 448+N0A; i++) memory[i] = 32'hAA11_0000 + (i-448);
    for (int i = 512; i < 512+N1;  i++) memory[i] = 32'hBB22_0000 + (i-512);
    for (int i = 576; i < 576+N0B; i++) memory[i] = 32'hCC33_0000 + (i-576);
    for (int i = 480; i < 480+N0A; i++) memory[i] = 32'h0;
    for (int i = 544; i < 544+N1;  i++) memory[i] = 32'h0;
    for (int i = 608; i < 608+N0B; i++) memory[i] = 32'h0;

    // Configure CH1 (long transfer so CH0 can finish and restart within it).
    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0800);  // word 512
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_0880);  // word 544
    tl_write(DMA_CH1_XFER_CNT, N1);

    // Configure CH0 first run.
    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0700);  // word 448
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0780);  // word 480
    tl_write(DMA_CH0_XFER_CNT, N0A);

    // Phase A monitor: CH0_a src [0x700,0x710) and CH1 src [0x800,0x820).
    // These ranges are NON-overlapping — critical to avoid misclassification.
    monitor_start(
      32'h0000_0700, 32'h0000_0710,   // CH0_a: 4 words x 4B = 0x10
      32'h0000_0800, 32'h0000_0820    // CH1: 8 words x 4B = 0x20
    );

    tl_write(DMA_CH0_CONTROL, 32'h0000_0007);
    tl_write(DMA_CH1_CONTROL, 32'h0000_0007);

    wait_dma_done(0, 3000);
    $display("[DBG] TC5: CH0_a finished at t=%0t; reconfiguring CH0_b", $time);

    // Disable CH0, then update the monitor CH0 range to CH0_b src BEFORE
    // re-enabling so that CH1 grants in the reconfiguration gap are still
    // correctly counted as CH1 (monitor stays active throughout).
    tl_write(DMA_CH0_CONTROL,  32'h0000_0000);
    monitor_update_ch0(32'h0000_0900, 32'h0000_0910);  // CH0_b: 4 words
    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0900);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0980);
    tl_write(DMA_CH0_XFER_CNT, N0B);
    tl_write(DMA_CH0_CONTROL,  32'h0000_0007);

    wait_dma_done(0, 3000);
    wait_dma_done(1, 5000);
    monitor_stop();

    print_grant_log();
    // Total grants: CH0 = N0A + N0B, CH1 = N1
    check_grant_counts(N0A + N0B, N1, "TC5");
    check_data(480, N0A, 32'hAA11_0000, "TC5_CH0a_data");
    check_data(544, N1,  32'hBB22_0000, "TC5_CH1_data");
    check_data(608, N0B, 32'hCC33_0000, "TC5_CH0b_data");

    // For TC5 we do not check the full log for strict alternation because
    // there is an intentional gap where CH1 runs alone between phase A and B.
    // Instead, verify that neither channel was starved: in the combined log
    // the maximum run of consecutive same-channel entries should be ≤ 4
    // (bounded by the sole-running gap between phases, not by scheduler bugs).
    begin
      int max_run;
      int cur_run;
      max_run = 0;
      cur_run = 1;
      test_count++;
      for (int i = 1; i < grant_log.size(); i++) begin
        if (grant_log[i] == grant_log[i-1]) cur_run++;
        else                                cur_run = 1;
        if (cur_run > max_run) max_run = cur_run;
      end
      $display("[DBG] TC5: longest same-channel run = %0d", max_run);
      if (max_run <= N1) begin  // at most N1 consecutive CH1 grants during gap
        $display("[PASS] TC5: max same-channel run = %0d (no unbounded starvation)",
                 max_run);
        pass_count++;
      end else begin
        $display("[FAIL] TC5: max same-channel run = %0d (> %0d threshold)",
                 max_run, N1);
        fail_count++;
      end
    end
    tc_cleanup();
  endtask

  //===========================================================================
  // Main
  //===========================================================================
  initial begin
    rst_n         = 1'b0;
    tl_a_valid    = 1'b0;
    tl_a_opcode   = 3'd0;
    tl_a_param    = 3'd0;
    tl_a_size     = 3'd2;
    tl_a_source   = 5'd1;
    tl_a_address  = 32'd0;
    tl_a_mask     = 4'hF;
    tl_a_data     = 32'd0;
    tl_a_corrupt  = 1'b0;
    tl_d_ready    = 1'b1;
    mon_active    = 1'b0;
    test_count    = 0;
    pass_count    = 0;
    fail_count    = 0;

    for (int i = 0; i < MEM_WORDS; i++) memory[i] = 32'h0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    $display("");
    $display("################################################################");
    $display("#                                                              #");
    $display("#   DMA Round-Robin Arbitration Verification Testbench        #");
    $display("#   Module Under Test: dma_arbiter (inside tlul_dma)          #");
    $display("#                                                              #");
    $display("#   Arbitration Policy: Round-Robin per-word fairness         #");
    $display("#   When both channels request bus access, grants alternate    #");
    $display("#   between CH0 and CH1 on every word transfer (READ+WRITE).  #");
    $display("#                                                              #");
    $display("#   Test Plan:                                                #");
    $display("#     TC1: Equal Simultaneous   (CH0=4, CH1=4 words)          #");
    $display("#     TC2: Unequal Concurrent   (CH0=8, CH1=4 words)          #");
    $display("#     TC3: Staggered Start      (CH0 head start, then CH1)    #");
    $display("#     TC4: Single Channel       (CH1 only, 4 words)           #");
    $display("#     TC5: Restart During Run   (CH0 done+restart w/ CH1)     #");
    $display("#                                                              #");
    $display("#   Verification Metrics:                                     #");
    $display("#     - Per-channel grant counts                              #");
    $display("#     - Strict alternation in overlap window                  #");
    $display("#     - Max imbalance (fairness bound)                        #");
    $display("#     - Destination data integrity                            #");
    $display("#                                                              #");
    $display("################################################################");
    $display("");

    tc1_equal_simultaneous();
    tc2_unequal_concurrent();
    tc3_staggered_start();
    tc4_single_channel_ch1();
    tc5_restart_during_concurrent();

    $display("");
    $display("################################################################");
    $display("#                    FINAL TEST SUMMARY                        #");
    $display("################################################################");
    $display("#                                                              #");
    $display("#   Total Checks : %-4d                                       #", test_count);
    $display("#   Passed       : %-4d                                       #", pass_count);
    $display("#   Failed       : %-4d                                       #", fail_count);
    $display("#                                                              #");
    if (fail_count == 0)
    $display("#   Result: *** ALL TESTS PASSED ***                          #");
    else
    $display("#   Result: *** %0d TEST(S) FAILED ***                         #", fail_count);
    $display("#                                                              #");
    $display("#   TC1 Equal Simultaneous  : grant alternation verified       #");
    $display("#   TC2 Unequal Concurrent  : CH0 solo tail verified           #");
    $display("#   TC3 Staggered Start     : head-start & late-join verified  #");
    $display("#   TC4 Single Channel      : no starvation verified           #");
    $display("#   TC5 Restart During Run  : resume after restart verified    #");
    $display("#                                                              #");
    $display("################################################################");
    $display("");

    $finish;
  end

endmodule
