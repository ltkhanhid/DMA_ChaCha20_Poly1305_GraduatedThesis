// TileLink UL Test Library
// Reusable tasks and functions for TL-UL verification

package tlul_test_lib;
  import tlul_pkg::*;
  
  // Test parameters
  parameter int MAX_TIMEOUT = 2000;
  parameter int FIFO_DEPTH = 8;
  
  // Statistics
  int test_pass = 0;
  int test_fail = 0;
  int total_trans = 0;
  
  // Random delays
  function automatic int get_random_delay(int min_delay, int max_delay);
    return $urandom_range(min_delay, max_delay);
  endfunction
  
  // Generate random address within range
  function automatic logic [31:0] get_random_addr(logic [31:0] base, logic [31:0] range);
    return base + ($urandom() % range);
  endfunction
  
  // Compare data with mask
  function automatic bit compare_data(logic [31:0] expected, logic [31:0] actual, logic [3:0] mask);
    for (int i = 0; i < 4; i++) begin
      if (mask[i] && (expected[i*8 +: 8] != actual[i*8 +: 8]))
        return 0;
    end
    return 1;
  endfunction
  
  // Print test result
  function automatic void print_result(string test_name, bit pass);
    if (pass) begin
      $display("[%0t] ✓ PASS: %s", $time, test_name);
      test_pass++;
    end else begin
      $display("[%0t] ✗ FAIL: %s", $time, test_name);
      test_fail++;
    end
  endfunction
  
  // Print summary
  function automatic void print_summary();
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("Total Transactions: %0d", total_trans);
    $display("PASS: %0d", test_pass);
    $display("FAIL: %0d", test_fail);
    if (test_fail == 0)
      $display("✓ ALL TESTS PASSED!");
    else
      $display("✗ SOME TESTS FAILED!");
    $display("========================================\n");
  endfunction
  
  // Task: Wait for cycles
  task automatic wait_cycles(ref logic clk, input int num_cycles);
    repeat(num_cycles) @(posedge clk);
  endtask
  
  // Task: TL-UL Write (single transaction)
  // TLUL Spec: valid asserted, data stable until ready
  task automatic tl_write(
    ref logic clk,
    ref logic tl_a_valid,
    ref logic [2:0] tl_a_opcode,
    ref logic [2:0] tl_a_size,
    ref logic [4:0] tl_a_source,
    ref tl_addr_t tl_a_address,
    ref tl_mask_t tl_a_mask,
    ref tl_data_t tl_a_data,
    ref logic tl_a_ready,  // Changed to ref for live sampling
    input tl_addr_t addr,
    input tl_data_t wdata,
    input tl_mask_t mask,
    input tl_size_t size,
    input tl_source_t source,
    input bit partial
  );
    @(posedge clk);
    tl_a_valid = 1'b1;
    tl_a_opcode = partial ? TL_A_PUT_PARTIAL_DATA : TL_A_PUT_FULL_DATA;
    tl_a_size = size;
    tl_a_source = source;
    tl_a_address = addr;
    tl_a_mask = mask;
    tl_a_data = wdata;
    
    // Wait for handshake (TLUL: valid && ready)
    @(posedge clk);
    while (!tl_a_ready) @(posedge clk);
    
    // Handshake complete, deassert valid
    tl_a_valid = 1'b0;
    total_trans++;
  endtask
  
  // Task: TL-UL Read (single transaction)
  task automatic tl_read(
    ref logic clk,
    ref logic tl_a_valid,
    ref logic [2:0] tl_a_opcode,
    ref logic [2:0] tl_a_size,
    ref logic [4:0] tl_a_source,
    ref tl_addr_t tl_a_address,
    ref tl_mask_t tl_a_mask,
    ref tl_data_t tl_a_data,
    ref logic tl_a_ready,  // Changed to ref for live sampling
    input tl_addr_t addr,
    input tl_size_t size,
    input tl_source_t source
  );
    @(posedge clk);
    tl_a_valid = 1'b1;
    tl_a_opcode = TL_A_GET;
    tl_a_size = size;
    tl_a_source = source;
    tl_a_address = addr;
    tl_a_mask = 4'hF;
    tl_a_data = '0;
    
    // Wait for handshake (TLUL: valid && ready)
    @(posedge clk);
    while (!tl_a_ready) @(posedge clk);
    
    // Handshake complete, deassert valid
    tl_a_valid = 1'b0;
    total_trans++;
  endtask
  
  // Task: Wait for TL-UL Response
  // TLUL Spec Compliant: 
  // - d_ready must be asserted to accept response
  // - Sample data when valid && ready (handshake)
  // All D channel signals must be ref to sample live values
  task automatic tl_wait_response(
    ref logic clk,
    ref logic tl_d_ready,
    ref logic tl_d_valid,
    ref logic [2:0] tl_d_opcode,
    ref tl_data_t tl_d_data,
    ref logic tl_d_denied,
    ref logic tl_d_corrupt,
    ref tl_source_t tl_d_source,
    output tl_data_t rdata,
    output logic denied,
    output logic corrupt,
    output logic [2:0] opcode,
    output tl_source_t source
  );
    int timeout = 0;
    
    // Assert ready to accept response (TLUL requirement)
    tl_d_ready = 1'b1;
    
    // Wait for valid response - sample immediately when detected
    forever begin
      @(posedge clk);
      timeout++;
      
      // Check valid immediately after clock edge (within same delta)
      if (tl_d_valid) begin
        // Sample response NOW - before any NBA updates
        rdata = tl_d_data;
        denied = tl_d_denied;
        corrupt = tl_d_corrupt;
        opcode = tl_d_opcode;
        source = tl_d_source;
        
        $display("[%0t] Response received: opcode=%0d, source=%0d, data=0x%08h, denied=%0d", 
                 $time, opcode, source, rdata, denied);
        break;
      end
      
      if (timeout > MAX_TIMEOUT) begin
        $display("[%0t] ERROR: Response timeout after %0d cycles! tl_d_valid=%0d", 
                 $time, timeout, tl_d_valid);
        $finish;
      end
    end
    
    // Deassert ready after completing handshake
    @(posedge clk);
    tl_d_ready = 1'b0;
  endtask
  
  // Task: Full Write-Read sequence with check
  task automatic write_read_check(
    ref logic clk,
    ref logic tl_a_valid,
    ref logic [2:0] tl_a_opcode,
    ref logic [2:0] tl_a_size,
    ref logic [4:0] tl_a_source,
    ref tl_addr_t tl_a_address,
    ref tl_mask_t tl_a_mask,
    ref tl_data_t tl_a_data,
    input logic tl_a_ready,
    ref logic tl_d_ready,
    input logic tl_d_valid,
    input logic [2:0] tl_d_opcode,
    input tl_data_t tl_d_data,
    input logic tl_d_denied,
    input logic tl_d_corrupt,
    input tl_source_t tl_d_source,
    input tl_addr_t addr,
    input tl_data_t wdata,
    input string test_name
  );
    tl_data_t rdata;
    logic denied, corrupt;
    logic [2:0] resp_opcode;
    tl_source_t resp_source;
    tl_source_t src_id = 0;
    
    // Write
    tl_write(clk, tl_a_valid, tl_a_opcode, tl_a_size, tl_a_source, 
             tl_a_address, tl_a_mask, tl_a_data, tl_a_ready,
             addr, wdata, 4'hF, 3'd2, src_id, 0);
    tl_wait_response(clk, tl_d_ready, tl_d_valid, tl_d_opcode, tl_d_data,
                     tl_d_denied, tl_d_corrupt, tl_d_source,
                     rdata, denied, corrupt, resp_opcode, resp_source);
    
    src_id++;
    
    // Read
    tl_read(clk, tl_a_valid, tl_a_opcode, tl_a_size, tl_a_source,
            tl_a_address, tl_a_mask, tl_a_data, tl_a_ready,
            addr, 3'd2, src_id);
    tl_wait_response(clk, tl_d_ready, tl_d_valid, tl_d_opcode, tl_d_data,
                     tl_d_denied, tl_d_corrupt, tl_d_source,
                     rdata, denied, corrupt, resp_opcode, resp_source);
    
    // Check
    print_result(test_name, (rdata == wdata) && !denied && !corrupt);
  endtask

endpackage
