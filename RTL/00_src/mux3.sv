module mux3(
    input logic [31:0] i_a, i_b, i_c,
    input logic [1:0] i_sel,
    output logic [31:0] o_data
);
    always_comb begin
        case(i_sel)
            2'b00: o_data = i_a;
            2'b01: o_data = i_b;
            2'b10: o_data = i_c;
            default: o_data = 32'b0; // Default case to avoid latches
        endcase
    end
endmodule

