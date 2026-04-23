module tlul_uart_bridge
  import tlul_pkg::*;
#(
  parameter int CLK_FREQ    = 50_000_000,
  parameter int FIFO_DEPTH  = 128          // TX FIFO depth (bytes)
)(
  input  logic        i_clk,
  input  logic        i_rst_n,
  
  // TL-UL Interface
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
  
  // UART Physical Interface
  input  logic        i_uart_rx,
  output logic        o_uart_tx,
  
  // Interrupt Output 
  output logic        o_irq_rx
);

  // Wires
  logic tx_done, tx_busy;
  logic rx_done, rx_busy;
  logic [7:0] rx_byte_wire;

  // RX data latch — single-byte register
  logic       rx_valid;
  logic [7:0] rx_data_reg;
  logic       rx_clear;          // pulse to clear rx_valid on read

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      rx_valid    <= 1'b0;
      rx_data_reg <= 8'b0;
    end else begin
      if (rx_done) begin
        rx_data_reg <= rx_byte_wire;
        rx_valid    <= 1'b1;
      end else if (rx_clear)
        rx_valid <= 1'b0;
    end
  end

  // Response buffering
  logic       rsp_pending;
  tl_source_t rsp_source;
  tl_size_t   rsp_size;
  logic [2:0] rsp_opcode;
  tl_data_t   rsp_data;

  // Address Decoding (Word Aligned)
  logic [3:0] addr_offset;
  assign addr_offset = i_tl_a_address[3:0];

  // -----------------------------------------------------------------------
  //  TX FIFO  (absorbs burst writes from CPU or DMA)
  //
  //  Register map (updated):
  //    0x0 Write : Push data[7:0] when data[8]=1  (backward compatible)
  //    0x0 Read  : {30'b0, fifo_full, tx_active}
  //                bit[0] = tx_active (UART busy OR FIFO not empty)
  //                bit[1] = fifo_full
  //    0x4 Read  : {rx_valid, 23'b0, rx_data[7:0]}
  //    0x8 Read  : 32'h0000_0004                   (baud code, unchanged)
  //    0xC Write : TX_FIFO_WORD — pushes 4 LE bytes into FIFO (for DMA)
  // -----------------------------------------------------------------------
  localparam FIFO_AW = $clog2(FIFO_DEPTH);          // 7 for depth=128

  logic [7:0]       tx_fifo [FIFO_DEPTH];
  logic [FIFO_AW:0] tx_wr_ptr, tx_rd_ptr;           // extra MSB for full/empty

  wire tx_fifo_empty = (tx_wr_ptr == tx_rd_ptr);
  wire tx_fifo_full  = (tx_wr_ptr[FIFO_AW] != tx_rd_ptr[FIFO_AW]) &&
                       (tx_wr_ptr[FIFO_AW-1:0] == tx_rd_ptr[FIFO_AW-1:0]);
  wire tx_active     = tx_busy | ~tx_fifo_empty;

  // FIFO push port (active 1 cycle → writes 1 byte)
  logic       tx_fifo_push;
  logic [7:0] tx_fifo_wdata;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
      tx_wr_ptr <= '0;
    else if (tx_fifo_push && !tx_fifo_full) begin
      tx_fifo[tx_wr_ptr[FIFO_AW-1:0]] <= tx_fifo_wdata;
      tx_wr_ptr <= tx_wr_ptr + 1;
    end
  end

  // FIFO auto-drain → UART TX
  logic       tx_start_pulse;
  logic [7:0] tx_data_reg;
  logic       drain_guard_q;

  wire tx_fifo_pop = !tx_fifo_empty && !tx_busy && !tx_start_pulse && !drain_guard_q;

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      tx_rd_ptr      <= '0;
      tx_start_pulse <= 1'b0;
      tx_data_reg    <= 8'b0;
      drain_guard_q  <= 1'b0;
    end else begin
      tx_start_pulse <= 1'b0;
      drain_guard_q  <= 1'b0;
      if (tx_fifo_pop) begin
        tx_data_reg    <= tx_fifo[tx_rd_ptr[FIFO_AW-1:0]];
        tx_start_pulse <= 1'b1;
        tx_rd_ptr      <= tx_rd_ptr + 1;
        drain_guard_q  <= 1'b1;
      end
    end
  end

  // -----------------------------------------------------------------------
  //  Word-push FSM  (register 0x0C: TX_FIFO_WORD)
  //    Accepts a 32-bit word and pushes 4 LE bytes into FIFO in 4 cycles.
  //    Used by DMA: src_inc=1, dst_inc=0, dst = 0x1002_000C.
  // -----------------------------------------------------------------------
  logic [31:0] word_sr_q;       // shift register (byte[0] first)
  logic [1:0]  word_cnt_q;      // 0..3
  logic        word_active_q;
  logic        word_start;      // 1-cycle pulse from TL-UL write
  logic [31:0] word_start_data; // latched write data

  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      word_active_q <= 1'b0;
      word_cnt_q    <= 2'd0;
      word_sr_q     <= 32'd0;
    end else if (word_start) begin
      word_sr_q     <= word_start_data;   // latch all 4 bytes
      word_cnt_q    <= 2'd0;
      word_active_q <= 1'b1;
    end else if (word_active_q && !tx_fifo_full) begin
      word_sr_q <= {8'b0, word_sr_q[31:8]};
      if (word_cnt_q == 2'd3) word_active_q <= 1'b0;
      else                    word_cnt_q    <= word_cnt_q + 1;
    end
  end

  // Push mux: word FSM > single-byte push
  logic       reg_byte_push;
  logic [7:0] reg_byte_data;

  always_comb begin
    if (word_active_q && !tx_fifo_full) begin
      tx_fifo_push  = 1'b1;
      tx_fifo_wdata = word_sr_q[7:0];
    end else if (reg_byte_push && !tx_fifo_full) begin
      tx_fifo_push  = 1'b1;
      tx_fifo_wdata = reg_byte_data;
    end else begin
      tx_fifo_push  = 1'b0;
      tx_fifo_wdata = 8'b0;
    end
  end

  // Backpressure: stall during pending response or word-push active
  assign o_tl_a_ready = !rsp_pending && !word_active_q;

  // --- Main Control Block ---
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        rsp_pending     <= 0;
        rsp_source      <= '0;
        rsp_size        <= '0;
        rsp_opcode      <= AccessAck;
        rsp_data        <= '0;
        reg_byte_push   <= 0;
        reg_byte_data   <= 0;
        word_start      <= 0;
        word_start_data <= 0;
        rx_clear        <= 0;
    end else begin
        // Auto-clear pulses
        reg_byte_push <= 1'b0;
        word_start    <= 1'b0;
        rx_clear      <= 1'b0;

        // TL-UL Request Handler
        if (i_tl_a_valid && o_tl_a_ready) begin
            rsp_pending <= 1'b1;
            rsp_source  <= i_tl_a_source;
            rsp_size    <= i_tl_a_size;

            // Write Operations
            if (i_tl_a_opcode == PutFullData || i_tl_a_opcode == PutPartialData) begin
                rsp_opcode <= AccessAck;
                rsp_data   <= '0;
                case (addr_offset)
                    4'h0: begin // TX byte (backward compatible: bit[8]=trigger)
                        if (i_tl_a_data[8]) begin
                            reg_byte_push <= 1'b1;
                            reg_byte_data <= i_tl_a_data[7:0];
                        end
                    end
                    4'hC: begin // TX_FIFO_WORD — push 4 LE bytes (for DMA)
                        word_start      <= 1'b1;
                        word_start_data <= i_tl_a_data;
                    end
                    default: ;
                endcase
            end
            // Read Operations
            else if (i_tl_a_opcode == Get) begin
                rsp_opcode <= AccessAckData;
                case (addr_offset)
                    4'h0: rsp_data <= {30'b0, tx_fifo_full, tx_active}; // TX Status
                    4'h4: begin
                        // RX: {rx_valid, 23'b0, rx_data[7:0]}
                        rsp_data <= {rx_valid, 23'b0, rx_data_reg};
                        rx_clear <= rx_valid;  // only clear if byte was actually valid
                    end
                    4'h8: rsp_data <= 32'h0000_0004; // Fixed baud rate
                    default: rsp_data <= 32'hFFFF_FFFF;
                endcase
            end
        end

        // TL-UL Response Handler
        if (rsp_pending && i_tl_d_ready) begin
            rsp_pending <= 1'b0;
        end
    end
  end

  // --- Output Assignments ---
  assign o_tl_d_valid   = rsp_pending;
  assign o_tl_d_opcode  = rsp_opcode;
  assign o_tl_d_param   = 3'b0;
  assign o_tl_d_size    = rsp_size;
  assign o_tl_d_source  = rsp_source;
  assign o_tl_d_sink    = '0;
  assign o_tl_d_data    = rsp_data;
  assign o_tl_d_denied  = 1'b0;
  assign o_tl_d_corrupt = 1'b0;
  
  // RX Interrupt: High when RX data available
  assign o_irq_rx = rx_valid;

  uart_tx_8bit u_tx (
    .clk      (i_clk),
    .rst_n    (i_rst_n),
    .data_byte(tx_data_reg),
    .send_en  (tx_start_pulse),
    .uart_tx  (o_uart_tx),
    .tx_done  (tx_done),
    .tx_busy  (tx_busy)
  );

  uart_rx_8bit u_rx (
    .clk      (i_clk),
    .rst_n    (i_rst_n),
    .uart_rx  (i_uart_rx),
    .data_byte(rx_byte_wire),
    .rx_done  (rx_done),
    .rx_busy  (rx_busy)
  );

endmodule