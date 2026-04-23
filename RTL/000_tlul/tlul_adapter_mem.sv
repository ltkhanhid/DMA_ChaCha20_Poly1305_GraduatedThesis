module tlul_adapter_mem
  import tlul_pkg::*;
#(
  parameter int unsigned DEPTH = 32768  // Memory depth in bytes
)(
  input  logic i_clk,
  input  logic i_rst_n,
  
  input  logic i_tl_a_valid,
  input  logic [2:0] i_tl_a_opcode,
  input  logic [2:0] i_tl_a_param,
  input  tl_size_t i_tl_a_size,
  input  tl_source_t i_tl_a_source,
  input  tl_addr_t i_tl_a_address,
  input  tl_mask_t i_tl_a_mask,
  input  tl_data_t i_tl_a_data,
  input  logic i_tl_a_corrupt,
  output logic o_tl_a_ready,     // Slave ->Master
  
  output logic o_tl_d_valid,
  output logic [2:0] o_tl_d_opcode,
  output logic [2:0] o_tl_d_param,
  output tl_size_t o_tl_d_size,
  output tl_source_t o_tl_d_source,
  output tl_sink_t o_tl_d_sink,
  output tl_data_t o_tl_d_data,
  output logic o_tl_d_denied,
  output logic o_tl_d_corrupt,
  input  logic i_tl_d_ready      // Master ->Slave
);

  
  
  typedef enum logic [1:0] {
    IDLE      = 2'b00,  // Chờ request
    RESPOND   = 2'b10   // Gửi response (PROCESS removed: mem read starts in IDLE)
  } state_t;
  
  state_t state_q, state_d;
  
  // Latch request info
  logic [2:0] opcode_q;
  logic [2:0] size_q;
  logic [TL_AIW-1:0] source_q;
  logic is_read_q;
  logic corrupt_q;
  logic [$clog2(DEPTH)-1:0] addr_q;  // Latched address
  logic [31:0] wdata_q;              // Latched write data
  logic [3:0] bmask_q;               // Latched byte mask
  
  // Memory interface signals
  logic [$clog2(DEPTH)-1:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [3:0] mem_bmask;
  logic mem_we;
  logic [31:0] mem_rdata;
  logic [31:0] mem_rdata_next;
  
  memory #(
    .DEPTH(DEPTH)
  ) u_memory (
    .i_clk        (i_clk),
    .i_addr       (mem_addr),
    .i_wdata      (mem_wdata),
    .i_bmask      (mem_bmask),
    .i_wren       (mem_we),
    .o_rdata      (mem_rdata),
    .o_rdata_next (mem_rdata_next)
  );
  
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end
   
  // FSM Next State Logic (2-state: skip PROCESS)
  // Memory read starts in IDLE (synchronous read: o_rdata valid next cycle = RESPOND)
  // Memory write executes at IDLE posedge when handshake accepted
  always_comb begin
    state_d = state_q;
    
    case (state_q)
      IDLE: begin
        if (i_tl_a_valid && o_tl_a_ready) begin
          state_d = RESPOND;  // Skip PROCESS: 1 less stall cycle per mem op
        end
      end
      
      RESPOND: begin
        if (o_tl_d_valid && i_tl_d_ready) begin
          state_d = IDLE;
        end
      end
      default: state_d = IDLE;
    endcase
  end
  
  
  // Latch Request
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      opcode_q  <= '0;
      size_q    <= '0;
      source_q  <= '0;
      is_read_q <= 1'b0;
      corrupt_q <= 1'b0;
      addr_q    <= '0;
      wdata_q   <= '0;
      bmask_q   <= '0;
    end else if (state_q == IDLE && i_tl_a_valid && o_tl_a_ready) begin
      opcode_q  <= i_tl_a_opcode;
      size_q    <= i_tl_a_size;
      source_q  <= i_tl_a_source;
      is_read_q <= (i_tl_a_opcode == Get);
      corrupt_q <= i_tl_a_corrupt;
      addr_q    <= i_tl_a_address[$clog2(DEPTH)-1:0];
      wdata_q   <= i_tl_a_data;
      bmask_q   <= i_tl_a_mask;
    end
  end
  
  
  // Memory Control Signals
  // In IDLE: use direct input so memory begins reading immediately
  // In RESPOND: use latched values
  assign mem_addr  = (state_q == IDLE) ? i_tl_a_address[$clog2(DEPTH)-1:0] : addr_q;
  assign mem_wdata = (state_q == IDLE) ? i_tl_a_data : wdata_q;
  assign mem_bmask = (state_q == IDLE) ? i_tl_a_mask : bmask_q;
  
  // Write executes in IDLE (handshake cycle) - synchronous write on same posedge
  assign mem_we = (state_q == IDLE) && i_tl_a_valid && (i_tl_a_opcode != Get);
  
  
  // Channel A ready
  assign o_tl_a_ready = (state_q == IDLE);

  // D response Logic
  always_comb begin
    o_tl_d_valid   = 1'b0;
    o_tl_d_opcode  = AccessAck;
    o_tl_d_param   = 3'b0;
    o_tl_d_size    = size_q;
    o_tl_d_source  = source_q;
    o_tl_d_sink    = 1'b0;
    o_tl_d_data    = mem_rdata;
    o_tl_d_denied  = 1'b0;
    o_tl_d_corrupt = corrupt_q; 
    
    if (state_q == RESPOND) begin
      o_tl_d_valid = 1'b1;
      
      // Opcode phụ thuộc vào loại operation
      if (is_read_q) begin
        o_tl_d_opcode = AccessAckData;  // Read ->trả data
        o_tl_d_data   = mem_rdata;
      end else begin
        o_tl_d_opcode = AccessAck;      // Write ->chỉ ACK
        o_tl_d_data   = '0;
      end
    end
  end

endmodule
