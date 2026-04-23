module tlul_chacha20
  import tlul_pkg::*;
(
  input  logic        i_clk,
  input  logic        i_rst_n,

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

  // ===== Interrupt =====
  output logic        o_chacha_irq
);

  
  // Word-address decode — addr[7:2] selects which 32-bit register
  
  //  Word  Byte    Register
  //  0-7   00-1C   KEY[0..7]
  //  8-10  20-28   NONCE[0..2]
  //  11    2C      COUNTER
  //  12    30      CONTROL
  //  13    34      STATUS
  //  14    38      IRQ_STATUS
  //  15    3C      (reserved)
  //  16-31 40-7C   PLAINTEXT[0..15]
  //  32-47 80-BC   CIPHERTEXT[0..15]  (read-only)
  

  
  // Configuration registers
  
  logic [31:0] reg_key   [8];
  logic [31:0] reg_nonce [3];
  logic [31:0] reg_counter;
  logic [31:0] reg_ptext [16];
  logic [31:0] reg_ctext [16];

  
  // Control / statu
  logic        start_trigger;           // 1-cycle pulse to core
  logic        irq_done_q;             // Sticky done interrupt (W1C)

  
  // Core interface
  logic [31:0] core_keystream [16];
  logic        core_ready;
  logic        core_valid;              // 1-cycle pulse when keystream ready

  
  // TileLink slave protocol
  logic [7:0]  reg_addr;
  logic [5:0]  word_addr;               // reg_addr[7:2]
  logic [2:0]  req_opcode_q;
  logic [2:0]  req_size_q;
  logic [TL_AIW-1:0] req_source_q;
  logic        req_valid_q;

  logic        reg_we;
  logic [31:0] reg_wdata;
  logic [31:0] reg_rdata;

  // Byte-lane write mask expanded from TL-UL a_mask (4 bits → 32 bits)
  wire  [31:0] wmask = {{8{i_tl_a_mask[3]}}, {8{i_tl_a_mask[2]}},
                        {8{i_tl_a_mask[1]}}, {8{i_tl_a_mask[0]}}};

  
  // ChaCha20 Core Instance
  chacha20_core u_core (
    .clk_i        (i_clk),
    .rst_ni       (i_rst_n),
    .start_i      (start_trigger),
    .key_i        (reg_key),
    .nonce_i      (reg_nonce),
    .counter_i    (reg_counter),
    .keystream_o  (core_keystream),
    .ready_o      (core_ready),
    .valid_o      (core_valid)
  );

  
  // Address Decode
  
  assign reg_addr  = i_tl_a_address[7:0];
  assign word_addr = reg_addr[7:2];
  assign reg_we    = i_tl_a_valid && o_tl_a_ready && (i_tl_a_opcode != Get);
  assign reg_wdata = i_tl_a_data;

  
  // TileLink Slave — Request Capture (same pattern as tlul_dma)
  
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

  
  // Register Write Logic
  
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      for (int i = 0; i < 8;  i++) reg_key[i]   <= 32'd0;
      for (int i = 0; i < 3;  i++) reg_nonce[i]  <= 32'd0;
      for (int i = 0; i < 16; i++) reg_ptext[i]  <= 32'd0;
      for (int i = 0; i < 16; i++) reg_ctext[i]  <= 32'd0;
      reg_counter    <= 32'd0;
      start_trigger  <= 1'b0;
      irq_done_q     <= 1'b0;
    end else begin
      //  Self-clearing start trigger 
      start_trigger <= 1'b0;

      //  Capture ciphertext on core completion 
      if (core_valid) begin
        for (int i = 0; i < 16; i++)
          reg_ctext[i] <= reg_ptext[i] ^ core_keystream[i];
        // Auto-increment counter (RFC 8439 §2.4 — "incrementing block counter")
        reg_counter <= reg_counter + 32'd1;
      end

      //  Register writes from CPU (before IRQ set, so SET wins same-cycle race)
      if (reg_we) begin
        case (word_addr)
          // KEY[0..7]  (0x00-0x1C)  — byte-masked writes
          6'd0:  reg_key[0] <= (reg_wdata & wmask) | (reg_key[0] & ~wmask);
          6'd1:  reg_key[1] <= (reg_wdata & wmask) | (reg_key[1] & ~wmask);
          6'd2:  reg_key[2] <= (reg_wdata & wmask) | (reg_key[2] & ~wmask);
          6'd3:  reg_key[3] <= (reg_wdata & wmask) | (reg_key[3] & ~wmask);
          6'd4:  reg_key[4] <= (reg_wdata & wmask) | (reg_key[4] & ~wmask);
          6'd5:  reg_key[5] <= (reg_wdata & wmask) | (reg_key[5] & ~wmask);
          6'd6:  reg_key[6] <= (reg_wdata & wmask) | (reg_key[6] & ~wmask);
          6'd7:  reg_key[7] <= (reg_wdata & wmask) | (reg_key[7] & ~wmask);

          // NONCE[0..2]  (0x20-0x28)  — byte-masked writes
          6'd8:  reg_nonce[0] <= (reg_wdata & wmask) | (reg_nonce[0] & ~wmask);
          6'd9:  reg_nonce[1] <= (reg_wdata & wmask) | (reg_nonce[1] & ~wmask);
          6'd10: reg_nonce[2] <= (reg_wdata & wmask) | (reg_nonce[2] & ~wmask);

          // COUNTER (0x2C) — CPU can override auto-increment, byte-masked
          6'd11: reg_counter <= (reg_wdata & wmask) | (reg_counter & ~wmask);

          // CONTROL (0x30) — bit[0] = start (gated by ready)
          6'd12: begin
            if (i_tl_a_mask[0] && reg_wdata[0] && core_ready)
              start_trigger <= 1'b1;
          end

          // STATUS (0x34) — read-only, ignore writes

          // IRQ_STATUS (0x38) — W1C (only if byte-0 mask active)
          6'd14: begin
            if (i_tl_a_mask[0] && reg_wdata[0]) irq_done_q <= 1'b0;
          end

          // PLAINTEXT[0..15]  (0x40-0x7C)  — byte-masked writes
          6'd16: reg_ptext[ 0] <= (reg_wdata & wmask) | (reg_ptext[ 0] & ~wmask);
          6'd17: reg_ptext[ 1] <= (reg_wdata & wmask) | (reg_ptext[ 1] & ~wmask);
          6'd18: reg_ptext[ 2] <= (reg_wdata & wmask) | (reg_ptext[ 2] & ~wmask);
          6'd19: reg_ptext[ 3] <= (reg_wdata & wmask) | (reg_ptext[ 3] & ~wmask);
          6'd20: reg_ptext[ 4] <= (reg_wdata & wmask) | (reg_ptext[ 4] & ~wmask);
          6'd21: reg_ptext[ 5] <= (reg_wdata & wmask) | (reg_ptext[ 5] & ~wmask);
          6'd22: reg_ptext[ 6] <= (reg_wdata & wmask) | (reg_ptext[ 6] & ~wmask);
          6'd23: reg_ptext[ 7] <= (reg_wdata & wmask) | (reg_ptext[ 7] & ~wmask);
          6'd24: reg_ptext[ 8] <= (reg_wdata & wmask) | (reg_ptext[ 8] & ~wmask);
          6'd25: reg_ptext[ 9] <= (reg_wdata & wmask) | (reg_ptext[ 9] & ~wmask);
          6'd26: reg_ptext[10] <= (reg_wdata & wmask) | (reg_ptext[10] & ~wmask);
          6'd27: reg_ptext[11] <= (reg_wdata & wmask) | (reg_ptext[11] & ~wmask);
          6'd28: reg_ptext[12] <= (reg_wdata & wmask) | (reg_ptext[12] & ~wmask);
          6'd29: reg_ptext[13] <= (reg_wdata & wmask) | (reg_ptext[13] & ~wmask);
          6'd30: reg_ptext[14] <= (reg_wdata & wmask) | (reg_ptext[14] & ~wmask);
          6'd31: reg_ptext[15] <= (reg_wdata & wmask) | (reg_ptext[15] & ~wmask);

          // CIPHERTEXT (0x80-0xBC) — read-only, ignore writes
          default: ;
        endcase
      end

      //  IRQ sticky set (after W1C, so SET wins same-cycle race)
      if (core_valid)
        irq_done_q <= 1'b1;
    end
  end

  
  // Register Read Logic
  
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
      // KEY
      6'd0:  reg_rdata = reg_key[0];
      6'd1:  reg_rdata = reg_key[1];
      6'd2:  reg_rdata = reg_key[2];
      6'd3:  reg_rdata = reg_key[3];
      6'd4:  reg_rdata = reg_key[4];
      6'd5:  reg_rdata = reg_key[5];
      6'd6:  reg_rdata = reg_key[6];
      6'd7:  reg_rdata = reg_key[7];

      // NONCE
      6'd8:  reg_rdata = reg_nonce[0];
      6'd9:  reg_rdata = reg_nonce[1];
      6'd10: reg_rdata = reg_nonce[2];

      // COUNTER
      6'd11: reg_rdata = reg_counter;

      // CONTROL — self-clearing, always reads 0
      6'd12: reg_rdata = 32'd0;

      // STATUS — [0]=ready
      6'd13: reg_rdata = {31'd0, core_ready};

      // IRQ_STATUS — [0]=done_irq
      6'd14: reg_rdata = {31'd0, irq_done_q};

      // PLAINTEXT
      6'd16: reg_rdata = reg_ptext[ 0];
      6'd17: reg_rdata = reg_ptext[ 1];
      6'd18: reg_rdata = reg_ptext[ 2];
      6'd19: reg_rdata = reg_ptext[ 3];
      6'd20: reg_rdata = reg_ptext[ 4];
      6'd21: reg_rdata = reg_ptext[ 5];
      6'd22: reg_rdata = reg_ptext[ 6];
      6'd23: reg_rdata = reg_ptext[ 7];
      6'd24: reg_rdata = reg_ptext[ 8];
      6'd25: reg_rdata = reg_ptext[ 9];
      6'd26: reg_rdata = reg_ptext[10];
      6'd27: reg_rdata = reg_ptext[11];
      6'd28: reg_rdata = reg_ptext[12];
      6'd29: reg_rdata = reg_ptext[13];
      6'd30: reg_rdata = reg_ptext[14];
      6'd31: reg_rdata = reg_ptext[15];

      // CIPHERTEXT
      6'd32: reg_rdata = reg_ctext[ 0];
      6'd33: reg_rdata = reg_ctext[ 1];
      6'd34: reg_rdata = reg_ctext[ 2];
      6'd35: reg_rdata = reg_ctext[ 3];
      6'd36: reg_rdata = reg_ctext[ 4];
      6'd37: reg_rdata = reg_ctext[ 5];
      6'd38: reg_rdata = reg_ctext[ 6];
      6'd39: reg_rdata = reg_ctext[ 7];
      6'd40: reg_rdata = reg_ctext[ 8];
      6'd41: reg_rdata = reg_ctext[ 9];
      6'd42: reg_rdata = reg_ctext[10];
      6'd43: reg_rdata = reg_ctext[11];
      6'd44: reg_rdata = reg_ctext[12];
      6'd45: reg_rdata = reg_ctext[13];
      6'd46: reg_rdata = reg_ctext[14];
      6'd47: reg_rdata = reg_ctext[15];

      default: reg_rdata = 32'd0;
    endcase
  end

  
  // TileLink Slave Response
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
  assign o_chacha_irq = irq_done_q;

endmodule
