
// Architecture (block diagram):

//   cfg_chX ──► ┌───────────┐  req   ┌───────────┐ grant  ┌────────────────┐
//               │dma_channel│──────►  │dma_arbiter│──────► │dma_tlul_master │──► TL-UL A
//               │    [0]    │◄──────  │           │        │                │◄── TL-UL D
//               └───────────┘  grant  └───────────┘        └────────────────┘
//   cfg_chX ──► ┌───────────┐  req        ▲                      │
//               │dma_channel│─────────────┘                      │
//               │    [1]    │◄─── read_data / write_done ────────┘
//               └───────────┘
//                     │ irq_pulse
//                     ▼
//               ┌───────────┐
//               │dma_irq_ctl│──► o_dma_irq
//               └───────────┘
module dma_controller
  import tlul_pkg::*;
#(
  parameter int unsigned TIMEOUT_LIMIT = 1024
)(
  input  logic        i_clk,
  input  logic        i_rst_n,

  // Channel 0
  input  logic        i_ch0_enable,
  input  logic [31:0] i_ch0_src_addr,
  input  logic [31:0] i_ch0_dst_addr,
  input  logic [15:0] i_ch0_xfer_count,
  input  logic        i_ch0_src_inc,
  input  logic        i_ch0_dst_inc,

  // Channel 1
  input  logic        i_ch1_enable,
  input  logic [31:0] i_ch1_src_addr,
  input  logic [31:0] i_ch1_dst_addr,
  input  logic [15:0] i_ch1_xfer_count,
  input  logic        i_ch1_src_inc,
  input  logic        i_ch1_dst_inc,

  //  Per-channel status 
  output logic        o_ch0_busy,
  output logic        o_ch1_busy,
  output logic        o_ch0_done,
  output logic        o_ch1_done,
  output logic [15:0] o_ch0_remaining,
  output logic [15:0] o_ch1_remaining,
  output logic        o_ch0_error,
  output logic        o_ch1_error,

  //  Interrupt 
  output logic        o_irq_ch0,
  output logic        o_irq_ch1,

  //  TileLink-UL Master Interface 
  output logic        o_tl_a_valid,
  output logic [2:0]  o_tl_a_opcode,
  output logic [2:0]  o_tl_a_param,
  output tl_size_t    o_tl_a_size,
  output tl_source_t  o_tl_a_source,
  output tl_addr_t    o_tl_a_address,
  output tl_mask_t    o_tl_a_mask,
  output tl_data_t    o_tl_a_data,
  output logic        o_tl_a_corrupt,
  input  logic        i_tl_a_ready,

  input  logic        i_tl_d_valid,
  input  logic [2:0]  i_tl_d_opcode,
  input  logic [2:0]  i_tl_d_param,
  input  tl_size_t    i_tl_d_size,
  input  tl_source_t  i_tl_d_source,
  input  tl_sink_t    i_tl_d_sink,
  input  tl_data_t    i_tl_d_data,
  input  logic        i_tl_d_denied,
  input  logic        i_tl_d_corrupt,
  output logic        o_tl_d_ready
);

  localparam int unsigned N_CH = 2;

  
  // Internal wire
  //  Channel <-> Arbiter 
  logic [N_CH-1:0] ch_req;
  logic [N_CH-1:0] ch_grant;
  logic [$clog2(N_CH)-1:0] grant_idx;
  logic             grant_valid;

  //  Channel outputs 
  logic [31:0] ch_src_addr  [N_CH];
  logic [31:0] ch_dst_addr  [N_CH];
  logic [31:0] ch_wdata     [N_CH];
  logic        ch_busy      [N_CH];
  logic        ch_done      [N_CH];
  logic        ch_error     [N_CH];
  logic [15:0] ch_remaining [N_CH];
  logic        ch_irq       [N_CH];

  //  Bus master - Channels 
  logic [31:0] bus_rdata;
  logic        bus_read_done;
  logic        bus_write_done;
  logic        bus_xfer_done;
  logic        bus_error;
  logic        bus_busy;

  //  Muxed channel -> bus master 
  logic [31:0] mux_src_addr;
  logic [31:0] mux_dst_addr;
  logic [31:0] mux_wdata;

  //  Bus master start 
  logic        bus_start;
  logic        arb_start_pulse;

  dma_channel #(.CH_ID(0)) u_ch0 (
    .clk_i          (i_clk),
    .rst_ni         (i_rst_n),

    .cfg_enable_i   (i_ch0_enable),
    .cfg_src_addr_i (i_ch0_src_addr),
    .cfg_dst_addr_i (i_ch0_dst_addr),
    .cfg_xfer_cnt_i (i_ch0_xfer_count),
    .cfg_src_inc_i  (i_ch0_src_inc),
    .cfg_dst_inc_i  (i_ch0_dst_inc),

    .busy_o         (ch_busy[0]),
    .done_o         (ch_done[0]),
    .error_o        (ch_error[0]),
    .remaining_o    (ch_remaining[0]),
    .irq_o          (ch_irq[0]),

    .req_valid_o    (ch_req[0]),
    .req_grant_i    (ch_grant[0]),
    .req_src_addr_o (ch_src_addr[0]),
    .read_data_i    (bus_rdata),
    .read_done_i    (bus_read_done  && (grant_idx == 0)),
    .req_dst_addr_o (ch_dst_addr[0]),
    .write_data_o   (ch_wdata[0]),
    .write_done_i   (bus_write_done && (grant_idx == 0)),
    .bus_error_i    (bus_error      && (grant_idx == 0))
  );


  dma_channel #(.CH_ID(1)) u_ch1 (
    .clk_i          (i_clk),
    .rst_ni         (i_rst_n),

    .cfg_enable_i   (i_ch1_enable),
    .cfg_src_addr_i (i_ch1_src_addr),
    .cfg_dst_addr_i (i_ch1_dst_addr),
    .cfg_xfer_cnt_i (i_ch1_xfer_count),
    .cfg_src_inc_i  (i_ch1_src_inc),
    .cfg_dst_inc_i  (i_ch1_dst_inc),

    .busy_o         (ch_busy[1]),
    .done_o         (ch_done[1]),
    .error_o        (ch_error[1]),
    .remaining_o    (ch_remaining[1]),
    .irq_o          (ch_irq[1]),

    .req_valid_o    (ch_req[1]),
    .req_grant_i    (ch_grant[1]),
    .req_src_addr_o (ch_src_addr[1]),
    .read_data_i    (bus_rdata),
    .read_done_i    (bus_read_done  && (grant_idx == 1)),
    .req_dst_addr_o (ch_dst_addr[1]),
    .write_data_o   (ch_wdata[1]),
    .write_done_i   (bus_write_done && (grant_idx == 1)),
    .bus_error_i    (bus_error      && (grant_idx == 1))
  );

  dma_arbiter #(.N_CH(N_CH)) u_arbiter (
    .clk_i        (i_clk),
    .rst_ni       (i_rst_n),

    .req_i        (ch_req),
    .grant_o      (ch_grant),

    .xfer_done_i  (bus_xfer_done),
    .bus_error_i  (bus_error),

    .grant_idx_o   (grant_idx),
    .grant_valid_o (grant_valid),
    .start_pulse_o (arb_start_pulse)
  );


  // grant index muxes for master signals
  always_comb begin
    if (grant_idx == 1'b1) begin
      mux_src_addr = ch_src_addr[1];
      mux_dst_addr = ch_dst_addr[1];
      mux_wdata    = ch_wdata[1];
    end else begin
      mux_src_addr = ch_src_addr[0];
      mux_dst_addr = ch_dst_addr[0];
      mux_wdata    = ch_wdata[0];
    end
  end

  // use for latching addresses at start of transfer
  assign bus_start = arb_start_pulse && !bus_busy;

  dma_tlul_master #(
    .TIMEOUT_LIMIT (TIMEOUT_LIMIT),
    .SOURCE_ID     (2)
  ) u_bus_master (
    .clk_i          (i_clk),
    .rst_ni         (i_rst_n),

    .start_i        (bus_start),
    .src_addr_i     (mux_src_addr),
    .dst_addr_i     (mux_dst_addr),
    .wdata_i        (mux_wdata),

    .rdata_o        (bus_rdata),
    .read_done_o    (bus_read_done),
    .write_done_o   (bus_write_done),
    .xfer_done_o    (bus_xfer_done),
    .bus_error_o    (bus_error),
    .busy_o         (bus_busy),

    .tl_a_valid_o   (o_tl_a_valid),
    .tl_a_opcode_o  (o_tl_a_opcode),
    .tl_a_param_o   (o_tl_a_param),
    .tl_a_size_o    (o_tl_a_size),
    .tl_a_source_o  (o_tl_a_source),
    .tl_a_address_o (o_tl_a_address),
    .tl_a_mask_o    (o_tl_a_mask),
    .tl_a_data_o    (o_tl_a_data),
    .tl_a_corrupt_o (o_tl_a_corrupt),
    .tl_a_ready_i   (i_tl_a_ready),

    .tl_d_valid_i   (i_tl_d_valid),
    .tl_d_opcode_i  (i_tl_d_opcode),
    .tl_d_param_i   (i_tl_d_param),
    .tl_d_size_i    (i_tl_d_size),
    .tl_d_source_i  (i_tl_d_source),
    .tl_d_sink_i    (i_tl_d_sink),
    .tl_d_data_i    (i_tl_d_data),
    .tl_d_denied_i  (i_tl_d_denied),
    .tl_d_corrupt_i (i_tl_d_corrupt),
    .tl_d_ready_o   (o_tl_d_ready)
  );


  // Output status each channel
  assign o_ch0_busy      = ch_busy[0];
  assign o_ch1_busy      = ch_busy[1];

  assign o_ch0_done      = ch_done[0];
  assign o_ch1_done      = ch_done[1];

  assign o_ch0_remaining = ch_remaining[0];
  assign o_ch1_remaining = ch_remaining[1];

  assign o_ch0_error     = ch_error[0];
  assign o_ch1_error     = ch_error[1];

  assign o_irq_ch0       = ch_irq[0];
  assign o_irq_ch1       = ch_irq[1];

endmodule
