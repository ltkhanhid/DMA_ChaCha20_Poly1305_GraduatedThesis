module ImmGen (
    input  logic [31:0] i_instr,      // instruction
    input  logic [2:0] i_imm_sel,   
    output logic [31:0] o_immgen       
);

    always_comb begin
        case (i_imm_sel)
                3'b000: o_immgen = {{20{i_instr[31]}}, i_instr[31:20]}; // I-type

                3'b001: o_immgen = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]}; // S-type

                3'b010: o_immgen = {{19{i_instr[31]}}, i_instr[31], i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0}; // B-type

                3'b011: o_immgen = {i_instr[31:12], 12'b0}; // U-type

                3'b100: o_immgen = {{12{i_instr[31]}}, i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0}; // J-type
                
                default: o_immgen = 32'b0;
        endcase
    end            
endmodule