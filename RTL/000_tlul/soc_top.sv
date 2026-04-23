module soc_top
  import tlul_pkg::*;
#(
  parameter int unsigned MEM_DEPTH = 32678, // Memory depth in bytes
  parameter int BAUD_RATE = 3'd4
)
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [9:0] sw_i,
  output logic [9:0] ledr_o,
  output logic [31:0] ledg_o,
  output logic [6:0]  hex0_o,
  output logic [6:0]  hex1_o,
  output logic [6:0]  hex2_o,
  output logic [6:0]  hex3_o,
  output logic [6:0]  hex4_o,
  output logic [6:0]  hex5_o,
  output logic [6:0]  hex6_o,
  output logic [6:0]  hex7_o,

  input  logic        uart_rx_i,
  output logic        uart_tx_o,

  // Debug outputs
  output logic [31:0] pc_debug_o,
  output logic [31:0] pc_wb_o,
  output logic [31:0] pc_mem_o,
  output logic        insn_vld_o,
  output logic        ctrl_o,
  output logic        mispred_o
);
	
 logic rst_n_sync_1, rst_n_sync;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_n_sync_1 <= 1'b0;
      rst_n_sync   <= 1'b0;
    end else begin
      rst_n_sync_1 <= 1'b1;
      rst_n_sync   <= rst_n_sync_1;
    end
  end

  // TileLink Bus Signals
  logic cpu_tl_a_valid;
  logic [2:0] cpu_tl_a_opcode;
  logic [2:0] cpu_tl_a_param;
  tl_size_t cpu_tl_a_size;
  tl_source_t cpu_tl_a_source;
  tl_addr_t cpu_tl_a_address;
  tl_mask_t cpu_tl_a_mask;
  tl_data_t cpu_tl_a_data;
  logic cpu_tl_a_corrupt;
  logic cpu_tl_a_ready;

  logic cpu_tl_d_valid;
  logic [2:0] cpu_tl_d_opcode;
  logic [2:0] cpu_tl_d_param;
  tl_size_t cpu_tl_d_size;
  tl_source_t cpu_tl_d_source;
  tl_sink_t cpu_tl_d_sink;
  tl_data_t cpu_tl_d_data;
  logic cpu_tl_d_denied;
  logic cpu_tl_d_corrupt;
  logic cpu_tl_d_ready;

  logic mem_tl_a_valid;
  logic [2:0] mem_tl_a_opcode;
  logic [2:0] mem_tl_a_param;
  tl_size_t mem_tl_a_size;
  tl_source_t mem_tl_a_source;
  tl_addr_t mem_tl_a_address;
  tl_mask_t mem_tl_a_mask;
  tl_data_t mem_tl_a_data;
  logic mem_tl_a_corrupt;
  logic mem_tl_a_ready;

  logic mem_tl_d_valid;
  logic [2:0] mem_tl_d_opcode;
  logic [2:0] mem_tl_d_param;
  tl_size_t mem_tl_d_size;
  tl_source_t mem_tl_d_source;
  tl_sink_t mem_tl_d_sink;
  tl_data_t mem_tl_d_data;
  logic mem_tl_d_denied;
  logic mem_tl_d_corrupt;
  logic mem_tl_d_ready;

  logic peri_tl_a_valid;
  logic [2:0] peri_tl_a_opcode;
  logic [2:0] peri_tl_a_param;
  tl_size_t peri_tl_a_size;
  tl_source_t peri_tl_a_source;
  tl_addr_t peri_tl_a_address;
  tl_mask_t peri_tl_a_mask;
  tl_data_t peri_tl_a_data;
  logic peri_tl_a_corrupt;
  logic peri_tl_a_ready;

  logic peri_tl_d_valid;
  logic [2:0] peri_tl_d_opcode;
  logic [2:0] peri_tl_d_param;
  tl_size_t peri_tl_d_size;
  tl_source_t peri_tl_d_source;
  tl_sink_t peri_tl_d_sink;
  tl_data_t peri_tl_d_data;
  logic peri_tl_d_denied;
  logic peri_tl_d_corrupt;
  logic peri_tl_d_ready;

  // UART TileLink signals
  logic uart_tl_a_valid;
  logic [2:0] uart_tl_a_opcode;
  logic [2:0] uart_tl_a_param;
  tl_size_t uart_tl_a_size;
  tl_source_t uart_tl_a_source;
  tl_addr_t uart_tl_a_address;
  tl_mask_t uart_tl_a_mask;
  tl_data_t uart_tl_a_data;
  logic uart_tl_a_corrupt;
  logic uart_tl_a_ready;

  logic uart_tl_d_valid;
  logic [2:0] uart_tl_d_opcode;
  logic [2:0] uart_tl_d_param;
  tl_size_t uart_tl_d_size;
  tl_source_t uart_tl_d_source;
  tl_sink_t uart_tl_d_sink;
  tl_data_t uart_tl_d_data;
  logic uart_tl_d_denied;
  logic uart_tl_d_corrupt;
  logic uart_tl_d_ready;

  
  pipelined_tl u_cpu (
    .i_clk(clk),
    .i_rst_n(rst_n_sync),

    .o_tl_a_valid(cpu_tl_a_valid),
    .o_tl_a_opcode(cpu_tl_a_opcode),
    .o_tl_a_param(cpu_tl_a_param),
    .o_tl_a_size(cpu_tl_a_size),
    .o_tl_a_source(cpu_tl_a_source),
    .o_tl_a_address(cpu_tl_a_address),
    .o_tl_a_mask(cpu_tl_a_mask),
    .o_tl_a_data(cpu_tl_a_data),
    .o_tl_a_corrupt(cpu_tl_a_corrupt),
    .i_tl_a_ready(cpu_tl_a_ready),

    .i_tl_d_valid(cpu_tl_d_valid),
    .i_tl_d_opcode(cpu_tl_d_opcode),
    .i_tl_d_param(cpu_tl_d_param),
    .i_tl_d_size(cpu_tl_d_size),
    .i_tl_d_source(cpu_tl_d_source),
    .i_tl_d_sink(cpu_tl_d_sink),
    .i_tl_d_data(cpu_tl_d_data),
    .i_tl_d_denied(cpu_tl_d_denied),
    .i_tl_d_corrupt(cpu_tl_d_corrupt),
    .o_tl_d_ready(cpu_tl_d_ready),

    .o_pc_debug(pc_debug_o),
    .o_pc_wb(pc_wb_o),
    .o_pc_mem(pc_mem_o),
    .o_insn_vld(insn_vld_o),
    .o_ctrl(ctrl_o),
    .o_mispred(mispred_o)
  );

  tlul_xbar_3s u_crossbar (
    .i_clk(clk),
    .i_rst_n(rst_n_sync),

    .i_tl_a_valid(cpu_tl_a_valid),
    .i_tl_a_opcode(cpu_tl_a_opcode),
    .i_tl_a_param(cpu_tl_a_param),
    .i_tl_a_size(cpu_tl_a_size),
    .i_tl_a_source(cpu_tl_a_source),
    .i_tl_a_address(cpu_tl_a_address),
    .i_tl_a_mask(cpu_tl_a_mask),
    .i_tl_a_data(cpu_tl_a_data),
    .i_tl_a_corrupt(cpu_tl_a_corrupt),
    .o_tl_a_ready(cpu_tl_a_ready),

    .o_tl_d_valid(cpu_tl_d_valid),
    .o_tl_d_opcode(cpu_tl_d_opcode),
    .o_tl_d_param(cpu_tl_d_param),
    .o_tl_d_size(cpu_tl_d_size),
    .o_tl_d_source(cpu_tl_d_source),
    .o_tl_d_sink(cpu_tl_d_sink),
    .o_tl_d_data(cpu_tl_d_data),
    .o_tl_d_denied(cpu_tl_d_denied),
    .o_tl_d_corrupt(cpu_tl_d_corrupt),
    .i_tl_d_ready(cpu_tl_d_ready),

    .o_mem_a_valid(mem_tl_a_valid),
    .o_mem_a_opcode(mem_tl_a_opcode),
    .o_mem_a_param(mem_tl_a_param),
    .o_mem_a_size(mem_tl_a_size),
    .o_mem_a_source(mem_tl_a_source),
    .o_mem_a_address(mem_tl_a_address),
    .o_mem_a_mask(mem_tl_a_mask),
    .o_mem_a_data(mem_tl_a_data),
    .o_mem_a_corrupt(mem_tl_a_corrupt),
    .i_mem_a_ready(mem_tl_a_ready),

    .i_mem_d_valid(mem_tl_d_valid),
    .i_mem_d_opcode(mem_tl_d_opcode),
    .i_mem_d_param(mem_tl_d_param),
    .i_mem_d_size(mem_tl_d_size),
    .i_mem_d_source(mem_tl_d_source),
    .i_mem_d_sink(mem_tl_d_sink),
    .i_mem_d_data(mem_tl_d_data),
    .i_mem_d_denied(mem_tl_d_denied),
    .i_mem_d_corrupt(mem_tl_d_corrupt),
    .o_mem_d_ready(mem_tl_d_ready),

    .o_peri_a_valid(peri_tl_a_valid),
    .o_peri_a_opcode(peri_tl_a_opcode),
    .o_peri_a_param(peri_tl_a_param),
    .o_peri_a_size(peri_tl_a_size),
    .o_peri_a_source(peri_tl_a_source),
    .o_peri_a_address(peri_tl_a_address),
    .o_peri_a_mask(peri_tl_a_mask),
    .o_peri_a_data(peri_tl_a_data),
    .o_peri_a_corrupt(peri_tl_a_corrupt),
    .i_peri_a_ready(peri_tl_a_ready),

    .i_peri_d_valid(peri_tl_d_valid),
    .i_peri_d_opcode(peri_tl_d_opcode),
    .i_peri_d_param(peri_tl_d_param),
    .i_peri_d_size(peri_tl_d_size),
    .i_peri_d_source(peri_tl_d_source),
    .i_peri_d_sink(peri_tl_d_sink),
    .i_peri_d_data(peri_tl_d_data),
    .i_peri_d_denied(peri_tl_d_denied),
    .i_peri_d_corrupt(peri_tl_d_corrupt),
    .o_peri_d_ready(peri_tl_d_ready),

    .o_uart_a_valid(uart_tl_a_valid),
    .o_uart_a_opcode(uart_tl_a_opcode),
    .o_uart_a_param(uart_tl_a_param),
    .o_uart_a_size(uart_tl_a_size),
    .o_uart_a_source(uart_tl_a_source),
    .o_uart_a_address(uart_tl_a_address),
    .o_uart_a_mask(uart_tl_a_mask),
    .o_uart_a_data(uart_tl_a_data),
    .o_uart_a_corrupt(uart_tl_a_corrupt),
    .i_uart_a_ready(uart_tl_a_ready),

    .i_uart_d_valid(uart_tl_d_valid),
    .i_uart_d_opcode(uart_tl_d_opcode),
    .i_uart_d_param(uart_tl_d_param),
    .i_uart_d_size(uart_tl_d_size),
    .i_uart_d_source(uart_tl_d_source),
    .i_uart_d_sink(uart_tl_d_sink),
    .i_uart_d_data(uart_tl_d_data),
    .i_uart_d_denied(uart_tl_d_denied),
    .i_uart_d_corrupt(uart_tl_d_corrupt),
    .o_uart_d_ready(uart_tl_d_ready)
  );

  tlul_adapter_mem #(
    .DEPTH(MEM_DEPTH)
  ) u_mem_adapter (
    .i_clk(clk),
    .i_rst_n(rst_n_sync),

    .i_tl_a_valid(mem_tl_a_valid),
    .i_tl_a_opcode(mem_tl_a_opcode),
    .i_tl_a_param(mem_tl_a_param),
    .i_tl_a_size(mem_tl_a_size),
    .i_tl_a_source(mem_tl_a_source),
    .i_tl_a_address(mem_tl_a_address),
    .i_tl_a_mask(mem_tl_a_mask),
    .i_tl_a_data(mem_tl_a_data),
    .i_tl_a_corrupt(mem_tl_a_corrupt),
    .o_tl_a_ready(mem_tl_a_ready),

    .o_tl_d_valid(mem_tl_d_valid),
    .o_tl_d_opcode(mem_tl_d_opcode),
    .o_tl_d_param(mem_tl_d_param),
    .o_tl_d_size(mem_tl_d_size),
    .o_tl_d_source(mem_tl_d_source),
    .o_tl_d_sink(mem_tl_d_sink),
    .o_tl_d_data(mem_tl_d_data),
    .o_tl_d_denied(mem_tl_d_denied),
    .o_tl_d_corrupt(mem_tl_d_corrupt),
    .i_tl_d_ready(mem_tl_d_ready)
  );

  tlul_adapter_peri u_peri_adapter (
    .i_clk(clk),
    .i_rst_n(rst_n_sync),

    .i_tl_a_valid(peri_tl_a_valid),
    .i_tl_a_opcode(peri_tl_a_opcode),
    .i_tl_a_param(peri_tl_a_param),
    .i_tl_a_size(peri_tl_a_size),
    .i_tl_a_source(peri_tl_a_source),
    .i_tl_a_address(peri_tl_a_address),
    .i_tl_a_mask(peri_tl_a_mask),
    .i_tl_a_data(peri_tl_a_data),
    .i_tl_a_corrupt(peri_tl_a_corrupt),
    .o_tl_a_ready(peri_tl_a_ready),

    .o_tl_d_valid(peri_tl_d_valid),
    .o_tl_d_opcode(peri_tl_d_opcode),
    .o_tl_d_param(peri_tl_d_param),
    .o_tl_d_size(peri_tl_d_size),
    .o_tl_d_source(peri_tl_d_source),
    .o_tl_d_sink(peri_tl_d_sink),
    .o_tl_d_data(peri_tl_d_data),
    .o_tl_d_denied(peri_tl_d_denied),
    .o_tl_d_corrupt(peri_tl_d_corrupt),
    .i_tl_d_ready(peri_tl_d_ready),

    .i_io_sw(sw_i),
    .o_io_ledr(ledr_o),
    .o_io_ledg(ledg_o),
    .o_io_lcd(),
    .o_io_hex0(hex0_o),
    .o_io_hex1(hex1_o),
    .o_io_hex2(hex2_o),
    .o_io_hex3(hex3_o),
    .o_io_hex4(hex4_o),
    .o_io_hex5(hex5_o),
    .o_io_hex6(hex6_o),
    .o_io_hex7(hex7_o)
  );

  // UART Bridge
  
  tlul_uart_bridge #( .BAUD_RATE(BAUD_RATE) ) 
  u_uart_bridge (
    .i_clk(clk),
    .i_rst_n(rst_n_sync),

    .i_tl_a_valid(uart_tl_a_valid),
    .i_tl_a_opcode(uart_tl_a_opcode),
    .i_tl_a_param(uart_tl_a_param),
    .i_tl_a_size(uart_tl_a_size),
    .i_tl_a_source(uart_tl_a_source),
    .i_tl_a_address(uart_tl_a_address),
    .i_tl_a_mask(uart_tl_a_mask),
    .i_tl_a_data(uart_tl_a_data),
    .i_tl_a_corrupt(uart_tl_a_corrupt),
    .o_tl_a_ready(uart_tl_a_ready),

    .o_tl_d_valid(uart_tl_d_valid),
    .o_tl_d_opcode(uart_tl_d_opcode),
    .o_tl_d_param(uart_tl_d_param),
    .o_tl_d_size(uart_tl_d_size),
    .o_tl_d_source(uart_tl_d_source),
    .o_tl_d_sink(uart_tl_d_sink),
    .o_tl_d_data(uart_tl_d_data),
    .o_tl_d_denied(uart_tl_d_denied),
    .o_tl_d_corrupt(uart_tl_d_corrupt),
    .i_tl_d_ready(uart_tl_d_ready),

    .i_uart_rx(uart_rx_i),
    .o_uart_tx(uart_tx_o)
  );

endmodule
