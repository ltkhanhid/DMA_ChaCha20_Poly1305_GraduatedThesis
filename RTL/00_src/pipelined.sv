module pipelined(
    input  logic         i_clk     ,
    input  logic         i_reset   ,
    input  logic [31:0]  i_io_sw   ,
  //  input  logic [31:0]  i_io_key  ,
    output logic [31:0]  o_io_ledr ,
    output logic [31:0]  o_io_ledg ,
    output logic [31:0]  o_io_lcd  ,
    output logic [ 6:0]  o_io_hex0 ,
    output logic [ 6:0]  o_io_hex1 ,
    output logic [ 6:0]  o_io_hex2 ,
    output logic [ 6:0]  o_io_hex3 ,
    output logic [ 6:0]  o_io_hex4 ,
    output logic [ 6:0]  o_io_hex5 ,
    output logic [ 6:0]  o_io_hex6 ,
    output logic [ 6:0]  o_io_hex7 ,

    // Debug
    output logic [31:0]  o_pc_debug,
    output logic         o_insn_vld,
    output logic         o_ctrl    ,
    output logic         o_mispred
);

//IF_ID
logic [31:0] o_pc_IF, o_instr_IF;
logic [31:0] i_pc_ID, i_instr_ID;
//ID_EX
logic [31:0] o_rs1_data_ID, o_rs2_data_ID;
logic [31:0] o_immgen_ID;
logic [3:0] o_alu_op_ID;
logic o_opa_sel_ID, o_opb_sel_ID;
logic o_br_un_ID;
logic [2:0] o_funct3_ID;

logic [1:0] o_wb_sel_ID;
logic [3:0] o_byte_num_ID;
logic o_rd_wren_ID;
logic o_pc_sel_ID;
logic o_lsu_wren_ID;

logic [31:0] i_pc_EX;
logic [31:0] i_instr_EX;
logic [31:0] i_rs1_data_EX, i_rs2_data_EX;
logic [31:0] i_immgen_EX;
logic i_opa_sel_EX, i_opb_sel_EX;
logic i_pc_sel_EX;
logic i_rd_wren_EX;
logic [3:0] i_alu_op_EX;
logic [1:0] i_wb_sel_EX;
logic [3:0] i_byte_num_EX;
logic i_lsu_wren_EX;
logic i_br_un_EX;
logic [2:0] i_funct3_EX;
logic o_pc_sel_EX_actual;

//EX_MEM
logic [31:0] o_alu_data_EX;

logic [31:0] i_pc_MEM;
logic [31:0] i_instr_MEM;
logic [31:0] i_alu_data_MEM;
logic [31:0] i_rs2_data_MEM;
logic i_rd_wren_MEM;
logic i_lsu_wren_MEM;
logic [1:0] i_wb_sel_MEM;
logic [3:0] i_byte_num_MEM;

//MEM_WB
logic [31:0] o_ld_data_MEM;
logic [31:0] o_pc_plus_4_MEM;
logic [31:0] i_pc_WB;
logic [31:0] i_pc_plus_4_WB;
logic [31:0] i_instr_WB;
logic [31:0] i_alu_data_WB;
logic i_rd_wren_WB;
logic [31:0] o_wb_data_WB;
logic [1:0] i_wb_sel_WB;
logic [31:0] i_ld_data_WB;

//hazard detection
logic flush, pc_en, stall;
logic pc_plus4_sel_A, pc_plus4_sel_B;
logic [1:0] fowarding_A, fowarding_B;
logic [31:0] o_rs2_data_EX;
logic mispred_MEM; // Output t? EX_MEM_reg
logic mispred_WB;  // Output t? MEM_WB_reg (S? d�ng l�m output cu?i)

// Branch prediction signals
logic bp_prediction_IF, bp_btb_hit_IF;
logic bp_prediction_ID, bp_btb_hit_ID;
logic bp_prediction_EX;
logic mispred_EX;  // Misprediction detected in EX (for stats)
logic br_flush;    // Flush signal from IF (Branch Predictor Misprediction)
logic bp_update_en;
logic [31:0] bp_update_pc;
logic bp_actual_taken;
logic [31:0] bp_actual_target;

assign o_pc_debug = i_pc_WB; // PC from MEM stage for scoreboard

// o_ctrl active for control transfer instructions (branch and jump)
assign o_ctrl = ~(|(i_instr_WB[6:0] ^ 7'b1100011)) | // Branch
                ~(|(i_instr_WB[6:0] ^ 7'b1101111)) | // JAL
                ~(|(i_instr_WB[6:0] ^ 7'b1100111));  // JALR

assign o_insn_vld = (i_instr_WB != 32'h00000013);
assign o_mispred = mispred_WB;

// Branch prediction update logic
assign bp_update_en = ~(|(i_instr_EX[6:0] ^ 7'b1100011)) || ~(|(i_instr_EX[6:0] ^ 7'b1101111)) || ~(|(i_instr_EX[6:0] ^ 7'b1100111)); // Update for branches, JAL, JALR
assign bp_update_pc = i_pc_EX;
assign bp_actual_taken = o_pc_sel_EX_actual;  // Use actual decision from EX
assign bp_actual_target = o_alu_data_EX;

IF IF (
    .i_clk(i_clk),
    .i_reset(i_reset), 
    .i_pc_en(pc_en),
    
    // Misprediction Detection
    .i_pc_id(i_pc_ID),
    .o_flush(br_flush),
    
    // Branch prediction
    .i_bp_update_en(bp_update_en),
    .i_bp_update_pc(bp_update_pc),
    .i_bp_actual_taken(bp_actual_taken),
    .i_bp_actual_target(bp_actual_target),
    
    .o_pc_out(o_pc_IF),
    .o_instr(o_instr_IF),
    .o_bp_prediction(bp_prediction_IF),
    .o_bp_btb_hit(bp_btb_hit_IF)
);

IF_ID_reg IF_ID_reg (
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_pc(o_pc_IF),
    .i_instr(o_instr_IF),
    .stall(stall),
    .flush(flush),
    .i_bp_prediction(bp_prediction_IF),
    .i_bp_btb_hit(bp_btb_hit_IF),
    .o_pc(i_pc_ID),
    .o_instr(i_instr_ID),
    .o_bp_prediction(bp_prediction_ID),
    .o_bp_btb_hit(bp_btb_hit_ID)
);

ID ID(
    .i_clk(i_clk), 
    .i_reset(i_reset),
    .i_instr(i_instr_ID),
    .i_pc(i_pc_ID),
    .i_rd_addr(i_instr_WB[11:7]), // lay tu wb
    .i_rd_wren(i_rd_wren_WB),
    .i_wb_data(o_wb_data_WB),

    .o_rs1_data(o_rs1_data_ID),
    .o_rs2_data(o_rs2_data_ID),
    .o_immgen(o_immgen_ID), // PC từ ID
    
    .o_alu_op(o_alu_op_ID),
    .o_opa_sel(o_opa_sel_ID),
    .o_opb_sel(o_opb_sel_ID),
    .o_pc_sel(o_pc_sel_ID),
    .o_lsu_wren(o_lsu_wren_ID),
    .o_wb_sel(o_wb_sel_ID),
    .o_byte_num(o_byte_num_ID),
    .o_rd_wren(o_rd_wren_ID),
    .o_br_un(o_br_un_ID),
    .o_funct3(o_funct3_ID),
    .o_insn_vld()  // Not used in top level
);

ID_EX_reg ID_EX_reg(
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_instr(i_instr_ID),
    .i_pc(i_pc_ID),
    .flush(flush),
    .stall(stall),

    .i_rs1_data(o_rs1_data_ID),
    .i_rs2_data(o_rs2_data_ID),
    .i_immgen(o_immgen_ID),

    .i_opa_sel(o_opa_sel_ID),
    .i_opb_sel(o_opb_sel_ID),
    .i_pc_sel(o_pc_sel_ID),
    .i_rd_wren(o_rd_wren_ID),
    .i_alu_op(o_alu_op_ID),
    .i_wb_sel(o_wb_sel_ID),
    .i_byte_num(o_byte_num_ID),
    .i_lsu_wren(o_lsu_wren_ID),
    .i_bp_prediction(bp_prediction_ID),
    .i_br_un(o_br_un_ID),
    .i_funct3(o_funct3_ID),

    .o_instr(i_instr_EX),
    .o_pc(i_pc_EX),
    .o_rs1_data(i_rs1_data_EX),
    .o_rs2_data(i_rs2_data_EX),
    .o_immgen(i_immgen_EX),

    .o_opa_sel(i_opa_sel_EX),
    .o_opb_sel(i_opb_sel_EX),
    .o_pc_sel(i_pc_sel_EX),
    .o_rd_wren(i_rd_wren_EX),
    .o_alu_op(i_alu_op_EX),
    .o_wb_sel(i_wb_sel_EX),
    .o_byte_num(i_byte_num_EX),
    .o_lsu_wren(i_lsu_wren_EX),
    .o_bp_prediction(bp_prediction_EX),
    .o_br_un(i_br_un_EX),
    .o_funct3(i_funct3_EX)
);

EX EX(
    .i_instr(i_instr_EX),
    .i_pc(i_pc_EX),
    .i_rs1_data(i_rs1_data_EX),
    .i_rs2_data(i_rs2_data_EX),
    .i_immgen(i_immgen_EX),

    .i_opa_sel(i_opa_sel_EX),
    .i_opb_sel(i_opb_sel_EX),
    .i_pc_sel(i_pc_sel_EX),
    .i_rd_wren(i_rd_wren_EX),
    .i_alu_op(i_alu_op_EX),
    .i_wb_sel(i_wb_sel_EX),
    .i_byte_num(i_byte_num_EX),
    .i_lsu_wren(i_lsu_wren_EX),
    .i_bp_prediction(bp_prediction_EX),
    .i_br_un(i_br_un_EX),
    .i_funct3(i_funct3_EX),

    .i_pc_plus_4_WB(i_pc_plus_4_WB),
    .i_pc_plus_4_MEM(o_pc_plus_4_MEM),
    .i_alu_data_MEM(i_alu_data_MEM),
    .i_wb_data_WB(o_wb_data_WB),
    .fowarding_A(fowarding_A),
    .fowarding_B(fowarding_B),
    .pc_plus4_sel_A(pc_plus4_sel_A),
    .pc_plus4_sel_B(pc_plus4_sel_B),

    .o_alu_data(o_alu_data_EX),
    .o_rs2_data(o_rs2_data_EX),
    .o_mispred(mispred_EX),
    .o_pc_sel_EX(o_pc_sel_EX_actual)
);

EX_MEM_reg EX_MEM_reg(
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_pc(i_pc_EX),
    .i_instr(i_instr_EX),
    .i_alu_data(o_alu_data_EX),
    .i_rs2_data(o_rs2_data_EX),

    .i_rd_wren(i_rd_wren_EX),
    .i_lsu_wren(i_lsu_wren_EX),
    .i_wb_sel(i_wb_sel_EX),
    .i_byte_num(i_byte_num_EX),

    .o_pc(i_pc_MEM),
    .o_instr(i_instr_MEM),
    .o_alu_data(i_alu_data_MEM),
    .o_rs2_data(i_rs2_data_MEM),

    .o_rd_wren(i_rd_wren_MEM),
    .o_lsu_wren(i_lsu_wren_MEM),
    .o_wb_sel(i_wb_sel_MEM),
    .o_byte_num(i_byte_num_MEM),

    .i_mispred(mispred_EX),
    .o_mispred(mispred_MEM)
);

MEM MEM(
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_pc(i_pc_MEM),
    .i_instr(i_instr_MEM),
    .i_alu_data(i_alu_data_MEM),
    .i_rs2_data(i_rs2_data_MEM),

    .i_rd_wren(i_rd_wren_MEM),
    .i_lsu_wren(i_lsu_wren_MEM),
    .i_wb_sel(i_wb_sel_MEM),
    .i_byte_num(i_byte_num_MEM),

    .i_io_sw(i_io_sw),
  //  .i_io_key(i_io_key),

    .o_io_ledr(o_io_ledr),
    .o_io_ledg(o_io_ledg),
    .o_io_lcd(o_io_lcd),
    .o_io_hex0(o_io_hex0),
    .o_io_hex1(o_io_hex1),
    .o_io_hex2(o_io_hex2),
    .o_io_hex3(o_io_hex3),
    .o_io_hex4(o_io_hex4),
    .o_io_hex5(o_io_hex5),
    .o_io_hex6(o_io_hex6),
    .o_io_hex7(o_io_hex7),

    .o_pc_plus_4(o_pc_plus_4_MEM),
    .o_ld_data(o_ld_data_MEM)


);

MEM_WB_reg MEM_WB_reg(
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_pc(i_pc_MEM),
    .i_pc_plus_4(o_pc_plus_4_MEM),
    .i_instr(i_instr_MEM),
    .i_alu_data(i_alu_data_MEM),
    .i_rd_wren(i_rd_wren_MEM),
    .i_wb_sel(i_wb_sel_MEM),

    .o_pc(i_pc_WB),
    .o_pc_plus_4(i_pc_plus_4_WB),
    .o_instr(i_instr_WB),
    .o_alu_data(i_alu_data_WB),
    .o_rd_wren(i_rd_wren_WB),
    .o_wb_sel(i_wb_sel_WB),

    .i_mispred(mispred_MEM),
    .o_mispred(mispred_WB)
);

WB WB(
    .i_pc_plus_4(i_pc_plus_4_WB),
    .i_instr(i_instr_WB),
    .i_alu_data(i_alu_data_WB),
    .i_ld_data(o_ld_data_MEM),
    .i_wb_sel(i_wb_sel_WB),

    .o_wb_data(o_wb_data_WB)
);
hazard_detection hazard_detection(
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_instr_ID(i_instr_ID),
    .i_instr_EX(i_instr_EX),
    .i_instr_MEM(i_instr_MEM),
    .i_pc_sel_EX(i_pc_sel_EX),
    .i_mispred_EX(br_flush), // Use br_flush from IF (Branch Predictor)
    .flush(flush),
    .pc_en(pc_en),
    .stall(stall)
);

forwarding_unit forwarding_unit_inst(
    .i_instr_EX(i_instr_EX),
    .i_instr_MEM(i_instr_MEM),
    .i_instr_WB(i_instr_WB),
    .i_rd_wren_MEM(i_rd_wren_MEM),
    .i_rd_wren_WB(i_rd_wren_WB),

    .pc_plus4_sel_A(pc_plus4_sel_A),
    .pc_plus4_sel_B(pc_plus4_sel_B),
    .fowarding_A(fowarding_A),
    .fowarding_B(fowarding_B)
);

endmodule
