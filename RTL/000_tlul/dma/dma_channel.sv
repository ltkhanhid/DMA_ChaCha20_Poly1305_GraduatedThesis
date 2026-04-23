// States:
//   CH_IDLE  – waiting for software enable
//   CH_WAIT  – request issued, waiting for arbiter grant
//   CH_READ  – granted, read transaction in progress on bus
//   CH_WRITE – granted, write transaction in progress on bus
//   CH_NEXT  – one word done, update address & count
//   CH_DONE  – transfer complete
//   CH_ERROR – bus returned error or timeout

module dma_channel #(
  parameter int unsigned CH_ID = 0 
)(
  input  logic        clk_i,
  input  logic        rst_ni,

  //   configuration from CPU
  input  logic        cfg_enable_i,      // start channel
  input  logic [31:0] cfg_src_addr_i,    
  input  logic [31:0] cfg_dst_addr_i,    
  input  logic [15:0] cfg_xfer_cnt_i,    // Transfer count (words)
  input  logic        cfg_src_inc_i,     // Increment source address per word
  input  logic        cfg_dst_inc_i,     // Increment destination address per word

  //  Status outputs to register bridge
  output logic        busy_o,            // Channel is active
  output logic        done_o,            // Transfer-complete pulse 
  output logic        error_o,           // Sticky error flag
  output logic [15:0] remaining_o,       // Words remaining
  output logic        irq_o,            // goi CPU khi done or error

  //  Bus request / response to arbiter & TL-UL master 
  output logic        req_valid_o,       // Channel wants bus access
  input  logic        req_grant_i,       // Arbiter grants this channel

  // Read 
  output logic [31:0] req_src_addr_o,    // Current read address
  input  logic [31:0] read_data_i,       // Data returned from bus read
  input  logic        read_done_i,       // Bus read completed

  // Write 
  output logic [31:0] req_dst_addr_o,    // Current write address
  output logic [31:0] write_data_o,      // Data to write
  input  logic        write_done_i,      // Bus write completed

  // Error from bus master
  input  logic        bus_error_i        // Error during read or write
);

  
  // FSM states
  typedef enum logic [2:0] {
    CH_IDLE  = 3'd0,
    CH_WAIT  = 3'd1,
    CH_READ  = 3'd2,
    CH_WRITE = 3'd3,
    CH_NEXT  = 3'd4,
    CH_DONE  = 3'd5,
    CH_ERROR = 3'd6
  } ch_state_t;

  ch_state_t state_q, state_d;

  logic [31:0] src_addr_q;
  logic [31:0] dst_addr_q;
  logic [15:0] count_q; // remain word transfer count
  logic [31:0] data_buf_q;      // Read-data buffer (read then write)
  logic        error_q;         // Sticky error
  logic        enabled_q;       // luu enable cua clk truoc do + cfg_enable_i tao rising edge detect

  
  // output
  assign busy_o         = (state_q == CH_WAIT)  || (state_q == CH_READ) ||
                          (state_q == CH_WRITE) || (state_q == CH_NEXT);
  assign remaining_o    = count_q;
  assign error_o        = error_q;
  assign req_src_addr_o = src_addr_q;
  assign req_dst_addr_o = dst_addr_q;
  assign write_data_o   = data_buf_q;

  // Request bus give to arbitere
  assign req_valid_o = (state_q == CH_WAIT);

  // FSM next-state logic
  always_comb begin
    state_d = state_q;

    case (state_q)
      CH_IDLE: begin
        // Rising-edge detect on enable with non-zero count
        if (cfg_enable_i && !enabled_q && cfg_xfer_cnt_i > 16'd0)
          state_d = CH_WAIT;
      end

      CH_WAIT: begin
        //cho arbiter cap quyen
        if (req_grant_i)
          state_d = CH_READ;
        // Allow cancel while waiting
        if (!cfg_enable_i)
          state_d = CH_IDLE;
      end

      CH_READ: begin
        if (bus_error_i)
          state_d = CH_ERROR;
        else if (read_done_i)
          state_d = CH_WRITE; 
      end

      CH_WRITE: begin
        if (bus_error_i)
          state_d = CH_ERROR;
        else if (write_done_i) //signal from bus master
          state_d = CH_NEXT;
      end

      CH_NEXT: begin
        // Decrement happened this cycle; check if count reaches 0
        if (count_q == 16'd1)
          state_d = CH_DONE;
        else
          state_d = CH_WAIT;  // More words -> request bus again
      end

      CH_DONE: begin
        // Stay until software de-asserts enable, then return to IDLE
        if (!cfg_enable_i)
          state_d = CH_IDLE;
      end

      CH_ERROR: begin
        // Stay until software de-asserts enable, then return to IDLE
        if (!cfg_enable_i)
          state_d = CH_IDLE;
      end

      default: state_d = CH_IDLE;
    endcase
  end

  
  // FSM registered logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= CH_IDLE;
      src_addr_q <= 32'd0;
      dst_addr_q <= 32'd0;
      count_q    <= 16'd0;
      data_buf_q <= 32'd0;
      error_q    <= 1'b0;
      enabled_q  <= 1'b0;
      done_o     <= 1'b0;
      irq_o      <= 1'b0;
    end else begin
      state_q   <= state_d;
      enabled_q <= cfg_enable_i;

      case (state_q)
        CH_IDLE: begin
          // chốt cau hinh 
          if (cfg_enable_i && !enabled_q && cfg_xfer_cnt_i > 16'd0) begin
            src_addr_q <= cfg_src_addr_i;
            dst_addr_q <= cfg_dst_addr_i;
            count_q    <= cfg_xfer_cnt_i;
            error_q    <= 1'b0;               // Clear sticky error
          end
        end

        CH_READ: begin
          if (read_done_i && !bus_error_i)
            data_buf_q <= read_data_i;        // Capture read data
        end

        CH_NEXT: begin
          // Address increment & count decrement
          if (cfg_src_inc_i) src_addr_q <= src_addr_q + 32'd4;
          if (cfg_dst_inc_i) dst_addr_q <= dst_addr_q + 32'd4;
          count_q <= count_q - 16'd1;
        end

        CH_ERROR: begin
          error_q <= 1'b1;
        end

        default: ;
      endcase

      // done_o / irq_o: registered 1-cycle pulses, merged into main FF block
      done_o <= (state_d == CH_DONE)  && (state_q != CH_DONE);
      irq_o  <= ((state_d == CH_DONE)  && (state_q != CH_DONE)) ||
                ((state_d == CH_ERROR) && (state_q != CH_ERROR));
    end
  end
endmodule
