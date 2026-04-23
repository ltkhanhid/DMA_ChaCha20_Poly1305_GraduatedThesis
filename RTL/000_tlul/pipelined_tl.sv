module pipelined_tl 
  import tlul_pkg::*;
#(
  parameter MEM_FILE = "../../02_test/uart_app_ver3.hex"  // Instruction memory file path
)
(
  input  logic        i_clk,
  input  logic        i_rst_n,
  
  // TileLink Master Port
  output logic         o_tl_a_valid,
  output logic [2:0]   o_tl_a_opcode,
  output logic [2:0]   o_tl_a_param,
  output tl_size_t     o_tl_a_size,
  output tl_source_t   o_tl_a_source,
  output tl_addr_t     o_tl_a_address,
  output tl_mask_t     o_tl_a_mask,
  output tl_data_t     o_tl_a_data,
  output logic         o_tl_a_corrupt,
  input  logic         i_tl_a_ready,

  input  logic         i_tl_d_valid,
  input  logic [2:0]   i_tl_d_opcode,
  input  logic [2:0]   i_tl_d_param,
  input  tl_size_t     i_tl_d_size,
  input  tl_source_t   i_tl_d_source,
  input  tl_sink_t     i_tl_d_sink,
  input  tl_data_t     i_tl_d_data,
  input  logic         i_tl_d_denied,
  input  logic         i_tl_d_corrupt,
  output logic         o_tl_d_ready,

  // Debug outputs
  output logic [31:0]  o_pc_debug,
  output logic [31:0]  o_pc_wb,
  output logic [31:0]  o_pc_mem,
  output logic         o_insn_vld,
  output logic         o_ctrl,
  output logic         o_mispred
);
  
  // IF Stage outputs
  logic [31:0] o_pc_IF, o_instr_IF;

  // IF/ID Register outputs
  logic [31:0] i_pc_ID, i_instr_ID;

  // ID Stage outputs
  logic [31:0] o_rs1_data_ID, o_rs2_data_ID;
  logic [31:0] o_immgen_ID;
  logic [3:0]  o_alu_op_ID;
  logic        o_opa_sel_ID, o_opb_sel_ID;
  logic [1:0]  o_wb_sel_ID;
  logic [3:0]  o_byte_num_ID;
  logic        o_rd_wren_ID;
  logic        o_pc_sel_ID;
  logic        o_lsu_wren_ID;
  logic        o_br_un_ID;
  logic [2:0]  o_funct3_ID;

  // ID/EX Register outputs
  logic [31:0] i_pc_EX;
  logic [31:0] i_instr_EX;
  logic [31:0] i_rs1_data_EX, i_rs2_data_EX;
  logic [31:0] i_immgen_EX;
  logic        i_opa_sel_EX, i_opb_sel_EX;
  logic        i_pc_sel_EX;
  logic        i_rd_wren_EX;
  logic [3:0]  i_alu_op_EX;
  logic [1:0]  i_wb_sel_EX;
  logic [3:0]  i_byte_num_EX;
  logic        i_lsu_wren_EX;
  logic        i_br_un_EX;
  logic [2:0]  i_funct3_EX;

  // EX Stage outputs
  logic [31:0] o_alu_data_EX;
  logic [31:0] o_rs2_data_EX;
  logic        o_mispred_EX;
  logic        o_pc_sel_EX;

  // EX/MEM Register outputs
  logic [31:0] i_pc_MEM;
  logic [31:0] i_instr_MEM;
  logic [31:0] i_alu_data_MEM;
  logic [31:0] i_rs2_data_MEM;
  logic        i_rd_wren_MEM;
  logic        i_lsu_wren_MEM;
  logic [1:0]  i_wb_sel_MEM;
  logic [3:0]  i_byte_num_MEM;
  logic        i_mispred_MEM;

  // MEM Stage outputs
  logic [31:0] o_ld_data_MEM;
  logic [31:0] o_pc_plus_4_MEM;
  logic [1:0]  o_wb_sel_MEM;  // wb_sel output from MEM stage
  logic        lsu_stall;

  // MEM/WB Register outputs
  logic [31:0] i_pc_WB;
  logic [31:0] i_pc_plus_4_WB;
  logic [31:0] i_instr_WB;
  logic [31:0] i_alu_data_WB;
  logic [31:0] o_ld_data_WB;    // Load data from MEM_WB_reg to WB stage
  logic        i_rd_wren_WB;
  logic [1:0]  i_wb_sel_WB;
  logic        i_mispred_WB;

  // WB Stage outputs
  logic [31:0] o_wb_data_WB;

  // Hazard detection outputs
  logic        flush, pc_en, stall;
  logic        load_bubble;        // Insert NOP bubble in ID_EX for load-use

  // Forwarding unit outputs
  logic        pc_plus4_sel_A, pc_plus4_sel_B;
  logic [1:0]  fowarding_A, fowarding_B;

  // Combined stall and flush signals for TileLink pipeline
  logic        combined_flush;
  logic        id_ex_flush;        // ID_EX flush: misprediction OR load-use bubble
  logic        combined_stall;     // stall from hazard_detection OR lsu_stall
  logic        pipeline_stall;     // Stall entire pipeline (for LSU)
  
  assign pipeline_stall = lsu_stall;  // Freeze entire pipeline when LSU is busy
  assign combined_stall = stall | pipeline_stall;  // Combined stall for IF/ID/EX stages
  
  // Flush on misprediction from EX (not during lsu_stall)
  assign combined_flush = (o_mispred_EX | flush) & ~pipeline_stall;
  
  // ID_EX flush: insert NOP bubble on misprediction OR load-use hazard
  // load_bubble inserts a NOP in EX when load is in EX and dependent in ID.
  // The load advances to MEM (EX_MEM not stalled) while dependent stays in ID.
  assign id_ex_flush = combined_flush | (load_bubble & ~pipeline_stall);

  assign o_pc_debug = i_pc_WB;  // PC from WB stage for scoreboard (như pipelined.sv)
  assign o_pc_wb = i_pc_WB;
  assign o_pc_mem = i_pc_MEM;

  assign o_insn_vld = (i_instr_WB != 32'h00000013) & ~pipeline_stall;
  
  // o_ctrl active for control transfer instructions (branch and jump) - dùng i_instr_WB
  assign o_ctrl = ~(|(i_instr_WB[6:0] ^ 7'b1100011)) | 
                  ~(|(i_instr_WB[6:0] ^ 7'b1101111)) | 
                  ~(|(i_instr_WB[6:0] ^ 7'b1100111));
  assign o_mispred = i_mispred_WB;  // Output mispred từ WB stage

  IF #(
    .MEM_FILE(MEM_FILE)
  ) IF_inst (
    .i_clk            (i_clk),
    .i_reset          (i_rst_n),
    .i_pc_en          (pc_en & ~pipeline_stall), 
    
    .i_pc_sel         (o_pc_sel_EX),
    .i_pc_target      (o_alu_data_EX),
    
    // Outputs
    .o_pc_out         (o_pc_IF),
    .o_instr          (o_instr_IF)
  );

  IF_ID_reg IF_ID_reg_inst (
    .i_clk          (i_clk),
    .i_reset        (i_rst_n),
    .i_pc           (o_pc_IF),
    .i_instr        (o_instr_IF),
    .stall          (combined_stall),   // Stall holds data, only flush when not stalled
    .flush          (combined_flush),   // Flush disabled during pipeline_stall
    
    .o_pc           (i_pc_ID),
    .o_instr        (i_instr_ID)
  );

  
  ID ID_inst (
    .i_clk        (i_clk),
    .i_reset      (i_rst_n),
    .i_instr      (i_instr_ID),
    .i_pc         (i_pc_ID),
    .i_rd_addr    (i_instr_WB[11:7]),
    .i_rd_wren    (i_rd_wren_WB),  
    .i_wb_data    (o_wb_data_WB),

    .o_rs1_data   (o_rs1_data_ID),
    .o_rs2_data   (o_rs2_data_ID),
    .o_immgen     (o_immgen_ID),
    
    .o_alu_op     (o_alu_op_ID),
    .o_opa_sel    (o_opa_sel_ID),
    .o_opb_sel    (o_opb_sel_ID),
    .o_pc_sel     (o_pc_sel_ID),
    .o_lsu_wren   (o_lsu_wren_ID),
    .o_wb_sel     (o_wb_sel_ID),
    .o_byte_num   (o_byte_num_ID),
    .o_rd_wren    (o_rd_wren_ID),
    .o_br_un      (o_br_un_ID),
    .o_funct3     (o_funct3_ID),
    .o_insn_vld   () 
  );

  ID_EX_reg_tl ID_EX_reg_inst (
    .i_clk          (i_clk),
    .i_reset        (i_rst_n),
    .flush          (id_ex_flush),      // Insert NOP bubble (mispred OR load-use)
    .stall          (pipeline_stall),   // Freeze/hold values (during LSU stall)
    
    .i_instr        (i_instr_ID),
    .i_pc           (i_pc_ID),
    .i_rs1_data     (o_rs1_data_ID),
    .i_rs2_data     (o_rs2_data_ID),
    .i_immgen       (o_immgen_ID),

    .i_opa_sel      (o_opa_sel_ID),
    .i_opb_sel      (o_opb_sel_ID),
    .i_pc_sel       (o_pc_sel_ID),
    .i_rd_wren      (o_rd_wren_ID),
    .i_alu_op       (o_alu_op_ID),
    .i_wb_sel       (o_wb_sel_ID),
    .i_byte_num     (o_byte_num_ID),
    .i_lsu_wren     (o_lsu_wren_ID),
    .i_br_un        (o_br_un_ID),
    .i_funct3       (o_funct3_ID),

    .o_instr        (i_instr_EX),
    .o_pc           (i_pc_EX),
    .o_rs1_data     (i_rs1_data_EX),
    .o_rs2_data     (i_rs2_data_EX),
    .o_immgen       (i_immgen_EX),

    .o_opa_sel      (i_opa_sel_EX),
    .o_opb_sel      (i_opb_sel_EX),
    .o_pc_sel       (i_pc_sel_EX),
    .o_rd_wren      (i_rd_wren_EX),
    .o_alu_op       (i_alu_op_EX),
    .o_wb_sel       (i_wb_sel_EX),
    .o_lsu_wren     (i_lsu_wren_EX),
    .o_byte_num     (i_byte_num_EX),
    .o_br_un        (i_br_un_EX),
    .o_funct3       (i_funct3_EX)
  );

  EX EX_inst (
    .i_instr        (i_instr_EX),
    .i_pc           (i_pc_EX),
    .i_rs1_data     (i_rs1_data_EX),
    .i_rs2_data     (i_rs2_data_EX),
    .i_immgen       (i_immgen_EX),

    .i_opa_sel      (i_opa_sel_EX),
    .i_opb_sel      (i_opb_sel_EX),
    .i_pc_sel       (i_pc_sel_EX),
    .i_rd_wren      (i_rd_wren_EX),
    .i_alu_op       (i_alu_op_EX),
    .i_wb_sel       (i_wb_sel_EX),
    .i_byte_num     (i_byte_num_EX),
    .i_lsu_wren     (i_lsu_wren_EX),
    
    .i_br_un        (i_br_un_EX),
    .i_funct3       (i_funct3_EX),

    // Forwarding inputs
    .fowarding_A    (fowarding_A),
    .fowarding_B    (fowarding_B),
    .pc_plus4_sel_A (pc_plus4_sel_A),
    .pc_plus4_sel_B (pc_plus4_sel_B),
    .i_pc_plus_4_WB (i_pc_plus_4_WB),
    .i_pc_plus_4_MEM(o_pc_plus_4_MEM),
    .i_alu_data_MEM (i_alu_data_MEM),
    .i_wb_data_WB   (o_wb_data_WB),

    // Outputs
    .o_alu_data     (o_alu_data_EX),
    .o_rs2_data     (o_rs2_data_EX),
    .o_mispred      (o_mispred_EX),
    .o_pc_sel_EX    (o_pc_sel_EX)
  );

  EX_MEM_reg_tl EX_MEM_reg_inst (
    .i_clk      (i_clk),
    .i_reset    (i_rst_n),
    .stall      (pipeline_stall),  // Hold data during LSU stall
    
    .i_pc       (i_pc_EX),
    .i_instr    (i_instr_EX),
    .i_alu_data (o_alu_data_EX),
    .i_rs2_data (o_rs2_data_EX),

    .i_rd_wren  (i_rd_wren_EX),
    .i_lsu_wren (i_lsu_wren_EX),
    .i_wb_sel   (i_wb_sel_EX),
    .i_byte_num (i_byte_num_EX),
    .i_mispred  (o_mispred_EX),

    .o_pc       (i_pc_MEM),
    .o_instr    (i_instr_MEM),
    .o_alu_data (i_alu_data_MEM),
    .o_rs2_data (i_rs2_data_MEM),

    .o_rd_wren  (i_rd_wren_MEM),
    .o_lsu_wren (i_lsu_wren_MEM),
    .o_wb_sel   (i_wb_sel_MEM),
    .o_byte_num (i_byte_num_MEM),
    .o_mispred  (i_mispred_MEM)
  );

  // ==========================================================================
  // MEM Stage - Memory Access via TileLink
  // ==========================================================================
  MEM_tl MEM_tl_inst (
    .i_clk      (i_clk),
    .i_rst_n    (i_rst_n),
    .i_pc       (i_pc_MEM),
    .i_instr    (i_instr_MEM),
    .i_alu_data (i_alu_data_MEM),
    .i_rs2_data (i_rs2_data_MEM),

    .i_rd_wren  (i_rd_wren_MEM),
    .i_lsu_wren (i_lsu_wren_MEM),
    .i_wb_sel   (i_wb_sel_MEM),
    .i_byte_num (i_byte_num_MEM),

    // Pipeline outputs
    .o_lsu_stall(lsu_stall),
    .o_pc_plus_4(o_pc_plus_4_MEM),
    .o_ld_data  (o_ld_data_MEM),
    .o_wb_sel   (o_wb_sel_MEM),
    
    // TileLink Master Port
    .o_tl_a_valid   (o_tl_a_valid),
    .o_tl_a_opcode  (o_tl_a_opcode),
    .o_tl_a_param   (o_tl_a_param),
    .o_tl_a_size    (o_tl_a_size),
    .o_tl_a_source  (o_tl_a_source),
    .o_tl_a_address (o_tl_a_address),
    .o_tl_a_mask    (o_tl_a_mask),
    .o_tl_a_data    (o_tl_a_data),
    .o_tl_a_corrupt (o_tl_a_corrupt),
    .i_tl_a_ready   (i_tl_a_ready),
    
    .i_tl_d_valid   (i_tl_d_valid),
    .i_tl_d_opcode  (i_tl_d_opcode),
    .i_tl_d_param   (i_tl_d_param),
    .i_tl_d_size    (i_tl_d_size),
    .i_tl_d_source  (i_tl_d_source),
    .i_tl_d_sink    (i_tl_d_sink),
    .i_tl_d_data    (i_tl_d_data),
    .i_tl_d_denied  (i_tl_d_denied),
    .i_tl_d_corrupt (i_tl_d_corrupt),
    .o_tl_d_ready   (o_tl_d_ready)
  );

  MEM_WB_reg_tl MEM_WB_reg_inst (
    .i_clk      (i_clk),
    .i_reset    (i_rst_n),
    .stall      (pipeline_stall),  // Hold data during LSU stall
    
    .i_pc       (i_pc_MEM),
    .i_instr    (i_instr_MEM),
    .i_alu_data (i_alu_data_MEM),
    .i_ld_data  (o_ld_data_MEM),           // NOT USED - load data bypasses this register
    .i_pc_plus_4(o_pc_plus_4_MEM),
    .i_mispred  (i_mispred_MEM),

    .i_wb_sel   (o_wb_sel_MEM),
    .i_rd_wren  (i_rd_wren_MEM),

    .o_pc       (i_pc_WB),
    .o_pc_plus_4(i_pc_plus_4_WB),
    .o_instr    (i_instr_WB),
    .o_alu_data (i_alu_data_WB),
    .o_ld_data  (o_ld_data_WB),          
    .o_wb_sel   (i_wb_sel_WB),
    .o_rd_wren  (i_rd_wren_WB),
    .o_mispred  (i_mispred_WB)
  );


  WB WB_inst (
    .i_pc_plus_4(i_pc_plus_4_WB),
    .i_instr    (i_instr_WB),
    .i_alu_data (i_alu_data_WB),
    .i_ld_data  (o_ld_data_WB),  // oad data comes DIRECTLY from MEM (bypasses MEM_WB_reg)
    .i_wb_sel   (i_wb_sel_WB),    // wb_sel goes through MEM_WB_reg (normal pipeline)

    .o_wb_data  (o_wb_data_WB)
  );

  hazard_detection_tl hazard_detection_inst (
    .i_clk      (i_clk),
    .i_reset    (i_rst_n),
    .i_instr_ID (i_instr_ID),
    .i_instr_EX (i_instr_EX),
    .i_instr_MEM(i_instr_MEM),
    .i_pc_sel_EX(i_pc_sel_EX),
    .i_mispred_EX(o_mispred_EX),
    .i_lsu_stall(lsu_stall),
    
    .flush      (flush),
    .pc_en      (pc_en),
    .stall      (stall),
    .load_bubble(load_bubble)
  );

  forwarding_unit forwarding_unit_inst (
    .i_instr_EX    (i_instr_EX),
    .i_instr_MEM   (i_instr_MEM),
    .i_instr_WB    (i_instr_WB),
    .i_rd_wren_MEM (i_rd_wren_MEM),
    .i_rd_wren_WB  (i_rd_wren_WB),

    .pc_plus4_sel_A(pc_plus4_sel_A),
    .pc_plus4_sel_B(pc_plus4_sel_B),
    .fowarding_A   (fowarding_A),
    .fowarding_B   (fowarding_B)
  );

endmodule
