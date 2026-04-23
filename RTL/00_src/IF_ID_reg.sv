module IF_ID_reg (
  input logic i_clk, i_reset,
  input logic [31:0] i_pc,
  input logic [31:0] i_instr,
  input logic stall,
  input logic flush,
  output logic [31:0] o_pc,
  output logic [31:0] o_instr
);
  always_ff @(posedge i_clk or negedge i_reset) begin
    if (!i_reset) begin
      o_pc <= 32'b0;
      o_instr <= 32'h00000013;
    end else if (stall) begin
      // FREEZE: Hold current values (stall has higher priority)
      // Do nothing - preserve instruction in ID stage
    end else if (flush) begin
      o_pc <= 32'b0;
      o_instr <= 32'h00000013;
    end else begin
      o_pc <= i_pc;
      o_instr <= i_instr;
    end
  end


endmodule
