module tlul_xbar_3s
  import tlul_pkg::*;
(
  // Clock and Reset
  input logic i_clk,
  input logic i_rst_n,

  // Channel A: Master -> Crossbar
  input logic i_tl_a_valid,
  input logic [2:0] i_tl_a_opcode,
  input logic [2:0] i_tl_a_param,
  input tl_size_t i_tl_a_size,
  input tl_source_t i_tl_a_source,
  input tl_addr_t i_tl_a_address,
  input tl_mask_t i_tl_a_mask,
  input tl_data_t i_tl_a_data,
  input logic i_tl_a_corrupt,
  output logic o_tl_a_ready,

  // Channel D: Crossbar -> Master
  output logic o_tl_d_valid,
  output logic [2:0] o_tl_d_opcode,
  output logic [2:0] o_tl_d_param,
  output tl_size_t o_tl_d_size,
  output tl_source_t o_tl_d_source,
  output tl_sink_t o_tl_d_sink,
  output tl_data_t o_tl_d_data,
  output logic o_tl_d_denied,
  output logic o_tl_d_corrupt,
  input logic i_tl_d_ready,

  // Memory Interface
  output logic o_mem_a_valid,
  output logic [2:0] o_mem_a_opcode,
  output logic [2:0] o_mem_a_param,
  output tl_size_t o_mem_a_size,
  output tl_source_t o_mem_a_source,
  output tl_addr_t o_mem_a_address,
  output tl_mask_t o_mem_a_mask,
  output tl_data_t o_mem_a_data,
  output logic o_mem_a_corrupt,
  input logic i_mem_a_ready,

  input logic i_mem_d_valid,
  input logic [2:0] i_mem_d_opcode,
  input logic [2:0] i_mem_d_param,
  input tl_size_t i_mem_d_size,
  input tl_source_t i_mem_d_source,
  input tl_sink_t i_mem_d_sink,
  input tl_data_t i_mem_d_data,
  input logic i_mem_d_denied,
  input logic i_mem_d_corrupt,
  output logic o_mem_d_ready,

  // Peripheral Interface
  output logic o_peri_a_valid,
  output logic [2:0] o_peri_a_opcode,
  output logic [2:0] o_peri_a_param,
  output tl_size_t o_peri_a_size,
  output tl_source_t o_peri_a_source,
  output tl_addr_t o_peri_a_address,
  output tl_mask_t o_peri_a_mask,
  output tl_data_t o_peri_a_data,
  output logic o_peri_a_corrupt,
  input logic i_peri_a_ready,

  input logic i_peri_d_valid,
  input logic [2:0] i_peri_d_opcode,
  input logic [2:0] i_peri_d_param,
  input tl_size_t i_peri_d_size,
  input tl_source_t i_peri_d_source,
  input tl_sink_t i_peri_d_sink,
  input tl_data_t i_peri_d_data,
  input logic i_peri_d_denied,
  input logic i_peri_d_corrupt,
  output logic o_peri_d_ready,

  // UART Interface
  output logic o_uart_a_valid,
  output logic [2:0] o_uart_a_opcode,
  output logic [2:0] o_uart_a_param,
  output tl_size_t o_uart_a_size,
  output tl_source_t o_uart_a_source,
  output tl_addr_t o_uart_a_address,
  output tl_mask_t o_uart_a_mask,
  output tl_data_t o_uart_a_data,
  output logic o_uart_a_corrupt,
  input logic i_uart_a_ready,

  input logic i_uart_d_valid,
  input logic [2:0] i_uart_d_opcode,
  input logic [2:0] i_uart_d_param,
  input tl_size_t i_uart_d_size,
  input tl_source_t i_uart_d_source,
  input tl_sink_t i_uart_d_sink,
  input tl_data_t i_uart_d_data,
  input logic i_uart_d_denied,
  input logic i_uart_d_corrupt,
  output logic o_uart_d_ready
);

  localparam logic [31:0] MEM_BASE   = 32'h0000_0000;
  localparam logic [31:0] MEM_SIZE   = 32'h0001_0000;  // 64KB (0x0000_0000 - 0x0000_FFFF)

  // Peripheral IO address ranges (4KB each)
  localparam logic [31:0] LEDR_BASE  = 32'h1000_0000;  // Red LEDs
  localparam logic [31:0] LEDG_BASE  = 32'h1000_1000;  // Green LEDs
  localparam logic [31:0] HEX0_BASE  = 32'h1000_2000;  // Seven-seg 3-0
  localparam logic [31:0] HEX4_BASE  = 32'h1000_3000;  // Seven-seg 7-4
  localparam logic [31:0] LCD_BASE   = 32'h1000_4000;  // LCD
  localparam logic [31:0] SW_BASE    = 32'h1001_0000;  // Switches
  localparam logic [31:0] PERI_SIZE  = 32'h0000_1000;  // Each peripheral has 4KB range
  localparam logic [31:0] UART_BASE  = 32'h1002_0000;
  localparam logic [31:0] UART_SIZE  = 32'h0000_0100;  // 256B

  // Slave selection encoding
  typedef enum logic [1:0] {
    SEL_MEM   = 2'b00,
    SEL_PERI  = 2'b01,
    SEL_UART  = 2'b10,
    SEL_ERROR = 2'b11
  } slave_sel_t;

  slave_sel_t addr_sel;

  logic is_peri_io;
  assign is_peri_io = ((i_tl_a_address >= LEDR_BASE) && (i_tl_a_address < LEDR_BASE + PERI_SIZE)) ||  // Red LEDs
                      ((i_tl_a_address >= LEDG_BASE) && (i_tl_a_address < LEDG_BASE + PERI_SIZE)) ||  // Green LEDs
                      ((i_tl_a_address >= HEX0_BASE) && (i_tl_a_address < HEX0_BASE + PERI_SIZE)) ||  // HEX0-3
                      ((i_tl_a_address >= HEX4_BASE) && (i_tl_a_address < HEX4_BASE + PERI_SIZE)) ||  // HEX4-7
                      ((i_tl_a_address >= LCD_BASE)  && (i_tl_a_address < LCD_BASE + PERI_SIZE))  ||  // LCD
                      ((i_tl_a_address >= SW_BASE)   && (i_tl_a_address < SW_BASE + PERI_SIZE));      // Switches

  slave_sel_t source_table_q [2**TL_AIW];

  logic [1:0] rr_priority_q;

  // Address Decode Logic
  always_comb begin
    addr_sel = SEL_ERROR;

    // UART range (0x1002_0000 - 0x1002_00FF)
    if ((i_tl_a_address >= UART_BASE) && (i_tl_a_address < (UART_BASE + UART_SIZE))) begin
      addr_sel = SEL_UART;
    end else if (is_peri_io) begin
      // Peripheral IO (0x1000_0000 - 0x1001_0FFF)
      addr_sel = SEL_PERI;
    end else if ((i_tl_a_address >= MEM_BASE) && (i_tl_a_address < (MEM_BASE + MEM_SIZE))) begin
      // Memory range (0x0000_0000 - 0x0000_FFFF, 64KB)
      addr_sel = SEL_MEM;
    end
  end

  // Source Table Update
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      for (int i = 0; i < 2**TL_AIW; i++) begin
        source_table_q[i] <= SEL_ERROR;
      end
    end else if (i_tl_a_valid && o_tl_a_ready) begin
      source_table_q[i_tl_a_source] <= addr_sel;
    end
  end

  // Round-Robin Priority Update
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      rr_priority_q <= 2'b00;
    end else if (o_tl_d_valid && i_tl_d_ready) begin
      rr_priority_q <= (rr_priority_q == 2'b10) ? 2'b00 : rr_priority_q + 1'b1;
    end
  end

  // Request Routing
  always_comb begin
    o_mem_a_valid   = 1'b0;
    o_mem_a_opcode  = 3'b0;
    o_mem_a_param   = 3'b0;
    o_mem_a_size    = 3'b0;
    o_mem_a_source  = '0;
    o_mem_a_address = '0;
    o_mem_a_mask    = '0;
    o_mem_a_data    = '0;
    o_mem_a_corrupt = 1'b0;

    o_peri_a_valid   = 1'b0;
    o_peri_a_opcode  = 3'b0;
    o_peri_a_param   = 3'b0;
    o_peri_a_size    = 3'b0;
    o_peri_a_source  = '0;
    o_peri_a_address = '0;
    o_peri_a_mask    = '0;
    o_peri_a_data    = '0;
    o_peri_a_corrupt = 1'b0;

    o_uart_a_valid   = 1'b0;
    o_uart_a_opcode  = 3'b0;
    o_uart_a_param   = 3'b0;
    o_uart_a_size    = 3'b0;
    o_uart_a_source  = '0;
    o_uart_a_address = '0;
    o_uart_a_mask    = '0;
    o_uart_a_data    = '0;
    o_uart_a_corrupt = 1'b0;

    case (addr_sel)
      SEL_MEM: begin
        o_mem_a_valid   = i_tl_a_valid;
        o_mem_a_opcode  = i_tl_a_opcode;
        o_mem_a_param   = i_tl_a_param;
        o_mem_a_size    = i_tl_a_size;
        o_mem_a_source  = i_tl_a_source;
        o_mem_a_address = i_tl_a_address;
        o_mem_a_mask    = i_tl_a_mask;
        o_mem_a_data    = i_tl_a_data;
        o_mem_a_corrupt = i_tl_a_corrupt;
      end
      SEL_PERI: begin
        o_peri_a_valid   = i_tl_a_valid;
        o_peri_a_opcode  = i_tl_a_opcode;
        o_peri_a_param   = i_tl_a_param;
        o_peri_a_size    = i_tl_a_size;
        o_peri_a_source  = i_tl_a_source;
        o_peri_a_address = i_tl_a_address;
        o_peri_a_mask    = i_tl_a_mask;
        o_peri_a_data    = i_tl_a_data;
        o_peri_a_corrupt = i_tl_a_corrupt;
      end
      SEL_UART: begin
        o_uart_a_valid   = i_tl_a_valid;
        o_uart_a_opcode  = i_tl_a_opcode;
        o_uart_a_param   = i_tl_a_param;
        o_uart_a_size    = i_tl_a_size;
        o_uart_a_source  = i_tl_a_source;
        o_uart_a_address = i_tl_a_address;
        o_uart_a_mask    = i_tl_a_mask;
        o_uart_a_data    = i_tl_a_data;
        o_uart_a_corrupt = i_tl_a_corrupt;
      end
      default: ;
    endcase
  end

  //error response fsm
  typedef enum logic {
    ERR_IDLE    = 1'b0,
    ERR_RESPOND = 1'b1
  } err_state_t;

  err_state_t err_state_q, err_state_d;
  logic [2:0] err_opcode_q, err_size_q;
  logic [TL_AIW-1:0] err_source_q;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      err_state_q  <= ERR_IDLE;
      err_opcode_q <= 3'b0;
      err_size_q   <= 3'b0;
      err_source_q <= '0;
    end else begin
      err_state_q <= err_state_d;
      if (err_state_q == ERR_IDLE && i_tl_a_valid && addr_sel == SEL_ERROR) begin
        err_opcode_q <= i_tl_a_opcode;
        err_size_q   <= i_tl_a_size;
        err_source_q <= i_tl_a_source;
      end
    end
  end

  always_comb begin
    err_state_d = err_state_q;
    case (err_state_q)
      ERR_IDLE: begin
        if (i_tl_a_valid && addr_sel == SEL_ERROR)
          err_state_d = ERR_RESPOND;
      end
      ERR_RESPOND: begin
        if (i_tl_d_ready)
          err_state_d = ERR_IDLE;
      end
    endcase
  end
  always_comb begin
    case (addr_sel)
      SEL_MEM:   o_tl_a_ready = i_mem_a_ready;
      SEL_PERI:  o_tl_a_ready = i_peri_a_ready;
      SEL_UART:  o_tl_a_ready = i_uart_a_ready;
      default:   o_tl_a_ready = (err_state_q == ERR_IDLE);
    endcase
  end

  // channel D response routinng
  slave_sel_t mem_expected, peri_expected, uart_expected;
  logic mem_valid_ok, peri_valid_ok, uart_valid_ok;

  always_comb begin
    mem_expected  = i_mem_d_valid  ? source_table_q[i_mem_d_source]  : SEL_ERROR;
    peri_expected = i_peri_d_valid ? source_table_q[i_peri_d_source] : SEL_ERROR;
    uart_expected = i_uart_d_valid ? source_table_q[i_uart_d_source] : SEL_ERROR;
    
    mem_valid_ok  = i_mem_d_valid  && (mem_expected  == SEL_MEM);
    peri_valid_ok = i_peri_d_valid && (peri_expected == SEL_PERI);
    uart_valid_ok = i_uart_d_valid && (uart_expected == SEL_UART);
  end

  always_comb begin
    o_tl_d_valid   = 1'b0;
    o_tl_d_opcode  = TL_D_ACCESS_ACK;
    o_tl_d_param   = 3'b0;
    o_tl_d_size    = 3'b0;
    o_tl_d_source  = '0;
    o_tl_d_sink    = 1'b0;
    o_tl_d_data    = '0;
    o_tl_d_denied  = 1'b0;
    o_tl_d_corrupt = 1'b0;
    
    o_mem_d_ready  = 1'b0;
    o_peri_d_ready = 1'b0;
    o_uart_d_ready = 1'b0;
    
    // Error response has highest priority
    if (err_state_q == ERR_RESPOND) begin
      o_tl_d_valid  = 1'b1;
      o_tl_d_opcode = (err_opcode_q == TL_A_GET) ? TL_D_ACCESS_ACK_DATA : TL_D_ACCESS_ACK;
      o_tl_d_size   = err_size_q;
      o_tl_d_source = err_source_q;
      o_tl_d_denied = 1'b1;
    end else begin
      case (rr_priority_q)
        2'b00: begin // MEM > PERI > UART
          if (mem_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_mem_d_opcode;
            o_tl_d_param   = i_mem_d_param;
            o_tl_d_size    = i_mem_d_size;
            o_tl_d_source  = i_mem_d_source;
            o_tl_d_sink    = i_mem_d_sink;
            o_tl_d_data    = i_mem_d_data;
            o_tl_d_denied  = i_mem_d_denied;
            o_tl_d_corrupt = i_mem_d_corrupt;
            o_mem_d_ready  = i_tl_d_ready;
          end else if (peri_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_peri_d_opcode;
            o_tl_d_param   = i_peri_d_param;
            o_tl_d_size    = i_peri_d_size;
            o_tl_d_source  = i_peri_d_source;
            o_tl_d_sink    = i_peri_d_sink;
            o_tl_d_data    = i_peri_d_data;
            o_tl_d_denied  = i_peri_d_denied;
            o_tl_d_corrupt = i_peri_d_corrupt;
            o_peri_d_ready = i_tl_d_ready;
          end else if (uart_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_uart_d_opcode;
            o_tl_d_param   = i_uart_d_param;
            o_tl_d_size    = i_uart_d_size;
            o_tl_d_source  = i_uart_d_source;
            o_tl_d_sink    = i_uart_d_sink;
            o_tl_d_data    = i_uart_d_data;
            o_tl_d_denied  = i_uart_d_denied;
            o_tl_d_corrupt = i_uart_d_corrupt;
            o_uart_d_ready = i_tl_d_ready;
          end
        end
        
        2'b01: begin // PERI > UART > MEM
          if (peri_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_peri_d_opcode;
            o_tl_d_param   = i_peri_d_param;
            o_tl_d_size    = i_peri_d_size;
            o_tl_d_source  = i_peri_d_source;
            o_tl_d_sink    = i_peri_d_sink;
            o_tl_d_data    = i_peri_d_data;
            o_tl_d_denied  = i_peri_d_denied;
            o_tl_d_corrupt = i_peri_d_corrupt;
            o_peri_d_ready = i_tl_d_ready;
          end else if (uart_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_uart_d_opcode;
            o_tl_d_param   = i_uart_d_param;
            o_tl_d_size    = i_uart_d_size;
            o_tl_d_source  = i_uart_d_source;
            o_tl_d_sink    = i_uart_d_sink;
            o_tl_d_data    = i_uart_d_data;
            o_tl_d_denied  = i_uart_d_denied;
            o_tl_d_corrupt = i_uart_d_corrupt;
            o_uart_d_ready = i_tl_d_ready;
          end else if (mem_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_mem_d_opcode;
            o_tl_d_param   = i_mem_d_param;
            o_tl_d_size    = i_mem_d_size;
            o_tl_d_source  = i_mem_d_source;
            o_tl_d_sink    = i_mem_d_sink;
            o_tl_d_data    = i_mem_d_data;
            o_tl_d_denied  = i_mem_d_denied;
            o_tl_d_corrupt = i_mem_d_corrupt;
            o_mem_d_ready  = i_tl_d_ready;
          end
        end
        
        default: begin // UART > MEM > PERI (2'b10, 2'b11)
          if (uart_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_uart_d_opcode;
            o_tl_d_param   = i_uart_d_param;
            o_tl_d_size    = i_uart_d_size;
            o_tl_d_source  = i_uart_d_source;
            o_tl_d_sink    = i_uart_d_sink;
            o_tl_d_data    = i_uart_d_data;
            o_tl_d_denied  = i_uart_d_denied;
            o_tl_d_corrupt = i_uart_d_corrupt;
            o_uart_d_ready = i_tl_d_ready;
          end else if (mem_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_mem_d_opcode;
            o_tl_d_param   = i_mem_d_param;
            o_tl_d_size    = i_mem_d_size;
            o_tl_d_source  = i_mem_d_source;
            o_tl_d_sink    = i_mem_d_sink;
            o_tl_d_data    = i_mem_d_data;
            o_tl_d_denied  = i_mem_d_denied;
            o_tl_d_corrupt = i_mem_d_corrupt;
            o_mem_d_ready  = i_tl_d_ready;
          end else if (peri_valid_ok) begin
            o_tl_d_valid   = 1'b1;
            o_tl_d_opcode  = i_peri_d_opcode;
            o_tl_d_param   = i_peri_d_param;
            o_tl_d_size    = i_peri_d_size;
            o_tl_d_source  = i_peri_d_source;
            o_tl_d_sink    = i_peri_d_sink;
            o_tl_d_data    = i_peri_d_data;
            o_tl_d_denied  = i_peri_d_denied;
            o_tl_d_corrupt = i_peri_d_corrupt;
            o_peri_d_ready = i_tl_d_ready;
          end
        end
      endcase
    end
  end

endmodule
