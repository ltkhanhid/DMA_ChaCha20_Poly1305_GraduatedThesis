module dma_tlul_master
  import tlul_pkg::*;
#(
  parameter int unsigned TIMEOUT_LIMIT = 1024, 
  parameter int unsigned SOURCE_ID     = 2      // TL-UL source identifier
)(
  input  logic        clk_i,
  input  logic        rst_ni,

  //  control signal from dma_controller 
  input  logic        start_i,          // Pulse: begin a read-then-write cycle
  input  logic [31:0] src_addr_i,       // Read address
  input  logic [31:0] dst_addr_i,       // Write address
  input  logic [31:0] wdata_i,          // Write data (only used if bypass, else internal buffer)

  //   back to controller / channels 
  output logic [31:0] rdata_o,          // Data read from bus
  output logic        read_done_o,      // Read phase completed successfully
  output logic        write_done_o,     // Write phase completed successfully
  output logic        xfer_done_o,      // Full read+write cycle completed (success or error)
  output logic        bus_error_o,      // Error: denied / corrupt / timeout
  output logic        busy_o,           // Bus master is busy

  // Master interface
  output logic        tl_a_valid_o,
  output logic [2:0]  tl_a_opcode_o,
  output logic [2:0]  tl_a_param_o,
  output tl_size_t    tl_a_size_o,
  output tl_source_t  tl_a_source_o,
  output tl_addr_t    tl_a_address_o,
  output tl_mask_t    tl_a_mask_o,
  output tl_data_t    tl_a_data_o,
  output logic        tl_a_corrupt_o,
  input  logic        tl_a_ready_i,

  // Slave interface
  input  logic        tl_d_valid_i,
  input  logic [2:0]  tl_d_opcode_i,
  input  logic [2:0]  tl_d_param_i,
  input  tl_size_t    tl_d_size_i,
  input  tl_source_t  tl_d_source_i,
  input  tl_sink_t    tl_d_sink_i,
  input  tl_data_t    tl_d_data_i,
  input  logic        tl_d_denied_i,
  input  logic        tl_d_corrupt_i,
  output logic        tl_d_ready_o
);

  
  // FSM definition
  typedef enum logic [2:0] {
    BUS_IDLE      = 3'd0,
    BUS_READ_REQ  = 3'd1,
    BUS_READ_RSP  = 3'd2,
    BUS_WRITE_REQ = 3'd3,
    BUS_WRITE_RSP = 3'd4,
    BUS_ERROR     = 3'd5
  } bus_state_t;

  bus_state_t state_q, state_d;

  logic [31:0] src_addr_q;
  logic [31:0] dst_addr_q;
  logic [15:0] timeout_cnt_q;

  
  // response error detection
  wire resp_error    = tl_d_valid_i && (tl_d_denied_i || tl_d_corrupt_i);
  wire timeout_exp   = (timeout_cnt_q >= TIMEOUT_LIMIT[15:0]);

  
  // Timeout counter
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      timeout_cnt_q <= 16'd0;
    end else begin
      if (state_q == BUS_READ_RSP || state_q == BUS_WRITE_RSP) begin
        if (!tl_d_valid_i)
          timeout_cnt_q <= timeout_cnt_q + 16'd1;
        else
          timeout_cnt_q <= 16'd0;
      end else begin
        timeout_cnt_q <= 16'd0;
      end
    end
  end

  
  // FSM control
  always_comb begin
    state_d = state_q;

    case (state_q)
      BUS_IDLE: begin
        if (start_i)
          state_d = BUS_READ_REQ;
      end

      BUS_READ_REQ: begin
        if (tl_a_valid_o && tl_a_ready_i)
          state_d = BUS_READ_RSP;
      end

      BUS_READ_RSP: begin
        if (timeout_exp)
          state_d = BUS_ERROR;
        else if (tl_d_valid_i && tl_d_ready_o) begin
          if (resp_error)
            state_d = BUS_ERROR;
          else
            state_d = BUS_WRITE_REQ;
        end
      end

      BUS_WRITE_REQ: begin
        if (tl_a_valid_o && tl_a_ready_i)
          state_d = BUS_WRITE_RSP;
      end

      BUS_WRITE_RSP: begin
        if (timeout_exp)
          state_d = BUS_ERROR;
        else if (tl_d_valid_i && tl_d_ready_o) begin
          if (resp_error)
            state_d = BUS_ERROR;
          else
            state_d = BUS_IDLE;       // Full cycle complete
        end
      end

      BUS_ERROR: begin
        state_d = BUS_IDLE;           // 1-cycle error pulse then return
      end

      default: state_d = BUS_IDLE;
    endcase
  end

  
  // FSM update and address latching
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= BUS_IDLE;
      src_addr_q <= 32'd0;
      dst_addr_q <= 32'd0;
    end else begin
      state_q <= state_d;

      // Latch addresses on start
      if (state_q == BUS_IDLE && start_i) begin
        src_addr_q <= src_addr_i;
        dst_addr_q <= dst_addr_i;
      end
    end
  end

  
  // TLUL Channel A drive
  always_comb begin
    // Defaults
    tl_a_valid_o   = 1'b0;
    tl_a_opcode_o  = Get;
    tl_a_param_o   = 3'd0;
    tl_a_size_o    = 3'd2;                        // 4 bytes
    tl_a_source_o  = SOURCE_ID[TL_AIW-1:0];
    tl_a_address_o = 32'd0;
    tl_a_mask_o    = 4'hF;
    tl_a_data_o    = 32'd0;
    tl_a_corrupt_o = 1'b0;
    tl_d_ready_o   = 1'b0;

    case (state_q)
      BUS_READ_REQ: begin
        tl_a_valid_o   = 1'b1;
        tl_a_opcode_o  = Get;
        tl_a_address_o = src_addr_q;
      end

      BUS_READ_RSP: begin
        tl_d_ready_o = 1'b1;
      end

      BUS_WRITE_REQ: begin
        tl_a_valid_o   = 1'b1;
        tl_a_opcode_o  = PutFullData;
        tl_a_address_o = dst_addr_q;
        tl_a_data_o    = wdata_i;    
      end

      BUS_WRITE_RSP: begin
        tl_d_ready_o = 1'b1;
      end

      default: ;
    endcase
  end

  
  // Status outputs
  assign rdata_o      = tl_d_data_i;
  assign busy_o       = (state_q != BUS_IDLE);

  // Pulse outputs — active for exactly 1 cycle
  assign read_done_o  = (state_q == BUS_READ_RSP)  && tl_d_valid_i && tl_d_ready_o && !resp_error;
  assign write_done_o = (state_q == BUS_WRITE_RSP) && tl_d_valid_i && tl_d_ready_o && !resp_error;
  assign xfer_done_o  = write_done_o || (state_q == BUS_ERROR);
  assign bus_error_o  = (state_q == BUS_ERROR);

endmodule
