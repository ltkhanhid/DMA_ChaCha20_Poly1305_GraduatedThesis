// Register Map (unchanged from original for backward compatibility):
//   Offset  Name            Access  Description
//   0x00    CH0_CONTROL     R/W     [0]=enable [1]=src_inc [2]=dst_inc
//   0x04    CH0_STATUS      R       [0]=busy [1]=done [2]=error [31:16]=remaining
//   0x08    CH0_SRC_ADDR    R/W     Source address
//   0x0C    CH0_DST_ADDR    R/W     Destination address
//   0x10    CH0_XFER_CNT    R/W     Transfer count (words)
//   0x20    CH1_CONTROL     R/W     Same layout as CH0
//   0x24    CH1_STATUS      R       Same layout as CH0
//   0x28    CH1_SRC_ADDR    R/W     Source address
//   0x2C    CH1_DST_ADDR    R/W     Destination address
//   0x30    CH1_XFER_CNT    R/W     Transfer count (words)
//   0x40    IRQ_STATUS      R/W1C   [0]=ch0_irq [1]=ch1_irq
//-----------------------------------------------------------------------------
module tlul_dma
  import tlul_pkg::*;
(
  input  logic        i_clk,
  input  logic        i_rst_n,

  //   Slave Interface
  input  logic        i_tl_a_valid,
  input  logic [2:0]  i_tl_a_opcode,
  input  logic [2:0]  i_tl_a_param,
  input  tl_size_t    i_tl_a_size,
  input  tl_source_t  i_tl_a_source,
  input  tl_addr_t    i_tl_a_address,
  input  tl_mask_t    i_tl_a_mask,
  input  tl_data_t    i_tl_a_data,
  input  logic        i_tl_a_corrupt,
  output logic        o_tl_a_ready,

  output logic        o_tl_d_valid,
  output logic [2:0]  o_tl_d_opcode,
  output logic [2:0]  o_tl_d_param,
  output tl_size_t    o_tl_d_size,
  output tl_source_t  o_tl_d_source,
  output tl_sink_t    o_tl_d_sink,
  output tl_data_t    o_tl_d_data,
  output logic        o_tl_d_denied,
  output logic        o_tl_d_corrupt,
  input  logic        i_tl_d_ready,

  //    Master Interface (DMA -> Memory/Peripherals)
  output logic        o_dma_tl_a_valid,
  output logic [2:0]  o_dma_tl_a_opcode,
  output logic [2:0]  o_dma_tl_a_param,
  output tl_size_t    o_dma_tl_a_size,
  output tl_source_t  o_dma_tl_a_source,
  output tl_addr_t    o_dma_tl_a_address,
  output tl_mask_t    o_dma_tl_a_mask,
  output tl_data_t    o_dma_tl_a_data,
  output logic        o_dma_tl_a_corrupt,
  input  logic        i_dma_tl_a_ready,

  input  logic        i_dma_tl_d_valid,
  input  logic [2:0]  i_dma_tl_d_opcode,
  input  logic [2:0]  i_dma_tl_d_param,
  input  tl_size_t    i_dma_tl_d_size,
  input  tl_source_t  i_dma_tl_d_source,
  input  tl_sink_t    i_dma_tl_d_sink,
  input  tl_data_t    i_dma_tl_d_data,
  input  logic        i_dma_tl_d_denied,
  input  logic        i_dma_tl_d_corrupt,
  output logic        o_dma_tl_d_ready,

  output logic        o_dma_irq
);

   
  // Register Address
  localparam logic [7:0] ADDR_CH0_CONTROL  = 8'h00;
  localparam logic [7:0] ADDR_CH0_STATUS   = 8'h04; // read only
  localparam logic [7:0] ADDR_CH0_SRC_ADDR = 8'h08;
  localparam logic [7:0] ADDR_CH0_DST_ADDR = 8'h0C;
  localparam logic [7:0] ADDR_CH0_XFER_CNT = 8'h10;

  localparam logic [7:0] ADDR_CH1_CONTROL  = 8'h20;
  localparam logic [7:0] ADDR_CH1_STATUS   = 8'h24;
  localparam logic [7:0] ADDR_CH1_SRC_ADDR = 8'h28;
  localparam logic [7:0] ADDR_CH1_DST_ADDR = 8'h2C;
  localparam logic [7:0] ADDR_CH1_XFER_CNT = 8'h30;

  localparam logic [7:0] ADDR_IRQ_STATUS   = 8'h40;

   
  // Configuration registers
  logic        reg_ch0_enable;
  logic        reg_ch0_src_inc;
  logic        reg_ch0_dst_inc;
  logic [31:0] reg_ch0_src_addr;
  logic [31:0] reg_ch0_dst_addr;
  logic [15:0] reg_ch0_xfer_cnt;

  logic        reg_ch1_enable;
  logic        reg_ch1_src_inc;
  logic        reg_ch1_dst_inc;
  logic [31:0] reg_ch1_src_addr;
  logic [31:0] reg_ch1_dst_addr;
  logic [15:0] reg_ch1_xfer_cnt;

   
  // DMA status signals from controller
  logic        dma_ch0_busy, dma_ch1_busy;
  logic        dma_ch0_done, dma_ch1_done;
  logic [15:0] dma_ch0_remaining, dma_ch1_remaining;
  logic        dma_ch0_error, dma_ch1_error;
  logic        dma_irq_ch0, dma_irq_ch1;

  // IRQ status 
  logic        irq_status_ch0_q, irq_status_ch1_q;

  // TileLink slave request handling
  logic [7:0]  reg_addr;
  logic [2:0]  req_opcode_q;
  logic [2:0]  req_size_q;
  logic [TL_AIW-1:0] req_source_q;
  logic        req_valid_q;

  logic        reg_we;
  logic [31:0] reg_wdata;
  logic [31:0] reg_rdata;

  // Byte-lane write mask expanded from TL-UL a_mask (4 bits  -> 32 bits)
  wire  [31:0] wmask = {{8{i_tl_a_mask[3]}}, {8{i_tl_a_mask[2]}},
                        {8{i_tl_a_mask[1]}}, {8{i_tl_a_mask[0]}}};

  dma_controller u_dma_controller (
    .i_clk            (i_clk),
    .i_rst_n          (i_rst_n),

    // Channel 0 config
    .i_ch0_enable     (reg_ch0_enable),
    .i_ch0_src_addr   (reg_ch0_src_addr),
    .i_ch0_dst_addr   (reg_ch0_dst_addr),
    .i_ch0_xfer_count (reg_ch0_xfer_cnt),
    .i_ch0_src_inc    (reg_ch0_src_inc),
    .i_ch0_dst_inc    (reg_ch0_dst_inc),

    // Channel 1 config
    .i_ch1_enable     (reg_ch1_enable),
    .i_ch1_src_addr   (reg_ch1_src_addr),
    .i_ch1_dst_addr   (reg_ch1_dst_addr),
    .i_ch1_xfer_count (reg_ch1_xfer_cnt),
    .i_ch1_src_inc    (reg_ch1_src_inc),
    .i_ch1_dst_inc    (reg_ch1_dst_inc),

    // Status
    .o_ch0_busy       (dma_ch0_busy),
    .o_ch1_busy       (dma_ch1_busy),
    .o_ch0_done       (dma_ch0_done),
    .o_ch1_done       (dma_ch1_done),
    .o_ch0_remaining  (dma_ch0_remaining),
    .o_ch1_remaining  (dma_ch1_remaining),
    .o_ch0_error      (dma_ch0_error),
    .o_ch1_error      (dma_ch1_error),

    .o_irq_ch0        (dma_irq_ch0),
    .o_irq_ch1        (dma_irq_ch1),

    // TileLink Master
    .o_tl_a_valid     (o_dma_tl_a_valid),
    .o_tl_a_opcode    (o_dma_tl_a_opcode),
    .o_tl_a_param     (o_dma_tl_a_param),
    .o_tl_a_size      (o_dma_tl_a_size),
    .o_tl_a_source    (o_dma_tl_a_source),
    .o_tl_a_address   (o_dma_tl_a_address),
    .o_tl_a_mask      (o_dma_tl_a_mask),
    .o_tl_a_data      (o_dma_tl_a_data),
    .o_tl_a_corrupt   (o_dma_tl_a_corrupt),
    .i_tl_a_ready     (i_dma_tl_a_ready),

    .i_tl_d_valid     (i_dma_tl_d_valid),
    .i_tl_d_opcode    (i_dma_tl_d_opcode),
    .i_tl_d_param     (i_dma_tl_d_param),
    .i_tl_d_size      (i_dma_tl_d_size),
    .i_tl_d_source    (i_dma_tl_d_source),
    .i_tl_d_sink      (i_dma_tl_d_sink),
    .i_tl_d_data      (i_dma_tl_d_data),
    .i_tl_d_denied    (i_dma_tl_d_denied),
    .i_tl_d_corrupt   (i_dma_tl_d_corrupt),
    .o_tl_d_ready     (o_dma_tl_d_ready)
  );

   
  // Address Decode
  assign reg_addr  = i_tl_a_address[7:0];
  // co req + DMA ready + khong phai la lenh doc
  assign reg_we    = i_tl_a_valid && o_tl_a_ready && (i_tl_a_opcode != Get);
  assign reg_wdata = i_tl_a_data;

   
  // TileLink Slave  Request Capture
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      req_opcode_q <= 3'd0;
      req_size_q   <= 3'd0;
      req_source_q <= '0;
      req_valid_q  <= 1'b0;
    end else begin
      if (i_tl_a_valid && o_tl_a_ready) begin
        req_opcode_q <= i_tl_a_opcode;
        req_size_q   <= i_tl_a_size;
        req_source_q <= i_tl_a_source;
        req_valid_q  <= 1'b1;
      end else if (o_tl_d_valid && i_tl_d_ready) begin
        req_valid_q  <= 1'b0;
      end
    end
  end

  // chi nhan req moi khi chua co pending req
  // DMA tu choi req moi cho toi khi resp trước được gửi CPU lấy đi
  assign o_tl_a_ready = !req_valid_q;

  //  Write Logic
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      reg_ch0_enable   <= 1'b0;
      reg_ch0_src_inc  <= 1'b1;
      reg_ch0_dst_inc  <= 1'b1;
      reg_ch0_src_addr <= 32'd0;
      reg_ch0_dst_addr <= 32'd0;
      reg_ch0_xfer_cnt <= 16'd0;

      reg_ch1_enable   <= 1'b0;
      reg_ch1_src_inc  <= 1'b1;
      reg_ch1_dst_inc  <= 1'b1;
      reg_ch1_src_addr <= 32'd0;
      reg_ch1_dst_addr <= 32'd0;
      reg_ch1_xfer_cnt <= 16'd0;

      irq_status_ch0_q <= 1'b0;
      irq_status_ch1_q <= 1'b0;
    end else begin
      
      // khi co IRQ thi
      // B1. ghi sticky bit trong thanh ghi status
      // B2. xoa bit enable trong thanh ghi control de chan channel tiep tuc hoat dong
      if (dma_irq_ch0) irq_status_ch0_q <= 1'b1;
      if (dma_irq_ch1) irq_status_ch1_q <= 1'b1;

      if (dma_irq_ch0) reg_ch0_enable <= 1'b0;
      if (dma_irq_ch1) reg_ch1_enable <= 1'b0;

      if (reg_we) begin
        case (reg_addr)
          ADDR_CH0_CONTROL: begin
            if (i_tl_a_mask[0]) begin               // bits [2:0] in byte-0
              reg_ch0_enable  <= reg_wdata[0];
              reg_ch0_src_inc <= reg_wdata[1];
              reg_ch0_dst_inc <= reg_wdata[2];
            end
          end
          // cap nhat dia chi an, tranh viec ghi vao byte khong dung trong o nho 
          ADDR_CH0_SRC_ADDR: reg_ch0_src_addr <= ((reg_wdata & wmask) | (reg_ch0_src_addr & ~wmask)) & 32'hFFFF_FFFC;
          ADDR_CH0_DST_ADDR: reg_ch0_dst_addr <= ((reg_wdata & wmask) | (reg_ch0_dst_addr & ~wmask)) & 32'hFFFF_FFFC;
          ADDR_CH0_XFER_CNT: begin
            if (i_tl_a_mask[0]) reg_ch0_xfer_cnt[7:0]  <= reg_wdata[7:0];
            if (i_tl_a_mask[1]) reg_ch0_xfer_cnt[15:8] <= reg_wdata[15:8];
          end

          ADDR_CH1_CONTROL: begin
            if (i_tl_a_mask[0]) begin               // bits [2:0] in byte-0
              reg_ch1_enable  <= reg_wdata[0];
              reg_ch1_src_inc <= reg_wdata[1];
              reg_ch1_dst_inc <= reg_wdata[2];
            end
          end
          ADDR_CH1_SRC_ADDR: reg_ch1_src_addr <= ((reg_wdata & wmask) | (reg_ch1_src_addr & ~wmask)) & 32'hFFFF_FFFC;
          ADDR_CH1_DST_ADDR: reg_ch1_dst_addr <= ((reg_wdata & wmask) | (reg_ch1_dst_addr & ~wmask)) & 32'hFFFF_FFFC;
          ADDR_CH1_XFER_CNT: begin
            if (i_tl_a_mask[0]) reg_ch1_xfer_cnt[7:0]  <= reg_wdata[7:0];
            if (i_tl_a_mask[1]) reg_ch1_xfer_cnt[15:8] <= reg_wdata[15:8];
          end

          ADDR_IRQ_STATUS: begin
            if (i_tl_a_mask[0]) begin               // bits [1:0] in byte-0
              if (reg_wdata[0]) irq_status_ch0_q <= 1'b0;
              if (reg_wdata[1]) irq_status_ch1_q <= 1'b0;
            end
          end
          default: ;
        endcase
      end
    end
  end

   
  // Register Read Logic
  logic [7:0] addr_latch_q;

  //latch addr use for read data mux
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      addr_latch_q <= 8'd0;
    else if (i_tl_a_valid && o_tl_a_ready)
      addr_latch_q <= reg_addr;
  end

  always_comb begin
    reg_rdata = 32'd0;

    case (addr_latch_q)
      ADDR_CH0_CONTROL:  reg_rdata = {29'd0, reg_ch0_dst_inc, reg_ch0_src_inc, reg_ch0_enable};
      ADDR_CH0_STATUS:   reg_rdata = {dma_ch0_remaining, 13'd0, dma_ch0_error, dma_ch0_done, dma_ch0_busy}; // bit 31:16 = remaining, bit 2 = error, bit 1 = done, bit 0 = busy
      ADDR_CH0_SRC_ADDR: reg_rdata = reg_ch0_src_addr;
      ADDR_CH0_DST_ADDR: reg_rdata = reg_ch0_dst_addr;
      ADDR_CH0_XFER_CNT: reg_rdata = {16'd0, reg_ch0_xfer_cnt};

      ADDR_CH1_CONTROL:  reg_rdata = {29'd0, reg_ch1_dst_inc, reg_ch1_src_inc, reg_ch1_enable};
      ADDR_CH1_STATUS:   reg_rdata = {dma_ch1_remaining, 13'd0, dma_ch1_error, dma_ch1_done, dma_ch1_busy};
      ADDR_CH1_SRC_ADDR: reg_rdata = reg_ch1_src_addr;
      ADDR_CH1_DST_ADDR: reg_rdata = reg_ch1_dst_addr;
      ADDR_CH1_XFER_CNT: reg_rdata = {16'd0, reg_ch1_xfer_cnt};

      ADDR_IRQ_STATUS:   reg_rdata = {30'd0, irq_status_ch1_q, irq_status_ch0_q};
      default:           reg_rdata = 32'd0;
    endcase
  end

   
  // Slave Response
  always_comb begin
    o_tl_d_valid   = req_valid_q;
    o_tl_d_param   = 3'd0;
    o_tl_d_size    = req_size_q;
    o_tl_d_source  = req_source_q;
    o_tl_d_sink    = 1'b0;
    o_tl_d_denied  = 1'b0;
    o_tl_d_corrupt = 1'b0;

    if (req_opcode_q == Get) begin
      o_tl_d_opcode = AccessAckData;
      o_tl_d_data   = reg_rdata;
    end else begin
      o_tl_d_opcode = AccessAck;
      o_tl_d_data   = 32'd0;
    end
  end

   
  // Interrupt Output
  assign o_dma_irq = irq_status_ch0_q | irq_status_ch1_q;

endmodule
