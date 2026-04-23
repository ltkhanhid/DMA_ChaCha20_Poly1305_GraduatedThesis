module SevenSegment (
    input  [31:0] input_data,   // 4-bit per digit: {d3[15:12], d2[11:8], d1[7:4], d0[3:0]}
    output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
);

    // Extract 4-bit nibbles from 32-bit input (pack 4 digits in lower 16 bits)
    // Firmware writes: hex_lo = {hex3[3:0]<<12 | hex2[3:0]<<8 | hex1[3:0]<<4 | hex0[3:0]}
    logic [7:0] data0, data1, data2, data3;
    
    assign data0 = {4'h0, input_data[3:0]};
    assign data1 = {4'h0, input_data[7:4]};
    assign data2 = {4'h0, input_data[11:8]};
    assign data3 = {4'h0, input_data[15:12]};

    // 7-segment encoding: active LOW (0 = ON, 1 = OFF)
    //       a
    //      ---
    //   f |   | b
    //      -g-
    //   e |   | c
    //      ---
    //       d
    // Format: gfedcba

    // Inline 7-segment decode (no function — for synthesis compatibility)
    always_comb begin
        case (data0)
            8'h00: HEX0 = 7'b1000000; // 0
            8'h01: HEX0 = 7'b1111001; // 1
            8'h02: HEX0 = 7'b0100100; // 2
            8'h03: HEX0 = 7'b0110000; // 3
            8'h04: HEX0 = 7'b0011001; // 4
            8'h05: HEX0 = 7'b0010010; // 5
            8'h06: HEX0 = 7'b0000010; // 6
            8'h07: HEX0 = 7'b1111000; // 7
            8'h08: HEX0 = 7'b0000000; // 8
            8'h09: HEX0 = 7'b0010000; // 9
            8'h0A: HEX0 = 7'b0001000; // A
            8'h0B: HEX0 = 7'b0000011; // b
            8'h0C: HEX0 = 7'b1000110; // C
            8'h0D: HEX0 = 7'b0100001; // d
            8'h0E: HEX0 = 7'b0000110; // E
            8'h0F: HEX0 = 7'b0001110; // F
            default: HEX0 = 7'b1111111; // Blank
        endcase
    end

    always_comb begin
        case (data1)
            8'h00: HEX1 = 7'b1000000;
            8'h01: HEX1 = 7'b1111001;
            8'h02: HEX1 = 7'b0100100;
            8'h03: HEX1 = 7'b0110000;
            8'h04: HEX1 = 7'b0011001;
            8'h05: HEX1 = 7'b0010010;
            8'h06: HEX1 = 7'b0000010;
            8'h07: HEX1 = 7'b1111000;
            8'h08: HEX1 = 7'b0000000;
            8'h09: HEX1 = 7'b0010000;
            8'h0A: HEX1 = 7'b0001000;
            8'h0B: HEX1 = 7'b0000011;
            8'h0C: HEX1 = 7'b1000110;
            8'h0D: HEX1 = 7'b0100001;
            8'h0E: HEX1 = 7'b0000110;
            8'h0F: HEX1 = 7'b0001110;
            default: HEX1 = 7'b1111111;
        endcase
    end

    always_comb begin
        case (data2)
            8'h00: HEX2 = 7'b1000000;
            8'h01: HEX2 = 7'b1111001;
            8'h02: HEX2 = 7'b0100100;
            8'h03: HEX2 = 7'b0110000;
            8'h04: HEX2 = 7'b0011001;
            8'h05: HEX2 = 7'b0010010;
            8'h06: HEX2 = 7'b0000010;
            8'h07: HEX2 = 7'b1111000;
            8'h08: HEX2 = 7'b0000000;
            8'h09: HEX2 = 7'b0010000;
            8'h0A: HEX2 = 7'b0001000;
            8'h0B: HEX2 = 7'b0000011;
            8'h0C: HEX2 = 7'b1000110;
            8'h0D: HEX2 = 7'b0100001;
            8'h0E: HEX2 = 7'b0000110;
            8'h0F: HEX2 = 7'b0001110;
            default: HEX2 = 7'b1111111;
        endcase
    end

    always_comb begin
        case (data3)
            8'h00: HEX3 = 7'b1000000;
            8'h01: HEX3 = 7'b1111001;
            8'h02: HEX3 = 7'b0100100;
            8'h03: HEX3 = 7'b0110000;
            8'h04: HEX3 = 7'b0011001;
            8'h05: HEX3 = 7'b0010010;
            8'h06: HEX3 = 7'b0000010;
            8'h07: HEX3 = 7'b1111000;
            8'h08: HEX3 = 7'b0000000;
            8'h09: HEX3 = 7'b0010000;
            8'h0A: HEX3 = 7'b0001000;
            8'h0B: HEX3 = 7'b0000011;
            8'h0C: HEX3 = 7'b1000110;
            8'h0D: HEX3 = 7'b0100001;
            8'h0E: HEX3 = 7'b0000110;
            8'h0F: HEX3 = 7'b0001110;
            default: HEX3 = 7'b1111111;
        endcase
    end
    
    // HEX4-7 not used in this instance (driven by separate instance for upper)
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;
    assign HEX6 = 7'b1111111;
    assign HEX7 = 7'b1111111;
    
endmodule