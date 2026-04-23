module fa (
    input  logic       i_a,       // Input a
    input  logic       i_b,       // Input b
    input  logic       i_ci,      // Input carry in
    output logic       o_s,       // Sum output
    output logic       o_co       // Carry out
);

    // Full Adder Logic
    assign o_s  = i_a ^ i_b ^ i_ci;                     // Sum bit
    assign o_co = (i_a & i_b) | (i_ci & (i_a ^ i_b));   // Carry out
endmodule