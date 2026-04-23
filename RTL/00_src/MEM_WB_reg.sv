module MEM_WB_reg(
    input logic i_clk, i_reset,
    input logic [31:0] i_pc,
    input logic [31:0] i_instr,
    input logic [31:0] i_alu_data,
    input logic [31:0] i_pc_plus_4, // PC+4 for jalr
    input logic i_mispred,

    // control signals
    input logic [1:0] i_wb_sel,
    input logic i_rd_wren,


    output logic [31:0] o_pc,
    output logic [31:0] o_pc_plus_4,
    output logic [31:0] o_instr,
    output logic [31:0] o_alu_data,
    output logic [1:0] o_wb_sel,
    output logic o_rd_wren,
    output logic o_mispred

);

always_ff @(posedge i_clk or negedge i_reset) begin
    if(!i_reset) begin
        o_pc <= 32'd0;
        o_instr  <= 32'h00000013; // NOP (addi x0, x0, 0)
        o_alu_data <= 32'd0;
        o_wb_sel <= 2'b00;
        o_rd_wren <= 1'b0;
        o_pc_plus_4 <= 32'd0;
        o_mispred <= 1'b0;
    end else begin
        o_pc <= i_pc;
        o_instr  <= i_instr;
        o_alu_data <= i_alu_data;
        o_wb_sel <= i_wb_sel;
        o_rd_wren <= i_rd_wren;
        o_pc_plus_4 <= i_pc_plus_4; // PC+4 for jalr
        o_mispred <= i_mispred;
    end
end

endmodule
