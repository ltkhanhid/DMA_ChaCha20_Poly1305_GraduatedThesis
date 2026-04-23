module PCplus4 (
    input logic [31:0] PCout,       //from PC
    output logic [31:0] PCplus4
);

    always_comb begin
        PCplus4 = PCout + 32'h4;
    end
endmodule