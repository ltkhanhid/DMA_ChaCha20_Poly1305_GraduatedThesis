`timescale 1ns/1ps
module mult_130x128_limb(
    input  wire clk,
    input  wire reset_n,
    input  wire start,
    input  wire [129:0] a_in,
    input  wire [127:0] b_in,
    output reg [257:0] product_out,
    output reg busy,
    output reg done
);
    reg [257:0] acc;
    reg [257:0] a_shift;
    reg [127:0] b_reg;
    reg [7:0] bit_idx;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            product_out <= 258'b0;
            acc <= 258'b0;
            a_shift <= 258'b0;
            b_reg <= 128'b0;
            bit_idx <= 8'd0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if(start && !busy) begin
                a_shift <= {128'b0, a_in};
                b_reg <= b_in;
                acc <= 258'b0;
                bit_idx <= 8'd0;
                busy <= 1'b1;
            end else if(busy) begin
                if(b_reg[0]) acc <= acc + a_shift;
                a_shift <= a_shift << 1;
                b_reg <= b_reg >> 1;
                bit_idx <= bit_idx + 1'b1;
                if(bit_idx == 127) begin
                    product_out <= acc;
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
