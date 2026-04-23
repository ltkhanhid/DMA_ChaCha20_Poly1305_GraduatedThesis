main:
    # ===========================================================
    # 1. Thiết lập các hằng số điều khiển LCD
    # ===========================================================
    li   s4, 0x400          # EN = bit10
    li   s5, 0x200          # RS = bit9
    li   s6, 0x100          # RW = bit8 (luôn = 0)

    # ===========================================================
    # 2. Địa chỉ ngoại vi
    # ===========================================================
    lui  s0, 0x10004        # LCD base = 0x1000_4000
    lui  s1, 0x10010        # Switch base = 0x1001_0000

    # ===========================================================
    # 3. Khởi tạo LCD 16x2
    # ===========================================================
    li   a1, 0x38           # 8-bit mode, 2 lines
    jal  send_cmd
    li   a1, 0x0C           # Display ON
    jal  send_cmd
    li   a1, 0x01           # Clear display
    jal  send_cmd
    jal  delay_clear
    li   a1, 0x06           # Entry mode
    jal  send_cmd

read_loop:
    # ===========================================================
    # 4. Đọc switch input
    # ===========================================================
    lw   s2, 0(s1)

    # ===========================================================
    # 5. Dòng 1: "Binary : " (chỉ set position, không clear)
    # ===========================================================
    li   a1, 0x80
    jal  send_cmd

    li a1, 'B' 
    jal send_data
    li a1, 'i'  
    jal send_data
    li a1, 'n' 
    jal send_data
    li a1, 'a'  
    jal send_data
    li a1, 'r'
    jal send_data
    li a1, 'y' 
    jal send_data
    li a1, ' ' 
    jal send_data
    li a1, ':' 
    jal send_data
    li a1, ' ' 
    jal send_data

    # Hiển thị 16-bit nhị phân
    li   t0, 15
bin_loop:
    srl  t1, s2, t0
    andi t1, t1, 1
    addi a1, t1, 0x30
    jal  send_data
    addi t0, t0, -1
    bgez t0, bin_loop

    # ===========================================================
    # 6. Dòng 2: "HEX: " và "DEC:"
    # ===========================================================
    li   a1, 0xC0
    jal  send_cmd

    li a1, 'H' 
    jal send_data
    li a1, 'E' 
    jal send_data
    li a1, 'X'
     jal send_data
    li a1, ':' 
    jal send_data
    li a1, ' ' 
    jal send_data

    # Hiển thị HEX
    li   t0, 12
hex_loop:
    srl  t1, s2, t0
    andi t1, t1, 0xF
    li   t2, 10
    blt  t1, t2, hex_num
    addi t1, t1, 55       # A-F
    j    hex_show
hex_num:
    addi t1, t1, 48       # 0-9
hex_show:
    mv   a1, t1
    jal  send_data
    addi t0, t0, -4
    bgez t0, hex_loop

    li a1, ' ' 
    jal send_data
    li a1, 'D' 
    jal send_data
    li a1, 'E' 
    jal send_data
    li a1, 'C' 
    jal send_data
    li a1, ':'
     jal send_data
    li a1, ' ' 
    jal send_data

    # Hiển thị DEC
    mv   a0, s2
    li   s8, 0
    li   a2, 10000
    jal  div_mod_10pow
    jal  display_digit_if
    mv   a0, a4
    li   a2, 1000
    jal  div_mod_10pow
    jal  display_digit_if
    mv   a0, a4
    li   a2, 100
    jal  div_mod_10pow
    jal  display_digit_if
    mv   a0, a4
    li   a2, 10
    jal  div_mod_10pow
    jal  display_digit_if
    mv   a0, a4
    li   a2, 1
    jal  div_mod_10pow
    jal  display_digit_if

    # Delay giữa các lần refresh (~100ms @ 20MHz)
    li   t5, 800000      # 800K cycles @ 20MHz ≈ 40ms
delay_refresh:
    addi t5, t5, -1
    bnez t5, delay_refresh

    j read_loop

# ===========================================================
# === Các hàm con ===========================================
# ===========================================================
display_digit_if:
    # Sử dụng t6 thay vì x20 (an toàn hơn cho temporary)
    mv   t6, ra
    li   t3, 1           # ← SỬA: Dùng t3 thay vì t1 để tránh conflict
    beq  a2, t3, display_it
    bnez s8, display_it
    beqz a3, ret_d
display_it:
    li   s8, 1
    addi a1, a3, 0x30
    
    # INLINE send_data để tránh nested call
    or   t1, a1, s5      # t1 = data | RS
    sw   t1, 0(s0)       # LCD = data | RS
    or   t2, t1, s4      # t2 = data | RS | EN
    sw   t2, 0(s0)       # LCD = data | RS | EN (pulse high)
    
    # Delay EN pulse (~0.5 µs @ 20MHz)
    li   t5, 4           # 4 cycles @ 20MHz ≈ 0.2µs (tối thiểu)
delay_pulse_d1:
    addi t5, t5, -1
    bnez t5, delay_pulse_d1
    
    sw   t1, 0(s0)       # LCD = data | RS (pulse low)
    
    # Delay giữa các lệnh (~40 µs @ 20MHz)
    li   t5, 320         # 320 cycles @ 20MHz ≈ 16µs (tối thiểu cho LCD)
delay_cmd_d1:
    addi t5, t5, -1
    bnez t5, delay_cmd_d1
    
ret_d:
    mv   ra, t6
    ret

div_mod_10pow:
    mv   a4, a0
    li   a3, 0
div_loop:
    blt  a4, a2, div_end
    sub  a4, a4, a2
    addi a3, a3, 1
    j    div_loop
div_end:
    ret

# ===========================================================
# === LCD FUNCTIONS =========================================
# ===========================================================
send_cmd:
    # Sử dụng t6 thay vì x21
    mv   t6, ra
    
    sw   a1, 0(s0)       # LCD = command
    or   t1, a1, s4      # t1 = command | EN
    sw   t1, 0(s0)       # LCD = command | EN (pulse high)
    
    # Delay EN pulse (~0.5 µs @ 20MHz)
    li   t5, 4
delay_pulse_c1:
    addi t5, t5, -1
    bnez t5, delay_pulse_c1
    
    sw   a1, 0(s0)       # LCD = command (pulse low)
    
    # Delay giữa các lệnh (~40 µs @ 20MHz)
    li   t5, 320
delay_cmd_c1:
    addi t5, t5, -1
    bnez t5, delay_cmd_c1
    
    mv   ra, t6
    ret

send_data:
    # Sử dụng t6 thay vì x21
    mv   t6, ra
    
    or   t1, a1, s5      # t1 = data | RS
    sw   t1, 0(s0)       # LCD = data | RS
    or   t2, t1, s4      # t2 = data | RS | EN
    sw   t2, 0(s0)       # LCD = data | RS | EN (pulse high)
    
    # Delay EN pulse (~0.5 µs @ 20MHz)
    li   t5, 4
delay_pulse_d2:
    addi t5, t5, -1
    bnez t5, delay_pulse_d2
    
    sw   t1, 0(s0)       # LCD = data | RS (pulse low)
    
    # Delay giữa các lệnh (~40 µs @ 20MHz)
    li   t5, 320
delay_cmd_d2:
    addi t5, t5, -1
    bnez t5, delay_cmd_d2
    
    mv   ra, t6
    ret

# ===========================================================
# === DELAY =================================================
# ===========================================================
# Các hàm delay_pulse và delay_cmd đã được inline vào send_cmd/send_data
# để tránh nested function calls

delay_clear:
    # Delay ~1.6 ms cho clear display @ 20MHz
    li   t5, 13000       # 13000 cycles @ 20MHz ≈ 0.65ms (tối thiểu)
delay_clear_loop:
    addi t5, t5, -1
    bnez t5, delay_clear_loop
    ret
