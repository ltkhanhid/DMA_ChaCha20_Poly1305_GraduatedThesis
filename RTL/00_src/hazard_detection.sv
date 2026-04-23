module hazard_detection (
  input logic i_clk, i_reset,
  input  logic [31:0] i_instr_ID, i_instr_EX, i_instr_MEM,
  input logic i_pc_sel_EX,
  input logic i_mispred_EX,   // Misprediction signal from EX stage
  output logic flush,
  output logic pc_en, stall
);

  logic [4:0] rs1_ID, rs2_ID, rsW_EX, rsW_MEM;
  logic [6:0] opcode_EX, opcode_ID;
  logic       load_use_EX, load_use_MEM;
  logic       jalr_ID, branch_ID;
  

  assign opcode_EX = i_instr_EX[6:0];
  assign opcode_ID = i_instr_ID[6:0];
  assign load_use_EX = ~(|(opcode_EX ^ 7'b0000011)); // Load lw, lb ...
  assign load_use_MEM = ~(|(i_instr_MEM[6:0] ^ 7'b0000011)); // Load in MEM
  assign branch_jump_EX = ~(|(opcode_EX ^ 7'b1100011)) ||  // Branch (beq, bne, etc.)
                          ~(|(opcode_EX ^ 7'b1101111)) ||  // jal
                          ~(|(opcode_EX ^ 7'b1100111));    // jalr
  assign jalr_ID = ~(|(opcode_ID ^ 7'b1100111)); // JALR at ID stage
  assign branch_ID = ~(|(opcode_ID ^ 7'b1100011)); // Branch at ID stage
  assign rs1_ID    = i_instr_ID[19:15];
  assign rs2_ID    = i_instr_ID[24:20];
  assign rsW_EX    = i_instr_EX[11:7];
  assign rsW_MEM   = i_instr_MEM[11:7];


  always_comb begin
    stall = 1'b0;
    flush = 1'b0;
    pc_en = 1'b1;

    // Load-use hazard (EX)
    if (load_use_EX && (rsW_EX != 5'd0) && (~(|(rsW_EX ^ rs1_ID)) || ~(|(rsW_EX ^ rs2_ID)))) begin
      stall = 1'b1;
      flush = 1'b0;
      pc_en = 1'b0;
    end
    else if (i_mispred_EX) begin
      flush = 1'b1;
      stall = 1'b0;
      pc_en = 1'b1;
    end
  end
endmodule