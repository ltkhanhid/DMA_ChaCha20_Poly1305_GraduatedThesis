
module regfile(
    input logic i_clk,                  
    input logic i_reset,                
    input logic [4:0] i_rs1_addr,       
    input logic [4:0] i_rs2_addr,       
    input logic [4:0] i_rd_addr,        
    input logic [31:0] i_rd_data,       
    input logic i_rd_wren,
    output logic [31:0] o_rs1_data,     
    output logic [31:0] o_rs2_data      
);
    
    // Mảng 32 thanh ghi, mỗi thanh ghi 32-bit
    // Synthesis attributes to ensure RAM inference
    (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] registers [0:31];

    // Phần đọc (combinational, with internal forwarding)
    always_comb begin
        // Forwarding: nếu đang ghi vào thanh ghi mà đồng thời đọc từ thanh ghi đó
        if (~(|(i_rs1_addr ^ 5'h0)))
            o_rs1_data = 32'h0;
        else if (i_rd_wren && ~(|(i_rd_addr ^ i_rs1_addr)))
            o_rs1_data = i_rd_data; // Forward data từ WB
        else
            o_rs1_data = registers[i_rs1_addr];
            
        if (~(|(i_rs2_addr ^ 5'h0)))
            o_rs2_data = 32'h0;
        else if (i_rd_wren && ~(|(i_rd_addr ^ i_rs2_addr)))
            o_rs2_data = i_rd_data; // Forward data từ WB
        else
            o_rs2_data = registers[i_rs2_addr];
    end
    
    // Phần ghi (đồng bộ ở cạnh lên - posedge write)
    always @(posedge i_clk or negedge i_reset) begin
        if (!i_reset) begin
            registers <= '{32{32'h0}}; // Reset tất cả thanh ghi về 0
        end
        else begin
            if (i_rd_wren && (i_rd_addr != 5'h0)) begin
                registers[i_rd_addr] <= i_rd_data; // Ghi dữ liệu vào thanh ghi (trừ x0)
            end
            // x0 luôn là 0, không cần gán lại mỗi cycle
        end
    end

endmodule
 
   