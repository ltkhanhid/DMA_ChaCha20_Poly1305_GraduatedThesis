module tlul_adapter_peri 
  import tlul_pkg::*;
(
  input  logic i_clk,
  input  logic i_rst_n,
  
  //  Channel A (Master -> Slave)
  input  logic i_tl_a_valid,
  input  logic [2:0] i_tl_a_opcode,
  input  logic [2:0] i_tl_a_param,
  input  tl_size_t i_tl_a_size,
  input  tl_source_t i_tl_a_source,
  input  tl_addr_t i_tl_a_address,
  input  tl_mask_t i_tl_a_mask,
  input  tl_data_t i_tl_a_data,
  input  logic i_tl_a_corrupt,
  output logic o_tl_a_ready,     // Slave -> Master
  
  //  Channel D (Slave -> Master)
  output logic o_tl_d_valid,
  output logic [2:0] o_tl_d_opcode,
  output logic [2:0] o_tl_d_param,
  output tl_size_t o_tl_d_size,
  output tl_source_t o_tl_d_source,
  output tl_sink_t o_tl_d_sink,
  output tl_data_t o_tl_d_data,
  output logic o_tl_d_denied,
  output logic o_tl_d_corrupt,
  input  logic i_tl_d_ready,     // Master -> Slave
  
  // Peripheral I/O (GPIO/LED/HEX only)
  input  logic [31:0] i_io_sw,
  output logic [31:0] o_io_ledr,
  output logic [31:0] o_io_ledg,
  output logic [31:0] o_io_lcd,
  output logic [6:0] o_io_hex0,
  output logic [6:0] o_io_hex1,
  output logic [6:0] o_io_hex2,
  output logic [6:0] o_io_hex3,
  output logic [6:0] o_io_hex4,
  output logic [6:0] o_io_hex5,
  output logic [6:0] o_io_hex6,
  output logic [6:0] o_io_hex7
);

  logic [19:0] peri_addr;      // Địa chỉ hiện tại (cho write)
  logic [19:0] peri_addr_q;    // Địa chỉ đã latch (cho read response)
  logic [31:0] peri_wdata;
  logic        peri_we;
  logic [31:0] peri_rdata;
  
  logic [2:0] req_opcode_q;
  logic [2:0] req_size_q;
  logic [TL_AIW-1:0] req_source_q;
  logic req_valid_q;
  logic req_corrupt_q;
  
  peripherals u_peripherals (
    .i_clk       (i_clk),
    .i_reset     (i_rst_n),
    .i_peri_addr (req_valid_q ? peri_addr_q : peri_addr),  // Dùng địa chỉ latch khi đang xử lý request
    .i_data_in   (peri_wdata),
    .i_write_en  (peri_we),
    .i_io_sw     (i_io_sw),
    .o_data_out  (peri_rdata),
    .o_io_ledr   (o_io_ledr),
    .o_io_ledg   (o_io_ledg),
    .o_io_lcd    (o_io_lcd),
    .o_io_hex0   (o_io_hex0),
    .o_io_hex1   (o_io_hex1),
    .o_io_hex2   (o_io_hex2),
    .o_io_hex3   (o_io_hex3),
    .o_io_hex4   (o_io_hex4),
    .o_io_hex5   (o_io_hex5),
    .o_io_hex6   (o_io_hex6),
    .o_io_hex7   (o_io_hex7)
  );
  
  assign peri_addr  = i_tl_a_address[19:0];  // 20 bit để cover 0x1001_0xxx
  assign peri_wdata = i_tl_a_data;
  
  assign peri_we = i_tl_a_valid && o_tl_a_ready && (i_tl_a_opcode != Get);
  
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      req_opcode_q  <= '0;
      req_size_q    <= '0;
      req_source_q  <= '0;
      req_valid_q   <= 1'b0;
      req_corrupt_q <= 1'b0;
      peri_addr_q   <= '0;  
    end else begin

      if (i_tl_a_valid && o_tl_a_ready) begin
        req_opcode_q  <= i_tl_a_opcode;
        req_size_q    <= i_tl_a_size;
        req_source_q  <= i_tl_a_source;
        req_corrupt_q <= i_tl_a_corrupt;
        req_valid_q   <= 1'b1;
        peri_addr_q   <= i_tl_a_address[19:0];  // Latch địa chỉ
      end else if (o_tl_d_valid && i_tl_d_ready) begin

        req_valid_q <= 1'b0;
      end
    end
  end
  
  assign o_tl_a_ready = !req_valid_q;
  
  always_comb begin
    o_tl_d_valid   = req_valid_q;
    o_tl_d_param   = 3'b0;
    o_tl_d_size    = req_size_q;
    o_tl_d_source  = req_source_q;
    o_tl_d_sink    = 1'b0;
    o_tl_d_denied  = 1'b0;
    o_tl_d_corrupt = req_corrupt_q;
    
    if (req_opcode_q == Get) begin
      o_tl_d_opcode = AccessAckData;
      o_tl_d_data   = peri_rdata;
    end else begin
      o_tl_d_opcode = AccessAck;
      o_tl_d_data   = '0;
    end
  end

endmodule
