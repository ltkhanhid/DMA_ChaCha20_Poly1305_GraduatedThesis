  // TileLink UL Host Adapter
  module tlul_host_adapter 
    import tlul_pkg::*;
  #(
    parameter int REQ_FIFO_DEPTH = 2,    //  request FIFO depth (reduced for FPGA)
    parameter int FIFO_DEPTH = 2,        // response FIFO depth (reduced for FPGA)
    parameter int MAX_OUTSTANDING = 2,   // reduced from 8 to 2
    parameter int TIMEOUT_CYCLES = 512   // reduced from 1024 
  )
  (
    input  logic i_clk,
    input  logic i_rst_n,
    
    // LSU Interface
    input  logic i_lsu_valid,      
    input  logic i_lsu_we,        
    input  logic [31:0] i_lsu_addr,    
    input  logic [31:0] i_lsu_wdata,     
    input  logic [3:0] i_lsu_be,        
    input  logic [2:0] i_lsu_size,      

    output logic o_lsu_ready,     
    output logic o_lsu_rvalid,     
    output logic [31:0] o_lsu_rdata,      
    output logic o_lsu_err,        

    output logic o_tl_a_valid,
    output logic [2:0] o_tl_a_opcode,
    output logic [2:0] o_tl_a_param,
    output tl_size_t o_tl_a_size,
    output tl_source_t o_tl_a_source,
    output tl_addr_t o_tl_a_address,
    output tl_mask_t o_tl_a_mask,
    output tl_data_t o_tl_a_data,
    output logic o_tl_a_corrupt,
    input  logic i_tl_a_ready,     

    input  logic i_tl_d_valid,
    input  logic [2:0] i_tl_d_opcode,
    input  logic [2:0] i_tl_d_param,
    input  tl_size_t i_tl_d_size,
    input  tl_source_t i_tl_d_source,
    input  tl_sink_t i_tl_d_sink,
    input  tl_data_t i_tl_d_data,
    input  logic i_tl_d_denied,
    input  logic i_tl_d_corrupt,
    output logic o_tl_d_ready      
  );

    
    typedef enum logic [1:0] {
      IDLE = 2'b00,  // chờ request
      ACTIVE = 2'b01,  // đang xử lý request
      REQ_SEND = 2'b10   // đang gửi request lên channel A
    } state_t;
    
    state_t state_q, state_d;
    
    // outstanding transaction counter
    logic [3:0] outstanding_cnt;  // số request đã gửi nhưng chưa nhận response
    
    // request transfer từ LSU
    logic [31:0] addr_q; 
    logic [31:0] wdata_q;
    logic [3:0] be_q; // byte enable
    logic [2:0] size_q;
    logic we_q;
    
    // transaction ID counter // every request +1
    logic [TL_AIW-1:0] source_id_q;

    // Request FIFO 
    localparam int REQ_PTR_WIDTH = (REQ_FIFO_DEPTH > 1) ? $clog2(REQ_FIFO_DEPTH) : 1;
    
    logic [REQ_PTR_WIDTH:0]   req_fifo_count; // 0 to REQ_FIFO_DEPTH entry
    logic [REQ_PTR_WIDTH-1:0] req_fifo_wptr; 
    logic [REQ_PTR_WIDTH-1:0] req_fifo_rptr;
    logic [31:0] req_fifo_addr [0:REQ_FIFO_DEPTH-1]; 
    logic [31:0] req_fifo_wdata [0:REQ_FIFO_DEPTH-1];
    logic [3:0] req_fifo_be [0:REQ_FIFO_DEPTH-1];
    logic [2:0] req_fifo_size [0:REQ_FIFO_DEPTH-1];
    logic req_fifo_we [0:REQ_FIFO_DEPTH-1];
    logic req_fifo_push;
    logic req_fifo_pop;
    logic req_fifo_full;
    logic req_fifo_empty;
    
    // D response FIFO
    localparam int PTR_WIDTH = (FIFO_DEPTH > 1) ? $clog2(FIFO_DEPTH) : 1;
    
    logic [PTR_WIDTH:0] d_fifo_count;      // 0 to FIFO_DEPTH entries 
    logic [PTR_WIDTH-1:0] d_fifo_wptr;       // Write pointer
    logic [PTR_WIDTH-1:0] d_fifo_rptr;       // Read pointer
    logic [31:0] d_fifo_data [0:FIFO_DEPTH-1];
    logic d_fifo_denied [0:FIFO_DEPTH-1];
    logic d_fifo_corrupt [0:FIFO_DEPTH-1];
    logic [2:0]  d_fifo_opcode  [0:FIFO_DEPTH-1];
    logic d_fifo_push;
    logic d_fifo_pop;
    logic d_fifo_full;
    logic d_fifo_empty;
    
    logic rvalid_pulse; // pulse to say response is valid or error for LSU, just 1 cycle

    // addr alignment error detection
    logic align_err;
    
    // timeout detection for slave non-response
    logic [15:0] timeout_counter;
    logic timeout_err;
    

    // Request FIFO
    assign req_fifo_full  = (req_fifo_count == REQ_FIFO_DEPTH);
    assign req_fifo_empty = (req_fifo_count == '0);
    
    // Push: LSU valid request, FIFO not full, no align error
    assign req_fifo_push = i_lsu_valid && !req_fifo_full && !align_err;
    
    // Pop: when send request and handshake
    assign req_fifo_pop = (state_q == REQ_SEND) && o_tl_a_valid && i_tl_a_ready;
    
    // FIFO counter
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        req_fifo_count <= '0;
      end else begin
        case ({req_fifo_push, req_fifo_pop})
          2'b10: req_fifo_count <= req_fifo_count + 1'b1;  // Push only
          2'b01: req_fifo_count <= req_fifo_count - 1'b1;  // Pop only
          2'b11: req_fifo_count <= req_fifo_count;         // Push+Pop
          default: req_fifo_count <= req_fifo_count;
        endcase
      end
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        req_fifo_wptr <= '0;
        req_fifo_rptr <= '0;
      end else begin
        if (req_fifo_push) begin
          req_fifo_wptr <= (req_fifo_wptr == (REQ_FIFO_DEPTH-1)) ? '0 : req_fifo_wptr + 1'b1;
        end
        if (req_fifo_pop) begin
          req_fifo_rptr <= (req_fifo_rptr == (REQ_FIFO_DEPTH-1)) ? '0 : req_fifo_rptr + 1'b1;
        end
      end
    end
    
    // FIFO storage
    always_ff @(posedge i_clk) begin
      if (req_fifo_push) begin
        req_fifo_addr[req_fifo_wptr]  <= i_lsu_addr;
        req_fifo_wdata[req_fifo_wptr] <= i_lsu_wdata;
        req_fifo_be[req_fifo_wptr]    <= i_lsu_be;
        req_fifo_size[req_fifo_wptr]  <= i_lsu_size;
        req_fifo_we[req_fifo_wptr]    <= i_lsu_we;
      end
    end
    
    // Outstanding Transaction Counter 
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        outstanding_cnt <= '0;
      end else begin
        case ({(o_tl_a_valid && i_tl_a_ready), (d_fifo_pop)})
          2'b10: outstanding_cnt <= outstanding_cnt + 1'b1;  // Request sent
          2'b01: outstanding_cnt <= outstanding_cnt - 1'b1;  // Response received
          2'b11: outstanding_cnt <= outstanding_cnt;        
          default: outstanding_cnt <= outstanding_cnt;
        endcase
      end
    end
 
    // non blocking FSM
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        state_q <= IDLE;
      end else begin
        state_q <= state_d;
      end
    end
    
    // next state logic decoder
    always_comb begin
      state_d = state_q;
      
      case (state_q)
        IDLE: begin
          if (!req_fifo_empty) begin
            state_d = REQ_SEND;
          end
        end
        
        REQ_SEND: begin
          // Send request on Channel A
          if (o_tl_a_valid && i_tl_a_ready) begin
            // Request sent successfully
            if (!req_fifo_empty) begin
              state_d = REQ_SEND;
            end else begin
              state_d = ACTIVE;    // no more requests, wait for responses
            end
          end
        end
        
        ACTIVE: begin
          if (!req_fifo_empty && (outstanding_cnt < MAX_OUTSTANDING)) begin
            state_d = REQ_SEND;  // send new request if possible
          end else if (outstanding_cnt == 0) begin
            state_d = IDLE;     // all done
          end
        end

        default: state_d = IDLE;
      endcase
    end

    
    // TIMEOUT counter to detect slave non-response
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        timeout_counter <= '0;
        timeout_err     <= 1'b0;
      end else begin
        if (outstanding_cnt > 0) begin  // Timeout when have outstanding
          if (TIMEOUT_CYCLES > 0) begin
            // response arrive will reset counter
            if (d_fifo_pop) begin
              timeout_counter <= '0; 
              timeout_err     <= 1'b0;
            end else if (timeout_counter >= TIMEOUT_CYCLES) begin
              timeout_err <= 1'b1; 
            end else begin
              timeout_counter <= timeout_counter + 1'b1; 
              timeout_err     <= 1'b0;
            end
          end else begin
            timeout_err <= 1'b0;  // disable timeout
          end
        end else begin
          // reset when no outstanding requests
          timeout_counter <= '0;
          timeout_err     <= 1'b0;
        end
      end
    end
    
    // addr alignment check
    always_comb begin
      align_err = 1'b0;
      // validate size is legal for tlul
      if (i_lsu_size > 3'd2) begin
        align_err = 1'b1;  // not legal -> error
      end else begin
        // check alignment based on access size
        case (i_lsu_size)
          3'd0: align_err = 1'b0;                       
          3'd1: align_err = (i_lsu_addr[0] != 1'b0);     
          3'd2: align_err = (i_lsu_addr[1:0] != 2'b00);  
          default: align_err = 1'b0;
        endcase
      end
    end

    // Latch request from FIFO when popping
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        addr_q <= '0;
        wdata_q <= '0;
        be_q <= '0;
        size_q <= '0;
        we_q <= '0;
      end else if (req_fifo_pop) begin
        // pop from FIFO
        addr_q <= req_fifo_addr[req_fifo_rptr];
        wdata_q <= req_fifo_wdata[req_fifo_rptr];
        be_q <= req_fifo_be[req_fifo_rptr];
        size_q <= req_fifo_size[req_fifo_rptr];
        we_q <= req_fifo_we[req_fifo_rptr];
      end
    end
    
    // transaction ID counter
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        source_id_q <= '0;
      end else if (req_fifo_pop) begin
        // Increment when popping from FIFO
        source_id_q <= source_id_q + 1'b1;
      end
    end
    
    
    // tlul channel A operation
    always_comb begin

      o_tl_a_valid = 1'b0;
      o_tl_a_opcode = Get;
      o_tl_a_param = 3'b0;  
      o_tl_a_size = req_fifo_size[req_fifo_rptr]; 
      o_tl_a_source = source_id_q;
      o_tl_a_address = req_fifo_addr[req_fifo_rptr]; 
      o_tl_a_mask = req_fifo_be[req_fifo_rptr];
      o_tl_a_data = req_fifo_wdata[req_fifo_rptr];
      o_tl_a_corrupt = 1'b0;
      
      // a_valid when in REQ_SEND state and have data
      if ((state_q == REQ_SEND) && !req_fifo_empty) begin
        o_tl_a_valid = 1'b1;
        
        // Determine opcode from FIFO data
        if (req_fifo_we[req_fifo_rptr]) begin
          // Write operation
          if (req_fifo_be[req_fifo_rptr] == 4'b1111) begin
            o_tl_a_opcode = PutFullData;     // full word write
          end else begin
            o_tl_a_opcode = PutPartialData;  // partial write
          end
        end else begin
          o_tl_a_opcode = Get;
        end
      end
    end
    
    // tlul channel D response FIFO 
    assign d_fifo_full = (d_fifo_count == FIFO_DEPTH);
    assign d_fifo_empty = (d_fifo_count == '0);
    
    // FIFO push when slave send valid response
    assign d_fifo_push = i_tl_d_valid && o_tl_d_ready;
    
    // FIFO pop: deliver one response per cycle when FIFO has data
    // The response is consumed when rvalid_pulse is asserted
    // Pop happens each cycle FIFO is not empty (one-shot per entry due to pointer advancement)
    assign d_fifo_pop = !d_fifo_empty;
    
    //FIFO counter 
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        d_fifo_count <= '0;
      end else begin
        case ({d_fifo_push, d_fifo_pop})
          2'b10: d_fifo_count <= d_fifo_count + 1'b1; 
          2'b01: d_fifo_count <= d_fifo_count - 1'b1; 
          2'b11: d_fifo_count <= d_fifo_count;        
          default: d_fifo_count <= d_fifo_count;      
        endcase
      end
    end
    
    // FIFO pointers
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        d_fifo_wptr <= '0;
        d_fifo_rptr <= '0;
      end else begin
        // Write pointer increment on push
        if (d_fifo_push) begin
          d_fifo_wptr <= (d_fifo_wptr == (FIFO_DEPTH-1)) ? '0 : d_fifo_wptr + 1'b1;
        end
        // Read pointer increment on pop
        if (d_fifo_pop) begin
          d_fifo_rptr <= (d_fifo_rptr == (FIFO_DEPTH-1)) ? '0 : d_fifo_rptr + 1'b1;
        end
      end
    end
    
    // FIFO storage write at wptr, read from rptr
    always_ff @(posedge i_clk) begin
      if (d_fifo_push) begin
        // Write to current write pointer location
        d_fifo_data[d_fifo_wptr] <= i_tl_d_data;
        d_fifo_denied[d_fifo_wptr] <= i_tl_d_denied;
        d_fifo_corrupt[d_fifo_wptr] <= i_tl_d_corrupt;
        d_fifo_opcode[d_fifo_wptr] <= i_tl_d_opcode;
      end
    end
    

    // tlul channel D response
    assign o_tl_d_ready = !d_fifo_full;
    
    // 1 cycle pulse for rvalid
    // Include bypass case: when response arrives and we're waiting for it
    assign rvalid_pulse = (i_lsu_valid && align_err) || d_fifo_pop || timeout_err || 
                         (i_tl_d_valid && o_tl_d_ready && d_fifo_empty);                    
    
    // Latch response data từ FIFO with opcode validation
    // Handle bypass when push+pop simultaneously (FIFO write hasn't completed)
    // Also handle immediate response when FIFO is empty
    logic bypass_fifo;
    logic immediate_response;
    logic [31:0] resp_data;
    logic resp_denied, resp_corrupt;
    
    assign immediate_response = i_tl_d_valid && o_tl_d_ready && d_fifo_empty;
    assign bypass_fifo = d_fifo_push && d_fifo_pop && (d_fifo_count == 0);
    
    // Priority: immediate response > bypass > FIFO
    assign resp_data = immediate_response ? i_tl_d_data :
                      (bypass_fifo ? i_tl_d_data : d_fifo_data[d_fifo_rptr]);
    assign resp_denied = immediate_response ? i_tl_d_denied :
                        (bypass_fifo ? i_tl_d_denied : d_fifo_denied[d_fifo_rptr]);
    assign resp_corrupt = immediate_response ? i_tl_d_corrupt :
                         (bypass_fifo ? i_tl_d_corrupt : d_fifo_corrupt[d_fifo_rptr]);
    
    // Register for persistent data (when not in bypass mode)
    logic [31:0] rdata_reg;
    logic err_reg;
    
    always_ff @(posedge i_clk or negedge i_rst_n) begin
      if (!i_rst_n) begin
        rdata_reg  <= '0;
        err_reg    <= 1'b0;
      end else begin
        // Latch data when response is ready (for non-bypass cases)
        if (rvalid_pulse) begin
          if (align_err) begin
            rdata_reg <= '0;
            err_reg   <= 1'b1;
          end else if (timeout_err) begin
            rdata_reg <= '0;
            err_reg   <= 1'b1;
          end else begin
            rdata_reg <= resp_data;
            err_reg   <= resp_denied | resp_corrupt;
          end
        end
      end
    end
    
    // rvalid is combinational for immediate response
    assign o_lsu_rvalid = rvalid_pulse;
    
    // rdata is combinational when rvalid (bypass mode), else use registered value
    assign o_lsu_rdata = rvalid_pulse ? resp_data : rdata_reg;
    assign o_lsu_err = rvalid_pulse ? (align_err || timeout_err || resp_denied || resp_corrupt) : err_reg;

    // LSU ready
    assign o_lsu_ready = !req_fifo_full && (outstanding_cnt < MAX_OUTSTANDING);

  endmodule
