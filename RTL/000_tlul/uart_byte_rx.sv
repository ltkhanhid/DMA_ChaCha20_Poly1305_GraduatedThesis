module uart_rx_8bit (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       uart_rx,
    output logic [7:0] data_byte,
    output logic       rx_done,
    output logic       rx_busy
);

    // Fixed baud rate: 115200 @ 50MHz -> 50_000_000 / 115200 - 1 = 433
    localparam logic [15:0] BPS_DR = 16'd433;

    // Sync & Edge Detect (2-stage synchronizer)
    logic rx_s1, rx_s2, rx_s2_prev, rx_negedge;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s1      <= 1'b1;
            rx_s2      <= 1'b1;
            rx_s2_prev <= 1'b1;
        end else begin
            rx_s1      <= uart_rx;
            rx_s2      <= rx_s1;
            rx_s2_prev <= rx_s2;
        end
    end
    assign rx_negedge = rx_s2_prev && !rx_s2; // Falling edge detection

    logic [15:0] div_cnt;
    logic        bps_clk;
    logic        start_bit_valid;
    logic        reset_div_cnt;  // Flag để reset counter sau khi sample start bit
    
    // FSM
    typedef enum logic [1:0] {IDLE, RECEIVING, STOP} state_t;
    state_t state_q, state_d;
    logic [3:0] bit_cnt;    // 0=start, 1-8=data, 9=stop
    logic [7:0] shift_reg;
    
    // Baud clock generator (Fixed 115200 baud)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            div_cnt <= 0; 
            bps_clk <= 0;
        end else if (reset_div_cnt) begin
            // Reset counter sau khi sample start bit
            div_cnt <= 0;
            bps_clk <= 0;
        end else if (state_q == RECEIVING) begin
            if (div_cnt == BPS_DR) begin 
                div_cnt <= 0; 
                bps_clk <= 1; 
            end else begin 
                div_cnt <= div_cnt + 1; 
                bps_clk <= 0; 
            end
        end else begin
            div_cnt <= 0;
            bps_clk <= 0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= IDLE;
        else state_q <= state_d;
    end

    always_comb begin
        state_d = state_q;
        case (state_q)
            IDLE: if (rx_negedge) state_d = RECEIVING;
            RECEIVING: if (bps_clk && bit_cnt == 4'd9) state_d = STOP;
            STOP: state_d = IDLE;
            default: state_d = IDLE;
        endcase
    end
    
    assign rx_busy = (state_q == RECEIVING);

    // Data Sampling & Assembly
    // Sample at middle of each bit: first sample after (bps_DR/2) clocks from edge
    // Then every bps_DR clocks
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt   <= 0;
            shift_reg <= 0;
            data_byte <= 0;
            rx_done   <= 0;
            start_bit_valid <= 0;
            reset_div_cnt <= 0;
        end else begin
            rx_done <= 1'b0; // Pulse rx_done only for 1 cycle
            reset_div_cnt <= 1'b0; // Clear flag

            case (state_q)
                IDLE: begin
                    bit_cnt <= 0;
                    shift_reg <= 0;
                    start_bit_valid <= 0;
                end
                
                RECEIVING: begin
                    if (bit_cnt == 0) begin
                        // Wait for middle of start bit and verify it's 0
                        if (div_cnt == (BPS_DR >> 1)) begin
                            if (rx_s2 == 1'b0) begin
                                start_bit_valid <= 1'b1;
                                bit_cnt <= 1;
                                reset_div_cnt <= 1'b1;  // Reset để sample bit tiếp theo sau BPS_DR
                            end else begin
                                // Invalid start bit, abort
                                bit_cnt <= 0;
                                start_bit_valid <= 0;
                            end
                        end
                    end else if (bps_clk && start_bit_valid) begin
                        // Sample data bits 1-8
                        if (bit_cnt <= 8) begin
                            shift_reg[bit_cnt - 1] <= rx_s2;
                        end
                        // bit_cnt = 9 is stop bit, just wait for it
                        bit_cnt <= bit_cnt + 1;
                    end
                end
                
                STOP: begin
                    // Latch final data only if start bit was valid
                    if (start_bit_valid) begin
                        data_byte <= shift_reg;
                        rx_done <= 1'b1;
                    end
                    start_bit_valid <= 0;
                end
                
                default: ;
            endcase
        end
    end

endmodule