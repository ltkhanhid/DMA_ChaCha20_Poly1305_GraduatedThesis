#-----------------------------------------------------------------------------
# File: soc_fpga.sdc
# Description: Timing Constraints for RISC-V SoC (2M6S) on Cyclone V
# Top-level: soc_top_fpga
# Target:    50 MHz (20 ns period)
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# Clock Definition
#-----------------------------------------------------------------------------
# Primary 50MHz clock from oscillator
create_clock -name clk_50 -period 20.000 [get_ports {clk}]

# If using PLL, define generated clock
# create_generated_clock -name clk_sys -source [get_ports {clk}] \
#     -divide_by 1 [get_pins {u_pll|outclk_0}]

#-----------------------------------------------------------------------------
# Clock Uncertainty
#-----------------------------------------------------------------------------
derive_clock_uncertainty

#-----------------------------------------------------------------------------
# Input Constraints
#-----------------------------------------------------------------------------
# Switches — slow mechanical inputs, relaxed timing
set_input_delay  -clock clk_50 -max 8.0 [get_ports {sw_i[*]}]
set_input_delay  -clock clk_50 -min 0.0 [get_ports {sw_i[*]}]

# Reset — asynchronous push-button, treat as false path
set_false_path -from [get_ports {rst_n}]

# UART RX — asynchronous serial input (double-synced inside design)
set_false_path -from [get_ports {uart_rx_i}]

#-----------------------------------------------------------------------------
# Output Constraints
#-----------------------------------------------------------------------------
# LEDs — human-visible, no timing requirement
set_false_path -to [get_ports {ledr_o[*]}]

# 7-Segment displays — human-visible, no timing requirement
set_false_path -to [get_ports {hex0_o[*] hex1_o[*] hex2_o[*]}]
set_false_path -to [get_ports {hex3_o[*] hex4_o[*] hex5_o[*]}]

# UART TX — async serial, relaxed
set_output_delay -clock clk_50 -max 10.0 [get_ports {uart_tx_o}]
set_output_delay -clock clk_50 -min  0.0 [get_ports {uart_tx_o}]
