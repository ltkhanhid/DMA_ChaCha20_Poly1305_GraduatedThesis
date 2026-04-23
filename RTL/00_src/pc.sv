module pc(
    input logic i_clk,                  // Đồng hồ
    input logic i_reset,                // i_reset bất đồng bộ (active-high)
    input logic i_pc_en,               // Enable để cập nhật PC 
    input logic [31:0] i_pc_in,       // Giá trị mới để ghi vào PC
    output logic [31:0] o_pc_out          // Giá trị hiện tại của PC
);

    always @(posedge i_clk or negedge i_reset) begin
        if (!i_reset) begin
            o_pc_out <= 32'h00000000;          // i_reset PC về 0
        end
        else if (i_pc_en) begin
            o_pc_out <= i_pc_in;        // Ghi giá trị mới khi có nhánh/jump
        end
    end

endmodule
