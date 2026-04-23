module EX_MEM_reg_tl(
    input i_clk, i_reset,
    input logic stall,          
    
    input logic [31:0] i_pc,
    input logic [31:0] i_instr,
    input logic [31:0] i_alu_data,
    input logic [31:0] i_rs2_data,

    input logic i_rd_wren,
    input logic i_lsu_wren,
    input logic [1:0] i_wb_sel,
    input logic [3:0] i_byte_num,
    input logic i_mispred,

    output logic [31:0] o_pc,
    output logic [31:0] o_instr,
    output logic [31:0] o_alu_data,
    output logic [31:0] o_rs2_data,

    output logic o_rd_wren,
    output logic o_lsu_wren,
    output logic [1:0] o_wb_sel,
    output logic [3:0] o_byte_num,
    output logic o_mispred
);

    always_ff @(posedge i_clk or negedge i_reset) begin
        if(!i_reset) begin
            o_pc       <= 32'd0;
            o_instr    <= 32'h00000013; // NOP (addi x0, x0, 0)
            o_alu_data <= 32'd0;
            o_rs2_data <= 32'd0;
            o_rd_wren  <= 1'b0;
            o_lsu_wren <= 1'b0;
            o_wb_sel   <= 2'b00;
            o_byte_num <= 4'b0000;
            o_mispred  <= 1'b0;
        end else if (!stall) begin
            // Only update when not stalled
            o_pc       <= i_pc;
            o_instr    <= i_instr;
            o_alu_data <= i_alu_data;
            o_rs2_data <= i_rs2_data;
            o_rd_wren  <= i_rd_wren;
            o_lsu_wren <= i_lsu_wren;
            o_wb_sel   <= i_wb_sel;
            o_byte_num <= i_byte_num;
            o_mispred  <= i_mispred;
        end
    end

endmodule
