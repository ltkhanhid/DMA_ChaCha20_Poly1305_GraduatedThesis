module peripherals (
    input i_clk,
    input i_reset,
    input logic [19:0] i_peri_addr, // Address input (20-bit: 0x1000_0000 to 0x1001_0FFF)
    input logic [31:0] i_data_in,
    input logic i_write_en,
    input logic [31:0] i_io_sw, // Switches input
   
    output logic [31:0] o_data_out,
    output logic [31:0] o_io_ledr, // LEDR output (required)
    output logic [31:0] o_io_lcd, // LCD output
    output logic [31:0] o_io_ledg, // LEDG output (required)
    output logic [6:0] o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3, o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7
);

    logic [6:0] seg7_HEX0, seg7_HEX1, seg7_HEX2, seg7_HEX3, seg7_HEX4, seg7_HEX5, seg7_HEX6, seg7_HEX7;
    logic [31:0] hex_lower_data, hex_upper_data; // Store lower/upper HEX data separately

    // Raw segment registers: firmware writes 7-bit patterns directly
    // seg_raw_lo: {1'b0, HEX3[6:0], 1'b0, HEX2[6:0], 1'b0, HEX1[6:0], 1'b0, HEX0[6:0]}
    // seg_raw_hi: {1'b0, HEX5[6:0], 1'b0, HEX4[6:0], ...}
    logic [31:0] seg_raw_lo, seg_raw_hi;
    logic        seg_raw_mode;  // 0 = hex-decoded, 1 = raw segment patterns

    SevenSegment ssc_lower (
        .input_data(hex_lower_data),
        .HEX0(seg7_HEX0),
        .HEX1(seg7_HEX1),
        .HEX2(seg7_HEX2),
        .HEX3(seg7_HEX3),
        .HEX4(),  // Not used for lower
        .HEX5(),
        .HEX6(),
        .HEX7()
    );

    SevenSegment ssc_upper (
        .input_data(hex_upper_data),
        .HEX0(seg7_HEX4),  // Upper data maps to HEX4-7
        .HEX1(seg7_HEX5),
        .HEX2(seg7_HEX6),
        .HEX3(seg7_HEX7),
        .HEX4(),  // Not used
        .HEX5(),
        .HEX6(),
        .HEX7()
    );
    
    // HEX outputs: mux between hex-decoded and raw segment mode
    assign o_io_hex0 = seg_raw_mode ? seg_raw_lo[ 6: 0] : seg7_HEX0;
    assign o_io_hex1 = seg_raw_mode ? seg_raw_lo[14: 8] : seg7_HEX1;
    assign o_io_hex2 = seg_raw_mode ? seg_raw_lo[22:16] : seg7_HEX2;
    assign o_io_hex3 = seg_raw_mode ? seg_raw_lo[30:24] : seg7_HEX3;
    assign o_io_hex4 = seg_raw_mode ? seg_raw_hi[ 6: 0] : seg7_HEX4;
    assign o_io_hex5 = seg_raw_mode ? seg_raw_hi[14: 8] : seg7_HEX5;
    assign o_io_hex6 = seg_raw_mode ? seg_raw_hi[22:16] : seg7_HEX6;
    assign o_io_hex7 = seg_raw_mode ? seg_raw_hi[30:24] : seg7_HEX7;

    //WRITE LOGIC 
    always_ff @(posedge i_clk or negedge i_reset) begin

        if (!i_reset) begin
            // Reset tất cả đầu ra về 0
            o_io_ledr <= 32'b0;
            o_io_lcd  <= 32'b0;
            o_io_ledg <= 32'b0;
            hex_lower_data <= 32'h00000000;
            hex_upper_data <= 32'h00000000;
            seg_raw_lo   <= 32'h7F7F7F7F;  // All segments OFF (active-low)
            seg_raw_hi   <= 32'h7F7F7F7F;
            seg_raw_mode <= 1'b0;           // Default: hex-decoded mode
        end 
        else if (i_write_en) begin
            // Address decode: bits[19:16] for bank, bits[15:12] for peripheral
            // 0x1000_xxxx: bits[19:16]=0x0
            // 0x1001_xxxx: bits[19:16]=0x1
            case ({i_peri_addr[19:16], i_peri_addr[15:12]})

                8'h00: // 0x1000_0xxx - Red LEDs
                    o_io_ledr <= i_data_in;

                8'h01: // 0x1000_1xxx - Green LEDs
                    o_io_ledg <= i_data_in;

                8'h02: begin // 0x1000_2xxx - HEX 3-0
                    hex_lower_data <= i_data_in;
                end

                8'h03: begin // 0x1000_3xxx - HEX 7-4
                    hex_upper_data <= i_data_in;
                end

                8'h04: // 0x1000_4xxx - LCD
                    o_io_lcd <= i_data_in;

                8'h05: // 0x1000_5xxx - SEG_RAW_LO (HEX3..HEX0 raw 7-bit patterns)
                    seg_raw_lo <= i_data_in;

                8'h06: // 0x1000_6xxx - SEG_RAW_HI (HEX5..HEX4 raw 7-bit patterns)
                    seg_raw_hi <= i_data_in;

                8'h07: // 0x1000_7xxx - SEG_MODE (bit0: 0=hex-decoded, 1=raw)
                    seg_raw_mode <= i_data_in[0];

                default: ; // Ignore reserved addresses
            endcase
        end
    end

    //READ LOGIC
    always_comb begin
        o_data_out = 32'b0; // Default return 0

        case ({i_peri_addr[19:16], i_peri_addr[15:12]})
            8'h00: // 0x1000_0xxx - Red LEDs
                o_data_out = o_io_ledr;

            8'h01: // 0x1000_1xxx - Green LEDs
                o_data_out = o_io_ledg;

            8'h04: // 0x1000_4xxx - LCD
                o_data_out = o_io_lcd;

            8'h10: // 0x1001_0xxx - Switches (READ ONLY)
                o_data_out = i_io_sw;

            default:
                o_data_out = 32'b0;
        endcase

    end
endmodule