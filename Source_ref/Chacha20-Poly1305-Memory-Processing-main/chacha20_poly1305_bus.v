`timescale 1ns/1ps
module chacha20_poly1305_bus(
    input  wire clk,
    input  wire reset_n,
    input  wire cs,
    input  wire we,
    input  wire [7:0] address,
    input  wire [511:0] write_data,
    output reg  [511:0] read_data
);
    // Control registers
    reg init_reg;
    reg encdec_reg;

    // Key, nonce, and data registers
    reg [31:0] key_reg[0:7];
    reg [31:0] nonce_reg[0:2];
    reg [31:0] data_reg[0:15];

    // Compose core inputs
    wire [255:0] core_key = {key_reg[0],key_reg[1],key_reg[2],key_reg[3],
                             key_reg[4],key_reg[5],key_reg[6],key_reg[7]};
    wire [95:0] core_nonce = {nonce_reg[2],nonce_reg[1],nonce_reg[0]};
    wire [511:0] core_data_in = {data_reg[0],data_reg[1],data_reg[2],data_reg[3],
                                 data_reg[4],data_reg[5],data_reg[6],data_reg[7],
                                 data_reg[8],data_reg[9],data_reg[10],data_reg[11],
                                 data_reg[12],data_reg[13],data_reg[14],data_reg[15]};

    // Core outputs
    wire core_ready, core_valid, core_tag_ok;
    wire [511:0] core_data_out;
    wire [127:0] core_tag;

    chacha20_poly1305_core core (
        .clk(clk),
        .reset_n(reset_n),
        .init(init_reg),
        .encdec(encdec_reg),
        .key(core_key),
        .nonce(core_nonce),
        .data_in(core_data_in),
        .ready(core_ready),
        .valid(core_valid),
        .tag_ok(core_tag_ok),
        .data_out(core_data_out),
        .tag(core_tag)
    );

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            init_reg <= 0;
            encdec_reg <= 0;
            for(i=0;i<8;i=i+1) key_reg[i]<=0;
            for(i=0;i<3;i=i+1) nonce_reg[i]<=0;
            for(i=0;i<16;i=i+1) data_reg[i]<=0;
        end else if(cs && we) begin
            case(address)
                8'h08: init_reg <= write_data[0];
                8'h0a: encdec_reg <= write_data[0];
                8'h10,8'h11,8'h12,8'h13,8'h14,8'h15,8'h16,8'h17:
                    key_reg[address[2:0]] <= write_data[31:0];
                8'h20,8'h21,8'h22:
                    nonce_reg[address[1:0]] <= write_data[31:0];
                8'h30: for(i=0;i<16;i=i+1) data_reg[i] <= write_data[(15-i)*32 +:32];
            endcase
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n)
            read_data <= 0;
        else if(cs && !we) begin
            case(address)
                8'h00: read_data <= 512'h6332307031333035302e3031; // ID
                8'h09: read_data <= {509'b0, core_tag_ok, core_valid, core_ready};
                8'h0a: read_data <= {511'b0, encdec_reg};
                8'h30: read_data <= core_data_out;
                8'h40: read_data <= {384'b0, core_tag};
                default: read_data <= 0;
            endcase
        end
    end
endmodule
