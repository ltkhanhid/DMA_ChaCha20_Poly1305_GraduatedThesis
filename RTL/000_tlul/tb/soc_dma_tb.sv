`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// soc_dma_tb — Integration test: CPU memcpy vs DMA memcpy through TileLink
//
// Firmware (dma_test.hex) does:
//   Phase 1: Init 100 words at DMEM 0x1000 (pattern 0x100+i)
//   Phase 2: CPU lw/sw copy  0x1000 → 0x2000
//   Phase 3: DMA hw transfer 0x1000 → 0x3000
//   Phase 4: Verify both destinations
//   Result:  LEDR = 0xAA (pass) or 0xFF (fail)
//
// Testbench measures cycle counts, IPC, and probes memory for verification.
//-----------------------------------------------------------------------------
module soc_dma_tb;
  import tlul_pkg::*;

  //===========================================================================
  // Parameters
  //===========================================================================
  parameter CLK_PERIOD   = 2;       // 1ns high + 1ns low = 500 MHz sim
  parameter RESET_PERIOD = 51;
  parameter TIMEOUT      = 500_000; // cycles

  //===========================================================================
  // Clock & Reset
  //===========================================================================
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
    $display("    DMA may be stuck. Check xbar arbitration.");
    $finish;
  end

  //===========================================================================
  // DUT Signals
  //===========================================================================
  logic [9:0]  sw_i;
  logic [9:0]  ledr_o;
  logic [31:0] ledg_o;
  logic [6:0]  hex0_o, hex1_o, hex2_o, hex3_o;
  logic [6:0]  hex4_o, hex5_o, hex6_o, hex7_o;
  logic        uart_rx_i, uart_tx_o;
  logic        irq_dma, irq_chacha;
  logic [31:0] pc_debug_o, pc_wb_o, pc_mem_o;
  logic        insn_vld_o, ctrl_o, mispred_o;

  initial begin
    sw_i      = 10'h0;
    uart_rx_i = 1'b1;   // UART idle
  end

  //===========================================================================
  // DUT: SoC Top (2M6S) with DMA test firmware
  //===========================================================================
  soc_top_2m6s #(
    .MEM_DEPTH (65536),
    .MEM_FILE  ("../02_test/dma_test.hex")
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
    .pc_debug_o (pc_debug_o),
    .pc_wb_o    (pc_wb_o),
    .pc_mem_o   (pc_mem_o),
    .insn_vld_o (insn_vld_o),
    .ctrl_o     (ctrl_o),
    .mispred_o  (mispred_o)
  );

  //===========================================================================
  // Internal signal probes
  //===========================================================================
  wire [31:0] ledr_internal = dut.peri_ledr_internal;

  //===========================================================================
  // Performance counters
  //===========================================================================
  int cycle_count;
  int cpu_copy_start, cpu_copy_end;
  int dma_copy_start, dma_copy_end;
  logic [31:0] prev_ledr;
  logic dma_irq_seen;

  // IPC counters
  real num_insn;
  real num_cycle;

  // Branch misprediction counter
  int mispred_count;
  int branch_count;

  // DMA bus transaction counter
  int dma_bus_rd_count;
  int dma_bus_wr_count;

  initial begin
    cycle_count    = 0;
    cpu_copy_start = 0;
    cpu_copy_end   = 0;
    dma_copy_start = 0;
    dma_copy_end   = 0;
    prev_ledr      = 32'hFFFF_FFFF;
    dma_irq_seen   = 0;
    num_insn       = 0;
    num_cycle      = 0;
    mispred_count  = 0;
    branch_count   = 0;
    dma_bus_rd_count = 0;
    dma_bus_wr_count = 0;
  end

  always @(posedge clk) begin
    if (rst_n) cycle_count <= cycle_count + 1;
  end

  // IPC tracking: count valid retired instructions and cycles
  always @(posedge clk) begin
    if (rst_n) begin
      num_cycle <= num_cycle + 1;
      if (insn_vld_o) num_insn <= num_insn + 1;
      if (mispred_o) mispred_count <= mispred_count + 1;
      if (ctrl_o) branch_count <= branch_count + 1;
    end
  end

  // DMA bus transaction monitor
  always @(posedge clk) begin
    if (rst_n) begin
      // Monitor DMA master port transactions through the DUT's internal xbar
      // Count TL-UL GET (read) and PUT (write) accepted on DMA master port
      if (dut.u_dma.o_dma_tl_a_valid && dut.u_dma.i_dma_tl_a_ready) begin
        if (dut.u_dma.o_dma_tl_a_opcode == 3'd4) // GET
          dma_bus_rd_count <= dma_bus_rd_count + 1;
        else // PUT
          dma_bus_wr_count <= dma_bus_wr_count + 1;
      end
    end
  end

  //===========================================================================
  // Phase Monitor — track LEDR changes
  //===========================================================================
  initial begin
    $display("");
    $display("################################################################");
    $display("#                                                              #");
    $display("#   SoC DMA Integration Test                                  #");
    $display("#   CPU memcpy vs DMA memcpy (100 words through TileLink)     #");
    $display("#                                                              #");
    $display("#   DUT: soc_top_2m6s (2-Master, 6-Slave TL-UL SoC)          #");
    $display("#   Firmware: dma_test.hex                                    #");
    $display("#                                                              #");
    $display("#   Phase 1: CPU initializes 100 words at DMEM 0x1000         #");
    $display("#   Phase 2: CPU memcpy lw/sw 0x1000 -> 0x2000                #");
    $display("#   Phase 3: DMA transfer     0x1000 -> 0x3000                #");
    $display("#   Phase 4: CPU verifies both destinations                   #");
    $display("#   Result:  LEDR = 0xAA (pass) or 0xFF (fail)                #");
    $display("#                                                              #");
    $display("#   Verification checks:                                      #");
    $display("#     - Cycle-accurate performance comparison                 #");
    $display("#     - Memory contents verification (direct probe)           #");
    $display("#     - DMA IRQ assertion                                     #");
    $display("#     - DMA bus transaction counts                            #");
    $display("#     - IPC and branch prediction analysis                    #");
    $display("#                                                              #");
    $display("################################################################");
    $display("");
  end

  always @(negedge clk) begin
    if (rst_n && ledr_internal !== prev_ledr) begin
      case (ledr_internal)
        32'h01: $display("[cycle %6d] Phase 1: Initializing source data (100 words at 0x1000)", cycle_count);
        32'h02: begin
          cpu_copy_start = cycle_count;
          $display("[cycle %6d] Phase 2: CPU memcpy START (0x1000 -> 0x2000)", cycle_count);
        end
        32'h03: begin
          cpu_copy_end = cycle_count;
          $display("[cycle %6d] Phase 2: CPU memcpy DONE  (%0d cycles)", cycle_count, cpu_copy_end - cpu_copy_start);
        end
        32'h04: begin
          dma_copy_start = cycle_count;
          $display("[cycle %6d] Phase 3: DMA memcpy START (0x1000 -> 0x3000)", cycle_count);
        end
        32'h05: begin
          dma_copy_end = cycle_count;
          $display("[cycle %6d] Phase 3: DMA memcpy DONE  (%0d cycles)", cycle_count, dma_copy_end - dma_copy_start);
        end
        32'h06: $display("[cycle %6d] Phase 4: Verification", cycle_count);
        32'hAA: begin
          $display("[cycle %6d] === RESULT: ALL PASS ===", cycle_count);
          $display("");
          print_comparison();
          verify_memory_contents();
          $finish;
        end
        32'hFF: begin
          $display("[cycle %6d] === RESULT: FAIL ===", cycle_count);
          $display("");
          print_comparison();
          verify_memory_contents();
          $finish;
        end
      endcase
      prev_ledr <= ledr_internal;
    end
  end

  //===========================================================================
  // DMA IRQ Monitor
  //===========================================================================
  always @(posedge clk) begin
    if (rst_n && irq_dma && !dma_irq_seen) begin
      dma_irq_seen <= 1;
      $display("[cycle %6d] >> DMA IRQ asserted", cycle_count);
    end
  end

  //===========================================================================
  // Print comparison: CPU copy vs DMA copy
  //===========================================================================
  task automatic print_comparison();
    int cpu_cycles, dma_cycles;
    cpu_cycles = cpu_copy_end - cpu_copy_start;
    dma_cycles = dma_copy_end - dma_copy_start;

    $display("========================================================");
    $display("  Performance Comparison (100-word transfer)");
    $display("========================================================");
    $display("");
    $display("  %-20s  %6s  %s", "Method", "Cycles", "Notes");
    $display("  %-20s  %6s  %s", "--------------------", "------", "-----");
    $display("  %-20s  %6d  %s", "CPU memcpy (lw/sw)", cpu_cycles, "100x (lw+sw+addi+addi+addi+bne)");
    $display("  %-20s  %6d  %s", "DMA transfer", dma_cycles, "5x sw config + poll + HW engine");
    $display("");
    if (cpu_cycles > 0 && dma_cycles > 0) begin
      if (dma_cycles < cpu_cycles)
        $display("  DMA is %.1fx FASTER than CPU copy", real'(cpu_cycles) / real'(dma_cycles));
      else if (dma_cycles > cpu_cycles)
        $display("  DMA is %.1fx SLOWER (config overhead dominates for small transfers)", real'(dma_cycles) / real'(cpu_cycles));
      else
        $display("  Both methods take equal cycles");
    end
    $display("");
    $display("  DMA advantage: CPU is FREE during transfer");
    $display("  (In real usage, CPU does other work while DMA runs)");
    $display("");

    // DMA bus transactions
    $display("========================================================");
    $display("  DMA Bus Transaction Analysis");
    $display("========================================================");
    $display("");
    $display("  DMA TL-UL GET (read)  requests: %0d", dma_bus_rd_count);
    $display("  DMA TL-UL PUT (write) requests: %0d", dma_bus_wr_count);
    $display("  Total DMA bus transactions:     %0d", dma_bus_rd_count + dma_bus_wr_count);
    $display("  Expected: 100 reads + 100 writes = 200 transactions");
    if (dma_bus_rd_count == 100 && dma_bus_wr_count == 100)
      $display("  Status: CORRECT - all 100 word transfers completed via bus");
    else
      $display("  Status: MISMATCH - check DMA data path");
    $display("");

    // IPC report
    $display("========================================================");
    $display("  CPU Performance Analysis");
    $display("========================================================");
    $display("");
    $display("  Total cycles:       %0.0f", num_cycle);
    $display("  Total instructions: %0.0f", num_insn);
    if (num_cycle > 0)
      $display("  IPC:                %0.3f", num_insn / num_cycle);
    $display("");
    $display("  Cycles/word (CPU):  %0.1f", real'(cpu_cycles) / 100.0);
    $display("  Cycles/word (DMA):  %0.1f", real'(dma_cycles) / 100.0);
    $display("");
    $display("  Branch mispredictions: %0d", mispred_count);
    $display("  Total branches:       %0d", branch_count);
    if (branch_count > 0)
      $display("  Misprediction rate:   %0.1f%%", 100.0 * real'(mispred_count) / real'(branch_count));
    $display("");
  endtask

  //===========================================================================
  // Memory contents verification (direct probe)
  //===========================================================================
  task automatic verify_memory_contents();
    logic [31:0] src_val, cpu_val, dma_val;
    int src_word, cpu_word, dma_word;
    int errors;
    int test_count, pass_count;

    test_count = 0;
    pass_count = 0;
    errors = 0;

    // Word addresses in memory array
    src_word = 32'h1000 / 4;  // 1024
    cpu_word = 32'h2000 / 4;  // 2048
    dma_word = 32'h3000 / 4;  // 3072

    $display("========================================================");
    $display("  Memory Verification (direct probe, 100 words)");
    $display("========================================================");
    $display("");
    $display("  %-4s  %-12s  %-12s  %-12s  %-8s  %s",
             "Word", "SRC @0x1000", "CPU @0x2000", "DMA @0x3000", "Expected", "Status");
    $display("  %-4s  %-12s  %-12s  %-12s  %-8s  %s",
             "----", "-----------", "-----------", "-----------", "--------", "------");

    for (int i = 0; i < 100; i++) begin
      src_val = dut.u_mem_adapter.u_memory.mem[src_word + i];
      cpu_val = dut.u_mem_adapter.u_memory.mem[cpu_word + i];
      dma_val = dut.u_mem_adapter.u_memory.mem[dma_word + i];

      test_count++;
      if (src_val == (32'h100 + i) && cpu_val == src_val && dma_val == src_val) begin
        pass_count++;
        // Only print first 5 and last 5 to keep output readable
        if (i < 5 || i >= 95)
          $display("  [%2d]  0x%08X    0x%08X    0x%08X    0x%08X  PASS",
                   i, src_val, cpu_val, dma_val, 32'h100 + i);
        else if (i == 5)
          $display("  ...   (words 5-94 checked, printing first 5 & last 5)");
      end else begin
        errors++;
        $display("  [%2d]  0x%08X    0x%08X    0x%08X    0x%08X  FAIL <<<",
                 i, src_val, cpu_val, dma_val, 32'h100 + i);
      end
    end

    $display("");
    $display("  Result: %0d / %0d PASS", pass_count, test_count);
    if (errors == 0)
      $display("  *** ALL DATA VERIFIED CORRECT ***");
    else
      $display("  *** %0d MISMATCHES DETECTED ***", errors);
    $display("");
    $display("  DMA IRQ observed: %s", dma_irq_seen ? "YES" : "NO");
    $display("");
    $display("################################################################");
    $display("#                    FINAL VERIFICATION SUMMARY                #");
    $display("################################################################");
    $display("#                                                              #");
    $display("#   Memory Integrity:   %0d / %0d words PASS               #", pass_count, test_count);
    if (errors == 0)
    $display("#   Data Result:        *** ALL DATA VERIFIED CORRECT ***     #");
    else
    $display("#   Data Result:        *** %0d MISMATCHES DETECTED ***        #", errors);
    $display("#   DMA IRQ:            %s                                   #", dma_irq_seen ? "ASSERTED (correct)" : "NOT SEEN (check)");
    $display("#   DMA bus txns:       %0d rd + %0d wr = %0d total           #", dma_bus_rd_count, dma_bus_wr_count, dma_bus_rd_count+dma_bus_wr_count);
    $display("#                                                              #");
    $display("################################################################");
    $display("");
  endtask

endmodule
