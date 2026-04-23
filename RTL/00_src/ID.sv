module ID(
    input logic i_clk, i_reset,
    input logic [31:0] i_instr,
    input logic [31:0] i_pc,
    input logic [4:0] i_rd_addr,
    input logic i_rd_wren,
    input logic [31:0] i_wb_data,

    output logic [31:0] o_rs1_data, o_rs2_data,
    output logic [31:0] o_immgen,
    
    output logic [3:0] o_alu_op,
    output logic o_opa_sel, o_opb_sel,
    output logic o_pc_sel,
    output logic o_lsu_wren,
    output logic [1:0] o_wb_sel,
    output logic [3:0] o_byte_num,
    output logic o_rd_wren,
    output logic o_br_un,
    output logic [2:0] o_funct3,
    output logic o_insn_vld
);

logic [2:0] o_imm_sel; //from control logic to immgen

regfile RegFile (.i_clk(i_clk), 
                 .i_reset(i_reset), 
                 .i_rs1_addr(i_instr[19:15]), 
                 .i_rs2_addr(i_instr[24:20]), 
                 .i_rd_addr(i_rd_addr), 
                 .i_rd_data(i_wb_data), 
                 .i_rd_wren(i_rd_wren), 
                 .o_rs1_data(o_rs1_data), 
                 .o_rs2_data(o_rs2_data));

ImmGen ImmGen ( .i_instr(i_instr), 
                .i_imm_sel(o_imm_sel),
                .o_immgen(o_immgen));

control_logic control_logic(.i_instr(i_instr), 
                            .o_alu_op(o_alu_op),
                            .o_imm_sel(o_imm_sel),
                            .o_byte_num(o_byte_num),
                            .o_wb_sel(o_wb_sel),
                            .o_opa_sel(o_opa_sel),
                            .o_opb_sel(o_opb_sel),
                            .o_pc_sel(o_pc_sel),
                            .o_rd_wren(o_rd_wren),
                            .o_lsu_wren(o_lsu_wren),
                            .o_br_un(o_br_un),
                            .o_funct3(o_funct3),
                            .o_insn_vld(o_insn_vld));
endmodule
