// ============================================================================
// tlul_poly1305.sv — TL-UL slave register bridge for Poly1305 MAC
//
// Register map  (word-address = addr[7:2]):
//
//  Word  Byte   Name        R/W   Description
//  ----  -----  ----------  ----  -----------------------------------------
//  0     0x00   KEY_R0      RW    r[31:0]    (clamped internally)
//  1     0x04   KEY_R1      RW    r[63:32]
//  2     0x08   KEY_R2      RW    r[95:64]
//  3     0x0C   KEY_R3      RW    r[127:96]
//  4     0x10   KEY_S0      RW    s[31:0]
//  5     0x14   KEY_S1      RW    s[63:32]
//  6     0x18   KEY_S2      RW    s[95:64]
//  7     0x1C   KEY_S3      RW    s[127:96]
//  8     0x20   MSG0        RW    block[31:0]
//  9     0x24   MSG1        RW    block[63:32]
//  10    0x28   MSG2        RW    block[95:64]
//  11    0x2C   MSG3        RW    block[127:96]
//  12    0x30   CONTROL     RW    [0]=init  [1]=block  [2]=finalize (self-clear)
//  13    0x34   BLOCK_LEN   RW    Bytes in current block (1–16), default 16
//  14    0x38   STATUS      RO    [0]=busy  [1]=valid
//  15    0x3C   IRQ_STATUS  W1C   [0]=done_irq
//  16    0x40   TAG0        RO    tag[31:0]
//  17    0x44   TAG1        RO    tag[63:32]
//  18    0x48   TAG2        RO    tag[95:64]
//  19    0x4C   TAG3        RO    tag[127:96]
//
// Author : Copilot  (following tlul_chacha20.sv pattern)
// ============================================================================

module tlul_poly1305
  import tlul_pkg::*;
(
  input  logic        i_clk,
  input  logic        i_rst_n,

  // TL-UL Channel A (host → device)
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

  // TL-UL Channel D (device → host)
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

  // Interrupt
  output logic        o_poly_irq
);

  // -----------------------------------------------------------------------
  //  Configuration registers
  // -----------------------------------------------------------------------
  logic [31:0] reg_key_r [4];     // KEY_R0..3  (r part of key)
  logic [31:0] reg_key_s [4];     // KEY_S0..3  (s part of key)
  logic [31:0] reg_msg   [4];     // MSG0..3    (message block)
  logic [4:0]  reg_block_len;     // BLOCK_LEN  (1–16)

  // Control triggers (self-clearing, 1-cycle pulse)
  logic        ctrl_init;
  logic        ctrl_block;
  logic        ctrl_finalize;

  // IRQ
  logic        irq_done_q;

  // -----------------------------------------------------------------------
  //  Core interface signals
  // -----------------------------------------------------------------------
  logic         core_busy;
  logic         core_done;
  logic         core_valid;
  logic [127:0] core_tag;

  // Pack register arrays into 128-bit buses
  wire [127:0] key_r_bus = {reg_key_r[3], reg_key_r[2], reg_key_r[1], reg_key_r[0]};
  wire [127:0] key_s_bus = {reg_key_s[3], reg_key_s[2], reg_key_s[1], reg_key_s[0]};
  wire [127:0] msg_bus   = {reg_msg[3],   reg_msg[2],   reg_msg[1],   reg_msg[0]};

  // -----------------------------------------------------------------------
  //  Poly1305 Core Instance
  // -----------------------------------------------------------------------
  poly1305_core u_core (
    .clk_i         (i_clk),
    .rst_ni        (i_rst_n),
    .init_i        (ctrl_init),
    .block_valid_i (ctrl_block),
    .finalize_i    (ctrl_finalize),
    .key_r_i       (key_r_bus),
    .key_s_i       (key_s_bus),
    .block_i       (msg_bus),
    .block_len_i   (reg_block_len),
    .busy_o        (core_busy),
    .done_o        (core_done),
    .valid_o       (core_valid),
    .tag_o         (core_tag)
  );

  // -----------------------------------------------------------------------
  //  TileLink slave protocol
  // -----------------------------------------------------------------------
  logic [7:0]           reg_addr;
  logic [5:0]           word_addr;      // reg_addr[7:2]  (up to 64 words)
  logic [2:0]           req_opcode_q;
  logic [2:0]           req_size_q;
  logic [TL_AIW-1:0]   req_source_q;
  logic                 req_valid_q;

  logic        reg_we;
  logic [31:0] reg_wdata;
  logic [31:0] reg_rdata;

  // Byte-lane write mask  (4 bits → 32 bits)
  wire [31:0] wmask = {{8{i_tl_a_mask[3]}}, {8{i_tl_a_mask[2]}},
                        {8{i_tl_a_mask[1]}}, {8{i_tl_a_mask[0]}}};

  assign reg_addr  = i_tl_a_address[7:0];
  assign word_addr = reg_addr[7:2];
  assign reg_we    = i_tl_a_valid && o_tl_a_ready && (i_tl_a_opcode != Get);
  assign reg_wdata = i_tl_a_data;

  // -----------------------------------------------------------------------
  //  Request capture  (same pattern as tlul_chacha20)
  // -----------------------------------------------------------------------
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

  assign o_tl_a_ready = !req_valid_q;

  // -----------------------------------------------------------------------
  //  Register Write Logic
  // -----------------------------------------------------------------------
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      for (int i = 0; i < 4; i++) reg_key_r[i] <= 32'd0;
      for (int i = 0; i < 4; i++) reg_key_s[i] <= 32'd0;
      for (int i = 0; i < 4; i++) reg_msg[i]   <= 32'd0;
      reg_block_len <= 5'd16;
      ctrl_init     <= 1'b0;
      ctrl_block    <= 1'b0;
      ctrl_finalize <= 1'b0;
      irq_done_q    <= 1'b0;
    end else begin
      // Self-clearing control triggers
      ctrl_init     <= 1'b0;
      ctrl_block    <= 1'b0;
      ctrl_finalize <= 1'b0;

      // Register writes from CPU (before IRQ set, so SET wins same-cycle race)
      if (reg_we) begin
        case (word_addr)
          // KEY_R0..3  (0x00–0x0C)
          6'd0:  reg_key_r[0] <= (reg_wdata & wmask) | (reg_key_r[0] & ~wmask);
          6'd1:  reg_key_r[1] <= (reg_wdata & wmask) | (reg_key_r[1] & ~wmask);
          6'd2:  reg_key_r[2] <= (reg_wdata & wmask) | (reg_key_r[2] & ~wmask);
          6'd3:  reg_key_r[3] <= (reg_wdata & wmask) | (reg_key_r[3] & ~wmask);

          // KEY_S0..3  (0x10–0x1C)
          6'd4:  reg_key_s[0] <= (reg_wdata & wmask) | (reg_key_s[0] & ~wmask);
          6'd5:  reg_key_s[1] <= (reg_wdata & wmask) | (reg_key_s[1] & ~wmask);
          6'd6:  reg_key_s[2] <= (reg_wdata & wmask) | (reg_key_s[2] & ~wmask);
          6'd7:  reg_key_s[3] <= (reg_wdata & wmask) | (reg_key_s[3] & ~wmask);

          // MSG0..3  (0x20–0x2C)
          6'd8:  reg_msg[0] <= (reg_wdata & wmask) | (reg_msg[0] & ~wmask);
          6'd9:  reg_msg[1] <= (reg_wdata & wmask) | (reg_msg[1] & ~wmask);
          6'd10: reg_msg[2] <= (reg_wdata & wmask) | (reg_msg[2] & ~wmask);
          6'd11: reg_msg[3] <= (reg_wdata & wmask) | (reg_msg[3] & ~wmask);

          // CONTROL (0x30) — [0]=init  [1]=block  [2]=finalize
          // Priority: init > block > finalize (only one action per write)
          6'd12: begin
            if (i_tl_a_mask[0] && !core_busy) begin
              if (reg_wdata[0])
                ctrl_init     <= 1'b1;
              else if (reg_wdata[1])
                ctrl_block    <= 1'b1;
              else if (reg_wdata[2])
                ctrl_finalize <= 1'b1;
            end
          end

          // BLOCK_LEN (0x34)
          6'd13: begin
            if (i_tl_a_mask[0])
              reg_block_len <= reg_wdata[4:0];
          end

          // STATUS (0x38)  — read-only, ignore writes

          // IRQ_STATUS (0x3C) — W1C
          6'd15: begin
            if (i_tl_a_mask[0] && reg_wdata[0]) irq_done_q <= 1'b0;
          end

          // TAG0..3 (0x40–0x4C) — read-only, ignore writes

          default: ;
        endcase
      end

      // IRQ sticky set (after W1C, so SET wins same-cycle race)
      if (core_done)
        irq_done_q <= 1'b1;
    end
  end

  // -----------------------------------------------------------------------
  //  Register Read Logic
  // -----------------------------------------------------------------------
  logic [7:0] addr_latch_q;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      addr_latch_q <= 8'd0;
    else if (i_tl_a_valid && o_tl_a_ready)
      addr_latch_q <= reg_addr;
  end

  wire [5:0] rd_word = addr_latch_q[7:2];

  always_comb begin
    reg_rdata = 32'd0;
    case (rd_word)
      // KEY_R0..3
      6'd0:  reg_rdata = reg_key_r[0];
      6'd1:  reg_rdata = reg_key_r[1];
      6'd2:  reg_rdata = reg_key_r[2];
      6'd3:  reg_rdata = reg_key_r[3];

      // KEY_S0..3
      6'd4:  reg_rdata = reg_key_s[0];
      6'd5:  reg_rdata = reg_key_s[1];
      6'd6:  reg_rdata = reg_key_s[2];
      6'd7:  reg_rdata = reg_key_s[3];

      // MSG0..3
      6'd8:  reg_rdata = reg_msg[0];
      6'd9:  reg_rdata = reg_msg[1];
      6'd10: reg_rdata = reg_msg[2];
      6'd11: reg_rdata = reg_msg[3];

      // CONTROL — self-clearing, reads 0
      6'd12: reg_rdata = 32'd0;

      // BLOCK_LEN
      6'd13: reg_rdata = {27'd0, reg_block_len};

      // STATUS — [0]=busy  [1]=valid
      6'd14: reg_rdata = {30'd0, core_valid, core_busy};

      // IRQ_STATUS — [0]=done_irq
      6'd15: reg_rdata = {31'd0, irq_done_q};

      // TAG0..3
      6'd16: reg_rdata = core_tag[ 31:  0];
      6'd17: reg_rdata = core_tag[ 63: 32];
      6'd18: reg_rdata = core_tag[ 95: 64];
      6'd19: reg_rdata = core_tag[127: 96];

      default: reg_rdata = 32'd0;
    endcase
  end
  
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

  // Interrupt output
  assign o_poly_irq = irq_done_q;

endmodule
