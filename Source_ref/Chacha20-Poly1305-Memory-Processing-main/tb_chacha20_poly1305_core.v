`timescale 1ns/1ps
module tb_chacha20_poly1305_core;
    reg clk, rst, init, encdec;
    reg [255:0] key;
    reg [95:0] nonce;
    reg [511:0] data_in;
    wire ready, valid, tag_ok;
    wire [511:0] data_out;
    wire [127:0] tag;

    integer cycle_count;
    integer i;
    reg [511:0] data_blocks [0:1];
    reg waiting_valid;

    initial clk = 0;
    always #5 clk = ~clk;

    chacha20_poly1305_core dut(
        .clk(clk),
        .reset_n(rst),
        .init(init),
        .encdec(encdec),
        .key(key),
        .nonce(nonce),
        .data_in(data_in),
        .ready(ready),
        .valid(valid),
        .tag_ok(tag_ok),
        .data_out(data_out),
        .tag(tag)
    );

    initial begin
        $dumpfile("tb_chacha20_poly1305_core.vcd");
        $dumpvars(0, tb_chacha20_poly1305_core);
    end

    initial cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

    initial begin
        // reset
        rst = 0; init = 0; encdec = 1;
        key = 256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        nonce = {32'h11111111,32'h22222222,32'h33333333};

        data_blocks[0] = {8{64'hcafebabedeadbeef}};
        data_blocks[1] = {8{64'h0123456789abcdef}};

        #20 rst = 1;
        $display("[Cycle %0d] RESET released", cycle_count);

        for(i=0; i<2; i=i+1) begin
            data_in = data_blocks[i];
            $display("[Cycle %0d] DATA_BLOCK %0d loaded: %h", cycle_count, i, data_in);

            // assert init
            init = 1; @(posedge clk); init = 0;
            $display("[Cycle %0d] INIT asserted", cycle_count);

            // wait until valid
            waiting_valid = 1;
            while(waiting_valid) begin
                @(posedge clk);
                if(valid) begin
                    $display("[Cycle %0d] VALID data_out: %h", cycle_count, data_out);
                    $display("[Cycle %0d] TAG: %h", cycle_count, tag);
                    waiting_valid = 0;
                end
            end
            $display("------------------------------------------------------");
        end

        $display("Simulation finished at cycle %0d", cycle_count);
        #20 $finish;
    end
endmodule

