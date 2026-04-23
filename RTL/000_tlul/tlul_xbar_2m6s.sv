module tlul_xbar_2m6s
  import tlul_pkg::*;
#(
  parameter int STARVATION_LIMIT = 8   // Max cycles before forced grant
)(
  input  logic i_clk,
  input  logic i_rst_n,
  
  //==========================================================================
  // Master 0 Interface (CPU)
  //==========================================================================
  input  logic        i_cpu_a_valid,
  input  logic [2:0]  i_cpu_a_opcode,
  input  logic [2:0]  i_cpu_a_param,
  input  tl_size_t    i_cpu_a_size,
  input  tl_source_t  i_cpu_a_source,
  input  tl_addr_t    i_cpu_a_address,
  input  tl_mask_t    i_cpu_a_mask,
  input  tl_data_t    i_cpu_a_data,
  input  logic        i_cpu_a_corrupt,
  output logic        o_cpu_a_ready,
  
  output logic        o_cpu_d_valid,
  output logic [2:0]  o_cpu_d_opcode,
  output logic [2:0]  o_cpu_d_param,
  output tl_size_t    o_cpu_d_size,
  output tl_source_t  o_cpu_d_source,
  output tl_sink_t    o_cpu_d_sink,
  output tl_data_t    o_cpu_d_data,
  output logic        o_cpu_d_denied,
  output logic        o_cpu_d_corrupt,
  input  logic        i_cpu_d_ready,
  
  //==========================================================================
  // Master 1 Interface (DMA)
  //==========================================================================
  input  logic        i_dma_a_valid,
  input  logic [2:0]  i_dma_a_opcode,
  input  logic [2:0]  i_dma_a_param,
  input  tl_size_t    i_dma_a_size,
  input  tl_source_t  i_dma_a_source,
  input  tl_addr_t    i_dma_a_address,
  input  tl_mask_t    i_dma_a_mask,
  input  tl_data_t    i_dma_a_data,
  input  logic        i_dma_a_corrupt,
  output logic        o_dma_a_ready,
  
  output logic        o_dma_d_valid,
  output logic [2:0]  o_dma_d_opcode,
  output logic [2:0]  o_dma_d_param,
  output tl_size_t    o_dma_d_size,
  output tl_source_t  o_dma_d_source,
  output tl_sink_t    o_dma_d_sink,
  output tl_data_t    o_dma_d_data,
  output logic        o_dma_d_denied,
  output logic        o_dma_d_corrupt,
  input  logic        i_dma_d_ready,
  
  //==========================================================================
  // Slave 0: Memory
  //==========================================================================
  output logic        o_mem_a_valid,
  output logic [2:0]  o_mem_a_opcode,
  output logic [2:0]  o_mem_a_param,
  output tl_size_t    o_mem_a_size,
  output tl_source_t  o_mem_a_source,
  output tl_addr_t    o_mem_a_address,
  output tl_mask_t    o_mem_a_mask,
  output tl_data_t    o_mem_a_data,
  output logic        o_mem_a_corrupt,
  input  logic        i_mem_a_ready,
  
  input  logic        i_mem_d_valid,
  input  logic [2:0]  i_mem_d_opcode,
  input  logic [2:0]  i_mem_d_param,
  input  tl_size_t    i_mem_d_size,
  input  tl_source_t  i_mem_d_source,
  input  tl_sink_t    i_mem_d_sink,
  input  tl_data_t    i_mem_d_data,
  input  logic        i_mem_d_denied,
  input  logic        i_mem_d_corrupt,
  output logic        o_mem_d_ready,
  
  //==========================================================================
  // Slave 1: Peripherals (GPIO/LED/7-Segment)
  //==========================================================================
  output logic        o_peri_a_valid,
  output logic [2:0]  o_peri_a_opcode,
  output logic [2:0]  o_peri_a_param,
  output tl_size_t    o_peri_a_size,
  output tl_source_t  o_peri_a_source,
  output tl_addr_t    o_peri_a_address,
  output tl_mask_t    o_peri_a_mask,
  output tl_data_t    o_peri_a_data,
  output logic        o_peri_a_corrupt,
  input  logic        i_peri_a_ready,
  
  input  logic        i_peri_d_valid,
  input  logic [2:0]  i_peri_d_opcode,
  input  logic [2:0]  i_peri_d_param,
  input  tl_size_t    i_peri_d_size,
  input  tl_source_t  i_peri_d_source,
  input  tl_sink_t    i_peri_d_sink,
  input  tl_data_t    i_peri_d_data,
  input  logic        i_peri_d_denied,
  input  logic        i_peri_d_corrupt,
  output logic        o_peri_d_ready,
  
  //==========================================================================
  // Slave 2: UART
  //==========================================================================
  output logic        o_uart_a_valid,
  output logic [2:0]  o_uart_a_opcode,
  output logic [2:0]  o_uart_a_param,
  output tl_size_t    o_uart_a_size,
  output tl_source_t  o_uart_a_source,
  output tl_addr_t    o_uart_a_address,
  output tl_mask_t    o_uart_a_mask,
  output tl_data_t    o_uart_a_data,
  output logic        o_uart_a_corrupt,
  input  logic        i_uart_a_ready,
  
  input  logic        i_uart_d_valid,
  input  logic [2:0]  i_uart_d_opcode,
  input  logic [2:0]  i_uart_d_param,
  input  tl_size_t    i_uart_d_size,
  input  tl_source_t  i_uart_d_source,
  input  tl_sink_t    i_uart_d_sink,
  input  tl_data_t    i_uart_d_data,
  input  logic        i_uart_d_denied,
  input  logic        i_uart_d_corrupt,
  output logic        o_uart_d_ready,
  
  //==========================================================================
  // Slave 3: DMA Registers
  //==========================================================================
  output logic        o_dmareg_a_valid,
  output logic [2:0]  o_dmareg_a_opcode,
  output logic [2:0]  o_dmareg_a_param,
  output tl_size_t    o_dmareg_a_size,
  output tl_source_t  o_dmareg_a_source,
  output tl_addr_t    o_dmareg_a_address,
  output tl_mask_t    o_dmareg_a_mask,
  output tl_data_t    o_dmareg_a_data,
  output logic        o_dmareg_a_corrupt,
  input  logic        i_dmareg_a_ready,
  
  input  logic        i_dmareg_d_valid,
  input  logic [2:0]  i_dmareg_d_opcode,
  input  logic [2:0]  i_dmareg_d_param,
  input  tl_size_t    i_dmareg_d_size,
  input  tl_source_t  i_dmareg_d_source,
  input  tl_sink_t    i_dmareg_d_sink,
  input  tl_data_t    i_dmareg_d_data,
  input  logic        i_dmareg_d_denied,
  input  logic        i_dmareg_d_corrupt,
  output logic        o_dmareg_d_ready,
  
  //==========================================================================
  // Slave 4: ChaCha20 Crypto
  //==========================================================================
  output logic        o_chacha_a_valid,
  output logic [2:0]  o_chacha_a_opcode,
  output logic [2:0]  o_chacha_a_param,
  output tl_size_t    o_chacha_a_size,
  output tl_source_t  o_chacha_a_source,
  output tl_addr_t    o_chacha_a_address,
  output tl_mask_t    o_chacha_a_mask,
  output tl_data_t    o_chacha_a_data,
  output logic        o_chacha_a_corrupt,
  input  logic        i_chacha_a_ready,
  
  input  logic        i_chacha_d_valid,
  input  logic [2:0]  i_chacha_d_opcode,
  input  logic [2:0]  i_chacha_d_param,
  input  tl_size_t    i_chacha_d_size,
  input  tl_source_t  i_chacha_d_source,
  input  tl_sink_t    i_chacha_d_sink,
  input  tl_data_t    i_chacha_d_data,
  input  logic        i_chacha_d_denied,
  input  logic        i_chacha_d_corrupt,
  output logic        o_chacha_d_ready,
  
  //==========================================================================
  // Slave 5: Poly1305 MAC
  //==========================================================================
  output logic        o_poly_a_valid,
  output logic [2:0]  o_poly_a_opcode,
  output logic [2:0]  o_poly_a_param,
  output tl_size_t    o_poly_a_size,
  output tl_source_t  o_poly_a_source,
  output tl_addr_t    o_poly_a_address,
  output tl_mask_t    o_poly_a_mask,
  output tl_data_t    o_poly_a_data,
  output logic        o_poly_a_corrupt,
  input  logic        i_poly_a_ready,
  
  input  logic        i_poly_d_valid,
  input  logic [2:0]  i_poly_d_opcode,
  input  logic [2:0]  i_poly_d_param,
  input  tl_size_t    i_poly_d_size,
  input  tl_source_t  i_poly_d_source,
  input  tl_sink_t    i_poly_d_sink,
  input  tl_data_t    i_poly_d_data,
  input  logic        i_poly_d_denied,
  input  logic        i_poly_d_corrupt,
  output logic        o_poly_d_ready
);

  //==========================================================================
  // Local Parameters
  //==========================================================================
  localparam int NUM_MASTERS = 2;
  localparam int NUM_SLAVES  = 6;
  
  // Address Decode Constants
  // Memory Map (per spec):
  //   0x0000_0000 - 0x0000_FFFF : Memory (64KB)
  //   0x1000_0000 - 0x1000_0FFF : Red LEDs
  //   0x1000_1000 - 0x1000_1FFF : Green LEDs  
  //   0x1000_2000 - 0x1000_2FFF : 7-Segment 3-0
  //   0x1000_3000 - 0x1000_3FFF : 7-Segment 7-4
  //   0x1000_4000 - 0x1000_4FFF : LCD
  //   0x1001_0000 - 0x1001_0FFF : Switches (part of Peripheral)
  //   0x1002_0000 - 0x1002_FFFF : UART
  //   0x1005_0000 - 0x1005_FFFF : DMA
  localparam logic [31:0] MEM_BASE     = 32'h0000_0000;
  localparam logic [31:0] MEM_MASK     = 32'h0FFF_FFFF;  // 256MB for memory region
  localparam logic [31:0] PERI_BASE    = 32'h1000_0000;  // 0x1000_0xxx and 0x1001_0xxx
  localparam logic [31:0] PERI_MASK    = 32'hFFFE_0000;  // Covers 0x1000_xxxx and 0x1001_xxxx (128KB)
  localparam logic [31:0] UART_BASE    = 32'h1002_0000;
  localparam logic [31:0] DMA_BASE     = 32'h1005_0000;
  localparam logic [31:0] CHACHA_BASE  = 32'h1006_0000;
  localparam logic [31:0] POLY_BASE    = 32'h1007_0000;
  localparam logic [31:0] SLAVE_MASK   = 32'hFFFF_0000;  // 64KB per slave (for UART, DMA, ChaCha, Poly)

  //==========================================================================
  // Master Arbitration Types
  //==========================================================================
  typedef enum logic [2:0] {
    ARB_IDLE     = 3'd0,
    ARB_CPU      = 3'd1,
    ARB_DMA      = 3'd2,
    ARB_PENDING  = 3'd3,
    ARB_ERROR    = 3'd4
  } arb_state_t;
  
  //==========================================================================
  // Internal Signals
  //==========================================================================
  // Arbitration
  arb_state_t arb_state, arb_state_next;
  logic [3:0] starvation_cnt;
  logic       rr_priority;       // 0=CPU priority, 1=DMA priority
  logic       cpu_grant, dma_grant;
  
  // Selected master signals (after arbitration)
  logic        sel_a_valid;
  logic [2:0]  sel_a_opcode;
  logic [2:0]  sel_a_param;
  tl_size_t    sel_a_size;
  tl_source_t  sel_a_source;
  tl_addr_t    sel_a_address;
  tl_mask_t    sel_a_mask;
  tl_data_t    sel_a_data;
  logic        sel_a_corrupt;
  logic        sel_a_ready;
  logic        sel_master_id;    // 0=CPU, 1=DMA
  
  // Response routing
  logic        sel_d_valid;
  logic [2:0]  sel_d_opcode;
  logic [2:0]  sel_d_param;
  tl_size_t    sel_d_size;
  tl_source_t  sel_d_source;
  tl_sink_t    sel_d_sink;
  tl_data_t    sel_d_data;
  logic        sel_d_denied;
  logic        sel_d_corrupt;
  logic        sel_d_ready;
  
  // Slave selection
  logic [5:0] slave_sel;
  logic       addr_valid;
  
  // Transaction tracking
  logic       cpu_pending, dma_pending;
  logic       cpu_resp_master, dma_resp_master;
  logic [2:0] pending_slave;
  logic       pending_master;
  
  // Error response
  logic       gen_error_resp;
  logic       error_resp_valid;
  
  //==========================================================================
  // Address Decode (inline — no function for synthesis compatibility)
  //==========================================================================
  always_comb begin
    slave_sel = 6'b000000;
    
    // Memory: 0x0000_0000 - 0x0FFF_FFFF
    if ((sel_a_address & ~MEM_MASK) == MEM_BASE)
      slave_sel = 6'b000001;  // Memory
    // Peripherals: 0x1000_0000 - 0x1001_FFFF (includes Switches at 0x1001_0xxx)
    else if ((sel_a_address & PERI_MASK) == PERI_BASE)
      slave_sel = 6'b000010;  // Peripherals (LEDR, LEDG, HEX, LCD, Switches)
    // UART: 0x1002_0000 - 0x1002_FFFF
    else if ((sel_a_address & SLAVE_MASK) == UART_BASE)
      slave_sel = 6'b000100;  // UART
    // DMA: 0x1005_0000 - 0x1005_FFFF
    else if ((sel_a_address & SLAVE_MASK) == DMA_BASE)
      slave_sel = 6'b001000;  // DMA Registers
    // ChaCha20: 0x1006_0000 - 0x1006_FFFF
    else if ((sel_a_address & SLAVE_MASK) == CHACHA_BASE)
      slave_sel = 6'b010000;  // ChaCha20 Crypto
    // Poly1305: 0x1007_0000 - 0x1007_FFFF
    else if ((sel_a_address & SLAVE_MASK) == POLY_BASE)
      slave_sel = 6'b100000;  // Poly1305 MAC
  end

  //==========================================================================
  // Round-Robin Arbitration with Starvation Prevention
  //==========================================================================
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      arb_state      <= ARB_IDLE;
      rr_priority    <= 1'b0;
      starvation_cnt <= 4'd0;
      pending_master <= 1'b0;
      pending_slave  <= 3'd0;
      cpu_pending    <= 1'b0;
      dma_pending    <= 1'b0;
    end else begin
      arb_state <= arb_state_next;
      
      // Track pending transactions
      if (cpu_grant && sel_a_valid && sel_a_ready)
        cpu_pending <= 1'b1;
      else if (o_cpu_d_valid && i_cpu_d_ready)
        cpu_pending <= 1'b0;
        
      if (dma_grant && sel_a_valid && sel_a_ready)
        dma_pending <= 1'b1;
      else if (o_dma_d_valid && i_dma_d_ready)
        dma_pending <= 1'b0;
      
      // Update round-robin priority after each grant
      if ((cpu_grant || dma_grant) && sel_a_valid && sel_a_ready) begin
        rr_priority    <= cpu_grant ? 1'b1 : 1'b0;  // Toggle priority
        starvation_cnt <= 4'd0;
        pending_master <= cpu_grant ? 1'b0 : 1'b1;
        pending_slave  <= slave_sel[5] ? 3'd5 :
                         slave_sel[4] ? 3'd4 :
                         slave_sel[3] ? 3'd3 :
                         slave_sel[2] ? 3'd2 :
                         slave_sel[1] ? 3'd1 : 3'd0;
      end else if ((i_cpu_a_valid || i_dma_a_valid) && !cpu_pending && !dma_pending) begin
        // Increment starvation counter if requests waiting
        if (starvation_cnt < STARVATION_LIMIT)
          starvation_cnt <= starvation_cnt + 4'd1;
      end
    end
  end

  // Arbitration State Machine
  always_comb begin
    arb_state_next = arb_state;
    cpu_grant      = 1'b0;
    dma_grant      = 1'b0;
    
    case (arb_state)
      ARB_IDLE: begin
        // No pending transactions - can grant new request
        if (!cpu_pending && !dma_pending) begin
          if (i_cpu_a_valid && i_dma_a_valid) begin
            // Both requesting - use round-robin with starvation check
            if (starvation_cnt >= STARVATION_LIMIT) begin
              // Force grant to starving master (flip priority)
              cpu_grant = rr_priority;
              dma_grant = !rr_priority;
            end else begin
              // Normal round-robin
              cpu_grant = !rr_priority;
              dma_grant = rr_priority;
            end
          end else if (i_cpu_a_valid) begin
            cpu_grant = 1'b1;
          end else if (i_dma_a_valid) begin
            dma_grant = 1'b1;
          end
          
          if (cpu_grant)
            arb_state_next = ARB_CPU;
          else if (dma_grant)
            arb_state_next = ARB_DMA;
        end
      end
      
      ARB_CPU: begin
        cpu_grant = 1'b1;
        // Wait for response
        if (o_cpu_d_valid && i_cpu_d_ready)
          arb_state_next = ARB_IDLE;
      end
      
      ARB_DMA: begin
        dma_grant = 1'b1;
        // Wait for response
        if (o_dma_d_valid && i_dma_d_ready)
          arb_state_next = ARB_IDLE;
      end
      
      default: arb_state_next = ARB_IDLE;
    endcase
  end

  //==========================================================================
  // Master Multiplexing
  //==========================================================================
  always_comb begin
    sel_master_id = cpu_grant ? 1'b0 : 1'b1;
    
    if (cpu_grant) begin
      sel_a_valid   = i_cpu_a_valid;
      sel_a_opcode  = i_cpu_a_opcode;
      sel_a_param   = i_cpu_a_param;
      sel_a_size    = i_cpu_a_size;
      sel_a_source  = i_cpu_a_source;
      sel_a_address = i_cpu_a_address;
      sel_a_mask    = i_cpu_a_mask;
      sel_a_data    = i_cpu_a_data;
      sel_a_corrupt = i_cpu_a_corrupt;
    end else begin
      sel_a_valid   = i_dma_a_valid;
      sel_a_opcode  = i_dma_a_opcode;
      sel_a_param   = i_dma_a_param;
      sel_a_size    = i_dma_a_size;
      sel_a_source  = i_dma_a_source;
      sel_a_address = i_dma_a_address;
      sel_a_mask    = i_dma_a_mask;
      sel_a_data    = i_dma_a_data;
      sel_a_corrupt = i_dma_a_corrupt;
    end
  end

  // Address decode is now in always_comb block above
  assign addr_valid = |slave_sel;

  //==========================================================================
  // Request Distribution to Slaves
  //==========================================================================
  // Memory
  assign o_mem_a_valid   = sel_a_valid && slave_sel[0];
  assign o_mem_a_opcode  = sel_a_opcode;
  assign o_mem_a_param   = sel_a_param;
  assign o_mem_a_size    = sel_a_size;
  assign o_mem_a_source  = {sel_master_id, sel_a_source[TL_AIW-2:0]};  // Encode master ID
  assign o_mem_a_address = sel_a_address;
  assign o_mem_a_mask    = sel_a_mask;
  assign o_mem_a_data    = sel_a_data;
  assign o_mem_a_corrupt = sel_a_corrupt;

  // Peripherals
  assign o_peri_a_valid   = sel_a_valid && slave_sel[1];
  assign o_peri_a_opcode  = sel_a_opcode;
  assign o_peri_a_param   = sel_a_param;
  assign o_peri_a_size    = sel_a_size;
  assign o_peri_a_source  = {sel_master_id, sel_a_source[TL_AIW-2:0]};
  assign o_peri_a_address = sel_a_address;
  assign o_peri_a_mask    = sel_a_mask;
  assign o_peri_a_data    = sel_a_data;
  assign o_peri_a_corrupt = sel_a_corrupt;

  // UART
  assign o_uart_a_valid   = sel_a_valid && slave_sel[2];
  assign o_uart_a_opcode  = sel_a_opcode;
  assign o_uart_a_param   = sel_a_param;
  assign o_uart_a_size    = sel_a_size;
  assign o_uart_a_source  = {sel_master_id, sel_a_source[TL_AIW-2:0]};
  assign o_uart_a_address = sel_a_address;
  assign o_uart_a_mask    = sel_a_mask;
  assign o_uart_a_data    = sel_a_data;
  assign o_uart_a_corrupt = sel_a_corrupt;

  // DMA Registers
  assign o_dmareg_a_valid   = sel_a_valid && slave_sel[3];
  assign o_dmareg_a_opcode  = sel_a_opcode;
  assign o_dmareg_a_param   = sel_a_param;
  assign o_dmareg_a_size    = sel_a_size;
  assign o_dmareg_a_source  = {sel_master_id, sel_a_source[TL_AIW-2:0]};
  assign o_dmareg_a_address = sel_a_address;
  assign o_dmareg_a_mask    = sel_a_mask;
  assign o_dmareg_a_data    = sel_a_data;
  assign o_dmareg_a_corrupt = sel_a_corrupt;

  // ChaCha20
  assign o_chacha_a_valid   = sel_a_valid && slave_sel[4];
  assign o_chacha_a_opcode  = sel_a_opcode;
  assign o_chacha_a_param   = sel_a_param;
  assign o_chacha_a_size    = sel_a_size;
  assign o_chacha_a_source  = {sel_master_id, sel_a_source[TL_AIW-2:0]};
  assign o_chacha_a_address = sel_a_address;
  assign o_chacha_a_mask    = sel_a_mask;
  assign o_chacha_a_data    = sel_a_data;
  assign o_chacha_a_corrupt = sel_a_corrupt;

  // Poly1305
  assign o_poly_a_valid   = sel_a_valid && slave_sel[5];
  assign o_poly_a_opcode  = sel_a_opcode;
  assign o_poly_a_param   = sel_a_param;
  assign o_poly_a_size    = sel_a_size;
  assign o_poly_a_source  = {sel_master_id, sel_a_source[TL_AIW-2:0]};
  assign o_poly_a_address = sel_a_address;
  assign o_poly_a_mask    = sel_a_mask;
  assign o_poly_a_data    = sel_a_data;
  assign o_poly_a_corrupt = sel_a_corrupt;

  //==========================================================================
  // Ready Signal Multiplexing
  //==========================================================================
  always_comb begin
    sel_a_ready = 1'b0;
    
    if (slave_sel[0])      sel_a_ready = i_mem_a_ready;
    else if (slave_sel[1]) sel_a_ready = i_peri_a_ready;
    else if (slave_sel[2]) sel_a_ready = i_uart_a_ready;
    else if (slave_sel[3]) sel_a_ready = i_dmareg_a_ready;
    else if (slave_sel[4]) sel_a_ready = i_chacha_a_ready;
    else if (slave_sel[5]) sel_a_ready = i_poly_a_ready;
    else                   sel_a_ready = 1'b1;  // Accept for error response
  end

  assign o_cpu_a_ready = cpu_grant ? sel_a_ready : 1'b0;
  assign o_dma_a_ready = dma_grant ? sel_a_ready : 1'b0;

  //==========================================================================
  // Response Multiplexing
  //==========================================================================
  // Combine all slave responses - only one should be valid at a time
  always_comb begin
    sel_d_valid   = 1'b0;
    sel_d_opcode  = 3'd0;
    sel_d_param   = 3'd0;
    sel_d_size    = '0;
    sel_d_source  = '0;
    sel_d_sink    = 1'b0;
    sel_d_data    = 32'd0;
    sel_d_denied  = 1'b0;
    sel_d_corrupt = 1'b0;
    
    if (i_mem_d_valid) begin
      sel_d_valid   = i_mem_d_valid;
      sel_d_opcode  = i_mem_d_opcode;
      sel_d_param   = i_mem_d_param;
      sel_d_size    = i_mem_d_size;
      sel_d_source  = i_mem_d_source;
      sel_d_sink    = i_mem_d_sink;
      sel_d_data    = i_mem_d_data;
      sel_d_denied  = i_mem_d_denied;
      sel_d_corrupt = i_mem_d_corrupt;
    end else if (i_peri_d_valid) begin
      sel_d_valid   = i_peri_d_valid;
      sel_d_opcode  = i_peri_d_opcode;
      sel_d_param   = i_peri_d_param;
      sel_d_size    = i_peri_d_size;
      sel_d_source  = i_peri_d_source;
      sel_d_sink    = i_peri_d_sink;
      sel_d_data    = i_peri_d_data;
      sel_d_denied  = i_peri_d_denied;
      sel_d_corrupt = i_peri_d_corrupt;
    end else if (i_uart_d_valid) begin
      sel_d_valid   = i_uart_d_valid;
      sel_d_opcode  = i_uart_d_opcode;
      sel_d_param   = i_uart_d_param;
      sel_d_size    = i_uart_d_size;
      sel_d_source  = i_uart_d_source;
      sel_d_sink    = i_uart_d_sink;
      sel_d_data    = i_uart_d_data;
      sel_d_denied  = i_uart_d_denied;
      sel_d_corrupt = i_uart_d_corrupt;
    end else if (i_dmareg_d_valid) begin
      sel_d_valid   = i_dmareg_d_valid;
      sel_d_opcode  = i_dmareg_d_opcode;
      sel_d_param   = i_dmareg_d_param;
      sel_d_size    = i_dmareg_d_size;
      sel_d_source  = i_dmareg_d_source;
      sel_d_sink    = i_dmareg_d_sink;
      sel_d_data    = i_dmareg_d_data;
      sel_d_denied  = i_dmareg_d_denied;
      sel_d_corrupt = i_dmareg_d_corrupt;
    end else if (i_chacha_d_valid) begin
      sel_d_valid   = i_chacha_d_valid;
      sel_d_opcode  = i_chacha_d_opcode;
      sel_d_param   = i_chacha_d_param;
      sel_d_size    = i_chacha_d_size;
      sel_d_source  = i_chacha_d_source;
      sel_d_sink    = i_chacha_d_sink;
      sel_d_data    = i_chacha_d_data;
      sel_d_denied  = i_chacha_d_denied;
      sel_d_corrupt = i_chacha_d_corrupt;
    end else if (i_poly_d_valid) begin
      sel_d_valid   = i_poly_d_valid;
      sel_d_opcode  = i_poly_d_opcode;
      sel_d_param   = i_poly_d_param;
      sel_d_size    = i_poly_d_size;
      sel_d_source  = i_poly_d_source;
      sel_d_sink    = i_poly_d_sink;
      sel_d_data    = i_poly_d_data;
      sel_d_denied  = i_poly_d_denied;
      sel_d_corrupt = i_poly_d_corrupt;
    end else if (error_resp_valid) begin
      // Error response for invalid address
      sel_d_valid   = 1'b1;
      sel_d_opcode  = AccessAck;
      sel_d_param   = 3'd0;
      sel_d_size    = sel_a_size;
      sel_d_source  = {sel_master_id, sel_a_source[TL_AIW-2:0]};
      sel_d_sink    = 1'b0;
      sel_d_data    = 32'hDEAD_BEEF;
      sel_d_denied  = 1'b1;
      sel_d_corrupt = 1'b0;
    end
  end

  // Route response to correct master based on source[MSB]
  wire resp_to_dma = sel_d_source[TL_AIW-1];
  
  // CPU Response
  assign o_cpu_d_valid   = sel_d_valid && !resp_to_dma;
  assign o_cpu_d_opcode  = sel_d_opcode;
  assign o_cpu_d_param   = sel_d_param;
  assign o_cpu_d_size    = sel_d_size;
  assign o_cpu_d_source  = {1'b0, sel_d_source[TL_AIW-2:0]};  // Strip master ID
  assign o_cpu_d_sink    = sel_d_sink;
  assign o_cpu_d_data    = sel_d_data;
  assign o_cpu_d_denied  = sel_d_denied;
  assign o_cpu_d_corrupt = sel_d_corrupt;

  // DMA Response
  assign o_dma_d_valid   = sel_d_valid && resp_to_dma;
  assign o_dma_d_opcode  = sel_d_opcode;
  assign o_dma_d_param   = sel_d_param;
  assign o_dma_d_size    = sel_d_size;
  assign o_dma_d_source  = {1'b0, sel_d_source[TL_AIW-2:0]};
  assign o_dma_d_sink    = sel_d_sink;
  assign o_dma_d_data    = sel_d_data;
  assign o_dma_d_denied  = sel_d_denied;
  assign o_dma_d_corrupt = sel_d_corrupt;

  //==========================================================================
  // D-channel Ready Routing
  //==========================================================================
  assign sel_d_ready = resp_to_dma ? i_dma_d_ready : i_cpu_d_ready;
  
  assign o_mem_d_ready    = sel_d_ready && i_mem_d_valid;
  assign o_peri_d_ready   = sel_d_ready && i_peri_d_valid;
  assign o_uart_d_ready   = sel_d_ready && i_uart_d_valid;
  assign o_dmareg_d_ready = sel_d_ready && i_dmareg_d_valid;
  assign o_chacha_d_ready = sel_d_ready && i_chacha_d_valid;
  assign o_poly_d_ready   = sel_d_ready && i_poly_d_valid;

  //==========================================================================
  // Error Response Generation
  //==========================================================================
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      error_resp_valid <= 1'b0;
    end else begin
      if (sel_a_valid && !addr_valid && sel_a_ready) begin
        error_resp_valid <= 1'b1;
      end else if (error_resp_valid && sel_d_ready) begin
        error_resp_valid <= 1'b0;
      end
    end
  end

endmodule
