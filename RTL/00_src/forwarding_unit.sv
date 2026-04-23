module forwarding_unit(
    input logic [31:0] i_instr_EX,
    input logic [31:0] i_instr_MEM,
    input logic [31:0] i_instr_WB,
    input logic i_rd_wren_MEM,
    input logic i_rd_wren_WB,

    output logic pc_plus4_sel_A, // 0: pc_plus4_EX, 1: pc_plus4_MEM
    output logic pc_plus4_sel_B, // 0: pc_plus4_EX, 1: pc_plus4_MEM
    output logic [1:0] fowarding_A, 
    output logic [1:0] fowarding_B
);
logic [4:0] rs1_EX, rs2_EX, rd_MEM, rd_WB;
logic [6:0] opcode_MEM, opcode_WB;
logic is_jal_MEM, is_jal_WB;

assign rs1_EX = i_instr_EX[19:15];
assign rs2_EX = i_instr_EX[24:20];
assign rd_MEM = i_instr_MEM[11:7];
assign rd_WB = i_instr_WB[11:7];

assign opcode_MEM = i_instr_MEM[6:0];
assign opcode_WB = i_instr_WB[6:0];

assign is_jal_MEM = ~(|(opcode_MEM ^ 7'b1101111)) || ~(|(opcode_MEM ^ 7'b1100111));  // jal hoặc jalr
assign is_jal_WB  = ~(|(opcode_WB ^ 7'b1101111)) || ~(|(opcode_WB ^ 7'b1100111));    // jal hoặc jalr

always_comb begin
    fowarding_A = 2'b00;
    fowarding_B = 2'b00;
    pc_plus4_sel_A = 1'b0; 
    pc_plus4_sel_B = 1'b0;
    
    // Forward to EX stage operand A (rs1)
    if(i_rd_wren_MEM && (rd_MEM != 5'd0) && ~(|(rd_MEM ^ rs1_EX))) begin
        if(is_jal_MEM) begin
            fowarding_A = 2'b11;
            pc_plus4_sel_A = 1'b0;
        end else begin
            fowarding_A = 2'b10;
        end
    end else if(i_rd_wren_WB && (rd_WB != 5'd0) && ~(|(rd_WB ^ rs1_EX))) begin
        if(is_jal_WB) begin
            fowarding_A = 2'b11;
            pc_plus4_sel_A = 1'b1;
        end else begin
            fowarding_A = 2'b01;
        end
    end

    // Forward to EX stage operand B (rs2)
    if(i_rd_wren_MEM && (rd_MEM != 5'd0) && ~(|(rd_MEM ^ rs2_EX))) begin
        if(is_jal_MEM) begin
            fowarding_B = 2'b11;
            pc_plus4_sel_B = 1'b0;
        end else begin
            fowarding_B = 2'b10;
        end
    end else if(i_rd_wren_WB && (rd_WB != 5'd0) && ~(|(rd_WB ^ rs2_EX))) begin
        if(is_jal_WB) begin
            fowarding_B = 2'b11;
            pc_plus4_sel_B = 1'b1;
        end else begin
            fowarding_B = 2'b01;
        end
    end
end
endmodule
