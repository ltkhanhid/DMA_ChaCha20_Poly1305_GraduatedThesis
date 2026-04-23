module lsu #(
    parameter DEPTH =  32768 // Depth of the memory
)(
    input logic i_clk, i_reset,
    input logic i_lsu_wren,
    input logic [3:0] i_byte_num, 
    input logic [31:0] i_st_data,
    input logic [31:0] i_lsu_addr,
    input logic [31:0] i_io_sw,
    input logic [31:0] i_io_key, // Key input
    output logic [31:0] o_ld_data,
    output logic [31:0] o_io_ledr, // LEDR output
    output logic [31:0] o_io_ledg,
    output logic [31:0] o_io_lcd, // LCD output
    output logic [6:0] o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3, o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7
);

    logic [3:0] byte_mask;        
    logic [31:0] mem_rdata; //data from memory
    logic [31:0] mem_rdata_next; //for misaligned
    logic [31:0] io_rdata; 
    logic [31:0] sw_reg;   // store switch input
    logic [31:0] key_reg;
    logic [1:0]  addr_off; // address offset
    logic [31:0] rdata_shift; // shifted read data
    logic [31:0] wdata_shift; // shifted write data
    logic [63:0] mem_double; //  64-bit for misaligned access

    logic is_mem, is_peri, is_sw;

    // Memory: 0x0000_0000 - 0x0000_7FFF
    // I/O:    0x1000_xxxx
    // Switch: 0x1001_xxxx

    assign is_mem  = ~(| (i_lsu_addr[31:16] ^ 16'h0000));
    assign is_peri = ~(| (i_lsu_addr[31:16] ^ 16'h1000));
    assign is_sw   = ~(| (i_lsu_addr[31:16] ^ 16'h1001));
    assign addr_off = i_lsu_addr[1:0];

    // use to handle delay off syn read
    logic [3:0] r_byte_num;
    logic [1:0] r_addr_off;
    logic r_is_mem, r_is_peri, r_is_sw;
    logic [31:0] r_io_rdata;
    logic [3:0] r_sw_key_sel; // Chọn giữa sw và key

    always_ff @(posedge i_clk or negedge i_reset) begin
        if (!i_reset) begin
            sw_reg <= 32'h0;  
            key_reg <= 32'h0;
            
            // Reset các thanh ghi pipeline
            r_byte_num <= 0;
            r_addr_off <= 0;
            r_is_mem   <= 0;
            r_is_peri  <= 0;
            r_is_sw    <= 0;
            r_io_rdata <= 0;
            r_sw_key_sel <= 0;
        end else begin
            sw_reg <= i_io_sw;   
            key_reg <= i_io_key;
            
            // Lưu lại trạng thái điều khiển cho read stage
            r_byte_num <= i_byte_num;
            r_addr_off <= addr_off;
            r_is_mem   <= is_mem;
            r_is_peri  <= is_peri;
            r_is_sw    <= is_sw;
            
            // Lưu lại output IO để đồng bộ với memory
            r_io_rdata <= io_rdata;
            r_sw_key_sel <= i_lsu_addr[15:12];
        end
    end

    memory #(.DEPTH(DEPTH)) mem(
        .i_clk(i_clk),
        .i_addr(i_lsu_addr[$clog2(DEPTH)-1:0]), 
        .i_wdata(wdata_shift),
        .i_bmask(byte_mask),
        .i_wren(i_lsu_wren & is_mem),
        .o_rdata(mem_rdata),           // Data này trễ 1 chu kỳ
        .o_rdata_next(mem_rdata_next)
    );

    peripherals peripherals(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_peri_addr(i_lsu_addr[19:0]), // 20-bit address for full peripheral space
        .i_data_in(i_st_data),
        .i_write_en(i_lsu_wren & is_peri),
        .i_io_sw(i_io_sw),
        .o_data_out(io_rdata),
        .o_io_ledr(o_io_ledr),
        .o_io_ledg(o_io_ledg),
        .o_io_lcd(o_io_lcd),
        .o_io_hex0(o_io_hex0), 
        .o_io_hex1(o_io_hex1), 
        .o_io_hex2(o_io_hex2), 
        .o_io_hex3(o_io_hex3), 
        .o_io_hex4(o_io_hex4), 
        .o_io_hex5(o_io_hex5),  
        .o_io_hex6(o_io_hex6), 
        .o_io_hex7(o_io_hex7)
    );

    // 
    always_comb begin
        case (i_byte_num)
            4'b0001: begin // store byte
                case(addr_off)
                    2'b00: begin wdata_shift = {24'b0, i_st_data[7:0]}; byte_mask = 4'b0001; end
                    2'b01: begin wdata_shift = {16'b0, i_st_data[7:0], 8'b0}; byte_mask = 4'b0010; end
                    2'b10: begin wdata_shift = {8'b0, i_st_data[7:0], 16'b0}; byte_mask = 4'b0100; end
                    2'b11: begin wdata_shift = {i_st_data[7:0], 24'b0}; byte_mask = 4'b1000; end
                    default: begin wdata_shift = 32'b0; byte_mask = 4'b0000; end
                endcase
            end
            4'b0011: begin // store half word
                case(addr_off)
                    2'b00: begin wdata_shift = {16'b0, i_st_data[15:0]}; byte_mask = 4'b0011; end
                    2'b01: begin wdata_shift = {8'b0, i_st_data[15:0], 8'b0}; byte_mask = 4'b0110; end
                    2'b10: begin wdata_shift = {i_st_data[15:0], 16'b0}; byte_mask = 4'b1100; end
                    2'b11: begin wdata_shift = {i_st_data[7:0], 24'b0}; byte_mask = 4'b1000; end
                    default: begin wdata_shift = 32'b0; byte_mask = 4'b0000; end
                endcase
            end
            4'b1111: begin
                wdata_shift = i_st_data;
                byte_mask = 4'b1111; // sw
            end
            default: begin
                wdata_shift = 32'b0;
                byte_mask = 4'b0000;
            end
        endcase
    end
    
    // read use delay logic
    always_comb begin
        rdata_shift = 32'b0;
        mem_double = {mem_rdata_next, mem_rdata}; // Dữ liệu từ RAM đã delay do syn read
        
        if (r_is_mem) begin
            rdata_shift = (mem_double >> {r_addr_off, 3'b000});
        end else if (r_is_peri) begin
            rdata_shift = r_io_rdata;
        end else if (r_is_sw) begin
            if(~(|(r_sw_key_sel ^ 4'b0000)))
                rdata_shift = sw_reg;
            else if(~(|(r_sw_key_sel ^ 4'b0001)))
                rdata_shift = key_reg;
        end 

        case (r_byte_num)
            4'b0001: o_ld_data = {{24{rdata_shift[7]}}, rdata_shift[7:0]};   // lb
            4'b0011: o_ld_data = {{16{rdata_shift[15]}}, rdata_shift[15:0]}; // lh
            4'b0100: o_ld_data = {24'b0, rdata_shift[7:0]};                  // lbu
            4'b0101: o_ld_data = {16'b0, rdata_shift[15:0]};                 // lhu
            4'b1111: o_ld_data = rdata_shift;                                // lw
            default: o_ld_data = 32'b0;
        endcase
    end

endmodule
