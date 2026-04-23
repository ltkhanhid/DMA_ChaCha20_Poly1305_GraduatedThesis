`timescale 1ns / 1ns
module pipelined_tb;

    // Declare signals for top-level ports of soc_top_2m6s
    logic i_clk;
    logic rst_n; // active-low reset for soc_top
    logic [9:0] sw_i;
    logic [9:0] o_io_ledr;
    logic [31:0] o_io_ledg;
    logic [6:0]  o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3, o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7;
    logic [31:0] o_pc_debug, o_pc_wb, o_pc_mem;
    logic        o_insn_vld, o_ctrl, o_mispred;
    logic        uart_rx_i;
    logic        uart_tx_o;
    
// Interrupt signals
      logic        irq_dma;
      logic        irq_chacha;
      logic        irq_poly;

    // Instantiate soc_top_2m6s as DUT (with DMA integrated)
    soc_top_2m6s #(
        .MEM_FILE("../../02_test/isa_4b.hex")  // ISA test hex file
    ) dut (
        .clk(i_clk),
        .rst_n(rst_n),
        .sw_i(sw_i),
        .ledr_o(o_io_ledr),
        .ledg_o(o_io_ledg),
        .hex0_o(o_io_hex0),
        .hex1_o(o_io_hex1),
        .hex2_o(o_io_hex2),
        .hex3_o(o_io_hex3),
        .hex4_o(o_io_hex4),
        .hex5_o(o_io_hex5),
        .hex6_o(o_io_hex6),
        .hex7_o(o_io_hex7),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        
        // Interrupts
        .irq_dma_o(irq_dma),
        .irq_chacha_o(irq_chacha),
        .irq_poly_o(irq_poly),

        .pc_debug_o(o_pc_debug),
        .pc_wb_o(o_pc_wb),
        .pc_mem_o(o_pc_mem),
        .insn_vld_o(o_insn_vld),
        .ctrl_o(o_ctrl),
        .mispred_o(o_mispred)
    );
    
    // Generate clock
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk; // Clock period = 10ns
    end

    // Initial reset and setup (soc_top uses active-low reset)
    initial begin
        rst_n = 1'b0; // assert reset
        #10; // Wait for 10ns
        rst_n = 1'b1; // deassert reset
    end

    // default peripheral inputs
    initial begin
        sw_i = 10'h0;
        uart_rx_i = 1'b1; // idle
    end

    integer display_time = 0;

    always @(posedge i_clk) begin
        $display("=== Cycle at Time=%0t ===", $time);
        $display("o_io_hex0 = %h, o_io_hex1 = %h, o_io_hex2 = %h, o_io_hex3 = %h", 
            o_io_hex0, o_io_hex1, o_io_hex2, o_io_hex3);
        $display("o_io_hex4 = %h, o_io_hex5 = %h, o_io_hex6 = %h, o_io_hex7 = %h",
            o_io_hex4, o_io_hex5, o_io_hex6, o_io_hex7);
        $display("LEDR = %h, LEDG = %h", o_io_ledr, o_io_ledg);
        $display("PC_IF = %h, PC_ID = %h, PC_EX = %h, PC_MEM = %h", 
            dut.u_cpu.o_pc_IF, dut.u_cpu.i_pc_ID, dut.u_cpu.i_pc_EX, dut.u_cpu.i_pc_MEM);
        
        $display("Instruction (IF stage) = %h, Opcode = %b, Funct3 = %b", dut.u_cpu.o_instr_IF, dut.u_cpu.o_instr_IF[6:0], dut.u_cpu.o_instr_IF[14:12]);
        $display("Instruction (ID stage) = %h", dut.u_cpu.i_instr_ID);
        $display("Instruction (EX stage) = %h", dut.u_cpu.i_instr_EX);
        $display("Instruction (MEM stage) = %h", dut.u_cpu.i_instr_MEM);
        $display("Instruction (WB stage) = %h", dut.u_cpu.i_instr_WB);
        $display("o_pc_sel (ID) = %b", dut.u_cpu.o_pc_sel_ID);
        $display("flush == %b, mispred_EX = %b, combined_flush = %b, combined_stall = %b, pipeline_stall = %b", 
            dut.u_cpu.flush, dut.u_cpu.o_mispred_EX, dut.u_cpu.combined_flush, dut.u_cpu.combined_stall, dut.u_cpu.pipeline_stall);
        $display("o_wb_sel (ID) = %b, o_wb_data (WB) = %h", dut.u_cpu.o_wb_sel_ID, dut.u_cpu.o_wb_data_WB);
        $display("o_alu_data (EX) = %h, o_alu_op (ID) = %h", dut.u_cpu.o_alu_data_EX, dut.u_cpu.o_alu_op_ID);
        $display("o_alu_data (MEM) = %h", dut.u_cpu.i_alu_data_MEM);
        $display("o_rs1_data (ID) = %h, o_rs2_data (ID) = %h", dut.u_cpu.o_rs1_data_ID, dut.u_cpu.o_rs2_data_ID);
        $display("o_opa_sel (ID) = %b, o_opb_sel (ID) = %b", dut.u_cpu.o_opa_sel_ID, dut.u_cpu.o_opb_sel_ID);
        $display("o_immgen (ID) = %h", dut.u_cpu.o_immgen_ID);
        $display("ALU EX: %h", dut.u_cpu.o_alu_data_EX);
        $display("RegFile write enable (EX) = %b", dut.u_cpu.i_rd_wren_WB);
        $display("RegFile write address (rd) = %h", dut.u_cpu.i_instr_WB[11:7]);
        $display("WB select (ID) = %b, WB data (WB) = %h", dut.u_cpu.i_wb_sel_WB, dut.u_cpu.o_wb_data_WB);
        $display("LSU data (MEM stage) = %h", dut.u_cpu.o_ld_data_MEM);
        $display("LSU address (MEM stage) = %h, byte_maker = %b, mem_i_bmask = %b", dut.u_cpu.i_alu_data_MEM, dut.u_cpu.i_byte_num_MEM, dut.u_mem_adapter.u_memory.mem_addr);
        $display("LSU write enable (ID) = %b, mem enable = %b", dut.u_cpu.o_lsu_wren_ID, dut.u_mem_adapter.u_memory.i_wren);
        $display("Mem data  = %h", dut.u_mem_adapter.u_memory.o_rdata);
        $display("WB select (WBs) = %b", dut.u_cpu.i_wb_sel_WB);
        $display("Registers:");
        for (int i = 0; i < 31;) begin
            $display("  x%0d = %h, x%0d = %h, x%0d = %h, x%0d = %h, x%0d = %h", 
                i, dut.u_cpu.ID_inst.RegFile.registers[i], 
                i+1, dut.u_cpu.ID_inst.RegFile.registers[i+1], 
                i+2, dut.u_cpu.ID_inst.RegFile.registers[i+2], 
                i+3, dut.u_cpu.ID_inst.RegFile.registers[i+3], 
                i+4, dut.u_cpu.ID_inst.RegFile.registers[i+4]);
            i = i + 5; // Increment by 5 to display next set of registers
        end
        $display("---------------------------------------------------");
        display_time = display_time + 1; // increment
    end
    // Run simulation for a certain time
    initial #500000000 $finish;

endmodule