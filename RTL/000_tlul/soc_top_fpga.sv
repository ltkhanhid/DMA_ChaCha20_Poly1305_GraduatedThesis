// ============================================================================
// File:  soc_top_fpga.sv
// Description: FPGA top-level wrapper for soc_top_2m6s
//              - Exposes only board-level I/O (no debug/IRQ pins)
//              - Prevents unneeded outputs from consuming FPGA pins
//              - Parameterized MEM_FILE for demo selection
// Target:  Cyclone V  5CSXFC6D6F31C6
// ============================================================================
module soc_top_fpga
  import tlul_pkg::*;
#(
  parameter int unsigned MEM_DEPTH = 65536,
  parameter MEM_FILE = "../02_test/demo_aead_dma_v2.hex"  // V2: interactive 7-seg display
)
(
  // Clock & Reset
  input  logic        clk,
  input  logic        rst_n,

  // Switches & LEDs
  input  logic [9:0]  sw_i,
  output logic [9:0]  ledr_o,

  // 7-Segment Displays (active-low, accent HEX0..HEX5)
  output logic [6:0]  hex0_o,
  output logic [6:0]  hex1_o,
  output logic [6:0]  hex2_o,
  output logic [6:0]  hex3_o,
  output logic [6:0]  hex4_o,
  output logic [6:0]  hex5_o,

  // UART
  input  logic        uart_rx_i,
  output logic        uart_tx_o
);

  // Internal wires for unneeded outputs
  logic [31:0] ledg_nc;
  logic [6:0]  hex6_nc, hex7_nc;

  soc_top_2m6s #(
    .MEM_DEPTH     (MEM_DEPTH),
    .MEM_FILE      (MEM_FILE),
    .SIM_SW_VALUE  (32'd0)          // Unused — real sw_i is connected inside
  ) u_soc (
    .clk           (clk),
    .rst_n         (rst_n),

    // GPIO
    .sw_i          (sw_i),
    .ledr_o        (ledr_o),
    .ledg_o        (ledg_nc),
    .hex0_o        (hex0_o),
    .hex1_o        (hex1_o),
    .hex2_o        (hex2_o),
    .hex3_o        (hex3_o),
    .hex4_o        (hex4_o),
    .hex5_o        (hex5_o),
    .hex6_o        (hex6_nc),
    .hex7_o        (hex7_nc),

    // UART
    .uart_rx_i     (uart_rx_i),
    .uart_tx_o     (uart_tx_o),

    // IRQ — not routed to pins (SW polling only)
    .irq_dma_o     (),
    .irq_chacha_o  (),
    .irq_poly_o    (),

    // Debug — not routed to FPGA pins (saves ~100 I/O + eliminates timing violations)
    .pc_debug_o    (),
    .pc_wb_o       (),
    .pc_mem_o      (),
    .insn_vld_o    (),
    .ctrl_o        (),
    .mispred_o     ()
  );

endmodule
