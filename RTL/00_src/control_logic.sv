module control_logic(
    input logic [31:0] i_instr, 
    output logic [3:0] o_alu_op,  //alu
    output logic [2:0] o_imm_sel, //immgen
    output logic [3:0] o_byte_num, 

    output logic o_insn_vld,
    output logic [1:0] o_wb_sel, //wb
    output logic o_opa_sel, o_opb_sel, //alu
    output logic o_pc_sel, o_rd_wren, o_lsu_wren, o_br_un, //pc, regfile, mem, wb
    output logic [2:0] o_funct3 // Export funct3 for branch decision in EX
);
    logic [6:0] opcode;
    logic [2:0] funct3;
    assign opcode = i_instr[6:0];
    assign funct3 = i_instr[14:12];
    assign o_funct3 = funct3; // Export funct3

    always_comb begin
        o_pc_sel   = 1'b0;    
        o_rd_wren  = 1'b0;    
        o_imm_sel  = 3'b0;    
        o_opa_sel  = 1'b0;    
        o_opb_sel  = 1'b0;    
        o_alu_op  = 4'b0; 
        o_br_un   = 1'b0;    
        o_lsu_wren = 1'b0;    
        o_wb_sel = 2'b00;   
		o_byte_num = 4'b0000;
        o_insn_vld = 1'b0;

        case (opcode)
            // R-type:
            7'b0110011: begin
                o_rd_wren  = 1'b1;    // cho phép ghi vào regfile
                o_imm_sel  = 3'b000;  // not use immediate
                o_opa_sel  = 1'b0;    // rs1
                o_opb_sel  = 1'b0;    // rs2
                o_wb_sel   = 2'b01;   // Write Back từ ALU
                o_insn_vld = 1'b1;    // instruction valid
                case (funct3)
                    3'b000: o_alu_op = (i_instr[30]) ? 4'b0001 : 4'b0000;  // sub/add
                    3'b001: o_alu_op = 4'b0010;  // sll
                    3'b010: o_alu_op = 4'b0011;  // slt signed
                    3'b011: o_alu_op = 4'b0100;  // sltu (unsigned)
                    3'b100: o_alu_op = 4'b0101;  // xor
                    3'b101: o_alu_op = (i_instr[30]) ? 4'b0111 : 4'b0110;  // sra/srl
                    3'b110: o_alu_op = 4'b1000;  // or
                    3'b111: o_alu_op = 4'b1001;  // and
                    default: o_alu_op = 4'b0000;  // Mặc định Add
                endcase
            end

            // I-type Arithmetic: 
            7'b0010011: begin
                o_rd_wren  = 1'b1;    // ghi kết quả vào register file
                o_imm_sel  = 3'b000;  // Itype immediate
                o_opa_sel    = 1'b0;    // rs1
                o_opb_sel    = 1'b1;    // alu B = imm
                o_wb_sel   = 2'b01;   // Write Back từ ALU
                o_insn_vld = 1'b1;    // instruction valid
                case (funct3)
                    3'b000: o_alu_op = 4'b0000;  // addi
                    3'b001: o_alu_op = 4'b0010;  // slli
                    3'b010: o_alu_op = 4'b0011;  // slti (signed)
                    3'b011: o_alu_op = 4'b0100;  // sltiu (unsigned)
                    3'b100: o_alu_op = 4'b0101;  // xori
                    3'b101: o_alu_op = (i_instr[30]) ? 4'b0111 : 4'b0110;  // srai/srli
                    3'b110: o_alu_op = 4'b1000;  // ori
                    3'b111: o_alu_op = 4'b1001;  // andi
                    default: o_alu_op = 4'b0000;  // Mặc định Add
                endcase
            end

            // I-type Load: lw, lh, lb, lhu, lbu
            7'b0000011: begin
                o_rd_wren  = 1'b1;    // Ghi dữ liệu từ DMEM vào registerfile
                o_imm_sel  = 3'b000;  // Itype immediate
                o_opa_sel    = 1'b0;    // rs1
                o_opb_sel    = 1'b1;    // ALU B = imm
                o_lsu_wren   = 1'b0;    // Đọc DMEM
                o_wb_sel   = 2'b10;   // Write Back từ DMEM
                o_insn_vld = 1'b1;    // instruction valid
                case (funct3)
                    3'b000: o_byte_num = 4'b0001 ;  // lb
                    3'b001: o_byte_num = 4'b0011 ;  // lh
                    3'b010: o_byte_num = 4'b1111 ;  // lw
                    3'b100: o_byte_num = 4'b0100 ;  // lbu
                    3'b101: o_byte_num = 4'b0101 ;  // lhu
                    default: o_byte_num = 4'b1111 ;  // Mặc định là lw
                endcase
            end

            // S-type: sw, sh, sb
            7'b0100011: begin
                o_rd_wren  = 1'b0;    // Không ghi vào Register File
                o_imm_sel  = 3'b001;  // Stype immediate
                o_opa_sel    = 1'b0;    // rs1
                o_opb_sel    = 1'b1;    // ALU B = imm
                o_lsu_wren   = 1'b1;    // Ghi vào DMEM
                o_insn_vld = 1'b1;    // instruction valid
                case (funct3)
                    3'b000: o_byte_num = 4'b0001 ;  // sb
                    3'b001: o_byte_num = 4'b0011 ;  // sh
                    3'b010: o_byte_num = 4'b1111 ;  // sw
                    default: o_byte_num = 4'b1111 ;  // Mặc định là sw
                endcase
            end

            // B-type: beq, bne, blt, bge, bltu, bgeu
            7'b1100011: begin
                o_pc_sel  = 1'b0;    // Will be determined in EX stage
                o_alu_op = 4'b0000;  
                o_rd_wren = 1'b0;    
                o_imm_sel = 3'b010;  
                o_opa_sel = 1'b1;    // ALU A = PC
                o_opb_sel = 1'b1;    // ALU B = imm
                o_wb_sel = 2'b01;    
                o_insn_vld = 1'b1;   // instruction valid

                // Set br_un based on funct3 (signed vs unsigned)
                case (funct3)
                    3'b000: o_br_un = 1'b0;  // beq - signed
                    3'b001: o_br_un = 1'b0;  // bne - signed
                    3'b100: o_br_un = 1'b0;  // blt - signed
                    3'b101: o_br_un = 1'b0;  // bge - signed
                    3'b110: o_br_un = 1'b1;  // bltu - unsigned
                    3'b111: o_br_un = 1'b1;  // bgeu - unsigned
                    default: o_br_un = 1'b0;
                endcase
            end

            // U-type: lui
            7'b0110111: begin  // lui
                o_rd_wren  = 1'b1;    // Ghi kết quả vào Register File
                o_imm_sel  = 3'b011;  // U-type immediate
                o_opa_sel  = 1'b0;    // ALU A = 0 (not used for lui)
                o_opb_sel  = 1'b1;    // ALU B = imm
                o_wb_sel   = 2'b01;   // Write Back từ ALU
                o_alu_op   = 4'b1111; // Pass through imm
                o_insn_vld = 1'b1;    // instruction valid
            end
            
            // U-type: auipc
            7'b0010111: begin  // auipc
                o_rd_wren  = 1'b1;    // Ghi kết quả vào Register File
                o_imm_sel  = 3'b011;  // U-type immediate
                o_opa_sel  = 1'b1;    // ALU A = PC
                o_opb_sel  = 1'b1;    // ALU B = imm
                o_wb_sel   = 2'b01;   // Write Back từ ALU
                o_alu_op   = 4'b0000; // ADD: PC + imm
                o_insn_vld = 1'b1;    // instruction valid
            end
            // J-type: jal
            7'b1101111: begin  // jal
                o_rd_wren  = 1'b1;    // Ghi pc+4 vào Register File
                o_imm_sel  = 3'b100;  // J-type immediate
                o_pc_sel   = 1'b1;    // Nhảy đến branch target
                o_wb_sel   = 2'b00;   // Write Back pc+4
                o_opa_sel    = 1'b1;    // ALU A = pc
                o_opb_sel    = 1'b1;    // ALU B = imm
                o_alu_op  = 4'b0000;  // ALU A + ALU B
                o_insn_vld = 1'b1;    // instruction valid
            end

            // I-type: jalr
            7'b1100111: begin  // jalr
                o_rd_wren  = 1'b1;    // Ghi pc+4 vào Register File
                o_imm_sel  = 3'b000;  // I-type immediate
                o_opa_sel    = 1'b0;    // rs1
                o_opb_sel    = 1'b1;    // ALU B = imm
                o_pc_sel   = 1'b1;    // Nhảy đến branch target
                o_wb_sel   = 2'b0;   // Write Back pc+4
                o_insn_vld = 1'b1;    // instruction valid
                o_alu_op  = 4'b0000;  // ALU A + ALU B
            end

            default: begin  
                o_pc_sel   = 1'b0;
                o_rd_wren  = 1'b0;
                o_imm_sel  = 3'b0;
                o_opa_sel    = 1'b0;
                o_opb_sel    = 1'b0;
                o_alu_op  = 4'b0;
                o_br_un    = 1'b0;
                o_lsu_wren   = 1'b0;
                o_wb_sel   = 2'b00;
                o_insn_vld = 1'b0;    // instruction valid
            end
        endcase

    end

endmodule