module cla_4bit (
    input  logic [3:0] i_a,      // 4-bit input A
    input  logic [3:0] i_b,      // 4-bit input B
    input  logic       i_ci,     // Carry in
    output logic [3:0] o_s,      // 4-bit sum output
    output logic       o_co      // Carry out
);


    logic [3:0] p;  
    logic [3:0] g; 
    logic [3:0] c;  // c[0] = carry into bit 0, c[1] = carry into bit 1
    logic [3:0] co_unused;
    
    // Generate and Propagate for each bit
    assign p[0] = i_a[0] ^ i_b[0];
    assign g[0] = i_a[0] & i_b[0];
    
    assign p[1] = i_a[1] ^ i_b[1];
    assign g[1] = i_a[1] & i_b[1];
    
    assign p[2] = i_a[2] ^ i_b[2];
    assign g[2] = i_a[2] & i_b[2];
    
    assign p[3] = i_a[3] ^ i_b[3];
    assign g[3] = i_a[3] & i_b[3];
    
    // Carry Look-Ahead Logic (fast parallel carry computation)
    assign c[0] = i_ci;
    assign c[1] = g[0] | (p[0] & c[0]);
    assign c[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & c[0]);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & c[0]);
    
    // Carry out (into next 4-bit block)
    assign o_co = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | 
                  (p[3] & p[2] & p[1] & g[0]) | (p[3] & p[2] & p[1] & p[0] & c[0]);
    
    // Sum calculation using Full Adders
    fa fa0 (.i_a(i_a[0]), .i_b(i_b[0]), .i_ci(c[0]), .o_s(o_s[0]), .o_co(co_unused[0]));
    fa fa1 (.i_a(i_a[1]), .i_b(i_b[1]), .i_ci(c[1]), .o_s(o_s[1]), .o_co(co_unused[1]));
    fa fa2 (.i_a(i_a[2]), .i_b(i_b[2]), .i_ci(c[2]), .o_s(o_s[2]), .o_co(co_unused[2]));
    fa fa3 (.i_a(i_a[3]), .i_b(i_b[3]), .i_ci(c[3]), .o_s(o_s[3]), .o_co(co_unused[3]));

endmodule
