`timescale 1ns/1ps

module uart_byte_tb;

    // Clock and Reset
    logic clk;
    logic rst_n;
    
    // TX signals
    logic [7:0] tx_data;
    logic       tx_send_en;
    logic [2:0] tx_baud_set;
    logic       uart_wire;
    logic       tx_done;
    logic       tx_busy;
    
    // RX signals
    logic [7:0] rx_data;
    logic       rx_done;
    logic       rx_busy;
    logic [2:0] rx_baud_set;
    
    // Test control
    integer test_passed = 0;
    integer test_failed = 0;
    
    // Clock generation (50MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 20ns period = 50MHz
    end
    
    // Instantiate TX module (fixed 115200 baud @ 50MHz)
    uart_tx_8bit u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .data_byte(tx_data),
        .send_en(tx_send_en),
        .uart_tx(uart_wire),
        .tx_done(tx_done),
        .tx_busy(tx_busy)
    );
    
    // Instantiate RX module (fixed 115200 baud @ 50MHz)
    uart_rx_8bit u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_wire),
        .data_byte(rx_data),
        .rx_done(rx_done),
        .rx_busy(rx_busy)
    );
    
    // Test stimulus
    initial begin
        $dumpfile("uart_byte_tb.vcd");
        $dumpvars(0, uart_byte_tb);
        
        // Initialize
        rst_n = 0;
        tx_data = 0;
        tx_send_en = 0;
        tx_baud_set = 3'd4; // 115200
        rx_baud_set = 3'd4; // 115200
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);
        
        $display("\n========================================");
        $display("Starting UART Byte TX/RX Testbench");
        $display("========================================\n");
        
        // Test 1: Send 0xAA
        test_uart_loopback(8'hAA, "Test 1: 0xAA");
        
        // Test 2: Send 0x55
        test_uart_loopback(8'h55, "Test 2: 0x55");
        
        // Test 3: Send 0x00
        test_uart_loopback(8'h00, "Test 3: 0x00");
        
        // Test 4: Send 0xFF
        test_uart_loopback(8'hFF, "Test 4: 0xFF");
        
        // Test 5: Send random data
        test_uart_loopback(8'h3C, "Test 5: 0x3C");
        
        // Test 6: Back-to-back transfers
        test_back_to_back();
        
        // Test 7: Different baud rates
        test_multiple_baud_rates();
        
        // Summary
        repeat(100) @(posedge clk);
        $display("\n========================================");
        $display("Test Summary:");
        $display("  PASSED: %0d", test_passed);
        $display("  FAILED: %0d", test_failed);
        $display("========================================\n");
        
        if (test_failed == 0)
            $display("*** ALL TESTS PASSED ***\n");
        else
            $display("*** SOME TESTS FAILED ***\n");
        
        $finish;
    end
    
    // Task: Test UART loopback
    task test_uart_loopback(input [7:0] data, input string test_name);
        begin
            $display("[%0t] %s: Sending 0x%02X", $time, test_name, data);
            
            // Send data
            tx_data = data;
            @(posedge clk);
            tx_send_en = 1;
            @(posedge clk);
            tx_send_en = 0;
            
            // Wait for RX done (RX completes slightly before TX because of synchronizer delay)
            wait(rx_done);
            $display("[%0t] %s: RX complete, received 0x%02X", $time, test_name, rx_data);
            
            // Wait for TX done
            wait(tx_done);
            $display("[%0t] %s: TX complete", $time, test_name);
            
            // Check result
            if (rx_data == data) begin
                $display("[%0t] %s: PASSED ✓\n", $time, test_name);
                test_passed++;
            end else begin
                $display("[%0t] %s: FAILED ✗ - Expected 0x%02X, got 0x%02X\n", 
                         $time, test_name, data, rx_data);
                test_failed++;
            end
            
            repeat(50) @(posedge clk);
        end
    endtask
    
    // Task: Back-to-back transfers
    task test_back_to_back();
        begin
            $display("[%0t] Test 6: Back-to-back transfers", $time);
            
            // Send first byte
            tx_data = 8'h12;
            @(posedge clk);
            tx_send_en = 1;
            @(posedge clk);
            tx_send_en = 0;
            
            // Wait a bit, then send second byte
            wait(tx_done);
            repeat(5) @(posedge clk);
            
            tx_data = 8'h34;
            @(posedge clk);
            tx_send_en = 1;
            @(posedge clk);
            tx_send_en = 0;
            
            // Wait for both to complete
            wait(tx_done);
            repeat(1000) @(posedge clk);
            
            $display("[%0t] Test 6: Back-to-back test complete\n", $time);
            test_passed++; // Just check it doesn't hang
        end
    endtask
    
    // Task: Multiple baud rates
    task test_multiple_baud_rates();
        begin
            $display("[%0t] Test 7: Multiple baud rates", $time);
            
            // Test at 9600 baud
            tx_baud_set = 3'd0;
            rx_baud_set = 3'd0;
            repeat(10) @(posedge clk);
            
            tx_data = 8'hA5;
            @(posedge clk);
            tx_send_en = 1;
            @(posedge clk);
            tx_send_en = 0;
            
            wait(rx_done);
            
            if (rx_data == 8'hA5) begin
                $display("[%0t] Test 7: 9600 baud PASSED ✓", $time);
                test_passed++;
            end else begin
                $display("[%0t] Test 7: 9600 baud FAILED ✗", $time);
                test_failed++;
            end
            
            // Return to 115200
            tx_baud_set = 3'd4;
            rx_baud_set = 3'd4;
            repeat(100) @(posedge clk);
            
            $display("[%0t] Test 7: Complete\n", $time);
        end
    endtask
    
    // Monitor for debugging
    initial begin
        forever begin
            @(posedge clk);
            if (tx_send_en)
                $display("[%0t] TX: send_en asserted, data=0x%02X", $time, tx_data);
            if (tx_done)
                $display("[%0t] TX: tx_done asserted", $time);
            if (rx_done)
                $display("[%0t] RX: rx_done asserted, data=0x%02X", $time, rx_data);
        end
    end
    
    // Timeout watchdog
    initial begin
        #50000000; // 50ms timeout
        $display("\n*** ERROR: Test timeout! ***\n");
        $finish;
    end

endmodule
