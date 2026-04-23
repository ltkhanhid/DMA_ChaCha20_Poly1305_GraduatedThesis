//Just for understanding the math behind Chacha not for use

`timescale 1ns/1ps
module chacha_functions;
    function [127:0] quarterround;
        input [31:0] a, b, c, d;
        reg [31:0] a1, b1, c1, d1;
        reg [31:0] a2, b2, c2, d2;
    begin
        a1 = a + b;
        d1 = { (d ^ a1) << 16 } | { (d ^ a1) >> 16 };
        c1 = c + d1;
        b1 = { (b ^ c1) << 12 } | { (b ^ c1) >> 20 };
        a2 = a1 + b1;
        d2 = { (d1 ^ a2) << 8 } | { (d1 ^ a2) >> 24 };
        c2 = c1 + d2;
        b2 = { (b1 ^ c2) << 7 } | { (b1 ^ c2) >> 25 };
        quarterround = {a2, b2, c2, d2};
    end
    endfunction
endmodule
