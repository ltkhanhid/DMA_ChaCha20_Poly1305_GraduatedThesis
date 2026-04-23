module instr_mem #(
    parameter DEPTH = 65536,  // Default depth (can be overridden from top)
    parameter MEM   = "../../02_test/uart_app_ver3.hex"  // Default path (override from top)
) ( 
    input i_clk,
    input  [31:0] i_imem_addr,
    output logic [31:0] o_instr
);

    // Force M10K inference - combinational read with ROM behavior
    (* ramstyle = "M10K" *) logic [31:0] IMem [0:(DEPTH/4)-1];
    
    initial begin
         $readmemh(MEM, IMem);
    end

    // Combinational read - keeps pipeline timing correct
    always_comb begin
        o_instr = IMem[i_imem_addr[31:2]];
    end
endmodule