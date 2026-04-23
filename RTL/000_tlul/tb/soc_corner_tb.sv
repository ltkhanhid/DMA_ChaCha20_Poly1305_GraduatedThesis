`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// soc_corner_tb — Corner case integration tests for ChaCha20 + DMA + UART
//
// Firmware (corner_test.hex) runs 10 tests:
//   T01: ChaCha20 basic encryption (all-zero, RFC 8439 TV#1)
//   T02: ChaCha20 back-to-back (counter auto-increment to 1)
//   T03: ChaCha20 IRQ W1C (set, clear, verify)
//   T04: ChaCha20 write to read-only CTEXT
//   T05: DMA CH0 basic MEM→MEM (4 words)
//   T06: DMA CH1 basic MEM→MEM (4 words)
//   T07: DMA FIFO mode (fixed destination)
//   T08: DMA zero-count transfer (sentinel preserved)
//   T09: DMA CH0+CH1 concurrent transfers
//   T10: DMA→ChaCha20 MMIO (DMA writes PTEXT, CPU encrypts)
//
//   Result: LEDR = 0xAA (ALL PASS) or 0xFF (FAIL, pass count in LEDG)
//-----------------------------------------------------------------------------
module soc_corner_tb;
  import tlul_pkg::*;

  parameter CLK_PERIOD   = 2;
  parameter RESET_PERIOD = 51;
  parameter TIMEOUT      = 1_000_000;  // large timeout for 10 tests

  // Clock & Reset
  logic clk, rst_n;

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    #RESET_PERIOD;
    rst_n = 1'b1;
  end

  initial begin
    #(TIMEOUT * CLK_PERIOD);
    $display("");
    $display("=== TIMEOUT after %0d cycles ===", TIMEOUT);
    $display("    Last LEDR = 0x%02X, pass_count in LEDG = %0d",
             ledr_internal, dut.ledg_o);
    $finish;
  end

  // DUT Signals
  logic [9:0]  sw_i;
  logic [9:0]  ledr_o;
  logic [31:0] ledg_o;
  logic [6:0]  hex0_o, hex1_o, hex2_o, hex3_o;
  logic [6:0]  hex4_o, hex5_o, hex6_o, hex7_o;
  logic        uart_rx_i, uart_tx_o;
  logic        irq_dma, irq_chacha, irq_poly;
  logic [31:0] pc_debug_o, pc_wb_o, pc_mem_o;
  logic        insn_vld_o, ctrl_o, mispred_o;

  initial begin
    sw_i      = 10'h0;
    uart_rx_i = 1'b1;
  end

  // DUT
  soc_top_2m6s #(
    .MEM_DEPTH (65536),
    .MEM_FILE  ("corner_test.hex")
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .sw_i       (sw_i),
    .ledr_o     (ledr_o),
    .ledg_o     (ledg_o),
    .hex0_o     (hex0_o),
    .hex1_o     (hex1_o),
    .hex2_o     (hex2_o),
    .hex3_o     (hex3_o),
    .hex4_o     (hex4_o),
    .hex5_o     (hex5_o),
    .hex6_o     (hex6_o),
    .hex7_o     (hex7_o),
    .uart_rx_i  (uart_rx_i),
    .uart_tx_o  (uart_tx_o),
    .irq_dma_o  (irq_dma),
    .irq_chacha_o(irq_chacha),
    .irq_poly_o(irq_poly),
    .pc_debug_o (pc_debug_o),
    .pc_wb_o    (pc_wb_o),
    .pc_mem_o   (pc_mem_o),
    .insn_vld_o (insn_vld_o),
    .ctrl_o     (ctrl_o),
    .mispred_o  (mispred_o)
  );

  // Internal probes
  wire [31:0] ledr_internal = dut.peri_ledr_internal;

  // Counters
  int cycle_count;
  logic [31:0] prev_ledr;
  int test_pass_count;
  int dma_irq_count, chacha_irq_count;
  logic prev_dma_irq, prev_chacha_irq;

  // Test names
  string test_names [11];
  initial begin
    test_names[1]  = "ChaCha20 basic (RFC8439 TV#1)";
    test_names[2]  = "ChaCha20 back-to-back (counter=1)";
    test_names[3]  = "ChaCha20 IRQ W1C";
    test_names[4]  = "ChaCha20 write to read-only CTEXT";
    test_names[5]  = "DMA CH0 basic 4-word MEM→MEM";
    test_names[6]  = "DMA CH1 basic 4-word MEM→MEM";
    test_names[7]  = "DMA FIFO mode (dst_inc=0)";
    test_names[8]  = "DMA zero-count transfer";
    test_names[9]  = "DMA CH0+CH1 concurrent";
    test_names[10] = "DMA→ChaCha20 MMIO";
  end

  initial begin
    cycle_count      = 0;
    prev_ledr        = 32'hFFFF_FFFF;
    test_pass_count  = 0;
    dma_irq_count    = 0;
    chacha_irq_count = 0;
    prev_dma_irq     = 0;
    prev_chacha_irq  = 0;
  end

  always @(posedge clk) begin
    if (rst_n) cycle_count <= cycle_count + 1;
  end

  // IRQ edge counters
  always @(posedge clk) begin
    if (rst_n) begin
      if (irq_dma && !prev_dma_irq) begin
        dma_irq_count <= dma_irq_count + 1;
        $display("[cycle %6d]   >> DMA IRQ asserted (#%0d)", cycle_count, dma_irq_count + 1);
      end
      if (irq_chacha && !prev_chacha_irq) begin
        chacha_irq_count <= chacha_irq_count + 1;
        $display("[cycle %6d]   >> ChaCha20 IRQ asserted (#%0d)", cycle_count, chacha_irq_count + 1);
      end
      prev_dma_irq    <= irq_dma;
      prev_chacha_irq <= irq_chacha;
    end
  end

  // Banner
  initial begin
    $display("");
    $display("============================================================");
    $display("  SoC Corner Case Integration Test (10 tests)");
    $display("  ChaCha20 + DMA + Cross-module");
    $display("============================================================");
    $display("");
  end

  // Phase monitor
  always @(negedge clk) begin
    if (rst_n && ledr_internal !== prev_ledr) begin
      if (ledr_internal >= 1 && ledr_internal <= 10) begin
        $display("[cycle %6d] T%02d: %s", cycle_count,
                 ledr_internal[4:0], test_names[ledr_internal[4:0]]);
      end
      else if (ledr_internal == 32'hAA) begin
        $display("[cycle %6d] === RESULT: ALL 10 TESTS PASS ===", cycle_count);
        $display("");
        print_summary();
        verify_dma_results();
        $finish;
      end
      else if (ledr_internal == 32'hFF) begin
        // Read pass count from LEDG (wait for propagation)
        #(CLK_PERIOD * 4);
        $display("[cycle %6d] === RESULT: FAIL ===", cycle_count);
        $display("");
        print_summary();
        verify_dma_results();
        $finish;
      end
      prev_ledr <= ledr_internal;
    end
  end

  //===========================================================================
  // Summary
  //===========================================================================
  task automatic print_summary();
    int ledg_val;
    ledg_val = dut.ledg_o;

    $display("============================================================");
    $display("  Corner Case Test Summary");
    $display("============================================================");
    $display("");
    if (ledr_internal == 32'hAA) begin
      $display("  Status:          ALL PASS (10/10)");
    end else begin
      $display("  Status:          FAIL");
      $display("  Tests passed:    %0d / 10", ledg_val);
      $display("  Failed at test:  T%02d — %s", ledg_val + 1,
               (ledg_val + 1 <= 10) ? test_names[ledg_val + 1] : "unknown");
    end
    $display("  Total cycles:    %0d", cycle_count);
    $display("  DMA IRQs seen:   %0d", dma_irq_count);
    $display("  ChaCha IRQs:     %0d", chacha_irq_count);
    $display("");

    // Print individual test results
    $display("  %-4s  %-40s  %s", "Test", "Description", "Result");
    $display("  %-4s  %-40s  %s", "----", "----------------------------------------", "------");
    for (int i = 1; i <= 10; i++) begin
      if (ledr_internal == 32'hAA || i <= ledg_val)
        $display("  T%02d   %-40s  PASS", i, test_names[i]);
      else if (i == ledg_val + 1)
        $display("  T%02d   %-40s  FAIL <<<", i, test_names[i]);
      else
        $display("  T%02d   %-40s  --", i, test_names[i]);
    end
    $display("");
  endtask

  //===========================================================================
  // Memory verification (direct probe into memory array)
  //===========================================================================
  task automatic verify_dma_results();
    logic [31:0] val;
    int pass, total;
    pass  = 0;
    total = 0;

    $display("============================================================");
    $display("  Memory Probe Verification");
    $display("============================================================");
    $display("");

    // T05: CH0 copy 0x2000 → 0x3000 (4 words)
    $display("  --- T05: DMA CH0 MEM→MEM (0x2000→0x3000) ---");
    for (int i = 0; i < 4; i++) begin
      val = dut.u_mem_adapter.u_memory.mem[32'h3000/4 + i];
      total++;
      if (i == 0 && val == 32'h11111111) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else if (i == 1 && val == 32'h22222222) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else if (i == 2 && val == 32'h33333333) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else if (i == 3 && val == 32'h44444444) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else $display("    [%0d] 0x%08X  FAIL", i, val);
    end
    $display("");

    // T06: CH1 copy 0x2000 → 0x4000 (4 words)
    $display("  --- T06: DMA CH1 MEM→MEM (0x2000→0x4000) ---");
    for (int i = 0; i < 4; i++) begin
      val = dut.u_mem_adapter.u_memory.mem[32'h4000/4 + i];
      total++;
      if (i == 0 && val == 32'h11111111) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else if (i == 1 && val == 32'h22222222) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else if (i == 2 && val == 32'h33333333) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else if (i == 3 && val == 32'h44444444) begin pass++; $display("    [%0d] 0x%08X  PASS", i, val); end
      else $display("    [%0d] 0x%08X  FAIL", i, val);
    end
    $display("");

    // T07: FIFO mode — 0x5000 should have last word only
    $display("  --- T07: DMA FIFO mode (0x5000, last word) ---");
    val = dut.u_mem_adapter.u_memory.mem[32'h5000/4];
    total++;
    if (val == 32'h44444444) begin pass++; $display("    [0] 0x%08X  PASS (last word)", val); end
    else $display("    [0] 0x%08X  FAIL (expected 0x44444444)", val);
    $display("");

    // T08: Zero-count — sentinel at 0x6000 should be preserved
    $display("  --- T08: DMA zero-count (0x6000, sentinel) ---");
    val = dut.u_mem_adapter.u_memory.mem[32'h6000/4];
    total++;
    if (val == 32'h12345678) begin pass++; $display("    [0] 0x%08X  PASS (sentinel)", val); end
    else $display("    [0] 0x%08X  FAIL (expected 0x12345678)", val);
    $display("");

    // T09: Concurrent — check both destinations
    $display("  --- T09: DMA concurrent CH0(→0x7000) + CH1(→0x7800) ---");
    // CH0
    val = dut.u_mem_adapter.u_memory.mem[32'h7000/4];
    total++;
    if (val == 32'h11111111) begin pass++; $display("    CH0[0] 0x%08X  PASS", val); end
    else $display("    CH0[0] 0x%08X  FAIL", val);
    val = dut.u_mem_adapter.u_memory.mem[32'h7000/4 + 3];
    total++;
    if (val == 32'h44444444) begin pass++; $display("    CH0[3] 0x%08X  PASS", val); end
    else $display("    CH0[3] 0x%08X  FAIL", val);
    // CH1
    val = dut.u_mem_adapter.u_memory.mem[32'h7800/4];
    total++;
    if (val == 32'hAAAA0001) begin pass++; $display("    CH1[0] 0x%08X  PASS", val); end
    else $display("    CH1[0] 0x%08X  FAIL", val);
    val = dut.u_mem_adapter.u_memory.mem[32'h7800/4 + 3];
    total++;
    if (val == 32'hAAAA0004) begin pass++; $display("    CH1[3] 0x%08X  PASS", val); end
    else $display("    CH1[3] 0x%08X  FAIL", val);
    $display("");

    $display("  Memory probe totals: %0d / %0d PASS", pass, total);
    $display("============================================================");
    $display("");
  endtask

endmodule
