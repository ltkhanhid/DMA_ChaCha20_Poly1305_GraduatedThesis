`timescale 1ns/1ps

// ============================================================
// soc_demo_tb.sv — Full SoC Demo Testbench
//
// UART → Memory → DMA → ChaCha20 → DMA → Memory → UART
//
// Test flow:
//   1. Testbench sends 64 plaintext bytes via UART RX (115200 baud)
//   2. Firmware receives, stores in DMEM buffer
//   3. Firmware configures ChaCha20 with RFC 8439 key/nonce/counter
//   4. DMA copies plaintext buffer → ChaCha20 PLAINTEXT registers
//   5. ChaCha20 encrypts (20 rounds)
//   6. DMA copies ChaCha20 CIPHERTEXT → output buffer
//   7. Firmware sends 64 ciphertext bytes via UART TX
//   8. Testbench captures UART TX, compares with expected ciphertext
//
// Uses RFC 8439 §2.4.2 "Sunscreen" test vector (first 64-byte block)
// ============================================================

module soc_demo_tb;
  import tlul_pkg::*;

  // ─── Parameters ───────────────────────────────────────────
  parameter CLK_PERIOD = 20;              // 50 MHz
  parameter MEM_DEPTH  = 65536;           // 64 KB memory
  parameter BIT_PERIOD = 50_000_000 / 115_200;  // = 434 cycles/bit

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
  // RFC 8439 §2.4.2 — "Ladies and Gentlemen of the class of '99: If I could offer you o"
  logic [7:0] PTEXT  [0:63];
  // Expected ciphertext (first 64 bytes of RFC 8439 §2.4.2 Sunscreen test)
  logic [7:0] EXP_CT [0:63];
  // Captured UART TX output
  logic [7:0] received [0:63];

  int  rx_count;
  logic capture_done;

  // ─── Clock ────────────────────────────────────────────────
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ─── DUT Instantiation ───────────────────────────────────
  soc_top_2m6s #(
    .MEM_DEPTH (MEM_DEPTH),
    .MEM_FILE  ("demo_chacha.hex")
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

  // Send one byte to DUT via UART RX pin (bit-bang at 115200)
  task uart_send_byte(input [7:0] data);
    integer i;
    uart_rx_i = 1'b0;                          // Start bit
    repeat(BIT_PERIOD) @(posedge clk);
    for (i = 0; i < 8; i++) begin
      uart_rx_i = data[i];                     // Data bits (LSB first)
      repeat(BIT_PERIOD) @(posedge clk);
    end
    uart_rx_i = 1'b1;                          // Stop bit
    repeat(BIT_PERIOD) @(posedge clk);
    repeat(BIT_PERIOD) @(posedge clk);         // Inter-byte gap
  endtask

  // Receive one byte from DUT via UART TX pin
  task automatic uart_recv_byte(output logic [7:0] data);
    integer i;
    @(negedge uart_tx_o);                       // Detect start bit
    repeat(BIT_PERIOD / 2) @(posedge clk);      // Middle of start bit
    for (i = 0; i < 8; i++) begin
      repeat(BIT_PERIOD) @(posedge clk);        // Middle of data bit[i]
      data[i] = uart_tx_o;
    end
    repeat(BIT_PERIOD) @(posedge clk);          // Skip to stop bit area
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
      $display("[%0t] Phase Update:", $time);
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

    while (rx_count < 64) begin
      uart_recv_byte(byte_data);
      received[rx_count] = byte_data;

      // Print first 4 and last 4 bytes, plus every 16th
      if (rx_count < 4 || rx_count >= 60 || (rx_count % 16 == 0))
        $display("  [%0t] Captured TX byte[%2d]: 0x%02h",
                 $time, rx_count, byte_data);
      else if (rx_count == 4)
        $display("  ... (capturing bytes 4-59) ...");

      rx_count = rx_count + 1;
    end

    capture_done = 1;
    $display("[%0t] All 64 ciphertext bytes captured from UART TX.", $time);
  end

  // ═════════════════════════════════════════════════════════
  //  MAIN TEST SEQUENCE
  // ═════════════════════════════════════════════════════════
  initial begin
    integer i;
    int pass_count, fail_count;
    int t_uart_rx_start, t_uart_rx_end;
    int t_process_start, t_process_end;

    // ── Initialize test data ────────────────────────────────
    // Plaintext: "Ladies and Gentlemen of the class of '99: If I could offer you o"
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

    // Expected ciphertext (RFC 8439 §2.4.2, first 64 bytes)
    EXP_CT[ 0] = 8'h6e; EXP_CT[ 1] = 8'h2e; EXP_CT[ 2] = 8'h35; EXP_CT[ 3] = 8'h9a;
    EXP_CT[ 4] = 8'h25; EXP_CT[ 5] = 8'h68; EXP_CT[ 6] = 8'hf9; EXP_CT[ 7] = 8'h80;
    EXP_CT[ 8] = 8'h41; EXP_CT[ 9] = 8'hba; EXP_CT[10] = 8'h07; EXP_CT[11] = 8'h28;
    EXP_CT[12] = 8'hdd; EXP_CT[13] = 8'h0d; EXP_CT[14] = 8'h69; EXP_CT[15] = 8'h81;
    EXP_CT[16] = 8'he9; EXP_CT[17] = 8'h7e; EXP_CT[18] = 8'h7a; EXP_CT[19] = 8'hec;
    EXP_CT[20] = 8'h1d; EXP_CT[21] = 8'h43; EXP_CT[22] = 8'h60; EXP_CT[23] = 8'hc2;
    EXP_CT[24] = 8'h0a; EXP_CT[25] = 8'h27; EXP_CT[26] = 8'haf; EXP_CT[27] = 8'hcc;
    EXP_CT[28] = 8'hfd; EXP_CT[29] = 8'h9f; EXP_CT[30] = 8'hae; EXP_CT[31] = 8'h0b;
    EXP_CT[32] = 8'hf9; EXP_CT[33] = 8'h1b; EXP_CT[34] = 8'h65; EXP_CT[35] = 8'hc5;
    EXP_CT[36] = 8'h52; EXP_CT[37] = 8'h47; EXP_CT[38] = 8'h33; EXP_CT[39] = 8'hab;
    EXP_CT[40] = 8'h8f; EXP_CT[41] = 8'h59; EXP_CT[42] = 8'h3d; EXP_CT[43] = 8'hab;
    EXP_CT[44] = 8'hcd; EXP_CT[45] = 8'h62; EXP_CT[46] = 8'hb3; EXP_CT[47] = 8'h57;
    EXP_CT[48] = 8'h16; EXP_CT[49] = 8'h39; EXP_CT[50] = 8'hd6; EXP_CT[51] = 8'h24;
    EXP_CT[52] = 8'he6; EXP_CT[53] = 8'h51; EXP_CT[54] = 8'h52; EXP_CT[55] = 8'hab;
    EXP_CT[56] = 8'h8f; EXP_CT[57] = 8'h53; EXP_CT[58] = 8'h0c; EXP_CT[59] = 8'h35;
    EXP_CT[60] = 8'h9f; EXP_CT[61] = 8'h08; EXP_CT[62] = 8'h61; EXP_CT[63] = 8'hd8;

    // ── Reset & Init ────────────────────────────────────────
    $display("");
    $display("================================================================");
    $display(" SOC FULL DEMO: UART -> DMA -> ChaCha20 -> DMA -> UART");
    $display(" Test Vector: RFC 8439 Sec 2.4.2 Sunscreen (64-byte block 1)");
    $display(" Key  : 00:01:02:...1e:1f  Nonce: ...00:4a:00:00:00:00");
    $display(" Counter = 1  |  Baud = 115200  |  Clock = 50 MHz");
    $display("================================================================");
    $display("");

    rst_n    = 0;
    sw_i     = 0;
    uart_rx_i = 1;    // UART idle = high
    wait_cycles(20);
    rst_n = 1;
    $display("[%0t] Reset released.", $time);

    // Wait for firmware to init and enter UART RX loop
    wait_cycles(2000);

    // ════════════════════════════════════════════════════════
    //  PHASE 1: Send 64 plaintext bytes via UART
    // ════════════════════════════════════════════════════════
    $display("");
    $display("--- Phase 1: Sending 64 plaintext bytes via UART (115200) ---");
    display_hex();

    t_uart_rx_start = $time;

    for (i = 0; i < 64; i++) begin
      if (i < 4 || i >= 60)
        $display("  [%0t] UART -> SoC byte[%2d]: 0x%02h ('%s')",
                 $time, i, PTEXT[i], ascii_to_char(PTEXT[i]));
      else if (i == 4)
        $display("  ... (sending bytes 4-59) ...");
      uart_send_byte(PTEXT[i]);
    end

    t_uart_rx_end = $time;
    $display("[%0t] All 64 bytes sent. UART RX duration: %0d ns (%0d cycles)",
             $time, t_uart_rx_end - t_uart_rx_start,
             (t_uart_rx_end - t_uart_rx_start) / CLK_PERIOD);
    display_hex();

    // ════════════════════════════════════════════════════════
    //  Wait for firmware: Key setup + DMA + ChaCha + DMA + UART TX
    // ════════════════════════════════════════════════════════
    $display("");
    $display("--- Waiting for firmware processing + UART TX output... ---");

    t_process_start = $time;

    // Wait for capture to complete, with 20ms timeout
    fork
      wait(capture_done === 1'b1);
      begin
        wait_cycles(1_000_000);   // 20ms timeout
        if (!capture_done) begin
          $display("");
          $display("*** TIMEOUT: Only captured %0d of 64 bytes ***", rx_count);
          display_hex();
          $display("  PC = 0x%08h", pc_debug);
          $stop;
        end
      end
    join_any
    disable fork;

    t_process_end = $time;
    wait_cycles(5000);       // Brief settle time

    $display("[%0t] Processing + UART TX duration: %0d ns (%0d cycles)",
             $time, t_process_end - t_process_start,
             (t_process_end - t_process_start) / CLK_PERIOD);
    $display("");
    display_hex();

    // ════════════════════════════════════════════════════════
    //  VERIFICATION
    // ════════════════════════════════════════════════════════
    $display("");
    $display("================================================================");
    $display("  VERIFICATION: Received ciphertext vs RFC 8439 expected");
    $display("================================================================");

    pass_count = 0;
    fail_count = 0;

    for (i = 0; i < 64; i++) begin
      if (received[i] === EXP_CT[i]) begin
        pass_count++;
        // Print first 4, last 4
        if (i < 4 || i >= 60)
          $display("  Byte[%2d]: Exp=0x%02h Got=0x%02h  PASS",
                   i, EXP_CT[i], received[i]);
      end else begin
        fail_count++;
        // Always print failures
        $display("  Byte[%2d]: Exp=0x%02h Got=0x%02h  **FAIL**",
                 i, EXP_CT[i], received[i]);
      end
      if (i == 3 && fail_count == 0)
        $display("  ... (bytes 4-59 checking) ...");
    end

    // ── Plaintext echo (for reference) ──────────────────────
    $display("");
    $display("  Plaintext  (first 16): %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
      PTEXT[ 0], PTEXT[ 1], PTEXT[ 2], PTEXT[ 3], PTEXT[ 4], PTEXT[ 5], PTEXT[ 6], PTEXT[ 7],
      PTEXT[ 8], PTEXT[ 9], PTEXT[10], PTEXT[11], PTEXT[12], PTEXT[13], PTEXT[14], PTEXT[15]);
    $display("  Ciphertext (first 16): %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
      received[ 0], received[ 1], received[ 2], received[ 3],
      received[ 4], received[ 5], received[ 6], received[ 7],
      received[ 8], received[ 9], received[10], received[11],
      received[12], received[13], received[14], received[15]);
    $display("  Expected   (first 16): %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
      EXP_CT[ 0], EXP_CT[ 1], EXP_CT[ 2], EXP_CT[ 3],
      EXP_CT[ 4], EXP_CT[ 5], EXP_CT[ 6], EXP_CT[ 7],
      EXP_CT[ 8], EXP_CT[ 9], EXP_CT[10], EXP_CT[11],
      EXP_CT[12], EXP_CT[13], EXP_CT[14], EXP_CT[15]);

    // ── Final Result ────────────────────────────────────────
    $display("");
    $display("================================================================");
    if (fail_count == 0) begin
      $display("  RESULT: %0d/64 PASS  *** ALL BYTES CORRECT ***", pass_count);
      $display("");
      $display("  Full data pipeline verified:");
      $display("    Host UART TX -> SoC UART RX -> DMEM buffer");
      $display("    -> DMA CH0 -> ChaCha20 PLAINTEXT registers");
      $display("    -> ChaCha20 encrypt (RFC 8439)");
      $display("    -> DMA CH0 -> DMEM buffer");
      $display("    -> SoC UART TX -> Host UART RX");
      $display("");
      $display("  Peripherals exercised: UART, DMA, ChaCha20, 7-Segment LED");
    end else begin
      $display("  RESULT: %0d PASS, %0d FAIL out of 64 bytes", pass_count, fail_count);
    end
    $display("================================================================");

    // ── Timing Summary ──────────────────────────────────────
    $display("");
    $display("  Timing Summary:");
    $display("    UART RX (64 bytes):       %0d cycles",
             (t_uart_rx_end - t_uart_rx_start) / CLK_PERIOD);
    $display("    Processing + UART TX:     %0d cycles",
             (t_process_end - t_process_start) / CLK_PERIOD);
    $display("    Total simulation time:    %0d ns", $time);
    $display("");

    $stop;
  end

endmodule
