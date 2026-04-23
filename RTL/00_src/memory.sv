module memory #(
    parameter DEPTH = 32768  // Depth of memory (in bytes)
) (
    input i_clk,
    input [$clog2(DEPTH)-1:0] i_addr,
    input [31:0] i_wdata,
    input [3:0] i_bmask,  // Byte mask (1 enable, 0 disable)
    input i_wren,
    output logic [31:0] o_rdata,
    output logic [31:0] o_rdata_next  // Next word for misaligned access
);

    (* ramstyle = "M10K" *) logic [3:0][7:0] mem [0:DEPTH/4-1];
    logic [$clog2(DEPTH)-1:0] mem_addr;
    logic [$clog2(DEPTH)-1:0] mem_addr_next;

    assign mem_addr = i_addr[$clog2(DEPTH)-1:2];
    assign mem_addr_next = (mem_addr + 1 < DEPTH/4) ? mem_addr + 1 : mem_addr;

    initial begin
        mem = '{default: 32'h00000000};  // Zero all memory
    end

    // Synchronous write with byte mask
    always @(posedge i_clk) begin
        if (i_wren) begin
            // Write only the bytes enabled by i_bmask
            if (i_bmask[0]) mem[mem_addr][0] <= i_wdata[7:0];
            if (i_bmask[1]) mem[mem_addr][1] <= i_wdata[15:8];
            if (i_bmask[2]) mem[mem_addr][2] <= i_wdata[23:16];
            if (i_bmask[3]) mem[mem_addr][3] <= i_wdata[31:24];
        end
    end

    //synchronus read 
    always_ff @(posedge i_clk) begin
        o_rdata <= mem[mem_addr];
        o_rdata_next <= mem[mem_addr_next];
    end
    
   

endmodule
