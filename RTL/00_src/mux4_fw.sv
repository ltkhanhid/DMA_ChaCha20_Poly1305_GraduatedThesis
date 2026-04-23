module mux4_fw(
    input logic [31:0] i_data1, i_data2, i_data3, i_data4,
    input logic [1:0] i_mux_sel,
    output logic [31:0] o_data_out
);
    always_comb begin
        case(i_mux_sel)
            2'b00: o_data_out = i_data1; // Chọn dữ liệu 1
            2'b01: o_data_out = i_data2; // Chọn dữ liệu 2
            2'b10: o_data_out = i_data3; // Chọn dữ liệu 3
            2'b11: o_data_out = i_data4; // Chọn dữ liệu 4
            default: o_data_out = 32'b0; // Giá trị mặc định
        endcase
    end
endmodule