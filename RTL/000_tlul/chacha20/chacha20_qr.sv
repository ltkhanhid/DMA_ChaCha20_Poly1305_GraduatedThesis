module chacha20_qr (
  input  logic [31:0] a_i, b_i, c_i, d_i,
  output logic [31:0] a_o, b_o, c_o, d_o
);

  // ARX cell 1: a += b;  d ^= a;  d <<<= 16 
  logic [31:0] a1, d1, dx1;
  assign a1  = a_i + b_i;
  assign dx1 = d_i ^ a1;
  assign d1  = {dx1[15:0], dx1[31:16]};                  // rotate left 16

  //  ARX cell 2: c += d;  b ^= c;  b <<<= 12 
  logic [31:0] c1, b1, bx1;
  assign c1  = c_i + d1;
  assign bx1 = b_i ^ c1;
  assign b1  = {bx1[19:0], bx1[31:20]};                  // rotate left 12

  //  ARX cell 3: a += b;  d ^= a;  d <<<= 8 
  logic [31:0] a2, d2, dx2;
  assign a2  = a1 + b1;
  assign dx2 = d1 ^ a2;
  assign d2  = {dx2[23:0], dx2[31:24]};                  // rotate left 8

  //  ARX cell 4: c += d;  b ^= c;  b <<<= 7 
  logic [31:0] c2, b2, bx2;
  assign c2  = c1 + d2;
  assign bx2 = b1 ^ c2;
  assign b2  = {bx2[24:0], bx2[31:25]};                  // rotate left 7

  assign a_o = a2;
  assign b_o = b2;
  assign c_o = c2;
  assign d_o = d2;

endmodule
