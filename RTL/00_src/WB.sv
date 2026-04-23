module WB(
    input logic [31:0] i_pc_plus_4,
    input logic [31:0] i_instr,
    input logic [31:0] i_alu_data,
    input logic [31:0] i_ld_data,


    // control signals
    input logic [1:0] i_wb_sel,

    output logic [31:0] o_wb_data
);


mux3_wb mux_wb(
    .i_alu_data(i_alu_data),
    .i_ld_data(i_ld_data),
    .i_pc_out(i_pc_plus_4), //pc+4 for jalr
    .i_wb_sel(i_wb_sel),
    .o_wb_data(o_wb_data)
);
endmodule
