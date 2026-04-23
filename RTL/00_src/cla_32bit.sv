module cla_32bit (
    input  logic [31:0] i_a,      // 32-bit input A
    input  logic [31:0] i_b,      // 32-bit input B
    input  logic        i_ci,     // Carry in (for subtraction support)
    output logic [31:0] o_s,      // 32-bit sum output
    output logic        o_co      // Carry out (for overflow detection)
);

    // Carry signals between 4-bit CLA blocks
    logic [7:0] carry;
    
    // First 4-bit CLA block (bits 0-3)
    cla_4bit cla_block0 (
        .i_a(i_a[3:0]),
        .i_b(i_b[3:0]),
        .i_ci(i_ci),
        .o_s(o_s[3:0]),
        .o_co(carry[0])
    );
    
    // Second 4-bit CLA block (bits 4-7)
    cla_4bit cla_block1 (
        .i_a(i_a[7:4]),
        .i_b(i_b[7:4]),
        .i_ci(carry[0]),
        .o_s(o_s[7:4]),
        .o_co(carry[1])
    );
    
    // Third 4-bit CLA block (bits 8-11)
    cla_4bit cla_block2 (
        .i_a(i_a[11:8]),
        .i_b(i_b[11:8]),
        .i_ci(carry[1]),
        .o_s(o_s[11:8]),
        .o_co(carry[2])
    );
    
    // Fourth 4-bit CLA block (bits 12-15)
    cla_4bit cla_block3 (
        .i_a(i_a[15:12]),
        .i_b(i_b[15:12]),
        .i_ci(carry[2]),
        .o_s(o_s[15:12]),
        .o_co(carry[3])
    );
    
    // Fifth 4-bit CLA block (bits 16-19)
    cla_4bit cla_block4 (
        .i_a(i_a[19:16]),
        .i_b(i_b[19:16]),
        .i_ci(carry[3]),
        .o_s(o_s[19:16]),
        .o_co(carry[4])
    );
    
    // Sixth 4-bit CLA block (bits 20-23)
    cla_4bit cla_block5 (
        .i_a(i_a[23:20]),
        .i_b(i_b[23:20]),
        .i_ci(carry[4]),
        .o_s(o_s[23:20]),
        .o_co(carry[5])
    );
    
    // Seventh 4-bit CLA block (bits 24-27)
    cla_4bit cla_block6 (
        .i_a(i_a[27:24]),
        .i_b(i_b[27:24]),
        .i_ci(carry[5]),
        .o_s(o_s[27:24]),
        .o_co(carry[6])
    );
    
    // Eighth 4-bit CLA block (bits 28-31)
    cla_4bit cla_block7 (
        .i_a(i_a[31:28]),
        .i_b(i_b[31:28]),
        .i_ci(carry[6]),
        .o_s(o_s[31:28]),
        .o_co(carry[7])
    );
    
    // Final carry out
    assign o_co = carry[7];

endmodule
