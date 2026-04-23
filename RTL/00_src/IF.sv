module IF #(
    parameter MEM_FILE = "../../02_test/uart_app_ver3.hex"  // Instruction memory file path
)(
    input logic i_clk,
    input logic i_reset, 
    input logic i_pc_en, // PC enable from hazard
    
    // Branch/Jump target from EX
    input logic        i_pc_sel,           // PC select: 0=PC+4, 1=branch/jump target
    input logic [31:0] i_pc_target,        // Branch/jump target address
    
    output logic [31:0] o_pc_out,
    output logic [31:0] o_instr
);

    logic [31:0] pc_plus4; 
    logic [31:0] i_pc_in;
    logic [31:0] current_pc;
    
    // Simple PC selection: branch target or PC+4
    assign i_pc_in = i_pc_sel ? i_pc_target : pc_plus4;

PCplus4 PCplus4(
    .PCout(current_pc),
    .PCplus4(pc_plus4) // PC+4
    );
    
pc pc(
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_pc_in(i_pc_in), 
    .i_pc_en(i_pc_en), 
    .o_pc_out(current_pc) 
);
instr_mem #(
    .MEM(MEM_FILE)
) IMem(
    .i_clk(i_clk),
    .i_imem_addr(current_pc), 
    .o_instr(o_instr) 
);


    assign o_pc_out = current_pc;

endmodule
