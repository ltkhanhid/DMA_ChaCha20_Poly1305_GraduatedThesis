// ID_EX Pipeline Register with TileLink support
// Separates flush (insert NOP) from stall (hold value)
// - flush: Insert NOP bubble (for branch misprediction, hazard)
// - stall: Hold current value (for LSU stall - pipeline freeze)

module ID_EX_reg_tl(
    input logic i_clk, i_reset,
    input logic flush,           // Insert NOP bubble
    input logic stall,           // Hold current value (freeze)
    
    input logic [31:0] i_instr,
    input logic [31:0] i_pc,
    input logic [31:0] i_rs1_data, i_rs2_data,
    input logic [31:0] i_immgen,

    input logic i_opa_sel, i_opb_sel,
    input logic i_pc_sel,
    input logic i_rd_wren,
    input logic [3:0] i_alu_op,
    input logic [1:0] i_wb_sel,
    input logic [3:0] i_byte_num,
    input logic i_lsu_wren,
    input logic i_br_un,              // Branch unsigned from control logic
    input logic [2:0] i_funct3,       // funct3 for branch decision in EX

    output logic [31:0] o_instr,
    output logic [31:0] o_pc,
    output logic [31:0] o_rs1_data, o_rs2_data,
    output logic [31:0] o_immgen,
    
    output logic o_opa_sel, o_opb_sel,
    output logic o_pc_sel,
    output logic o_rd_wren,
    output logic [3:0] o_alu_op,
    output logic [1:0] o_wb_sel,
    output logic o_lsu_wren,
    output logic [3:0] o_byte_num,
    output logic o_br_un,             // Pass br_un to EX
    output logic [2:0] o_funct3       // Pass funct3 to EX
);
    always_ff @(posedge i_clk or negedge i_reset) begin
        if(!i_reset) begin
            // Reset to NOP
            o_instr <= 32'h00000013; // NOP (addi x0, x0, 0)
            o_pc <= 32'd0;
            o_rs1_data <= 32'd0;
            o_rs2_data <= 32'd0;
            o_immgen <= 32'd0;
            o_opa_sel <= 1'd0;
            o_opb_sel <= 1'd0;
            o_pc_sel <= 1'd0;
            o_rd_wren <= 1'd0;
            o_alu_op <= 4'd0;
            o_wb_sel <= 2'd0;
            o_byte_num <= 4'd0;
            o_lsu_wren <= 1'd0;
            o_br_un <= 1'b0;
            o_funct3 <= 3'd0;
        end else if (stall) begin
            // FREEZE: Hold current values (do nothing)
            // This is critical for LSU stall - we must preserve instruction in EX
        end else if (flush) begin
            // INSERT BUBBLE: Clear to NOP (for branch misprediction, hazard)
            o_instr <= 32'h00000013; // NOP (addi x0, x0, 0)
            o_pc <= 32'd0;
            o_rs1_data <= 32'd0;
            o_rs2_data <= 32'd0;
            o_immgen <= 32'd0;
            o_opa_sel <= 1'd0;
            o_opb_sel <= 1'd0;
            o_pc_sel <= 1'd0;
            o_rd_wren <= 1'd0;
            o_alu_op <= 4'd0;
            o_wb_sel <= 2'd0;
            o_byte_num <= 4'd0;
            o_lsu_wren <= 1'd0;
            o_br_un <= 1'b0;
            o_funct3 <= 3'd0;
        end else begin
            // Normal operation: Latch new values from ID stage
            o_instr <= i_instr;
            o_pc <= i_pc;
            o_rs1_data <= i_rs1_data;
            o_rs2_data <= i_rs2_data;
            o_immgen <= i_immgen;
            o_opa_sel <= i_opa_sel;
            o_opb_sel <= i_opb_sel;
            o_pc_sel <= i_pc_sel;
            o_rd_wren <= i_rd_wren;
            o_alu_op <= i_alu_op;
            o_wb_sel <= i_wb_sel;
            o_byte_num <= i_byte_num;
            o_lsu_wren <= i_lsu_wren;
            o_br_un <= i_br_un;
            o_funct3 <= i_funct3;
        end
    end

endmodule
