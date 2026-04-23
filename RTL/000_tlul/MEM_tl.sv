module MEM_tl 
  import tlul_pkg::*;
(
  input  logic i_clk,
  input  logic i_rst_n,
  
  input  logic [31:0] i_pc,
  input  logic [31:0] i_instr,
  input  logic [31:0] i_alu_data,       // Address for Load/Store
  input  logic [31:0] i_rs2_data,       // Store data
  
  // Control signals
  input  logic i_rd_wren,
  input  logic i_lsu_wren,       // 1=Store, 0=Load
  input  logic [1:0]  i_wb_sel,
  input  logic [3:0]  i_byte_num,
  
  output logic o_lsu_stall,      // Stall signal to pipeline
  output logic [31:0] o_pc_plus_4,
  output logic [31:0] o_ld_data,        // Load data to WB stage
  output logic [1:0]  o_wb_sel,         // Pass wb_sel to WB stage
  
  // TileLink Master Port
  output logic o_tl_a_valid,
  output logic [2:0] o_tl_a_opcode,
  output logic [2:0] o_tl_a_param,
  output tl_size_t   o_tl_a_size,
  output tl_source_t o_tl_a_source,
  output tl_addr_t   o_tl_a_address,
  output tl_mask_t   o_tl_a_mask,
  output tl_data_t   o_tl_a_data,
  output logic o_tl_a_corrupt,
  input  logic i_tl_a_ready,
  
  input  logic i_tl_d_valid,
  input  logic [2:0] i_tl_d_opcode,
  input  logic [2:0] i_tl_d_param,
  input  tl_size_t   i_tl_d_size,
  input  tl_source_t i_tl_d_source,
  input  tl_sink_t   i_tl_d_sink,
  input  tl_data_t   i_tl_d_data,
  input  logic i_tl_d_denied,
  input  logic i_tl_d_corrupt,
  output logic o_tl_d_ready
);

  // 1. Decode Instruction Type
  logic is_load, is_store, is_mem_op;
  assign is_load  = (i_instr[6:0] == 7'b0000011);  // Load instructions
  assign is_store = (i_instr[6:0] == 7'b0100011);  // Store instructions
  assign is_mem_op = is_load || is_store;
  
  // Internal signals for LSU Handshake
  logic lsu_req_valid;
  logic lsu_req_ready;
  logic lsu_resp_valid;
  logic [31:0] lsu_resp_rdata;
  logic lsu_resp_err;
  
  // Internal signals for Data Formatting
  logic [3:0]  lsu_be;
  logic [2:0]  lsu_size;
  logic [31:0] lsu_wdata;
  logic [1:0]  addr_off;
  
  assign addr_off = i_alu_data[1:0];

  // Calculate PC+4
  PCplus4 u_PCplus4 (
    .PCout   (i_pc),
    .PCplus4 (o_pc_plus_4)
  );

  // 2. Logic tạo Mask và Data cho Store/Load (Combinational)
  always_comb begin
    lsu_wdata = i_rs2_data;
    lsu_size  = 3'd2;  // Default: word
    lsu_be    = 4'b1111;
    
    if (is_store) begin
      // Store operations: Shift data to correct byte lane and set Byte Enable (Mask)
      case (i_byte_num)
        // Store Byte (sb)
        4'b0001: begin
          lsu_size = 3'd0;
          case (addr_off)
            2'b00: begin lsu_wdata = {24'b0, i_rs2_data[7:0]};       lsu_be = 4'b0001; end
            2'b01: begin lsu_wdata = {16'b0, i_rs2_data[7:0], 8'b0}; lsu_be = 4'b0010; end
            2'b10: begin lsu_wdata = {8'b0, i_rs2_data[7:0], 16'b0}; lsu_be = 4'b0100; end
            2'b11: begin lsu_wdata = {i_rs2_data[7:0], 24'b0};       lsu_be = 4'b1000; end
          endcase
        end
        
        // Store Halfword (sh)
        4'b0011: begin
          lsu_size = 3'd1;
          case (addr_off)
            2'b00: begin lsu_wdata = {16'b0, i_rs2_data[15:0]};      lsu_be = 4'b0011; end
            2'b01: begin lsu_wdata = {8'b0, i_rs2_data[15:0], 8'b0}; lsu_be = 4'b0110; end
            2'b10: begin lsu_wdata = {i_rs2_data[15:0], 16'b0};      lsu_be = 4'b1100; end
            2'b11: begin lsu_wdata = {i_rs2_data[7:0], 24'b0};       lsu_be = 4'b1000; end // Unaligned handling (simplified)
          endcase
        end
        
        // Store Word (sw)
        4'b1111: begin
          lsu_size  = 3'd2;
          lsu_wdata = i_rs2_data;
          lsu_be    = 4'b1111;
        end
        
        default: begin lsu_size = 3'd2; lsu_be = 4'b1111; end
      endcase
    end else begin
      // Load operations: Just set the size
      case (i_byte_num)
        4'b0001, 4'b0100: begin lsu_size = 3'd0; lsu_be = 4'b1111; end // lb, lbu
        4'b0011, 4'b0101: begin lsu_size = 3'd1; lsu_be = 4'b1111; end // lh, lhu
        4'b1111:          begin lsu_size = 3'd2; lsu_be = 4'b1111; end // lw
        default:          begin lsu_size = 3'd2; lsu_be = 4'b1111; end
      endcase
    end
  end

  // 3. Request Tracking State Machine
  logic waiting_for_response;  // True when request sent, waiting for response
  logic request_completed;     // True when this instruction's request is done
  logic [31:0] last_pc;        // Track PC to detect new instruction
  logic [3:0] byte_num_q;      // Latched byte_num for load formatting
  logic [1:0] addr_off_q;      // Latched addr offset for load shift
  logic data_ready;            // Flag indicating load data is registered and ready for WB
  logic transaction_done;      // Combinational: transaction finished this cycle
  logic error_response;        // Combinational: error response (alignment error, etc)
  
  // Detect new instruction
  logic new_instruction;
  assign new_instruction = (i_pc != last_pc);
  
  // Detect error response: response valid with error flag, AND we sent a request
  // This handles alignment errors which return immediately
  assign error_response = lsu_resp_valid && lsu_resp_err;
  
  // Detect transaction completion (combinational)
  // Normal completion: waiting for response and got valid response
  // Error completion: sent request and got error response immediately
  assign transaction_done = (waiting_for_response && lsu_resp_valid) ||
                           (lsu_req_valid && error_response);
  
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      waiting_for_response <= 1'b0;
      request_completed    <= 1'b0;
      data_ready           <= 1'b0;
      last_pc              <= 32'hFFFFFFFF;
      byte_num_q           <= 4'b0;
      addr_off_q           <= 2'b0;
    end else begin
      // State: START REQUEST
      // When request is accepted (handshake valid & ready), mark as waiting
      // But NOT if we got an immediate error response (alignment error)
      if (is_mem_op && lsu_req_valid && lsu_req_ready && !error_response) begin
        waiting_for_response <= 1'b1;
        data_ready           <= 1'b0;
        // Latch control info needed for processing the response later
        byte_num_q           <= i_byte_num;
        addr_off_q           <= addr_off;
      end
      
      // State: RESPONSE ARRIVED (normal or error)
      if (transaction_done) begin
        waiting_for_response <= 1'b0;
        request_completed    <= 1'b1;
        if (is_load && !lsu_resp_err) begin
          data_ready <= 1'b1;
        end
      end
      
      // Clear flags when instruction advances (PC changes and not stalled)
      // This happens when instruction moves from MEM to WB
      if (new_instruction && !o_lsu_stall) begin
        data_ready        <= 1'b0;
        request_completed <= 1'b0;
        last_pc           <= i_pc;
      end
    end
  end
  
  // Valid logic: Send request only if it's a Mem Op AND we are not waiting/done
  assign lsu_req_valid = is_mem_op && !waiting_for_response && !request_completed;

  always_comb begin
      o_lsu_stall = 1'b0;

      if (is_mem_op) begin
          // Default: stall when memory operation is in MEM stage
          o_lsu_stall = 1'b1;

          if (request_completed) begin
              o_lsu_stall = 1'b0;
          end
      end
  end
  
  // 5. Load Data Processing (Shift & Extend)
  logic [31:0] rdata_shifted;
  logic [31:0] ld_data_raw;
  logic [31:0] ld_data_latched; 
  
  // Use saved control signals if we are processing a delayed response
  logic [3:0] byte_num_use;
  logic [1:0] addr_off_use;
  assign byte_num_use = (waiting_for_response || request_completed) ? byte_num_q : i_byte_num;
  assign addr_off_use = (waiting_for_response || request_completed) ? addr_off_q : addr_off;
  
  always_comb begin
    rdata_shifted = lsu_resp_rdata >> {addr_off_use, 3'b000};
    
    case (byte_num_use)
      4'b0001: ld_data_raw = {{24{rdata_shifted[7]}}, rdata_shifted[7:0]};    // LB
      4'b0011: ld_data_raw = {{16{rdata_shifted[15]}}, rdata_shifted[15:0]};  // LH
      4'b0100: ld_data_raw = {24'b0, rdata_shifted[7:0]};                     // LBU
      4'b0101: ld_data_raw = {16'b0, rdata_shifted[15:0]};                    // LHU
      4'b1111: ld_data_raw = rdata_shifted;                                   // LW
      default: ld_data_raw = 32'b0;
    endcase
  end
  
  // 6. Data Latch (To hold data for next stages if needed)
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      ld_data_latched <= 32'b0;
    end else begin
      // Capture data whenever valid response arrives
      // This happens on the SAME cycle as lsu_resp_valid
      if (lsu_resp_valid) begin
        ld_data_latched <= ld_data_raw;
      end
    end
  end

  assign o_ld_data = (lsu_resp_valid) ? ld_data_raw : ld_data_latched;
  
  assign o_wb_sel = i_wb_sel;

  // 8. Host Adapter Instantiation
  tlul_host_adapter #(
    .REQ_FIFO_DEPTH  (8),
    .FIFO_DEPTH      (8),
    .MAX_OUTSTANDING (8),
    .TIMEOUT_CYCLES  (1024)
  ) u_host_adapter (
    .i_clk        (i_clk),
    .i_rst_n      (i_rst_n),
    
    // LSU Interface
    .i_lsu_valid  (lsu_req_valid),
    .i_lsu_we     (i_lsu_wren),
    .i_lsu_addr   (i_alu_data),
    .i_lsu_wdata  (lsu_wdata),
    .i_lsu_be     (lsu_be),
    .i_lsu_size   (lsu_size),
    
    .o_lsu_ready  (lsu_req_ready),
    .o_lsu_rvalid (lsu_resp_valid),
    .o_lsu_rdata  (lsu_resp_rdata),
    .o_lsu_err    (lsu_resp_err),
    
    // TileLink A Channel
    .o_tl_a_valid (o_tl_a_valid),
    .o_tl_a_opcode(o_tl_a_opcode),
    .o_tl_a_param (o_tl_a_param),
    .o_tl_a_size  (o_tl_a_size),
    .o_tl_a_source(o_tl_a_source),
    .o_tl_a_address(o_tl_a_address),
    .o_tl_a_mask  (o_tl_a_mask),
    .o_tl_a_data  (o_tl_a_data),
    .o_tl_a_corrupt(o_tl_a_corrupt),
    .i_tl_a_ready (i_tl_a_ready),
    
    // TileLink D Channel
    .i_tl_d_valid (i_tl_d_valid),
    .i_tl_d_opcode(i_tl_d_opcode),
    .i_tl_d_param (i_tl_d_param),
    .i_tl_d_size  (i_tl_d_size),
    .i_tl_d_source(i_tl_d_source),
    .i_tl_d_sink  (i_tl_d_sink),
    .i_tl_d_data  (i_tl_d_data),
    .i_tl_d_denied(i_tl_d_denied),
    .i_tl_d_corrupt(i_tl_d_corrupt),
    .o_tl_d_ready (o_tl_d_ready)
  );

endmodule