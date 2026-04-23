module mux2 (
    input logic [31:0] i_data1,  // Input 1
    input logic [31:0] i_data2,  // Input 2
    input logic i_mux_sel,       // Chọn đầu vào
    output logic [31:0] o_data_out  // Output
);
    always_comb begin
        if (i_mux_sel)
            o_data_out = i_data2;
        else
            o_data_out = i_data1;
    end
endmodule