module hazard_detection_tl (
  input logic i_clk, i_reset,
  input  logic [31:0] i_instr_ID, i_instr_EX, i_instr_MEM,
  input logic i_pc_sel_EX,
  input logic i_mispred_EX,   // Misprediction signal from EX stage
  input logic i_lsu_stall,    // LSU is waiting for TileLink response
  output logic flush,
  output logic pc_en, stall,
  output logic load_bubble     // Insert NOP bubble in ID_EX for load-use hazard
);

  logic [4:0] rs1_ID, rs2_ID, rsW_EX;
  logic [6:0] opcode_EX;
  logic       load_use_EX;

  assign opcode_EX   = i_instr_EX[6:0];
  assign load_use_EX = ~(|(opcode_EX ^ 7'b0000011)); // Load: lw, lb, lbu, ...

  assign rs1_ID  = i_instr_ID[19:15];
  assign rs2_ID  = i_instr_ID[24:20];
  assign rsW_EX  = i_instr_EX[11:7];

  // ── Load-use hazard: load in EX, dependent instruction in ID ──
  // When detected:
  //   • Stall IF_ID (hold dependent instruction in ID)
  //   • Flush ID_EX (insert NOP bubble so load advances EX→MEM unblocked)
  //   • Freeze PC (pc_en = 0)
  //
  // After the bubble: load enters MEM, NOP in EX, dependent held in ID.
  // pipeline_stall (from lsu_stall) freezes everything while load processes TL-UL.
  // When load completes: load→WB, NOP→MEM, dependent→EX.
  // Forwarding from WB→EX provides correct load data to the dependent. ✓
  //
  // NOTE: load_hazard_MEM_EX and load_hazard_MEM_ID are NOT needed because
  // the NOP bubble separates the load from the dependent by exactly the right
  // number of stages. The pipeline_stall from TL-UL latency handles the rest.
  
  logic load_hazard_EX_ID;
  
  assign load_hazard_EX_ID = load_use_EX && (rsW_EX != 5'd0) && 
                             (~(|(rsW_EX ^ rs1_ID)) || ~(|(rsW_EX ^ rs2_ID)));

  always_comb begin
    stall       = 1'b0;
    flush       = 1'b0;
    pc_en       = 1'b1;
    load_bubble = 1'b0;

    if (load_hazard_EX_ID) begin
      stall       = 1'b1;   // Stall IF_ID (hold dependent in ID)
      load_bubble = 1'b1;   // Flush ID_EX (insert NOP bubble in EX)
      pc_en       = 1'b0;   // Freeze PC
    end
    else if (i_mispred_EX) begin
      flush = 1'b1;
      stall = 1'b0;
      pc_en = 1'b1;
    end
  end
endmodule
