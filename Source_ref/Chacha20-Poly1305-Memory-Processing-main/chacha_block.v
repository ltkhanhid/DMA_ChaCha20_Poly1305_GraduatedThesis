`timescale 1ns/1ps
// chacha_block.v
// One ChaCha round per cycle (20 rounds). Start by pulsing 'start' for 1 cycle with state_in loaded.
// When done pulses 'done' for 1 cycle and state_out contains feed-forwarded output.

module chacha_block(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // pulse to start (load state_in)
    input  wire [511:0] state_in,
    output reg  [511:0] state_out,
    output reg         done          // one-cycle pulse when final output is ready
);
    // Use individual regs for 16 words to avoid SystemVerilog array slice issues
    reg [31:0] w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11,w12,w13,w14,w15;
    reg [31:0] w_orig0,w_orig1,w_orig2,w_orig3,w_orig4,w_orig5,w_orig6,w_orig7;
    reg [31:0] w_orig8,w_orig9,w_orig10,w_orig11,w_orig12,w_orig13,w_orig14,w_orig15;

    reg [4:0] round_cnt; // 0..19
    reg running;

    integer r;

    // local function: quarterround returning 128 bits (a,b,c,d)
    function [127:0] qr_func;
        input [31:0] a_in, b_in, c_in, d_in;
        reg [31:0] a1,b1,c1,d1;
        reg [31:0] a2,b2,c2,d2;
    begin
        a1 = a_in + b_in;
        d1 = ((d_in ^ a1) << 16) | ((d_in ^ a1) >> 16);
        c1 = c_in + d1;
        b1 = ((b_in ^ c1) << 12) | ((b_in ^ c1) >> 20);
        a2 = a1 + b1;
        d2 = ((d1 ^ a2) << 8) | ((d1 ^ a2) >> 24);
        c2 = c1 + d2;
        b2 = ((b1 ^ c2) << 7) | ((b1 ^ c2) >> 25);
        qr_func = {a2, b2, c2, d2};
    end
    endfunction

    // temp regs used inside round update
    reg [31:0] na0, na1, na2, na3, na4, na5, na6, na7, na8, na9, na10, na11, na12, na13, na14, na15;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state_out <= 512'h0;
            done <= 1'b0;
            running <= 1'b0;
            round_cnt <= 5'd0;
            w0<=0;w1<=0;w2<=0;w3<=0;w4<=0;w5<=0;w6<=0;w7<=0;
            w8<=0;w9<=0;w10<=0;w11<=0;w12<=0;w13<=0;w14<=0;w15<=0;
            w_orig0<=0; w_orig1<=0; w_orig2<=0; w_orig3<=0;
            w_orig4<=0; w_orig5<=0; w_orig6<=0; w_orig7<=0;
            w_orig8<=0; w_orig9<=0; w_orig10<=0; w_orig11<=0;
            w_orig12<=0; w_orig13<=0; w_orig14<=0; w_orig15<=0;
        end else begin
            done <= 1'b0;

            if(start && !running) begin
                // Load input state_in into working registers and saved original
                w0  <= state_in[511:480]; w1  <= state_in[479:448];
                w2  <= state_in[447:416]; w3  <= state_in[415:384];
                w4  <= state_in[383:352]; w5  <= state_in[351:320];
                w6  <= state_in[319:288]; w7  <= state_in[287:256];
                w8  <= state_in[255:224]; w9  <= state_in[223:192];
                w10 <= state_in[191:160]; w11 <= state_in[159:128];
                w12 <= state_in[127:96];  w13 <= state_in[95:64];
                w14 <= state_in[63:32];   w15 <= state_in[31:0];

                w_orig0  <= state_in[511:480]; w_orig1  <= state_in[479:448];
                w_orig2  <= state_in[447:416]; w_orig3  <= state_in[415:384];
                w_orig4  <= state_in[383:352]; w_orig5  <= state_in[351:320];
                w_orig6  <= state_in[319:288]; w_orig7  <= state_in[287:256];
                w_orig8  <= state_in[255:224]; w_orig9  <= state_in[223:192];
                w_orig10 <= state_in[191:160]; w_orig11 <= state_in[159:128];
                w_orig12 <= state_in[127:96];  w_orig13 <= state_in[95:64];
                w_orig14 <= state_in[63:32];   w_orig15 <= state_in[31:0];

                round_cnt <= 5'd0;
                running <= 1'b1;
            end else if(running) begin
                // perform one round per cycle
                // round parity: even -> column round, odd -> diagonal round
                if(round_cnt[0] == 1'b0) begin
                    // Column rounds:
                    // QR(t0,t4,t8,t12)
                    {na0, na4, na8, na12} = qr_func(w0, w4, w8, w12);
                    {na1, na5, na9, na13} = qr_func(w1, w5, w9, w13);
                    {na2, na6, na10, na14} = qr_func(w2, w6, w10, w14);
                    {na3, na7, na11, na15} = qr_func(w3, w7, w11, w15);
                end else begin
                    // Diagonal rounds:
                    {na0, na5, na10, na15} = qr_func(w0, w5, w10, w15);
                    {na1, na6, na11, na12} = qr_func(w1, w6, w11, w12);
                    {na2, na7, na8, na13}  = qr_func(w2, w7, w8,  w13);
                    {na3, na4, na9, na14}  = qr_func(w3, w4, w9,  w14);
                end

                // commit new words
                w0  <= na0;  w1  <= na1;  w2  <= na2;  w3  <= na3;
                w4  <= na4;  w5  <= na5;  w6  <= na6;  w7  <= na7;
                w8  <= na8;  w9  <= na9;  w10 <= na10; w11 <= na11;
                w12 <= na12; w13 <= na13; w14 <= na14; w15 <= na15;

                if(round_cnt == 5'd19) begin
                    // feed-forward, produce state_out
                    state_out[511:480] <= w_orig0 + na0;
                    state_out[479:448] <= w_orig1 + na1;
                    state_out[447:416] <= w_orig2 + na2;
                    state_out[415:384] <= w_orig3 + na3;
                    state_out[383:352] <= w_orig4 + na4;
                    state_out[351:320] <= w_orig5 + na5;
                    state_out[319:288] <= w_orig6 + na6;
                    state_out[287:256] <= w_orig7 + na7;
                    state_out[255:224] <= w_orig8 + na8;
                    state_out[223:192] <= w_orig9 + na9;
                    state_out[191:160] <= w_orig10 + na10;
                    state_out[159:128] <= w_orig11 + na11;
                    state_out[127:96]  <= w_orig12 + na12;
                    state_out[95:64]   <= w_orig13 + na13;
                    state_out[63:32]   <= w_orig14 + na14;
                    state_out[31:0]    <= w_orig15 + na15;

                    running <= 1'b0;
                    round_cnt <= 5'd0;
                    done <= 1'b1;
                end else begin
                    round_cnt <= round_cnt + 1'b1;
                end
            end
        end
    end
endmodule
