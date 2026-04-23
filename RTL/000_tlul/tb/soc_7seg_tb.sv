`timescale 1ns/1ps

module soc_7seg_tb;
  import tlul_pkg::*;

  // Parameters
  parameter CLK_PERIOD = 20; // 50MHz
  parameter MEM_DEPTH  = 65536;
  parameter HEX_FILE   = "uart.hex"; 
  parameter TARGET_BAUD = 115200;
  
  // Tính toán số chu kỳ clock chuẩn cho 1 bit
  // 50,000,000 / 115,200 = 434.02 cycles
  parameter REAL_BIT_CYCLES = 50000000 / TARGET_BAUD;

  // DUT Signals
  logic clk, rst_n;
  logic [9:0] sw_i;
  logic [9:0] ledr_o;
  logic [31:0] ledg_o;
  logic [6:0] hex0_o, hex1_o, hex2_o, hex3_o, hex4_o, hex5_o, hex6_o, hex7_o;
  logic uart_rx_i, uart_tx_o;
  logic [31:0] pc_debug_o, pc_wb_o, pc_mem_o;
  logic insn_vld_o, ctrl_o, mispred_o;
  
  logic irq_dma, irq_chacha, irq_poly;

  // Clock Generation
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // DUT Instantiation - Using soc_top_2m6s with DMA (UART fixed 115200 baud)
  soc_top_2m6s #(
    .MEM_DEPTH(MEM_DEPTH),
    .MEM_FILE("uart_7seg_new.hex")
  ) u_soc (
    .clk(clk), .rst_n(rst_n),
    .sw_i(sw_i), .ledr_o(ledr_o), .ledg_o(ledg_o),
    .hex0_o(hex0_o), .hex1_o(hex1_o), .hex2_o(hex2_o), .hex3_o(hex3_o),
    .hex4_o(hex4_o), .hex5_o(hex5_o), .hex6_o(hex6_o), .hex7_o(hex7_o),
    .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o),
    // Interrupts
    .irq_dma_o(irq_dma),
    .irq_chacha_o(irq_chacha),
    .irq_poly_o(irq_poly),
    // Debug
    .pc_debug_o(pc_debug_o), .pc_wb_o(pc_wb_o), .pc_mem_o(pc_mem_o),
    .insn_vld_o(insn_vld_o), .ctrl_o(ctrl_o), .mispred_o(mispred_o)
  );

  // Helper Functions
  function string ascii_to_char(input [7:0] ascii);
    if (ascii >= 32 && ascii <= 126) ascii_to_char = $sformatf("%c", ascii);
    else ascii_to_char = ".";
  endfunction

  function string hex_to_char(input [6:0] seg);
      case(seg)
          // Numbers 0-9
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
          // Letters
          7'b0001000: hex_to_char = "A";
          7'b0000011: hex_to_char = "b";
          7'b1000110: hex_to_char = "C";
          7'b0100001: hex_to_char = "d";
          7'b0000110: hex_to_char = "E";
          7'b0001110: hex_to_char = "F";
          7'b1000010: hex_to_char = "G";
          7'b0001001: hex_to_char = "H";
          7'b1100001: hex_to_char = "J";
          7'b1000111: hex_to_char = "L";
          7'b0101011: hex_to_char = "n";
          7'b0001100: hex_to_char = "P";
          7'b0011000: hex_to_char = "q";
          7'b0101111: hex_to_char = "r";
          7'b0000111: hex_to_char = "t";
          7'b1000001: hex_to_char = "U";
          7'b0010001: hex_to_char = "Y";
          7'b0100111: hex_to_char = "c";
          7'b0001011: hex_to_char = "h";
          7'b1111011: hex_to_char = "i";
          7'b0100011: hex_to_char = "o";
          7'b1100011: hex_to_char = "u";
          // Special
          7'b1111111: hex_to_char = " ";
          7'b0111111: hex_to_char = "-";
          default: hex_to_char = "?";
      endcase
  endfunction


  task wait_cycles(int n);
    repeat(n) @(posedge clk);
  endtask

  task display_hex_status();
    $display("\tDisplay: [ %s | %s | %s | %s | %s | %s | %s | %s ]", 
        hex_to_char(hex7_o), hex_to_char(hex6_o), hex_to_char(hex5_o), hex_to_char(hex4_o),
        hex_to_char(hex3_o), hex_to_char(hex2_o), hex_to_char(hex1_o), hex_to_char(hex0_o));
  endtask

  // Task gửi UART với tốc độ tùy chỉnh (để test baud rate)
  task uart_send_custom_baud(input logic [7:0] data, input int bit_period_cycles);
    integer i;
    begin
      $display("  [%0t] TX -> SOC (Baud Cycles: %0d): 0x%02h ('%s')", 
               $time, bit_period_cycles, data, ascii_to_char(data));
      
      uart_rx_i = 1'b0; // Start bit
      repeat(bit_period_cycles) @(posedge clk);
      
      for (i = 0; i < 8; i++) begin
        uart_rx_i = data[i];
        repeat(bit_period_cycles) @(posedge clk);
      end
      
      uart_rx_i = 1'b1; // Stop bit
      repeat(bit_period_cycles) @(posedge clk);
      
      // Gap giữa các ký tự
      repeat(bit_period_cycles) @(posedge clk); 
    end
  endtask

  // ========================================================================
  // MAIN TEST SEQUENCE
  // ========================================================================
  initial begin
    $display("=== SOC UART 7-SEG TEST (WITH BAUD CHECK) ===");
    rst_n = 0;
    sw_i = 0;
    uart_rx_i = 1;

    wait_cycles(20);
    rst_n = 1;
    $display("[%0t] Reset Released", $time);
    
    // Wait for firmware to boot and enter polling loop
    wait_cycles(500000);

    // -----------------------------------------------------------------
    // TEST 1: Normal Operation (115200 Baud)
    // -----------------------------------------------------------------
    $display("\n--- TEST 1: Normal Operation (115200 Baud) ---");
    uart_send_custom_baud(8'h31, REAL_BIT_CYCLES);  // '1'
    wait_cycles(500000);
    display_hex_status();

    // -----------------------------------------------------------------
    // TEST 2: Wrong Baud Rate (9600 Baud) - Should Fail
    // -----------------------------------------------------------------
    $display("\n--- TEST 2: Wrong Baud Rate (9600 Baud) - Should Fail ---");
    uart_send_custom_baud(8'h32, 50_000_000 / 9_600);  // '2' at 9600 baud
    wait_cycles(500000);
    display_hex_status();

    // -----------------------------------------------------------------
    // TEST 3: Stress Test - Slightly Fast Baud (~117.6 kHz)
    // -----------------------------------------------------------------
    $display("\n--- TEST 3: Stress Test  - Should Pass ---");
    uart_send_custom_baud(8'h33, 425);  // '3' at 425 cycles/bit
    wait_cycles(500000);
    display_hex_status();

    // -----------------------------------------------------------------
    // TEST 4: Stress Test - Slightly Slow Baud (~112.9 kHz)
    // -----------------------------------------------------------------
    $display("\n--- TEST 4: Stress Test- Should Pass ---");
    uart_send_custom_baud(8'h41, 443);  // 'A' at 443 cycles/bit
    wait_cycles(500000);
    display_hex_status();

    $display("\n=== Test Complete ===");
    $stop;
  end

endmodule