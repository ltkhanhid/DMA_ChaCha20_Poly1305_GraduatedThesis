module soc_top_2m6s
  import tlul_pkg::*;
#(
  parameter int unsigned MEM_DEPTH = 32768,  // Memory depth in bytes
  parameter MEM_FILE = "../../02_test/isa_4b.hex",
  parameter logic [31:0] SIM_SW_VALUE = 32'h12345678  // Switch value for simulation
)
(
  input  logic        clk,
  input  logic        rst_n,

  // GPIO
  input  logic [9:0]  sw_i,
  output logic [9:0]  ledr_o,
  output logic [31:0] ledg_o,
  output logic [6:0]  hex0_o,
  output logic [6:0]  hex1_o,
  output logic [6:0]  hex2_o,
  output logic [6:0]  hex3_o,
  output logic [6:0]  hex4_o,
  output logic [6:0]  hex5_o,
  output logic [6:0]  hex6_o,
  output logic [6:0]  hex7_o,

  // UART
  input  logic        uart_rx_i,
  output logic        uart_tx_o,
  
  // Interrupts (directly exposed)
  output logic        irq_dma_o,
  output logic        irq_chacha_o,
  output logic        irq_poly_o,

  // Debug outputs
  output logic [31:0] pc_debug_o,
  output logic [31:0] pc_wb_o,
  output logic [31:0] pc_mem_o,
  output logic        insn_vld_o,
  output logic        ctrl_o,
  output logic        mispred_o
);

  //==========================================================================
  // Reset Synchronizer
  //==========================================================================
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

  //==========================================================================
  // CPU TileLink Signals (Master 0)
  //==========================================================================
  logic        cpu_tl_a_valid;
  logic [2:0]  cpu_tl_a_opcode;
  logic [2:0]  cpu_tl_a_param;
  tl_size_t    cpu_tl_a_size;
  tl_source_t  cpu_tl_a_source;
  tl_addr_t    cpu_tl_a_address;
  tl_mask_t    cpu_tl_a_mask;
  tl_data_t    cpu_tl_a_data;
  logic        cpu_tl_a_corrupt;
  logic        cpu_tl_a_ready;

  logic        cpu_tl_d_valid;
  logic [2:0]  cpu_tl_d_opcode;
  logic [2:0]  cpu_tl_d_param;
  tl_size_t    cpu_tl_d_size;
  tl_source_t  cpu_tl_d_source;
  tl_sink_t    cpu_tl_d_sink;
  tl_data_t    cpu_tl_d_data;
  logic        cpu_tl_d_denied;
  logic        cpu_tl_d_corrupt;
  logic        cpu_tl_d_ready;

  //==========================================================================
  // DMA Master TileLink Signals (Master 1)
  //==========================================================================
  logic        dma_m_tl_a_valid;
  logic [2:0]  dma_m_tl_a_opcode;
  logic [2:0]  dma_m_tl_a_param;
  tl_size_t    dma_m_tl_a_size;
  tl_source_t  dma_m_tl_a_source;
  tl_addr_t    dma_m_tl_a_address;
  tl_mask_t    dma_m_tl_a_mask;
  tl_data_t    dma_m_tl_a_data;
  logic        dma_m_tl_a_corrupt;
  logic        dma_m_tl_a_ready;

  logic        dma_m_tl_d_valid;
  logic [2:0]  dma_m_tl_d_opcode;
  logic [2:0]  dma_m_tl_d_param;
  tl_size_t    dma_m_tl_d_size;
  tl_source_t  dma_m_tl_d_source;
  tl_sink_t    dma_m_tl_d_sink;
  tl_data_t    dma_m_tl_d_data;
  logic        dma_m_tl_d_denied;
  logic        dma_m_tl_d_corrupt;
  logic        dma_m_tl_d_ready;

  //==========================================================================
  // Memory TileLink Signals (Slave 0)
  //==========================================================================
  logic        mem_tl_a_valid;
  logic [2:0]  mem_tl_a_opcode;
  logic [2:0]  mem_tl_a_param;
  tl_size_t    mem_tl_a_size;
  tl_source_t  mem_tl_a_source;
  tl_addr_t    mem_tl_a_address;
  tl_mask_t    mem_tl_a_mask;
  tl_data_t    mem_tl_a_data;
  logic        mem_tl_a_corrupt;
  logic        mem_tl_a_ready;

  logic        mem_tl_d_valid;
  logic [2:0]  mem_tl_d_opcode;
  logic [2:0]  mem_tl_d_param;
  tl_size_t    mem_tl_d_size;
  tl_source_t  mem_tl_d_source;
  tl_sink_t    mem_tl_d_sink;
  tl_data_t    mem_tl_d_data;
  logic        mem_tl_d_denied;
  logic        mem_tl_d_corrupt;
  logic        mem_tl_d_ready;

  //==========================================================================
  // Peripheral TileLink Signals (Slave 1)
  //==========================================================================
  logic        peri_tl_a_valid;
  logic [2:0]  peri_tl_a_opcode;
  logic [2:0]  peri_tl_a_param;
  tl_size_t    peri_tl_a_size;
  tl_source_t  peri_tl_a_source;
  tl_addr_t    peri_tl_a_address;
  tl_mask_t    peri_tl_a_mask;
  tl_data_t    peri_tl_a_data;
  logic        peri_tl_a_corrupt;
  logic        peri_tl_a_ready;

  logic        peri_tl_d_valid;
  logic [2:0]  peri_tl_d_opcode;
  logic [2:0]  peri_tl_d_param;
  tl_size_t    peri_tl_d_size;
  tl_source_t  peri_tl_d_source;
  tl_sink_t    peri_tl_d_sink;
  tl_data_t    peri_tl_d_data;
  logic        peri_tl_d_denied;
  logic        peri_tl_d_corrupt;
  logic        peri_tl_d_ready;

  //==========================================================================
  // UART TileLink Signals (Slave 2)
  //==========================================================================
  logic        uart_tl_a_valid;
  logic [2:0]  uart_tl_a_opcode;
  logic [2:0]  uart_tl_a_param;
  tl_size_t    uart_tl_a_size;
  tl_source_t  uart_tl_a_source;
  tl_addr_t    uart_tl_a_address;
  tl_mask_t    uart_tl_a_mask;
  tl_data_t    uart_tl_a_data;
  logic        uart_tl_a_corrupt;
  logic        uart_tl_a_ready;

  logic        uart_tl_d_valid;
  logic [2:0]  uart_tl_d_opcode;
  logic [2:0]  uart_tl_d_param;
  tl_size_t    uart_tl_d_size;
  tl_source_t  uart_tl_d_source;
  tl_sink_t    uart_tl_d_sink;
  tl_data_t    uart_tl_d_data;
  logic        uart_tl_d_denied;
  logic        uart_tl_d_corrupt;
  logic        uart_tl_d_ready;

  //==========================================================================
  // DMA Slave TileLink Signals (Slave 3 - for CPU to configure DMA)
  //==========================================================================
  logic        dma_tl_a_valid;
  logic [2:0]  dma_tl_a_opcode;
  logic [2:0]  dma_tl_a_param;
  tl_size_t    dma_tl_a_size;
  tl_source_t  dma_tl_a_source;
  tl_addr_t    dma_tl_a_address;
  tl_mask_t    dma_tl_a_mask;
  tl_data_t    dma_tl_a_data;
  logic        dma_tl_a_corrupt;
  logic        dma_tl_a_ready;

  logic        dma_tl_d_valid;
  logic [2:0]  dma_tl_d_opcode;
  logic [2:0]  dma_tl_d_param;
  tl_size_t    dma_tl_d_size;
  tl_source_t  dma_tl_d_source;
  tl_sink_t    dma_tl_d_sink;
  tl_data_t    dma_tl_d_data;
  logic        dma_tl_d_denied;
  logic        dma_tl_d_corrupt;
  logic        dma_tl_d_ready;

  //==========================================================================
  // ChaCha20 TileLink Signals (Slave 6)
  //==========================================================================
  logic        chacha_tl_a_valid;
  logic [2:0]  chacha_tl_a_opcode;
  logic [2:0]  chacha_tl_a_param;
  tl_size_t    chacha_tl_a_size;
  tl_source_t  chacha_tl_a_source;
  tl_addr_t    chacha_tl_a_address;
  tl_mask_t    chacha_tl_a_mask;
  tl_data_t    chacha_tl_a_data;
  logic        chacha_tl_a_corrupt;
  logic        chacha_tl_a_ready;

  logic        chacha_tl_d_valid;
  logic [2:0]  chacha_tl_d_opcode;
  logic [2:0]  chacha_tl_d_param;
  tl_size_t    chacha_tl_d_size;
  tl_source_t  chacha_tl_d_source;
  tl_sink_t    chacha_tl_d_sink;
  tl_data_t    chacha_tl_d_data;
  logic        chacha_tl_d_denied;
  logic        chacha_tl_d_corrupt;
  logic        chacha_tl_d_ready;

  //==========================================================================
  // Poly1305 TileLink Signals (Slave 7)
  //==========================================================================
  logic        poly_tl_a_valid;
  logic [2:0]  poly_tl_a_opcode;
  logic [2:0]  poly_tl_a_param;
  tl_size_t    poly_tl_a_size;
  tl_source_t  poly_tl_a_source;
  tl_addr_t    poly_tl_a_address;
  tl_mask_t    poly_tl_a_mask;
  tl_data_t    poly_tl_a_data;
  logic        poly_tl_a_corrupt;
  logic        poly_tl_a_ready;

  logic        poly_tl_d_valid;
  logic [2:0]  poly_tl_d_opcode;
  logic [2:0]  poly_tl_d_param;
  tl_size_t    poly_tl_d_size;
  tl_source_t  poly_tl_d_source;
  tl_sink_t    poly_tl_d_sink;
  tl_data_t    poly_tl_d_data;
  logic        poly_tl_d_denied;
  logic        poly_tl_d_corrupt;
  logic        poly_tl_d_ready;

  //==========================================================================
  // Peripheral Internal Signals (32-bit internal, truncated to output)
  //==========================================================================
  logic [31:0] peri_ledr_internal;
  assign ledr_o = peri_ledr_internal[9:0];  // Truncate to 10-bit output

  //==========================================================================
  // CPU Instance (Master 0)
  //==========================================================================
  pipelined_tl #(
    .MEM_FILE(MEM_FILE)  // Pass hex file path from top parameter
  ) u_cpu (
    .i_clk       (clk),
    .i_rst_n     (rst_n_sync),

    .o_tl_a_valid  (cpu_tl_a_valid),
    .o_tl_a_opcode (cpu_tl_a_opcode),
    .o_tl_a_param  (cpu_tl_a_param),
    .o_tl_a_size   (cpu_tl_a_size),
    .o_tl_a_source (cpu_tl_a_source),
    .o_tl_a_address(cpu_tl_a_address),
    .o_tl_a_mask   (cpu_tl_a_mask),
    .o_tl_a_data   (cpu_tl_a_data),
    .o_tl_a_corrupt(cpu_tl_a_corrupt),
    .i_tl_a_ready  (cpu_tl_a_ready),

    .i_tl_d_valid  (cpu_tl_d_valid),
    .i_tl_d_opcode (cpu_tl_d_opcode),
    .i_tl_d_param  (cpu_tl_d_param),
    .i_tl_d_size   (cpu_tl_d_size),
    .i_tl_d_source (cpu_tl_d_source),
    .i_tl_d_sink   (cpu_tl_d_sink),
    .i_tl_d_data   (cpu_tl_d_data),
    .i_tl_d_denied (cpu_tl_d_denied),
    .i_tl_d_corrupt(cpu_tl_d_corrupt),
    .o_tl_d_ready  (cpu_tl_d_ready),

    .o_pc_debug(pc_debug_o),
    .o_pc_wb   (pc_wb_o),
    .o_pc_mem  (pc_mem_o),
    .o_insn_vld(insn_vld_o),
    .o_ctrl    (ctrl_o),
    .o_mispred (mispred_o)
  );

  //==========================================================================
  // 2-Master 7-Slave TileLink Crossbar
  //==========================================================================
  tlul_xbar_2m6s u_crossbar (
    .i_clk   (clk),
    .i_rst_n (rst_n_sync),

    //----------------------------------------------------------------------
    // Master 0: CPU
    //----------------------------------------------------------------------
    .i_cpu_a_valid  (cpu_tl_a_valid),
    .i_cpu_a_opcode (cpu_tl_a_opcode),
    .i_cpu_a_param  (cpu_tl_a_param),
    .i_cpu_a_size   (cpu_tl_a_size),
    .i_cpu_a_source (cpu_tl_a_source),
    .i_cpu_a_address(cpu_tl_a_address),
    .i_cpu_a_mask   (cpu_tl_a_mask),
    .i_cpu_a_data   (cpu_tl_a_data),
    .i_cpu_a_corrupt(cpu_tl_a_corrupt),
    .o_cpu_a_ready  (cpu_tl_a_ready),

    .o_cpu_d_valid  (cpu_tl_d_valid),
    .o_cpu_d_opcode (cpu_tl_d_opcode),
    .o_cpu_d_param  (cpu_tl_d_param),
    .o_cpu_d_size   (cpu_tl_d_size),
    .o_cpu_d_source (cpu_tl_d_source),
    .o_cpu_d_sink   (cpu_tl_d_sink),
    .o_cpu_d_data   (cpu_tl_d_data),
    .o_cpu_d_denied (cpu_tl_d_denied),
    .o_cpu_d_corrupt(cpu_tl_d_corrupt),
    .i_cpu_d_ready  (cpu_tl_d_ready),

    //----------------------------------------------------------------------
    // Master 1: DMA
    //----------------------------------------------------------------------
    .i_dma_a_valid  (dma_m_tl_a_valid),
    .i_dma_a_opcode (dma_m_tl_a_opcode),
    .i_dma_a_param  (dma_m_tl_a_param),
    .i_dma_a_size   (dma_m_tl_a_size),
    .i_dma_a_source (dma_m_tl_a_source),
    .i_dma_a_address(dma_m_tl_a_address),
    .i_dma_a_mask   (dma_m_tl_a_mask),
    .i_dma_a_data   (dma_m_tl_a_data),
    .i_dma_a_corrupt(dma_m_tl_a_corrupt),
    .o_dma_a_ready  (dma_m_tl_a_ready),

    .o_dma_d_valid  (dma_m_tl_d_valid),
    .o_dma_d_opcode (dma_m_tl_d_opcode),
    .o_dma_d_param  (dma_m_tl_d_param),
    .o_dma_d_size   (dma_m_tl_d_size),
    .o_dma_d_source (dma_m_tl_d_source),
    .o_dma_d_sink   (dma_m_tl_d_sink),
    .o_dma_d_data   (dma_m_tl_d_data),
    .o_dma_d_denied (dma_m_tl_d_denied),
    .o_dma_d_corrupt(dma_m_tl_d_corrupt),
    .i_dma_d_ready  (dma_m_tl_d_ready),

    //----------------------------------------------------------------------
    // Slave 0: Memory
    //----------------------------------------------------------------------
    .o_mem_a_valid  (mem_tl_a_valid),
    .o_mem_a_opcode (mem_tl_a_opcode),
    .o_mem_a_param  (mem_tl_a_param),
    .o_mem_a_size   (mem_tl_a_size),
    .o_mem_a_source (mem_tl_a_source),
    .o_mem_a_address(mem_tl_a_address),
    .o_mem_a_mask   (mem_tl_a_mask),
    .o_mem_a_data   (mem_tl_a_data),
    .o_mem_a_corrupt(mem_tl_a_corrupt),
    .i_mem_a_ready  (mem_tl_a_ready),

    .i_mem_d_valid  (mem_tl_d_valid),
    .i_mem_d_opcode (mem_tl_d_opcode),
    .i_mem_d_param  (mem_tl_d_param),
    .i_mem_d_size   (mem_tl_d_size),
    .i_mem_d_source (mem_tl_d_source),
    .i_mem_d_sink   (mem_tl_d_sink),
    .i_mem_d_data   (mem_tl_d_data),
    .i_mem_d_denied (mem_tl_d_denied),
    .i_mem_d_corrupt(mem_tl_d_corrupt),
    .o_mem_d_ready  (mem_tl_d_ready),

    //----------------------------------------------------------------------
    // Slave 1: Peripherals
    //----------------------------------------------------------------------
    .o_peri_a_valid  (peri_tl_a_valid),
    .o_peri_a_opcode (peri_tl_a_opcode),
    .o_peri_a_param  (peri_tl_a_param),
    .o_peri_a_size   (peri_tl_a_size),
    .o_peri_a_source (peri_tl_a_source),
    .o_peri_a_address(peri_tl_a_address),
    .o_peri_a_mask   (peri_tl_a_mask),
    .o_peri_a_data   (peri_tl_a_data),
    .o_peri_a_corrupt(peri_tl_a_corrupt),
    .i_peri_a_ready  (peri_tl_a_ready),

    .i_peri_d_valid  (peri_tl_d_valid),
    .i_peri_d_opcode (peri_tl_d_opcode),
    .i_peri_d_param  (peri_tl_d_param),
    .i_peri_d_size   (peri_tl_d_size),
    .i_peri_d_source (peri_tl_d_source),
    .i_peri_d_sink   (peri_tl_d_sink),
    .i_peri_d_data   (peri_tl_d_data),
    .i_peri_d_denied (peri_tl_d_denied),
    .i_peri_d_corrupt(peri_tl_d_corrupt),
    .o_peri_d_ready  (peri_tl_d_ready),

    //----------------------------------------------------------------------
    // Slave 2: UART
    //----------------------------------------------------------------------
    .o_uart_a_valid  (uart_tl_a_valid),
    .o_uart_a_opcode (uart_tl_a_opcode),
    .o_uart_a_param  (uart_tl_a_param),
    .o_uart_a_size   (uart_tl_a_size),
    .o_uart_a_source (uart_tl_a_source),
    .o_uart_a_address(uart_tl_a_address),
    .o_uart_a_mask   (uart_tl_a_mask),
    .o_uart_a_data   (uart_tl_a_data),
    .o_uart_a_corrupt(uart_tl_a_corrupt),
    .i_uart_a_ready  (uart_tl_a_ready),

    .i_uart_d_valid  (uart_tl_d_valid),
    .i_uart_d_opcode (uart_tl_d_opcode),
    .i_uart_d_param  (uart_tl_d_param),
    .i_uart_d_size   (uart_tl_d_size),
    .i_uart_d_source (uart_tl_d_source),
    .i_uart_d_sink   (uart_tl_d_sink),
    .i_uart_d_data   (uart_tl_d_data),
    .i_uart_d_denied (uart_tl_d_denied),
    .i_uart_d_corrupt(uart_tl_d_corrupt),
    .o_uart_d_ready  (uart_tl_d_ready),

    //----------------------------------------------------------------------
    // Slave 3: DMA Registers
    //----------------------------------------------------------------------
    .o_dmareg_a_valid  (dma_tl_a_valid),
    .o_dmareg_a_opcode (dma_tl_a_opcode),
    .o_dmareg_a_param  (dma_tl_a_param),
    .o_dmareg_a_size   (dma_tl_a_size),
    .o_dmareg_a_source (dma_tl_a_source),
    .o_dmareg_a_address(dma_tl_a_address),
    .o_dmareg_a_mask   (dma_tl_a_mask),
    .o_dmareg_a_data   (dma_tl_a_data),
    .o_dmareg_a_corrupt(dma_tl_a_corrupt),
    .i_dmareg_a_ready  (dma_tl_a_ready),

    .i_dmareg_d_valid  (dma_tl_d_valid),
    .i_dmareg_d_opcode (dma_tl_d_opcode),
    .i_dmareg_d_param  (dma_tl_d_param),
    .i_dmareg_d_size   (dma_tl_d_size),
    .i_dmareg_d_source (dma_tl_d_source),
    .i_dmareg_d_sink   (dma_tl_d_sink),
    .i_dmareg_d_data   (dma_tl_d_data),
    .i_dmareg_d_denied (dma_tl_d_denied),
    .i_dmareg_d_corrupt(dma_tl_d_corrupt),
    .o_dmareg_d_ready  (dma_tl_d_ready),

    //----------------------------------------------------------------------
    // Slave 4: ChaCha20
    //----------------------------------------------------------------------
    .o_chacha_a_valid  (chacha_tl_a_valid),
    .o_chacha_a_opcode (chacha_tl_a_opcode),
    .o_chacha_a_param  (chacha_tl_a_param),
    .o_chacha_a_size   (chacha_tl_a_size),
    .o_chacha_a_source (chacha_tl_a_source),
    .o_chacha_a_address(chacha_tl_a_address),
    .o_chacha_a_mask   (chacha_tl_a_mask),
    .o_chacha_a_data   (chacha_tl_a_data),
    .o_chacha_a_corrupt(chacha_tl_a_corrupt),
    .i_chacha_a_ready  (chacha_tl_a_ready),

    .i_chacha_d_valid  (chacha_tl_d_valid),
    .i_chacha_d_opcode (chacha_tl_d_opcode),
    .i_chacha_d_param  (chacha_tl_d_param),
    .i_chacha_d_size   (chacha_tl_d_size),
    .i_chacha_d_source (chacha_tl_d_source),
    .i_chacha_d_sink   (chacha_tl_d_sink),
    .i_chacha_d_data   (chacha_tl_d_data),
    .i_chacha_d_denied (chacha_tl_d_denied),
    .i_chacha_d_corrupt(chacha_tl_d_corrupt),
    .o_chacha_d_ready  (chacha_tl_d_ready),

    //----------------------------------------------------------------------
    // Slave 5: Poly1305 MAC
    //----------------------------------------------------------------------
    .o_poly_a_valid  (poly_tl_a_valid),
    .o_poly_a_opcode (poly_tl_a_opcode),
    .o_poly_a_param  (poly_tl_a_param),
    .o_poly_a_size   (poly_tl_a_size),
    .o_poly_a_source (poly_tl_a_source),
    .o_poly_a_address(poly_tl_a_address),
    .o_poly_a_mask   (poly_tl_a_mask),
    .o_poly_a_data   (poly_tl_a_data),
    .o_poly_a_corrupt(poly_tl_a_corrupt),
    .i_poly_a_ready  (poly_tl_a_ready),

    .i_poly_d_valid  (poly_tl_d_valid),
    .i_poly_d_opcode (poly_tl_d_opcode),
    .i_poly_d_param  (poly_tl_d_param),
    .i_poly_d_size   (poly_tl_d_size),
    .i_poly_d_source (poly_tl_d_source),
    .i_poly_d_sink   (poly_tl_d_sink),
    .i_poly_d_data   (poly_tl_d_data),
    .i_poly_d_denied (poly_tl_d_denied),
    .i_poly_d_corrupt(poly_tl_d_corrupt),
    .o_poly_d_ready  (poly_tl_d_ready)
  );

  //==========================================================================
  // Memory Adapter (Slave 0)
  //==========================================================================
  tlul_adapter_mem #(
    .DEPTH(MEM_DEPTH)
  ) u_mem_adapter (
    .i_clk   (clk),
    .i_rst_n (rst_n_sync),

    .i_tl_a_valid  (mem_tl_a_valid),
    .i_tl_a_opcode (mem_tl_a_opcode),
    .i_tl_a_param  (mem_tl_a_param),
    .i_tl_a_size   (mem_tl_a_size),
    .i_tl_a_source (mem_tl_a_source),
    .i_tl_a_address(mem_tl_a_address),
    .i_tl_a_mask   (mem_tl_a_mask),
    .i_tl_a_data   (mem_tl_a_data),
    .i_tl_a_corrupt(mem_tl_a_corrupt),
    .o_tl_a_ready  (mem_tl_a_ready),

    .o_tl_d_valid  (mem_tl_d_valid),
    .o_tl_d_opcode (mem_tl_d_opcode),
    .o_tl_d_param  (mem_tl_d_param),
    .o_tl_d_size   (mem_tl_d_size),
    .o_tl_d_source (mem_tl_d_source),
    .o_tl_d_sink   (mem_tl_d_sink),
    .o_tl_d_data   (mem_tl_d_data),
    .o_tl_d_denied (mem_tl_d_denied),
    .o_tl_d_corrupt(mem_tl_d_corrupt),
    .i_tl_d_ready  (mem_tl_d_ready)
  );

  //==========================================================================
  // Peripheral Adapter (Slave 1 - GPIO/LED/HEX)
  //==========================================================================
  tlul_adapter_peri u_peri_adapter (
    .i_clk   (clk),
    .i_rst_n (rst_n_sync),

    .i_tl_a_valid  (peri_tl_a_valid),
    .i_tl_a_opcode (peri_tl_a_opcode),
    .i_tl_a_param  (peri_tl_a_param),
    .i_tl_a_size   (peri_tl_a_size),
    .i_tl_a_source (peri_tl_a_source),
    .i_tl_a_address(peri_tl_a_address),
    .i_tl_a_mask   (peri_tl_a_mask),
    .i_tl_a_data   (peri_tl_a_data),
    .i_tl_a_corrupt(peri_tl_a_corrupt),
    .o_tl_a_ready  (peri_tl_a_ready),

    .o_tl_d_valid  (peri_tl_d_valid),
    .o_tl_d_opcode (peri_tl_d_opcode),
    .o_tl_d_param  (peri_tl_d_param),
    .o_tl_d_size   (peri_tl_d_size),
    .o_tl_d_source (peri_tl_d_source),
    .o_tl_d_sink   (peri_tl_d_sink),
    .o_tl_d_data   (peri_tl_d_data),
    .o_tl_d_denied (peri_tl_d_denied),
    .o_tl_d_corrupt(peri_tl_d_corrupt),
    .i_tl_d_ready  (peri_tl_d_ready),

    .i_io_sw  ({22'b0, sw_i}),  // Connect real switches (10-bit → 32-bit zero-extend)
    .o_io_ledr(peri_ledr_internal),
    .o_io_ledg(ledg_o),
    .o_io_lcd (),
    .o_io_hex0(hex0_o),
    .o_io_hex1(hex1_o),
    .o_io_hex2(hex2_o),
    .o_io_hex3(hex3_o),
    .o_io_hex4(hex4_o),
    .o_io_hex5(hex5_o),
    .o_io_hex6(hex6_o),
    .o_io_hex7(hex7_o)
  );

  //==========================================================================
  // UART Bridge (Slave 2) - Fixed Baud Rate 115200
  //==========================================================================
  tlul_uart_bridge u_uart_bridge (
    .i_clk   (clk),
    .i_rst_n (rst_n_sync),

    .i_tl_a_valid  (uart_tl_a_valid),
    .i_tl_a_opcode (uart_tl_a_opcode),
    .i_tl_a_param  (uart_tl_a_param),
    .i_tl_a_size   (uart_tl_a_size),
    .i_tl_a_source (uart_tl_a_source),
    .i_tl_a_address(uart_tl_a_address),
    .i_tl_a_mask   (uart_tl_a_mask),
    .i_tl_a_data   (uart_tl_a_data),
    .i_tl_a_corrupt(uart_tl_a_corrupt),
    .o_tl_a_ready  (uart_tl_a_ready),

    .o_tl_d_valid  (uart_tl_d_valid),
    .o_tl_d_opcode (uart_tl_d_opcode),
    .o_tl_d_param  (uart_tl_d_param),
    .o_tl_d_size   (uart_tl_d_size),
    .o_tl_d_source (uart_tl_d_source),
    .o_tl_d_sink   (uart_tl_d_sink),
    .o_tl_d_data   (uart_tl_d_data),
    .o_tl_d_denied (uart_tl_d_denied),
    .o_tl_d_corrupt(uart_tl_d_corrupt),
    .i_tl_d_ready  (uart_tl_d_ready),

    .i_uart_rx(uart_rx_i),
    .o_uart_tx(uart_tx_o),
    .o_irq_rx ()  // UART RX interrupt - not used (no interrupt controller)
  );

  //==========================================================================
  // DMA Controller (Slave 3 + Master 1)
  //==========================================================================
  tlul_dma u_dma (
    .i_clk   (clk),
    .i_rst_n (rst_n_sync),

    // Slave interface (CPU -> DMA registers)
    .i_tl_a_valid  (dma_tl_a_valid),
    .i_tl_a_opcode (dma_tl_a_opcode),
    .i_tl_a_param  (dma_tl_a_param),
    .i_tl_a_size   (dma_tl_a_size),
    .i_tl_a_source (dma_tl_a_source),
    .i_tl_a_address(dma_tl_a_address),
    .i_tl_a_mask   (dma_tl_a_mask),
    .i_tl_a_data   (dma_tl_a_data),
    .i_tl_a_corrupt(dma_tl_a_corrupt),
    .o_tl_a_ready  (dma_tl_a_ready),

    .o_tl_d_valid  (dma_tl_d_valid),
    .o_tl_d_opcode (dma_tl_d_opcode),
    .o_tl_d_param  (dma_tl_d_param),
    .o_tl_d_size   (dma_tl_d_size),
    .o_tl_d_source (dma_tl_d_source),
    .o_tl_d_sink   (dma_tl_d_sink),
    .o_tl_d_data   (dma_tl_d_data),
    .o_tl_d_denied (dma_tl_d_denied),
    .o_tl_d_corrupt(dma_tl_d_corrupt),
    .i_tl_d_ready  (dma_tl_d_ready),

    // Master interface (DMA -> Memory via Crossbar)
    .o_dma_tl_a_valid  (dma_m_tl_a_valid),
    .o_dma_tl_a_opcode (dma_m_tl_a_opcode),
    .o_dma_tl_a_param  (dma_m_tl_a_param),
    .o_dma_tl_a_size   (dma_m_tl_a_size),
    .o_dma_tl_a_source (dma_m_tl_a_source),
    .o_dma_tl_a_address(dma_m_tl_a_address),
    .o_dma_tl_a_mask   (dma_m_tl_a_mask),
    .o_dma_tl_a_data   (dma_m_tl_a_data),
    .o_dma_tl_a_corrupt(dma_m_tl_a_corrupt),
    .i_dma_tl_a_ready  (dma_m_tl_a_ready),

    .i_dma_tl_d_valid  (dma_m_tl_d_valid),
    .i_dma_tl_d_opcode (dma_m_tl_d_opcode),
    .i_dma_tl_d_param  (dma_m_tl_d_param),
    .i_dma_tl_d_size   (dma_m_tl_d_size),
    .i_dma_tl_d_source (dma_m_tl_d_source),
    .i_dma_tl_d_sink   (dma_m_tl_d_sink),
    .i_dma_tl_d_data   (dma_m_tl_d_data),
    .i_dma_tl_d_denied (dma_m_tl_d_denied),
    .i_dma_tl_d_corrupt(dma_m_tl_d_corrupt),
    .o_dma_tl_d_ready  (dma_m_tl_d_ready),

    .o_dma_irq(irq_dma_o)
  );

  //==========================================================================
  // ChaCha20 Crypto Peripheral (Slave 6)
  //==========================================================================
  tlul_chacha20 u_chacha20 (
    .i_clk   (clk),
    .i_rst_n (rst_n_sync),

    .i_tl_a_valid  (chacha_tl_a_valid),
    .i_tl_a_opcode (chacha_tl_a_opcode),
    .i_tl_a_param  (chacha_tl_a_param),
    .i_tl_a_size   (chacha_tl_a_size),
    .i_tl_a_source (chacha_tl_a_source),
    .i_tl_a_address(chacha_tl_a_address),
    .i_tl_a_mask   (chacha_tl_a_mask),
    .i_tl_a_data   (chacha_tl_a_data),
    .i_tl_a_corrupt(chacha_tl_a_corrupt),
    .o_tl_a_ready  (chacha_tl_a_ready),

    .o_tl_d_valid  (chacha_tl_d_valid),
    .o_tl_d_opcode (chacha_tl_d_opcode),
    .o_tl_d_param  (chacha_tl_d_param),
    .o_tl_d_size   (chacha_tl_d_size),
    .o_tl_d_source (chacha_tl_d_source),
    .o_tl_d_sink   (chacha_tl_d_sink),
    .o_tl_d_data   (chacha_tl_d_data),
    .o_tl_d_denied (chacha_tl_d_denied),
    .o_tl_d_corrupt(chacha_tl_d_corrupt),
    .i_tl_d_ready  (chacha_tl_d_ready),

    .o_chacha_irq  (irq_chacha_o)
  );

  //==========================================================================
  // Poly1305 MAC Peripheral (Slave 7)
  //==========================================================================
  tlul_poly1305 u_poly1305 (
    .i_clk   (clk),
    .i_rst_n (rst_n_sync),

    .i_tl_a_valid  (poly_tl_a_valid),
    .i_tl_a_opcode (poly_tl_a_opcode),
    .i_tl_a_param  (poly_tl_a_param),
    .i_tl_a_size   (poly_tl_a_size),
    .i_tl_a_source (poly_tl_a_source),
    .i_tl_a_address(poly_tl_a_address),
    .i_tl_a_mask   (poly_tl_a_mask),
    .i_tl_a_data   (poly_tl_a_data),
    .i_tl_a_corrupt(poly_tl_a_corrupt),
    .o_tl_a_ready  (poly_tl_a_ready),

    .o_tl_d_valid  (poly_tl_d_valid),
    .o_tl_d_opcode (poly_tl_d_opcode),
    .o_tl_d_param  (poly_tl_d_param),
    .o_tl_d_size   (poly_tl_d_size),
    .o_tl_d_source (poly_tl_d_source),
    .o_tl_d_sink   (poly_tl_d_sink),
    .o_tl_d_data   (poly_tl_d_data),
    .o_tl_d_denied (poly_tl_d_denied),
    .o_tl_d_corrupt(poly_tl_d_corrupt),
    .i_tl_d_ready  (poly_tl_d_ready),

    .o_poly_irq    (irq_poly_o)
  );

endmodule
