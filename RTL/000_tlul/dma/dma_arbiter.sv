module dma_arbiter #(
  parameter int unsigned N_CH = 2
)(
  input  logic             clk_i,
  input  logic             rst_ni,

  input  logic [N_CH-1:0]  req_i, //req from channels         
  output logic [N_CH-1:0]  grant_o,       //tin hieu cap quyen

  // Bus transaction lifecycle
  input  logic             xfer_done_i,    //khi master da xu ly xong, arbiter biet de nha bus
  input  logic             bus_error_i,  //khi master bao loi

  //  grant index for mux select in controller
  output logic [$clog2(N_CH)-1:0] grant_idx_o, // kenh nao dang duoc cap quyen
  output logic              grant_valid_o, 
  output logic              start_pulse_o  
);

  logic                    busy_q; // 1 khi bus dang ban, 0 khi san sang cap quyen moi
  logic [$clog2(N_CH)-1:0] last_served_q; 
  logic [$clog2(N_CH)-1:0] next_ch;        // Next channel selected by round-robin
  logic                    any_req; // 1 khi co it nhat 1 kenh dang yeu cau bus

  // RR logic
  always_comb begin
    any_req = req_i[0] | req_i[1];
    next_ch = last_served_q;

    if (any_req) begin
      if (last_served_q == 1'b0) begin
        // CH0 was last prefer CH1 first
        next_ch = req_i[1] ? 1'b1 : 1'b0;
      end else begin
        // CH1 was last prefer CH0 first
        next_ch = req_i[0] ? 1'b0 : 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q        <= 1'b0;
      last_served_q <= '0;
    end else begin
      if (!busy_q && any_req) begin //bus ranh va co kenh dang req
        busy_q        <= 1'b1;
        last_served_q <= next_ch;
      end else if (busy_q && (xfer_done_i || bus_error_i)) begin
        busy_q <= 1'b0;
      end
    end
  end

  // Outputs
  always_comb begin
    grant_o       = '0;
    grant_idx_o   = '0;
    grant_valid_o = 1'b0;

    if (!busy_q && any_req) begin // co yeu cau moi trong luc bus ranh
      grant_o[next_ch]  = 1'b1;
      grant_idx_o       = next_ch;
      grant_valid_o     = 1'b1;
    end else if (busy_q) begin
      // hold existing grant until xfer completes
      grant_o[last_served_q] = 1'b1;
      grant_idx_o            = last_served_q;
      grant_valid_o          = 1'b1;
    end
  end

  // start pulse for dma_tlul_master to initiate bus trans
  assign start_pulse_o = !busy_q && any_req;

endmodule
