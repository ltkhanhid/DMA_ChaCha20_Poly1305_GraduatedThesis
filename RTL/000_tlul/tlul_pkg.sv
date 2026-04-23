package tlul_pkg;

  parameter int unsigned TL_AW  = 32;
  parameter int unsigned TL_DW  = 32;
  parameter int unsigned TL_AIW = 5;
  parameter int unsigned TL_DIW = 1;
  parameter int unsigned TL_DBW = TL_DW/8;

  typedef logic [TL_AW-1:0] tl_addr_t;
  typedef logic [TL_DW-1:0] tl_data_t;
  typedef logic [TL_DBW-1:0] tl_mask_t;
  typedef logic [2:0] tl_size_t;
  typedef logic [TL_AIW-1:0] tl_source_t;
  typedef logic [TL_DIW-1:0] tl_sink_t;

  typedef struct packed {
    logic [2:0] a_opcode;
    logic [2:0] a_param;
    tl_size_t a_size;    
    tl_source_t a_source;
    tl_addr_t a_address;
    tl_mask_t a_mask;
    tl_data_t a_data;
    logic a_corrupt;
    logic a_valid;

    logic a_ready;
  } tl_h2d_t;

  typedef struct packed {
    logic [2:0] d_opcode;
    logic [2:0] d_param;
    tl_size_t d_size;
    tl_source_t d_source;
    tl_sink_t d_sink;
    tl_data_t d_data;
    logic d_denied;
    logic d_corrupt;
    logic d_valid;

    logic d_ready;
  } tl_d2h_t;

  // TileLink Channel A Opcodes
  localparam logic [2:0] PutFullData = 3'd0;
  localparam logic [2:0] PutPartialData = 3'd1;
  localparam logic [2:0] Get = 3'd4;
  
  localparam logic [2:0] TL_A_PUT_FULL_DATA = 3'd0;
  localparam logic [2:0] TL_A_PUT_PARTIAL_DATA = 3'd1;
  localparam logic [2:0] TL_A_GET = 3'd4;

  // TileLink Channel D Opcodes
  localparam logic [2:0] AccessAck = 3'd0;
  localparam logic [2:0] AccessAckData = 3'd1;
  
  localparam logic [2:0] TL_D_ACCESS_ACK = 3'd0;
  localparam logic [2:0] TL_D_ACCESS_ACK_DATA = 3'd1;

endpackage
