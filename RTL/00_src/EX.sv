module EX(
    input logic [31:0] i_instr,
    input logic [31:0] i_pc,
    input logic [31:0] i_rs1_data, i_rs2_data,
    input logic [31:0] i_immgen,
// control logic signals
    input logic i_opa_sel, i_opb_sel,
    input logic i_pc_sel,
    input logic i_rd_wren,
    input logic [3:0] i_alu_op,
    input logic [1:0] i_wb_sel,
    input logic [3:0] i_byte_num,
    input logic i_lsu_wren,
    input logic i_br_un,                 // Branch unsigned
    input logic [2:0] i_funct3,          // funct3 for branch decision

    //hazard detection, forwarding signals
    input logic [1:0] fowarding_A, fowarding_B,
    input logic pc_plus4_sel_A, pc_plus4_sel_B,
    input logic [31:0] i_pc_plus_4_WB, i_pc_plus_4_MEM,
    input logic [31:0] i_alu_data_MEM,
    input logic [31:0] i_wb_data_WB,


    output logic [31:0] o_alu_data,
    output logic [31:0] o_rs2_data,
    output logic        o_mispred,          // Misprediction detected
    output logic        o_pc_sel_EX         // Actual branch decision from EX

);
    logic [31:0] pc_plus4_out_A, pc_plus4_out_B;
    logic [31:0] i_op_a, i_op_b;
    logic [31:0] data_fw_out_A, data_fw_out_B;

mux2 mux_pc_plus4_fw_A (
    .i_data1(i_pc_plus_4_MEM), 
    .i_data2(i_pc_plus_4_WB), 
    .i_mux_sel(pc_plus4_sel_A), 
    .o_data_out(pc_plus4_out_A)); // PC+4 cho jalr

mux2 mux_pc_plus4_fw_B (
    .i_data1(i_alu_data_MEM), 
    .i_data2(i_wb_data_WB), 
    .i_mux_sel(pc_plus4_sel_B), 
    .o_data_out(pc_plus4_out_B)); // PC+4 cho jalr

mux4_fw mux4_fw_A(
    .i_data1(i_rs1_data),
    .i_data2(i_wb_data_WB),
    .i_data3(i_alu_data_MEM),
    .i_data4(pc_plus4_out_A),
    .i_mux_sel(fowarding_A),
    .o_data_out(data_fw_out_A) // PC+4 cho jalr
    );

mux4_fw mux4_fw_B(
    .i_data1(i_rs2_data),
    .i_data2(i_wb_data_WB),
    .i_data3(i_alu_data_MEM),
    .i_data4(pc_plus4_out_B),
    .i_mux_sel(fowarding_B),
    .o_data_out(data_fw_out_B) // PC+4 cho jalr
    );

mux2 mux_opa (
    .i_data1(data_fw_out_A),
    .i_data2(i_pc), 
    .i_mux_sel(i_opa_sel), 
    .o_data_out(i_op_a));

mux2 mux_opb (
    .i_data1(data_fw_out_B),
    .i_data2(i_immgen), 
    .i_mux_sel(i_opb_sel),
    .o_data_out(i_op_b));


    alu alu(
    .i_op_a(i_op_a), 
    .i_op_b(i_op_b), 
    .i_alu_op(i_alu_op), 
    .o_alu_data(o_alu_data)
    );   

assign o_rs2_data = data_fw_out_B;

// BRC instantiation - Branch comparator in EX stage
logic br_equal, br_less;

brc brc(
    .i_rs1_data(data_fw_out_A),
    .i_rs2_data(data_fw_out_B),
    .i_br_un(i_br_un),
    .o_br_equal(br_equal),
    .o_br_less(br_less)
);

// Branch decision logic in EX
// Determine actual branch outcome based on BRC results and funct3
logic is_branch;
logic actual_taken;
logic branch_condition;

assign is_branch = ~(|(i_instr[6:0] ^ 7'b1100011)); // Only conditional branches

// Evaluate branch condition based on funct3
always_comb begin
    case (i_funct3)
        3'b000: branch_condition = br_equal;              // beq
        3'b001: branch_condition = ~br_equal;             // bne
        3'b100: branch_condition = br_less;               // blt
        3'b101: branch_condition = ~br_less | br_equal;   // bge
        3'b110: branch_condition = br_less;               // bltu
        3'b111: branch_condition = ~br_less | br_equal;   // bgeu
        default: branch_condition = 1'b0;
    endcase
end

// Actual branch decision
// For conditional branches: use BRC result
// For JAL/JALR: always taken (i_pc_sel from ID)
assign actual_taken = is_branch ? branch_condition : i_pc_sel;
assign o_pc_sel_EX = actual_taken;

// Misprediction detection
// Without branch predictor, flush on all taken branches/jumps
assign o_mispred = actual_taken;

endmodule
