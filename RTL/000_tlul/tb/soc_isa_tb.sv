`timescale 1ns/1ps

// SOC Testbench - ISA Test Mode
// Runs the same ISA test as tbench but through TileLink bus

module soc_isa_tb;
  import tlul_pkg::*;

  parameter CLK_PERIOD = 2;      // Match tbench clock period
  parameter RESET_PERIOD = 51;
  parameter TIMEOUT = 5_000_000;   // cycles - increased for all tests
  
  logic clk;
  logic rst_n;
  
  // Clock generation
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;
  
  // Reset generation
  initial begin
    rst_n = 1'b0;
    #RESET_PERIOD;
    rst_n = 1'b1;
  end
  
  // Timeout
  initial begin
    #(TIMEOUT * CLK_PERIOD);
    $display("");
    $display("=== TIMEOUT after %0d cycles ===", TIMEOUT);
    $finish;
  end

  // Peripheral signals
  logic [9:0]  sw_i;
  logic [9:0]  ledr_o;
  logic [31:0] ledg_o;
  logic [6:0]  hex0_o, hex1_o, hex2_o, hex3_o;
  logic [6:0]  hex4_o, hex5_o, hex6_o, hex7_o;
  
  // UART
  logic uart_rx_i;
  logic uart_tx_o;
  
  // Debug outputs
  logic [31:0] pc_debug_o;
  logic [31:0] pc_wb_o;
  logic [31:0] pc_mem_o;
  logic        insn_vld_o;
  logic        ctrl_o;
  logic        mispred_o;
  
  // Initialize inputs
  // sw_i is 10-bit but ISA test expects 32-bit value 0x12345678
  initial begin
    sw_i = 10'h278;  // Lower 10 bits of 0x12345678
    uart_rx_i = 1'b1;  // UART idle
  end
  
  // DUT: SOC Top with DMA
    logic        irq_dma, irq_chacha, irq_poly;
  soc_top_2m6s #(
    .MEM_DEPTH(65536),
    .MEM_FILE("../02_test/isa_4b.hex")  // Path relative to 03_sim directory
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    
    // Peripheral IOs
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
    
    // UART
    .uart_rx_i  (uart_rx_i),
    .uart_tx_o  (uart_tx_o),

    // Interrupts
    .irq_dma_o  (irq_dma),
    .irq_chacha_o(irq_chacha),
    .irq_poly_o(irq_poly),
    
    // Debug outputs
    .pc_debug_o (pc_debug_o),
    .pc_wb_o    (pc_wb_o),
    .pc_mem_o   (pc_mem_o),
    .insn_vld_o (insn_vld_o),
    .ctrl_o     (ctrl_o),
    .mispred_o  (mispred_o)
  );
  
  // Statistics counters
  real num_cycle;
  real num_insn;
  real num_ctrl;
  
  // Display test name
  initial begin
    $display("");
    $display("SOC PIPELINE (TileLink) - ISA tests");
    $display("");
  end
  
  // Counter logic
  always @(negedge clk) begin
    if (!rst_n) begin
      num_cycle   <= 0;
      num_ctrl    <= 0;
      num_insn    <= 0;
    end else begin
      num_cycle   <= num_cycle + 1;
      num_ctrl    <= ctrl_o     ? num_ctrl + 1 : num_ctrl;
      num_insn    <= insn_vld_o ? num_insn + 1 : num_insn;
    end
  end
  
  // Debug - trace instruction in WB stage
  // Access internal signals via hierarchical reference
  wire [31:0] instr_WB = dut.u_cpu.i_instr_WB;
  wire [31:0] instr_EX = dut.u_cpu.i_instr_EX;
  wire [31:0] instr_MEM = dut.u_cpu.i_instr_MEM;
  wire flush_sig = dut.u_cpu.flush;
  
  int instr_cnt;
  // Debug internal MEM stage signals
  wire lsu_stall_sig = dut.u_cpu.lsu_stall;
  wire pipeline_stall_sig = dut.u_cpu.pipeline_stall;
  wire [31:0] pc_IF_sig = dut.u_cpu.o_pc_IF;
  wire [31:0] pc_ID_sig = dut.u_cpu.i_pc_ID;
  wire [31:0] pc_EX_sig = dut.u_cpu.i_pc_EX;
  wire [31:0] pc_MEM_sig = dut.u_cpu.i_pc_MEM;
  // Additional debug signals
  wire [31:0] alu_data_MEM = dut.u_cpu.i_alu_data_MEM;
  wire [3:0] byte_num_MEM = dut.u_cpu.i_byte_num_MEM;
  wire lsu_wren_MEM = dut.u_cpu.i_lsu_wren_MEM;
  
  always @(negedge clk) begin
    if (!rst_n) begin
      instr_cnt <= 0;
    end else begin
      if (insn_vld_o) begin
        instr_cnt <= instr_cnt + 1;
      end
    end
  end
  
  // ISA test output - match scoreboard.sv logic
  // Access internal 32-bit LEDR from peripheral adapter
  wire [31:0] ledr_internal = dut.u_peri_adapter.o_io_ledr;
  
  int char_count;
  logic [7:0] last_char;
  initial char_count = 0;
  
  // Detect when test loop happens
  int sltu_pass_count;
  initial sltu_pass_count = 0;
  
  always @(negedge clk) begin
    if (rst_n && insn_vld_o && (pc_debug_o == 32'h18)) begin
      $write("%s", ledr_internal[7:0]);  // Use internal 32-bit LEDR for character output
      $fflush();  // Force flush output
      char_count <= char_count + 1;
      last_char <= ledr_internal[7:0];
    end
  end

  // Debug: Track when pipeline gets stuck
  int stuck_counter;
  logic [31:0] last_pc_debug;
  initial stuck_counter = 0;
  
  always @(negedge clk) begin
    if (!rst_n) begin
      stuck_counter <= 0;
      last_pc_debug <= 32'h0;
    end else begin
      if (pc_debug_o == last_pc_debug && !insn_vld_o) begin
        stuck_counter <= stuck_counter + 1;
        if (stuck_counter == 1000) begin
          $display("\n=== PIPELINE STUCK DEBUG ===");
          $display("PC_debug: %h, lsu_stall: %b, pipeline_stall: %b", 
                   pc_debug_o, lsu_stall_sig, pipeline_stall_sig);
          $display("PC_IF: %h, PC_ID: %h, PC_EX: %h, PC_MEM: %h",
                   pc_IF_sig, pc_ID_sig, pc_EX_sig, pc_MEM_sig);
          $display("instr_WB: %h, instr_EX: %h, instr_MEM: %h", instr_WB, instr_EX, instr_MEM);
          $display("alu_data_MEM (addr): %h, byte_num_MEM: %b, lsu_wren_MEM: %b",
                   alu_data_MEM, byte_num_MEM, lsu_wren_MEM);
          $display("============================\n");
        end
      end else begin
        stuck_counter <= 0;
        last_pc_debug <= pc_debug_o;
      end
    end
  end
  
  // End of ISA test detection
  always @(negedge clk) begin
    if (rst_n && (pc_debug_o == 32'h1c)) begin
      $display("");
      $display("=== END of ISA test ===");
      $display("");
      $display("Statistics:");
      $display("  Cycles:       %0.0f", num_cycle);
      $display("  Instructions: %0.0f", num_insn);
      $display("  Control Xfer: %0.0f", num_ctrl);
      $display("  IPC:          %0.3f", num_insn / num_cycle);
      $finish;
    end
  end

endmodule
