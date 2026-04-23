 module alu (
    input logic [31:0] i_op_a,           // Input 1 
    input logic [31:0] i_op_b,           // Input 2 
    input logic [3:0] i_alu_op,   
    output logic [31:0] o_alu_data // Kết quả phép toán
);

    logic [31:0] temp; 
    logic [31:0] shift_stage1, shift_stage2, shift_stage3, shift_stage4, shift_stage5;
    logic [31:0] shift_input;
    logic carry;
    
    // Adder signals (use + operator for FPGA carry-chain inference)
    logic [31:0] cla_a, cla_b;
    logic [31:0] cla_sum;
    logic        cla_cin, cla_cout;

    // 32-bit add with carry: {cout, sum} = a + b + cin
    // Replaces structural CLA for native FPGA carry-chain (~3ns vs ~12ns)
    assign {cla_cout, cla_sum} = {1'b0, cla_a} + {1'b0, cla_b} + {32'b0, cla_cin};

    always_comb begin
		carry = 1'b0;
        o_alu_data = 32'h0;
        shift_input = 32'h0;
        shift_stage1 = 32'h0;
        shift_stage2 = 32'h0;
        shift_stage3 = 32'h0;
        shift_stage4 = 32'h0;
        shift_stage5 = 32'h0;

        cla_a = 32'h0;
        cla_b = 32'h0;
        cla_cin = 1'b0;

        case (i_alu_op)
            4'b0000: begin  // ADD signed  funct3 = 000 funct7 = 0000000
                cla_a = i_op_a;
                cla_b = i_op_b;
                cla_cin = 1'b0;
                o_alu_data = cla_sum;
                end

            4'b0001: begin  // SUB signed funct3 = 000 funct7 = 0100000
                cla_a = i_op_a;
                cla_b = ~i_op_b; 
                cla_cin = 1'b1;   
                o_alu_data = cla_sum;
                end

            4'b0010: begin  // SLL  funct3 = 001 funct 7 = 0000000
                //barrel shifter
                shift_input = i_op_a;                
                shift_stage1 = i_op_b[0] ? {shift_input[30:0], 1'b0} : shift_input;     // shift left 1          
                shift_stage2 = i_op_b[1] ? {shift_stage1[29:0], 2'b00} : shift_stage1;   //2
                shift_stage3 = i_op_b[2] ? {shift_stage2[27:0], 4'b0000} : shift_stage2; //4
                shift_stage4 = i_op_b[3] ? {shift_stage3[23:0], 8'b00000000} : shift_stage3; //8
                shift_stage5 = i_op_b[4] ? {shift_stage4[15:0], 16'b0000000000000000} : shift_stage4; //16
                o_alu_data = shift_stage5;
                end

            4'b0011: begin  // SLT  signed funct3 = 010
                if (i_op_a[31] ^ i_op_b[31]) begin 
                    o_alu_data = i_op_a[31] ? 32'h1 : 32'h0;  // compare signed
                end else begin
                    // Use CLA for subtraction: i_op_a - i_op_b
                    cla_a = i_op_a;
                    cla_b = ~i_op_b;
                    cla_cin = 1'b1;
                    o_alu_data = cla_sum[31] ? 32'h1 : 32'h0;  // compare signed
                end
            end

            4'b0100: begin  // SLTU funct3 = 011 
                cla_a = i_op_a;
                cla_b = ~i_op_b;
                cla_cin = 1'b1;
                carry = cla_cout;
                o_alu_data = (~carry) ? 32'h1 : 32'h0;
                end

            4'b0101: begin  // XOR  funct3 = 100
                o_alu_data = i_op_a ^ i_op_b;
                end

            4'b0110: begin  // SRL  funct3 = 101,funct7 = 0000000
                shift_input = i_op_a;
                shift_stage1 = i_op_b[0] ? {1'b0, shift_input[31:1]} : shift_input;
                shift_stage2 = i_op_b[1] ? {2'b00, shift_stage1[31:2]} : shift_stage1;
                shift_stage3 = i_op_b[2] ? {4'b0000, shift_stage2[31:4]} : shift_stage2;
                shift_stage4 = i_op_b[3] ? {8'b00000000, shift_stage3[31:8]} : shift_stage3;
                shift_stage5 = i_op_b[4] ? {16'b0000000000000000, shift_stage4[31:16]} : shift_stage4;
                o_alu_data = shift_stage5;
                end

            4'b0111: begin  // SRA  funct3 = 101, funct7 = 0100000
                shift_input = i_op_a;
                shift_stage1 = i_op_b[0] ? {shift_input[31], shift_input[31:1]} : shift_input;
                shift_stage2 = i_op_b[1] ? {{2{shift_stage1[31]}}, shift_stage1[31:2]} : shift_stage1;
                shift_stage3 = i_op_b[2] ? {{4{shift_stage2[31]}}, shift_stage2[31:4]} : shift_stage2;
                shift_stage4 = i_op_b[3] ? {{8{shift_stage3[31]}}, shift_stage3[31:8]} : shift_stage3;
                shift_stage5 = i_op_b[4] ? {{16{shift_stage4[31]}}, shift_stage4[31:16]} : shift_stage4;
                o_alu_data = shift_stage5;
                end

            4'b1000: begin  // OR  funct3 = 110
                o_alu_data = i_op_a | i_op_b;
                end

            4'b1001: 
                begin  // AND  funct3 = 111
                    o_alu_data = i_op_a & i_op_b;
                end
            4'b1111: begin  // lui
                o_alu_data = i_op_b;
                end
            default: begin
                o_alu_data = 32'h0;
                end
        endcase
    end

endmodule
