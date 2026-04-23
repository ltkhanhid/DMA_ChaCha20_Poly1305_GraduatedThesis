//-----------------------------------------------------------------------------
// Testbench: dma_tb
// Description: Comprehensive testbench for modular DMA Controller.
//              Tests individual sub-modules as well as full integration.
//
// Tests:
//   1. Register R/W              - basic register interface
//   2. Memory-to-Memory          - single-channel sequential transfer
//   3. No-increment (fill)       - fixed src, incrementing dst
//   4. Channel 1                 - verify second channel
//   5. Dual-channel concurrent   - both channels active, round-robin
//   6. Error injection           - d_denied response → DMA_ERROR
//   7. Back-to-back transfers    - disable then re-enable same channel
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module dma_tb;

  //===========================================================================
  // Parameters
  //===========================================================================
  parameter CLK_PERIOD = 20;   // 50 MHz
  parameter MEM_SIZE   = 256;  // words

  //===========================================================================
  // DUT Signals
  //===========================================================================
  logic        clk;
  logic        rst_n;

  // TileLink Slave signals (CPU → DMA registers)
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

  // TileLink Master signals (DMA → Memory)
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

  // Interrupt
  logic        dma_irq;

  // Test bookkeeping
  logic [31:0] read_data;
  int          test_count;
  int          pass_count;
  int          fail_count;

  // Error injection control
  logic        inject_denied;
  int          deny_after_n;  // Deny Nth DMA bus transaction
  int          dma_txn_cnt;   // Running count of DMA bus transactions
  logic        reset_txn_cnt; // Flag to reset dma_txn_cnt from tasks safely

  //===========================================================================
  // TileLink Opcodes
  //===========================================================================
  localparam logic [2:0] TL_GET              = 3'd4;
  localparam logic [2:0] TL_PUT_FULL_DATA    = 3'd0;
  localparam logic [2:0] TL_ACCESS_ACK       = 3'd0;
  localparam logic [2:0] TL_ACCESS_ACK_DATA  = 3'd1;

  //===========================================================================
  // DMA Register Addresses (Base 0x1005_0000 - matches tlul_xbar_2m6s)
  //===========================================================================
  localparam logic [31:0] DMA_BASE         = 32'h1005_0000;
  localparam logic [31:0] DMA_CH0_CONTROL  = DMA_BASE + 32'h00;
  localparam logic [31:0] DMA_CH0_STATUS   = DMA_BASE + 32'h04;
  localparam logic [31:0] DMA_CH0_SRC_ADDR = DMA_BASE + 32'h08;
  localparam logic [31:0] DMA_CH0_DST_ADDR = DMA_BASE + 32'h0C;
  localparam logic [31:0] DMA_CH0_XFER_CNT = DMA_BASE + 32'h10;

  localparam logic [31:0] DMA_CH1_CONTROL  = DMA_BASE + 32'h20;
  localparam logic [31:0] DMA_CH1_STATUS   = DMA_BASE + 32'h24;
  localparam logic [31:0] DMA_CH1_SRC_ADDR = DMA_BASE + 32'h28;
  localparam logic [31:0] DMA_CH1_DST_ADDR = DMA_BASE + 32'h2C;
  localparam logic [31:0] DMA_CH1_XFER_CNT = DMA_BASE + 32'h30;

  localparam logic [31:0] DMA_IRQ_STATUS   = DMA_BASE + 32'h40;

  //===========================================================================
  // Memory Model
  //===========================================================================
  logic [31:0] memory [0:MEM_SIZE-1];

  typedef enum logic [1:0] { MEM_IDLE, MEM_RESPOND } mem_state_t;

  mem_state_t  mem_state_q;
  logic [2:0]  mem_opcode_q;
  logic [2:0]  mem_size_q;
  logic [4:0]  mem_source_q;
  logic [31:0] mem_rdata_q;
  logic        mem_denied_q;

  //===========================================================================
  // Clock
  //===========================================================================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Timeformat: display time in nanoseconds, no decimals
  initial $timeformat(-9, 0, "", 0);

  // Global watchdog - prevent infinite hang
  initial begin
    #(CLK_PERIOD * 200_000);
    $display("[DMA_TB] @%0t ns | FATAL | Simulation timeout - possible deadlock!", $time);
    $finish;
  end

  //===========================================================================
  // DUT: modular tlul_dma
  //===========================================================================
  tlul_dma u_dut (
    .i_clk             (clk),
    .i_rst_n           (rst_n),

    // Slave
    .i_tl_a_valid      (tl_a_valid),
    .i_tl_a_opcode     (tl_a_opcode),
    .i_tl_a_param      (tl_a_param),
    .i_tl_a_size       (tl_a_size),
    .i_tl_a_source     (tl_a_source),
    .i_tl_a_address    (tl_a_address),
    .i_tl_a_mask       (tl_a_mask),
    .i_tl_a_data       (tl_a_data),
    .i_tl_a_corrupt    (tl_a_corrupt),
    .o_tl_a_ready      (tl_a_ready),

    .o_tl_d_valid      (tl_d_valid),
    .o_tl_d_opcode     (tl_d_opcode),
    .o_tl_d_param      (tl_d_param),
    .o_tl_d_size       (tl_d_size),
    .o_tl_d_source     (tl_d_source),
    .o_tl_d_sink       (tl_d_sink),
    .o_tl_d_data       (tl_d_data),
    .o_tl_d_denied     (tl_d_denied),
    .o_tl_d_corrupt    (tl_d_corrupt),
    .i_tl_d_ready      (tl_d_ready),

    // Master
    .o_dma_tl_a_valid  (dma_tl_a_valid),
    .o_dma_tl_a_opcode (dma_tl_a_opcode),
    .o_dma_tl_a_param  (dma_tl_a_param),
    .o_dma_tl_a_size   (dma_tl_a_size),
    .o_dma_tl_a_source (dma_tl_a_source),
    .o_dma_tl_a_address(dma_tl_a_address),
    .o_dma_tl_a_mask   (dma_tl_a_mask),
    .o_dma_tl_a_data   (dma_tl_a_data),
    .o_dma_tl_a_corrupt(dma_tl_a_corrupt),
    .i_dma_tl_a_ready  (dma_tl_a_ready),

    .i_dma_tl_d_valid  (dma_tl_d_valid),
    .i_dma_tl_d_opcode (dma_tl_d_opcode),
    .i_dma_tl_d_param  (dma_tl_d_param),
    .i_dma_tl_d_size   (dma_tl_d_size),
    .i_dma_tl_d_source (dma_tl_d_source),
    .i_dma_tl_d_sink   (dma_tl_d_sink),
    .i_dma_tl_d_data   (dma_tl_d_data),
    .i_dma_tl_d_denied (dma_tl_d_denied),
    .i_dma_tl_d_corrupt(dma_tl_d_corrupt),
    .o_dma_tl_d_ready  (dma_tl_d_ready),

    .o_dma_irq         (dma_irq)
  );

  //===========================================================================
  // Memory Model - with error injection
  //===========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_state_q  <= MEM_IDLE;
      mem_opcode_q <= 3'd0;
      mem_size_q   <= 3'd0;
      mem_source_q <= 5'd0;
      mem_rdata_q  <= 32'd0;
      mem_denied_q <= 1'b0;
      dma_txn_cnt  <= 0;
    end else begin
      if (reset_txn_cnt)
        dma_txn_cnt <= 0;

      case (mem_state_q)
        MEM_IDLE: begin
          if (dma_tl_a_valid && dma_tl_a_ready) begin
            mem_opcode_q <= dma_tl_a_opcode;
            mem_size_q   <= dma_tl_a_size;
            mem_source_q <= dma_tl_a_source;
            dma_txn_cnt  <= dma_txn_cnt + 1;

            if (dma_tl_a_opcode == TL_GET)
              mem_rdata_q <= memory[dma_tl_a_address[9:2]];

            // Error injection: deny the Nth transaction
            if (inject_denied && (dma_txn_cnt + 1) == deny_after_n)
              mem_denied_q <= 1'b1;
            else
              mem_denied_q <= 1'b0;

            mem_state_q <= MEM_RESPOND;
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

  // Memory write
  always @(posedge clk) begin
    if (mem_state_q == MEM_IDLE && dma_tl_a_valid && dma_tl_a_ready) begin
      if (dma_tl_a_opcode != TL_GET) begin
        if (!(inject_denied && (dma_txn_cnt + 1) == deny_after_n))
          memory[dma_tl_a_address[9:2]] = dma_tl_a_data;
      end
    end
  end

  assign dma_tl_a_ready  = (mem_state_q == MEM_IDLE);
  assign dma_tl_d_valid  = (mem_state_q == MEM_RESPOND);
  assign dma_tl_d_opcode = (mem_opcode_q == TL_GET) ? TL_ACCESS_ACK_DATA : TL_ACCESS_ACK;
  assign dma_tl_d_param  = 3'd0;
  assign dma_tl_d_size   = mem_size_q;
  assign dma_tl_d_source = mem_source_q;
  assign dma_tl_d_sink   = 1'b0;
  assign dma_tl_d_data   = mem_rdata_q;
  assign dma_tl_d_denied = mem_denied_q;
  assign dma_tl_d_corrupt= 1'b0;

  //===========================================================================
  // TileLink CPU-side Tasks
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

  task automatic wait_dma_done(input int channel, input int timeout_cycles);
    logic [31:0] status;
    int timeout;
    logic [31:0] status_addr;

    status_addr = (channel == 0) ? DMA_CH0_STATUS : DMA_CH1_STATUS;
    timeout = 0;

    do begin
      tl_read(status_addr, status);
      timeout++;
      if (timeout > timeout_cycles) begin
        $display("[DMA_TB] @%0t ns | ERROR | DMA CH%0d timeout after %0d polls!", $time, channel, timeout);
        return;
      end
    end while (status[0] == 1'b1);  // busy

    $display("[DMA_TB] @%0t ns | DBG   | DMA CH%0d done after %0d polls, status=0x%08X", $time, channel, timeout, status);
  endtask

  //===========================================================================
  // Helper: check a single register write-readback
  //===========================================================================
  task automatic check_reg(input string name, input logic [31:0] addr,
                           input logic [31:0] wval, input logic [31:0] mask);
    logic [31:0] rdata;
    test_count++;
    tl_write(addr, wval);
    tl_read(addr, rdata);
    if ((rdata & mask) == (wval & mask)) begin
      $display("[DMA_TB] @%0t ns | PASS  | %-16s  addr=0x%08X  WR=0x%08X  RD=0x%08X", $time, name, addr, wval, rdata);
      pass_count++;
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | %-16s  addr=0x%08X  WR=0x%08X  RD=0x%08X  (exp 0x%08X)", $time,
               name, addr, wval, rdata, wval & mask);
      fail_count++;
    end
  endtask

  //===========================================================================
  // TEST 1 - Register Read/Write (all DMA registers)
  //===========================================================================
  task automatic test_register_rw();
    logic [31:0] rdata;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 1: Register Read/Write Verification", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Verify all DMA config registers write/readback via TL-UL", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Method:  Write known value -> Read back -> Compare with mask", $time);
    $display("");
    $display("[DMA_TB] @%0t ns | INFO  | --- Channel 0 Registers ---", $time);
    check_reg("CH0_SRC_ADDR",  DMA_CH0_SRC_ADDR,  32'h0000_0100, 32'hFFFF_FFFC);
    check_reg("CH0_DST_ADDR",  DMA_CH0_DST_ADDR,  32'h0000_0200, 32'hFFFF_FFFC);
    check_reg("CH0_XFER_CNT",  DMA_CH0_XFER_CNT,  32'h0000_0010, 32'h0000_FFFF);
    check_reg("CH0_CONTROL",   DMA_CH0_CONTROL,    32'h0000_0007, 32'h0000_0007);
    // Disable after test
    tl_write(DMA_CH0_CONTROL, 32'h0000_0000);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000000 (disable)", $time);
    repeat(20) @(posedge clk); // let IRQ clear
    tl_write(DMA_IRQ_STATUS,  32'h0000_0003);
    $display("[DMA_TB] @%0t ns | CFG   | Write IRQ_STATUS   = 0x00000003 (clear both)", $time);

    $display("");
    $display("[DMA_TB] @%0t ns | INFO  | --- Channel 1 Registers ---", $time);
    check_reg("CH1_SRC_ADDR",  DMA_CH1_SRC_ADDR,  32'h0000_0300, 32'hFFFF_FFFC);
    check_reg("CH1_DST_ADDR",  DMA_CH1_DST_ADDR,  32'h0000_0400, 32'hFFFF_FFFC);
    check_reg("CH1_XFER_CNT",  DMA_CH1_XFER_CNT,  32'h0000_0020, 32'h0000_FFFF);
    check_reg("CH1_CONTROL",   DMA_CH1_CONTROL,    32'h0000_0005, 32'h0000_0007);
    tl_write(DMA_CH1_CONTROL, 32'h0000_0000);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_CONTROL  = 0x00000000 (disable)", $time);
    repeat(20) @(posedge clk);
    tl_write(DMA_IRQ_STATUS,  32'h0000_0003);
    $display("[DMA_TB] @%0t ns | CFG   | Write IRQ_STATUS   = 0x00000003 (clear both)", $time);

    $display("");
    $display("[DMA_TB] @%0t ns | INFO  | --- IRQ Status Register (W1C) ---", $time);
    test_count++;
    tl_read(DMA_IRQ_STATUS, rdata);
    if (rdata[1:0] == 2'b00) begin
      $display("[DMA_TB] @%0t ns | PASS  | IRQ_STATUS       RD=0x%08X (cleared OK)", $time, rdata);
      pass_count++;
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | IRQ_STATUS       RD=0x%08X (exp 0x00)", $time, rdata);
      fail_count++;
    end

    $display("");
    $display("[DMA_TB] @%0t ns | INFO  | --- Status Register (Read-Only) ---", $time);
    test_count++;
    tl_read(DMA_CH0_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS       RD=0x%08X  busy=%b done=%b error=%b remaining=%0d",
             $time, rdata, rdata[0], rdata[1], rdata[2], rdata[31:16]);
    if (rdata[0] == 1'b0) begin
      $display("[DMA_TB] @%0t ns | PASS  | CH0 not busy after disable", $time);
      pass_count++;
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | CH0 still busy after disable", $time);
      fail_count++;
    end
  endtask

  //===========================================================================
  // TEST 2 - Memory-to-Memory Transfer (CH0, 8 words)
  //===========================================================================
  task automatic test_mem_to_mem_transfer();
    logic [31:0] rdata;
    logic        all_ok;
    int          t_start, t_end;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 2: Memory-to-Memory Transfer (CH0, 8 words)", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Verify DMA copies 8 words from src to dst", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Config:  SRC=0x000 DST=0x080 COUNT=8 src_inc=1 dst_inc=1", $time);
    $display("");
    test_count++;

    // Initialize source data and clear destination
    for (int i = 0; i < 8; i++) memory[i]    = 32'hDEAD_0000 + i;
    for (int i = 32; i < 40; i++) memory[i]  = 32'h0;

    $display("[DMA_TB] @%0t ns | DATA  | Source data initialized:", $time);
    for (int i = 0; i < 8; i++)
      $display("[DMA_TB] @%0t ns | DATA  |   mem[%3d] (0x%03X) = 0x%08X", $time, i, i*4, memory[i]);
    $display("");

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0000);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_SRC_ADDR = 0x00000000", $time);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0080);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_DST_ADDR = 0x00000080", $time);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0008);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_XFER_CNT = 0x00000008 (8 words)", $time);

    t_start = $time;
    tl_write(DMA_CH0_CONTROL,  32'h0000_0007);   // en=1 src_inc=1 dst_inc=1
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000007 (en=1 src_inc=1 dst_inc=1)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 transfer STARTED <<<", $time);

    wait_dma_done(0, 2000);
    t_end = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 transfer DONE - duration = %0d ns <<<", $time, t_end - t_start);

    // Read back status register
    tl_read(DMA_CH0_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS = 0x%08X  [busy=%b done=%b error=%b remaining=%0d]",
             $time, rdata, rdata[0], rdata[1], rdata[2], rdata[31:16]);
    $display("");

    // Verify data with detailed dump
    $display("[DMA_TB] @%0t ns | DATA  | Memory verification (SRC -> DST):", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "Word", "SRC @0x000", "DST @0x080", "Expected", "Status");
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "------", "-----------", "-----------", "-----------", "------");
    all_ok = 1'b1;
    for (int i = 0; i < 8; i++) begin
      logic ok;
      ok = (memory[i+32] === (32'hDEAD_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d]    0x%08X      0x%08X      0x%08X      %s",
               $time, i, memory[i], memory[i+32], 32'hDEAD_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    $display("");
    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | All 8 words transferred correctly", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | Data mismatch detected", $time); fail_count++; end

    // IRQ check
    test_count++;
    tl_read(DMA_IRQ_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | IRQ_STATUS = 0x%08X  [ch0_irq=%b ch1_irq=%b]", $time, rdata, rdata[0], rdata[1]);
    if (rdata[0]) begin
      $display("[DMA_TB] @%0t ns | PASS  | CH0 IRQ correctly asserted after transfer complete", $time);
      pass_count++;
      tl_write(DMA_IRQ_STATUS, 32'h0000_0001);
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | CH0 IRQ not set after transfer complete", $time);
      fail_count++;
    end
  endtask

  //===========================================================================
  // TEST 3 - No-Increment (Peripheral Fill)
  //===========================================================================
  task automatic test_no_increment_mode();
    logic all_ok;
    logic [31:0] rdata;
    int t_start, t_end;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 3: No-Increment Fill Mode", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Fill memory region with constant value (src_inc=0)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Config:  SRC=0x100 (fixed) DST=0x140 COUNT=4 src_inc=0 dst_inc=1", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Expected: All 4 dst words = 0xCAFEBABE", $time);
    $display("");
    test_count++;

    memory[64] = 32'hCAFEBABE;
    for (int i = 80; i < 84; i++) memory[i] = 32'h0;
    $display("[DMA_TB] @%0t ns | DATA  | Source:  mem[64] (0x100) = 0xCAFEBABE (fixed, no increment)", $time);
    $display("[DMA_TB] @%0t ns | DATA  | Dest:    mem[80..83] (0x140..0x14C) = cleared to 0", $time);
    $display("");

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0100);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_SRC_ADDR = 0x00000100", $time);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0140);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_DST_ADDR = 0x00000140", $time);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0004);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_XFER_CNT = 0x00000004 (4 words)", $time);

    t_start = $time;
    tl_write(DMA_CH0_CONTROL,  32'h0000_0005);   // en=1 src_inc=0 dst_inc=1
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000005 (en=1 src_inc=0 dst_inc=1)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 fill STARTED <<<", $time);

    wait_dma_done(0, 1000);
    t_end = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 fill DONE - duration = %0d ns <<<", $time, t_end - t_start);

    tl_read(DMA_CH0_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS = 0x%08X  [busy=%b done=%b error=%b remaining=%0d]",
             $time, rdata, rdata[0], rdata[1], rdata[2], rdata[31:16]);
    $display("");

    $display("[DMA_TB] @%0t ns | DATA  | Fill verification:", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-10s  %-14s  %-14s  %s",
             $time, "Index", "Address", "Actual", "Expected", "Status");
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-10s  %-14s  %-14s  %s",
             $time, "------", "----------", "-----------", "-----------", "------");
    all_ok = 1'b1;
    for (int i = 80; i < 84; i++) begin
      logic ok;
      ok = (memory[i] === 32'hCAFEBABE);
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d]   0x%03X      0x%08X      0xCAFEBABE      %s",
               $time, i-80, i*4, memory[i], ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    $display("");
    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | Fill mode works - all 4 words = 0xCAFEBABE", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | Fill mode data mismatch", $time); fail_count++; end

    tl_write(DMA_IRQ_STATUS, 32'h0000_0001);
  endtask

  //===========================================================================
  // TEST 4 - Channel 1 Transfer
  //===========================================================================
  task automatic test_channel1();
    logic all_ok;
    logic [31:0] rdata;
    int t_start, t_end;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 4: Channel 1 Transfer (4 words)", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Verify CH1 operates independently and correctly", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Config:  CH1 SRC=0x190 DST=0x1E0 COUNT=4 src_inc=1 dst_inc=1", $time);
    $display("");
    test_count++;

    for (int i = 100; i < 104; i++) memory[i] = 32'hBEEF_0000 + (i-100);
    for (int i = 120; i < 124; i++) memory[i] = 32'h0;

    $display("[DMA_TB] @%0t ns | DATA  | Source data (CH1):", $time);
    for (int i = 100; i < 104; i++)
      $display("[DMA_TB] @%0t ns | DATA  |   mem[%3d] (0x%03X) = 0x%08X", $time, i, i*4, memory[i]);
    $display("");

    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0190);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_SRC_ADDR = 0x00000190", $time);
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_01E0);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_DST_ADDR = 0x000001E0", $time);
    tl_write(DMA_CH1_XFER_CNT, 32'h0000_0004);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_XFER_CNT = 0x00000004 (4 words)", $time);

    t_start = $time;
    tl_write(DMA_CH1_CONTROL,  32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_CONTROL  = 0x00000007 (en=1 src_inc=1 dst_inc=1)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH1 transfer STARTED <<<", $time);

    wait_dma_done(1, 1000);
    t_end = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH1 transfer DONE - duration = %0d ns <<<", $time, t_end - t_start);

    tl_read(DMA_CH1_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH1_STATUS = 0x%08X  [busy=%b done=%b error=%b remaining=%0d]",
             $time, rdata, rdata[0], rdata[1], rdata[2], rdata[31:16]);
    $display("");

    $display("[DMA_TB] @%0t ns | DATA  | CH1 Data verification:", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "Word", "SRC @0x190", "DST @0x1E0", "Expected", "Status");
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "------", "-----------", "-----------", "-----------", "------");
    all_ok = 1'b1;
    for (int i = 0; i < 4; i++) begin
      logic ok;
      ok = (memory[120+i] === (32'hBEEF_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d]    0x%08X      0x%08X      0x%08X      %s",
               $time, i, memory[100+i], memory[120+i], 32'hBEEF_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    $display("");
    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | CH1 transferred all 4 words correctly", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | CH1 data mismatch", $time); fail_count++; end

    test_count++;
    tl_read(DMA_IRQ_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | IRQ_STATUS = 0x%08X  [ch0_irq=%b ch1_irq=%b]", $time, rdata, rdata[0], rdata[1]);
    if (rdata[1]) begin $display("[DMA_TB] @%0t ns | PASS  | CH1 IRQ correctly asserted", $time); pass_count++; end
    else          begin $display("[DMA_TB] @%0t ns | FAIL  | CH1 IRQ not set", $time); fail_count++; end
    tl_write(DMA_IRQ_STATUS, 32'h0000_0002);
  endtask

  //===========================================================================
  // TEST 5 - Dual-Channel Concurrent (round-robin verification)
  //===========================================================================
  task automatic test_dual_channel();
    logic all_ok;
    logic [31:0] status0, status1, rdata;
    int t_start, t_end;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 5: Dual-Channel Concurrent Transfer", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Verify CH0+CH1 concurrent with round-robin arbitration", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Config:  CH0: SRC=0x000 DST=0x230 COUNT=4", $time);
    $display("[DMA_TB] @%0t ns | INFO  |          CH1: SRC=0x028 DST=0x258 COUNT=4", $time);
    $display("");
    test_count++;

    // CH0: words 0-3 -> words 140-143
    for (int i = 0; i < 4; i++) memory[i]     = 32'hAAAA_0000 + i;
    for (int i = 140; i < 144; i++) memory[i]  = 32'h0;
    // CH1: words 10-13 -> words 150-153
    for (int i = 10; i < 14; i++) memory[i]    = 32'hBBBB_0000 + (i-10);
    for (int i = 150; i < 154; i++) memory[i]  = 32'h0;

    $display("[DMA_TB] @%0t ns | DATA  | CH0 Source: mem[0..3]   = {0xAAAA0000..0xAAAA0003}", $time);
    $display("[DMA_TB] @%0t ns | DATA  | CH1 Source: mem[10..13] = {0xBBBB0000..0xBBBB0003}", $time);
    $display("");

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0000);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_SRC_ADDR = 0x00000000", $time);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0230);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_DST_ADDR = 0x00000230", $time);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0004);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_XFER_CNT = 0x00000004 (4 words)", $time);
    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0028);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_SRC_ADDR = 0x00000028", $time);
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_0258);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_DST_ADDR = 0x00000258", $time);
    tl_write(DMA_CH1_XFER_CNT, 32'h0000_0004);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_XFER_CNT = 0x00000004 (4 words)", $time);

    t_start = $time;
    tl_write(DMA_CH0_CONTROL, 32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000007 (enable)", $time);
    tl_write(DMA_CH1_CONTROL, 32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH1_CONTROL  = 0x00000007 (enable)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> Both channels STARTED (round-robin arbitration) <<<", $time);

    wait_dma_done(0, 3000);
    $display("[DMA_TB] @%0t ns | INFO  | CH0 done", $time);
    wait_dma_done(1, 3000);
    t_end = $time;
    $display("[DMA_TB] @%0t ns | INFO  | CH1 done", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> Dual-channel COMPLETE - total duration = %0d ns <<<", $time, t_end - t_start);
    $display("");

    // Read statuses
    tl_read(DMA_CH0_STATUS, status0);
    tl_read(DMA_CH1_STATUS, status1);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS = 0x%08X  [busy=%b done=%b error=%b]", $time, status0, status0[0], status0[1], status0[2]);
    $display("[DMA_TB] @%0t ns | INFO  | CH1_STATUS = 0x%08X  [busy=%b done=%b error=%b]", $time, status1, status1[0], status1[1], status1[2]);
    $display("");

    // Verify CH0
    $display("[DMA_TB] @%0t ns | DATA  | CH0 Data verification:", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "Word", "SRC", "DST @0x230", "Expected", "Status");
    all_ok = 1'b1;
    for (int i = 0; i < 4; i++) begin
      logic ok;
      ok = (memory[140+i] === (32'hAAAA_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d]    0x%08X      0x%08X      0x%08X      %s",
               $time, i, memory[i], memory[140+i], 32'hAAAA_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    $display("");

    // Verify CH1
    $display("[DMA_TB] @%0t ns | DATA  | CH1 Data verification:", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "Word", "SRC", "DST @0x258", "Expected", "Status");
    for (int i = 0; i < 4; i++) begin
      logic ok;
      ok = (memory[150+i] === (32'hBBBB_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d]    0x%08X      0x%08X      0x%08X      %s",
               $time, i, memory[10+i], memory[150+i], 32'hBBBB_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    $display("");

    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | Both channels transferred correctly", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | Dual-channel data mismatch", $time); fail_count++; end

    // IRQ check
    tl_read(DMA_IRQ_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | IRQ_STATUS = 0x%08X  [ch0_irq=%b ch1_irq=%b]", $time, rdata, rdata[0], rdata[1]);
    tl_write(DMA_IRQ_STATUS, 32'h0000_0003);
  endtask

  //===========================================================================
  // TEST 6 - Error Injection (d_denied → CH error)
  //===========================================================================
  task automatic test_error_injection();
    logic [31:0] rdata;
    int t_start, t_end;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 6: Error Injection (TL-UL d_denied response)", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Inject bus error (d_denied=1) during DMA transfer", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Method:  Memory model returns d_denied on 2nd bus transaction", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Expected: CH0 status error bit set, transfer aborted", $time);
    $display("");
    test_count++;

    // Reset transaction counter and enable injection on 2nd DMA txn
    reset_txn_cnt = 1'b1;
    @(posedge clk);
    reset_txn_cnt = 1'b0;
    inject_denied = 1'b1;
    deny_after_n  = 2;    // The 2nd bus transaction will be denied
    $display("[DMA_TB] @%0t ns | CFG   | Error injection enabled: deny_after_n=%0d", $time, deny_after_n);

    for (int i = 0; i < 4; i++) memory[160+i] = 32'hFACE_0000 + i;
    for (int i = 170; i < 174; i++) memory[i]  = 32'h0;

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0280);  // word 160
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_SRC_ADDR = 0x00000280 (word 160)", $time);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_02A8);  // word 170
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_DST_ADDR = 0x000002A8 (word 170)", $time);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0004);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_XFER_CNT = 0x00000004 (4 words)", $time);

    t_start = $time;
    tl_write(DMA_CH0_CONTROL,  32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000007 (enable - error expected!)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 STARTED (error injection active) <<<", $time);

    // Wait - should abort on error
    wait_dma_done(0, 3000);
    t_end = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 STOPPED - duration = %0d ns <<<", $time, t_end - t_start);

    // Check error bit in status
    tl_read(DMA_CH0_STATUS, rdata);
    $display("");
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS = 0x%08X", $time, rdata);
    $display("[DMA_TB] @%0t ns | INFO  |   busy      = %b", $time, rdata[0]);
    $display("[DMA_TB] @%0t ns | INFO  |   done      = %b", $time, rdata[1]);
    $display("[DMA_TB] @%0t ns | INFO  |   error     = %b  <-- should be 1", $time, rdata[2]);
    $display("[DMA_TB] @%0t ns | INFO  |   remaining = %0d words (aborted early)", $time, rdata[31:16]);
    $display("");
    if (rdata[2] == 1'b1) begin
      $display("[DMA_TB] @%0t ns | PASS  | CH0 error bit correctly set after d_denied", $time);
      pass_count++;
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | CH0 error bit NOT set (bus error not detected)", $time);
      fail_count++;
    end

    // Check that transfer was incomplete (remaining > 0)
    test_count++;
    if (rdata[31:16] > 0) begin
      $display("[DMA_TB] @%0t ns | PASS  | Transfer aborted with %0d words remaining", $time, rdata[31:16]);
      pass_count++;
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | remaining=0 but error injected mid-transfer", $time);
      fail_count++;
    end

    // IRQ should still fire on error
    test_count++;
    tl_read(DMA_IRQ_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | IRQ_STATUS = 0x%08X  [ch0_irq=%b]", $time, rdata, rdata[0]);
    if (rdata[0]) begin
      $display("[DMA_TB] @%0t ns | PASS  | IRQ asserted on error condition", $time);
      pass_count++;
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | IRQ not asserted on error", $time);
      fail_count++;
    end

    // Disable injection
    inject_denied = 1'b0;
    $display("[DMA_TB] @%0t ns | CFG   | Error injection disabled", $time);

    // Clear enable and IRQ
    tl_write(DMA_CH0_CONTROL, 32'h0000_0000);
    tl_write(DMA_IRQ_STATUS,  32'h0000_0001);
  endtask

  //===========================================================================
  // TEST 7 - Back-to-Back Transfers (re-enable same channel)
  //===========================================================================
  task automatic test_back_to_back();
    logic all_ok;
    logic [31:0] rdata;
    int t_start_a, t_end_a, t_start_b, t_end_b;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 7: Back-to-Back Transfers (re-enable same channel)", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Verify CH0 can be disabled, reconfigured, and re-enabled", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Transfer A: SRC=0x000 DST=0x320 COUNT=4 (pattern 0x1111xxxx)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Transfer B: SRC=0x010 DST=0x348 COUNT=4 (pattern 0x2222xxxx)", $time);
    $display("");
    test_count++;

    // == Transfer A ==
    $display("[DMA_TB] @%0t ns | INFO  | --- Transfer A ---", $time);
    for (int i = 0; i < 4; i++) memory[i]     = 32'h1111_0000 + i;
    for (int i = 200; i < 204; i++) memory[i]  = 32'h0;

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0000);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_SRC_ADDR = 0x00000000", $time);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0320);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_DST_ADDR = 0x00000320", $time);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0004);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_XFER_CNT = 0x00000004 (4 words)", $time);

    t_start_a = $time;
    tl_write(DMA_CH0_CONTROL,  32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000007 (enable)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> Transfer A STARTED <<<", $time);
    wait_dma_done(0, 1000);
    t_end_a = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> Transfer A DONE - duration = %0d ns <<<", $time, t_end_a - t_start_a);

    tl_read(DMA_CH0_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS after A: 0x%08X [done=%b error=%b]", $time, rdata, rdata[1], rdata[2]);

    tl_write(DMA_CH0_CONTROL,  32'h0000_0000);
    tl_write(DMA_IRQ_STATUS,   32'h0000_0001);
    $display("[DMA_TB] @%0t ns | CFG   | CH0 disabled, IRQ cleared. Reconfiguring...", $time);
    $display("");

    // == Transfer B ==
    $display("[DMA_TB] @%0t ns | INFO  | --- Transfer B ---", $time);
    for (int i = 4; i < 8; i++) memory[i]     = 32'h2222_0000 + (i-4);
    for (int i = 210; i < 214; i++) memory[i]  = 32'h0;

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0010);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_SRC_ADDR = 0x00000010", $time);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0348);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_DST_ADDR = 0x00000348", $time);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0004);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_XFER_CNT = 0x00000004 (4 words)", $time);

    t_start_b = $time;
    tl_write(DMA_CH0_CONTROL,  32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000007 (re-enable)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> Transfer B STARTED <<<", $time);
    wait_dma_done(0, 1000);
    t_end_b = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> Transfer B DONE - duration = %0d ns <<<", $time, t_end_b - t_start_b);

    tl_read(DMA_CH0_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS after B: 0x%08X [done=%b error=%b]", $time, rdata, rdata[1], rdata[2]);
    $display("");

    // Verify both transfers
    $display("[DMA_TB] @%0t ns | DATA  | Transfer A verification (DST @0x320):", $time);
    all_ok = 1'b1;
    for (int i = 0; i < 4; i++) begin
      logic ok;
      ok = (memory[200+i] === (32'h1111_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d] mem[%3d] = 0x%08X  exp=0x%08X  %s",
               $time, i, 200+i, memory[200+i], 32'h1111_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end

    $display("[DMA_TB] @%0t ns | DATA  | Transfer B verification (DST @0x348):", $time);
    for (int i = 0; i < 4; i++) begin
      logic ok;
      ok = (memory[210+i] === (32'h2222_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d] mem[%3d] = 0x%08X  exp=0x%08X  %s",
               $time, i, 210+i, memory[210+i], 32'h2222_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    $display("");

    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | Back-to-back transfers both correct", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | Back-to-back data mismatch", $time); fail_count++; end

    tl_write(DMA_IRQ_STATUS, 32'h0000_0001);
  endtask

  //===========================================================================
  // TEST 8 - Large Transfer (CH0, 64 words)
  //===========================================================================
  task automatic test_large_transfer();
    logic all_ok;
    logic [31:0] rdata;
    int t_start, t_end;
    int pass_words, fail_words;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 8: Large Transfer (CH0, 64 words)", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose: Verify DMA transfer counter decrements correctly", $time);
    $display("[DMA_TB] @%0t ns | INFO  |          over a large 64-word burst - counter must reach 0", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Config:  SRC=0x000 DST=0x100 COUNT=64 src_inc=1 dst_inc=1", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Pattern: SRC[i] = 0xA5A5_0000 + i", $time);
    $display("");
    test_count++;

    // Init source mem[0..63], clear dest mem[64..127]
    for (int i = 0; i < 64; i++) memory[i]      = 32'hA5A5_0000 + i;
    for (int i = 64; i < 128; i++) memory[i]    = 32'h0;

    $display("[DMA_TB] @%0t ns | DATA  | Source  mem[  0.. 3] = 0xA5A50000..0xA5A50003  (first 4)", $time);
    $display("[DMA_TB] @%0t ns | DATA  | Source  mem[ 32..35] = 0xA5A50020..0xA5A50023  (mid 4)", $time);
    $display("[DMA_TB] @%0t ns | DATA  | Source  mem[ 60..63] = 0xA5A5003C..0xA5A5003F  (last 4)", $time);
    $display("[DMA_TB] @%0t ns | DATA  | Dest    mem[ 64..127] (0x100-0x1FC) = cleared to 0", $time);
    $display("");

    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0000);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_SRC_ADDR = 0x00000000", $time);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0100);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_DST_ADDR = 0x00000100", $time);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0040);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_XFER_CNT = 0x00000040 (64 words)", $time);

    t_start = $time;
    tl_write(DMA_CH0_CONTROL, 32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | Write CH0_CONTROL  = 0x00000007 (en=1 src_inc=1 dst_inc=1)", $time);
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 Large Transfer STARTED (64 words) <<<", $time);

    wait_dma_done(0, 5000);
    t_end = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> DMA CH0 Large Transfer DONE - duration = %0d ns <<<", $time, t_end - t_start);

    // Check transfer counter reached 0
    tl_read(DMA_CH0_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS = 0x%08X  [busy=%b done=%b error=%b remaining=%0d]",
             $time, rdata, rdata[0], rdata[1], rdata[2], rdata[31:16]);
    test_count++;
    if (rdata[31:16] == 16'd0) begin
      $display("[DMA_TB] @%0t ns | PASS  | Transfer counter reached 0 - all 64 words sent", $time);
      pass_count++;
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | Transfer counter = %0d (expected 0)", $time, rdata[31:16]);
      fail_count++;
    end
    $display("");

    // Verify all 64 words
    $display("[DMA_TB] @%0t ns | DATA  | Data spot-check -- 3 representative words (first / mid / last):", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "Word", "SRC @0x000", "DST @0x100", "Expected", "Status");
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "------", "-----------", "-----------", "-----------", "------");
    all_ok     = 1'b1;
    pass_words = 0;
    fail_words = 0;
    for (int i = 0; i < 64; i++) begin
      logic ok;
      ok = (memory[64+i] === (32'hA5A5_0000 + i));
      // Print only word 0, 32 and 63 as representative samples
      if (i == 0 || i == 32 || i == 63)
        $display("[DMA_TB] @%0t ns | DATA  |   [%2d]    0x%08X      0x%08X      0x%08X      %s",
                 $time, i, memory[i], memory[64+i], 32'hA5A5_0000+i, ok ? "PASS" : "FAIL <<<");
      if (ok) pass_words++; else begin fail_words++; all_ok = 1'b0; end
    end
    $display("[DMA_TB] @%0t ns | DATA  |   ... (%0d words total - only 3 samples shown above)", $time, 64);
    $display("");
    $display("[DMA_TB] @%0t ns | DATA  | Full-range check result: %0d PASS, %0d FAIL (out of 64 words)", $time, pass_words, fail_words);
    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | All 64 words transferred correctly (data integrity OK)", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | Data mismatch detected in large transfer", $time); fail_count++; end

    // IRQ check
    test_count++;
    tl_read(DMA_IRQ_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | IRQ_STATUS = 0x%08X  [ch0_irq=%b ch1_irq=%b]", $time, rdata, rdata[0], rdata[1]);
    if (rdata[0]) begin
      $display("[DMA_TB] @%0t ns | PASS  | CH0 IRQ correctly asserted after 64-word transfer", $time);
      pass_count++;
      tl_write(DMA_IRQ_STATUS, 32'h0000_0001);
    end else begin
      $display("[DMA_TB] @%0t ns | FAIL  | CH0 IRQ not set after large transfer", $time);
      fail_count++;
    end
    tl_write(DMA_CH0_CONTROL, 32'h0000_0000);
  endtask

  //===========================================================================
  // TEST 9 - Sequential Dual-Channel (CH0 done → SW enables CH1)
  //===========================================================================
  task automatic test_sequential_dual_channel();
    logic all_ok;
    logic [31:0] rdata;
    int t_start_ch0, t_end_ch0, t_start_ch1, t_end_ch1;

    $display("");
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | TEST 9: Sequential Dual-Channel Transfer", $time);
    $display("[DMA_TB] @%0t ns | ================================================================", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Purpose : Verify CH1 can reuse TL-UL bus after CH0 completes", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Sequence: [1] Enable CH0 only  ->  [2] CH0 done, SW clears  ->  [3] SW enables CH1", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Config  : CH0  SRC=0x000 DST=0x200 COUNT=8  pattern=0xC0C0_0000+i", $time);
    $display("[DMA_TB] @%0t ns | INFO  |           CH1  SRC=0x040 DST=0x220 COUNT=8  pattern=0xC1C1_0000+i", $time);
    $display("");
    test_count++;

    // CH0 source: mem[0..7]  = 0xC0C0_0000+i, dest mem[128..135] cleared
    // CH1 source: mem[16..23] = 0xC1C1_0000+i, dest mem[136..143] cleared
    for (int i = 0;  i < 8;  i++) memory[i]      = 32'hC0C0_0000 + i;
    for (int i = 16; i < 24; i++) memory[i]      = 32'hC1C1_0000 + (i-16);
    for (int i = 128; i < 136; i++) memory[i]    = 32'h0;
    for (int i = 136; i < 144; i++) memory[i]    = 32'h0;

    // Pre-configure both channels (addresses + counts), but DO NOT enable yet
    tl_write(DMA_CH0_SRC_ADDR, 32'h0000_0000);
    tl_write(DMA_CH0_DST_ADDR, 32'h0000_0200);
    tl_write(DMA_CH0_XFER_CNT, 32'h0000_0008);
    tl_write(DMA_CH1_SRC_ADDR, 32'h0000_0040);
    tl_write(DMA_CH1_DST_ADDR, 32'h0000_0220);
    tl_write(DMA_CH1_XFER_CNT, 32'h0000_0008);
    $display("[DMA_TB] @%0t ns | CFG   | CH0: SRC=0x000 DST=0x200 CNT=8   CH1: SRC=0x040 DST=0x220 CNT=8", $time);
    $display("[DMA_TB] @%0t ns | INFO  | Both channels pre-configured -- neither enabled yet", $time);
    $display("");

    // === PHASE 1: CH0 only ===
    $display("[DMA_TB] @%0t ns | INFO  | ---- Phase 1: Enable CH0 only (CH1 remains idle) ----", $time);
    t_start_ch0 = $time;
    tl_write(DMA_CH0_CONTROL, 32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | CH0_CONTROL = 0x7  [en=1 src_inc=1 dst_inc=1] -- CH0 STARTED", $time);

    wait_dma_done(0, 2000);
    t_end_ch0 = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> CH0 DONE -- duration = %0d ns <<<", $time, t_end_ch0 - t_start_ch0);

    // Read CH0 status, clear IRQ, disable CH0
    tl_read(DMA_CH0_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH0_STATUS = 0x%08X  [busy=%b done=%b error=%b remaining=%0d]",
             $time, rdata, rdata[0], rdata[1], rdata[2], rdata[31:16]);
    tl_read(DMA_IRQ_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | IRQ_STATUS = 0x%08X  [ch0_irq=%b ch1_irq=%b]", $time, rdata, rdata[0], rdata[1]);
    tl_write(DMA_CH0_CONTROL, 32'h0000_0000);
    tl_write(DMA_IRQ_STATUS,  32'h0000_0001);
    $display("[DMA_TB] @%0t ns | CFG   | CH0 disabled + IRQ cleared -- TL-UL bus is now free", $time);
    $display("");

    // === PHASE 2: CH1 reuses bus ===
    $display("[DMA_TB] @%0t ns | INFO  | ---- Phase 2: Software enables CH1 (bus reuse) ----", $time);
    t_start_ch1 = $time;
    tl_write(DMA_CH1_CONTROL, 32'h0000_0007);
    $display("[DMA_TB] @%0t ns | CFG   | CH1_CONTROL = 0x7  [en=1 src_inc=1 dst_inc=1] -- CH1 STARTED", $time);

    wait_dma_done(1, 2000);
    t_end_ch1 = $time;
    $display("[DMA_TB] @%0t ns | INFO  | >>> CH1 DONE - duration = %0d ns <<<", $time, t_end_ch1 - t_start_ch1);

    tl_read(DMA_CH1_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | CH1_STATUS = 0x%08X  [busy=%b done=%b error=%b remaining=%0d]",
             $time, rdata, rdata[0], rdata[1], rdata[2], rdata[31:16]);
    tl_read(DMA_IRQ_STATUS, rdata);
    $display("[DMA_TB] @%0t ns | INFO  | IRQ_STATUS = 0x%08X  [ch0_irq=%b ch1_irq=%b]", $time, rdata, rdata[0], rdata[1]);
    tl_write(DMA_CH1_CONTROL, 32'h0000_0000);
    tl_write(DMA_IRQ_STATUS,  32'h0000_0002);
    $display("");
    $display("[DMA_TB] @%0t ns | INFO  | Sequential timing: CH0=%0d ns, CH1=%0d ns, bus gap=%0d ns",
             $time, t_end_ch0-t_start_ch0, t_end_ch1-t_start_ch1, t_start_ch1-t_end_ch0);
    $display("[DMA_TB] @%0t ns | INFO  | No overlap -- confirms strictly sequential execution", $time);
    $display("");

    // === Verify CH0 data ===
    $display("[DMA_TB] @%0t ns | DATA  | CH0 Data verification (SRC @0x000 -> DST @0x200):", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "Word", "SRC @0x000", "DST @0x200", "Expected", "Status");
    all_ok = 1'b1;
    for (int i = 0; i < 8; i++) begin
      logic ok;
      ok = (memory[128+i] === (32'hC0C0_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d]    0x%08X      0x%08X      0x%08X      %s",
               $time, i, memory[i], memory[128+i], 32'hC0C0_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | CH0: all 8 words transferred correctly (Phase 1 OK)", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | CH0 data mismatch in sequential test", $time); fail_count++; end
    $display("");

    // === Verify CH1 data ===
    $display("[DMA_TB] @%0t ns | DATA  | CH1 Data verification (SRC @0x040 -> DST @0x220):", $time);
    $display("[DMA_TB] @%0t ns | DATA  |   %-6s  %-14s  %-14s  %-14s  %s",
             $time, "Word", "SRC @0x040", "DST @0x220", "Expected", "Status");
    all_ok = 1'b1;
    for (int i = 0; i < 8; i++) begin
      logic ok;
      ok = (memory[136+i] === (32'hC1C1_0000 + i));
      $display("[DMA_TB] @%0t ns | DATA  |   [%2d]    0x%08X      0x%08X      0x%08X      %s",
               $time, i, memory[16+i], memory[136+i], 32'hC1C1_0000+i, ok ? "PASS" : "FAIL <<<");
      if (!ok) all_ok = 1'b0;
    end
    if (all_ok) begin $display("[DMA_TB] @%0t ns | PASS  | CH1: all 8 words transferred correctly (bus reuse verified)", $time); pass_count++; end
    else        begin $display("[DMA_TB] @%0t ns | FAIL  | CH1 data mismatch in sequential test", $time); fail_count++; end
  endtask

  //===========================================================================
  // Main
  //===========================================================================
  initial begin
    // Defaults
    rst_n         = 1'b0;
    tl_a_valid    = 1'b0;
    tl_a_opcode   = 3'd0;
    tl_a_param    = 3'd0;
    tl_a_size     = 3'd0;
    tl_a_source   = 5'd0;
    tl_a_address  = 32'd0;
    tl_a_mask     = 4'd0;
    tl_a_data     = 32'd0;
    tl_a_corrupt  = 1'b0;
    tl_d_ready    = 1'b1;
    inject_denied = 1'b0;
    deny_after_n  = 0;
    reset_txn_cnt = 1'b0;

    test_count = 0;
    pass_count = 0;
    fail_count = 0;

    for (int i = 0; i < MEM_SIZE; i++) memory[i] = 32'h0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    $display("");
    $display("[DMA_TB] @%0t ns | ################################################################", $time);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | #   DMA Controller - Comprehensive Verification Testbench     #", $time);
    $display("[DMA_TB] @%0t ns | #   Module Under Test: tlul_dma (modular DMA controller)      #", $time);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | #   Sub-modules: dma_controller, dma_channel x2,              #", $time);
    $display("[DMA_TB] @%0t ns | #                dma_arbiter (round-robin), dma_tlul_master    #", $time);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | #   Bus Protocol: TileLink Uncached Lightweight (TL-UL)       #", $time);
    $display("[DMA_TB] @%0t ns | #   Clock Period: %0d ns (%0d MHz)                               #", $time, CLK_PERIOD, 1000/CLK_PERIOD);
    $display("[DMA_TB] @%0t ns | #   Memory Size:  %0d words (%0d bytes)                         #", $time, MEM_SIZE, MEM_SIZE*4);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | #   Test Plan:                                                #", $time);
    $display("[DMA_TB] @%0t ns | #     1. Register R/W        - all config registers           #", $time);
    $display("[DMA_TB] @%0t ns | #     2. Memory-to-Memory    - CH0, 8 words sequential        #", $time);
    $display("[DMA_TB] @%0t ns | #     3. No-Increment Fill   - fixed src, incrementing dst    #", $time);
    $display("[DMA_TB] @%0t ns | #     4. Channel 1           - independent CH1 operation      #", $time);
    $display("[DMA_TB] @%0t ns | #     5. Dual-Channel        - concurrent CH0+CH1, RR arb    #", $time);
    $display("[DMA_TB] @%0t ns | #     6. Error Injection     - d_denied -> DMA_ERROR state    #", $time);
    $display("[DMA_TB] @%0t ns | #     7. Back-to-Back        - disable, reconfig, re-enable   #", $time);
    $display("[DMA_TB] @%0t ns | #     8. Large Transfer      - CH0, 64 words, counter check   #", $time);
    $display("[DMA_TB] @%0t ns | #     9. Sequential Dual-Ch  - CH0 done, SW enables CH1       #", $time);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | ################################################################", $time);

    test_register_rw();
    test_mem_to_mem_transfer();
    test_no_increment_mode();
    test_channel1();
    test_dual_channel();
    test_error_injection();
    test_back_to_back();
    test_large_transfer();
    test_sequential_dual_channel();

    $display("");
    $display("[DMA_TB] @%0t ns | ################################################################", $time);
    $display("[DMA_TB] @%0t ns | #                    FINAL TEST SUMMARY                        #", $time);
    $display("[DMA_TB] @%0t ns | ################################################################", $time);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | #   Total Checks : %-4d                                       #", $time, test_count);
    $display("[DMA_TB] @%0t ns | #   Passed       : %-4d                                       #", $time, pass_count);
    $display("[DMA_TB] @%0t ns | #   Failed       : %-4d                                       #", $time, fail_count);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    if (fail_count == 0)
    $display("[DMA_TB] @%0t ns | #   Result: *** ALL TESTS PASSED ***                          #", $time);
    else
    $display("[DMA_TB] @%0t ns | #   Result: *** %0d TEST(S) FAILED ***                         #", $time, fail_count);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | #   Simulation Time : %0t ns                                   #", $time, $time);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | #   Test Breakdown:                                           #", $time);
    $display("[DMA_TB] @%0t ns | #     T1 Register R/W          : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T2 Memory-to-Memory      : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T3 No-Increment Fill     : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T4 Channel 1 Transfer    : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T5 Dual-Channel Conc.    : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T6 Error Injection       : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T7 Back-to-Back          : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T8 Large Transfer (64w)  : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #     T9 Sequential Dual-Ch    : verified                     #", $time);
    $display("[DMA_TB] @%0t ns | #                                                              #", $time);
    $display("[DMA_TB] @%0t ns | ################################################################", $time);
    $display("");

    $finish;
  end

endmodule
