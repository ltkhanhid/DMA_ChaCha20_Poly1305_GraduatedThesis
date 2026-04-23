module MEM(
    input logic i_clk,
    input logic i_reset,
    input logic [31:0] i_pc,
    input logic [31:0] i_instr,
    input logic [31:0] i_alu_data,
    input logic [31:0] i_rs2_data,

    // control signals
    input logic i_rd_wren,
    input logic i_lsu_wren,
    input logic [1:0] i_wb_sel,
    input logic [3:0] i_byte_num,

    // IO signals
    input logic [31:0] i_io_sw,
    input logic [31:0] i_io_key,

    output logic [31:0] o_pc_plus_4,
    output logic [31:0] o_ld_data,
    output logic [31:0] o_io_ledr,
    output logic [31:0] o_io_ledg,
    output logic [31:0] o_io_lcd,
    output logic [6:0] o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3,
    output logic [6:0] o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7

);


PCplus4 PCplus4(
    .PCout(i_pc),
    .PCplus4(o_pc_plus_4) // PC+4
);

lsu lsu(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_lsu_wren(i_lsu_wren),
        .i_byte_num(i_byte_num),
        .i_st_data(i_rs2_data),
        .i_lsu_addr(i_alu_data),
        .i_io_sw(i_io_sw),
        .i_io_key(i_io_key),
        .o_ld_data(o_ld_data),
        .o_io_ledr(o_io_ledr), 
        .o_io_ledg(o_io_ledg),
        .o_io_lcd(o_io_lcd),
        .o_io_hex0(o_io_hex0),
        .o_io_hex1(o_io_hex1),
        .o_io_hex2(o_io_hex2),
        .o_io_hex3(o_io_hex3),
        .o_io_hex4(o_io_hex4),
        .o_io_hex5(o_io_hex5),
        .o_io_hex6(o_io_hex6),
        .o_io_hex7(o_io_hex7)
);

endmodule
