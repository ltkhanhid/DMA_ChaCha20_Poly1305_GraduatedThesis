module mux3_wb (
    input logic [31:0] i_alu_data, i_ld_data, i_pc_out, //alu, mem, pc, wb
    input logic [1:0] i_wb_sel, //wb
    output logic [31:0] o_wb_data //wb
);
    always_comb begin
        case (i_wb_sel)
            2'b00: o_wb_data = i_pc_out; //pc
            2'b01: o_wb_data = i_alu_data; //alu
            2'b10: o_wb_data = i_ld_data; //mem
            default: o_wb_data = 32'h0;
        endcase
    end
endmodule