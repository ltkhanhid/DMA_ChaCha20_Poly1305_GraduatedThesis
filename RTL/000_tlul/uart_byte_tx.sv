module uart_tx_8bit (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data_byte,   // Dữ liệu 8-bit
    input  logic       send_en,     // Xung kích hoạt gửi (1 cycle)
    output logic       uart_tx,
    output logic       tx_done,
    output logic       tx_busy
);

    // Fixed baud rate: 115200 @ 50MHz -> 50_000_000 / 115200 - 1 = 433
    localparam logic [15:0] BPS_DR = 16'd433;

    logic [15:0] div_cnt;
    logic        bps_clk;
    logic [3:0]  bit_cnt;
    logic [7:0]  tx_reg;
    
    typedef enum logic [1:0] {IDLE, SENDING, DONE} state_t;
    state_t state_q, state_d;

    // Divider (Fixed 115200 baud)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) div_cnt <= 0;
        else if (state_q == SENDING) begin
            if (div_cnt == BPS_DR) div_cnt <= 0;
            else div_cnt <= div_cnt + 1;
        end else div_cnt <= 0;
    end
    assign bps_clk = (div_cnt == BPS_DR);

    // 2. FSM & Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= IDLE;
        else state_q <= state_d;
    end

    always_comb begin
        state_d = state_q;
        case (state_q)
            IDLE:    if (send_en) state_d = SENDING;
            SENDING: if (bit_cnt == 4'd9 && bps_clk) state_d = DONE;  // 0-7: data, 8: stop
            DONE:    state_d = IDLE;
            default: state_d = IDLE;
        endcase
    end

    // Datapath
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx <= 1'b1;
            tx_reg  <= 8'h0;
            bit_cnt <= 0;
        end else begin
            if (state_q == IDLE && send_en) begin
                tx_reg <= data_byte;
                uart_tx <= 1'b0;  // Start bit ngay lập tức
                bit_cnt <= 0;
            end else if (state_q == SENDING && bps_clk) begin
                case (bit_cnt)  // Gửi bit tương ứng bit_cnt
                    4'd0: uart_tx <= tx_reg[0]; // D0
                    4'd1: uart_tx <= tx_reg[1]; // D1
                    4'd2: uart_tx <= tx_reg[2]; // D2
                    4'd3: uart_tx <= tx_reg[3]; // D3
                    4'd4: uart_tx <= tx_reg[4]; // D4
                    4'd5: uart_tx <= tx_reg[5]; // D5
                    4'd6: uart_tx <= tx_reg[6]; // D6
                    4'd7: uart_tx <= tx_reg[7]; // D7
                    4'd8: uart_tx <= 1'b1;      // Stop bit
                    default: uart_tx <= 1'b1;   // Idle
                endcase
                bit_cnt <= bit_cnt + 1;
            end else if (state_q == DONE) begin
                uart_tx <= 1'b1; // Idle state
            end
        end
    end

    assign tx_busy = (state_q == SENDING);
    assign tx_done = (state_q == DONE);

endmodule