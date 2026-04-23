# =================================================================
# 1. CONFIG & PATHS
# =================================================================
QUESTA_PATH = C:/questasim64_2024.1/win64
VLOG        = $(QUESTA_PATH)/vlog
VSIM        = $(QUESTA_PATH)/vsim

# Flags
VLOG_FLAGS  = -sv -timescale 1ns/1ps +access+rwc +incdir+..
VSIM_FLAGS  = -voptargs="+acc" -wlf vsim.wlf

# Directories
SRC_DIR     = ../../00_src
RTL_DIR     = ..
TB_DIR      = ../tb
TEST_DIR    = ../02_test

# =================================================================
# 2. DYNAMIC TEST CONFIGURATION (Phần quan trọng)
# =================================================================
# Mặc định chạy soc_tb nếu không nhập TEST=...
TEST ?= soc_isa_tb

# Xác định file source testbench: ../tb/<tên_test>.sv
TB_SRC = $(TB_DIR)/$(TEST).sv

# Tự động chọn file HEX dựa trên tên TEST
# Logic: Nếu là pipelined_tb thì dùng load_store.hex, còn lại dùng isa_4b.hex
HEX_FILE = isa_4b.hex
ifeq ($(TEST),pipelined_tb)
    HEX_FILE = load_store.hex
endif

ifeq ($(TEST),soc_tb)
    HEX_FILE = uart.hex
endif

ifeq ($(TEST),soc_uart_tb)
    HEX_FILE = uart.hex
endif

ifeq ($(TEST),soc_7seg_tb)
    HEX_FILE = uart_app.hex
endif

# =================================================================
# 3. SOURCE FILES (RTL Dùng chung)
# =================================================================
RTL_SOURCES = \
    $(RTL_DIR)/tlul_pkg.sv \
    $(RTL_DIR)/tlul_host_adapter.sv \
    $(RTL_DIR)/tlul_xbar_3s.sv \
    $(RTL_DIR)/tlul_adapter_mem.sv \
    $(RTL_DIR)/tlul_adapter_peri.sv \
    $(RTL_DIR)/uart_byte_tx.sv \
    $(RTL_DIR)/uart_byte_rx.sv \
    $(RTL_DIR)/tlul_uart_bridge.sv \
    $(SRC_DIR)/memory.sv \
    $(SRC_DIR)/SevenSegment.sv \
    $(SRC_DIR)/peripherals.sv \
    $(SRC_DIR)/pc.sv \
    $(SRC_DIR)/PCplus4.sv \
    $(SRC_DIR)/instr_mem.sv \
    $(SRC_DIR)/IF.sv \
    $(SRC_DIR)/IF_ID_reg.sv \
    $(SRC_DIR)/regfile.sv \
    $(SRC_DIR)/immgen.sv \
    $(SRC_DIR)/control_logic.sv \
    $(SRC_DIR)/ID.sv \
    $(SRC_DIR)/ID_EX_reg.sv \
    $(RTL_DIR)/ID_EX_reg_tl.sv \
    $(SRC_DIR)/fa.sv \
    $(SRC_DIR)/cla_4bit.sv \
    $(SRC_DIR)/cla_32bit.sv \
    $(SRC_DIR)/alu.sv \
    $(SRC_DIR)/brc.sv \
    $(SRC_DIR)/mux2.sv \
    $(SRC_DIR)/mux3.sv \
    $(SRC_DIR)/mux4.sv \
    $(SRC_DIR)/mux4_fw.sv \
    $(SRC_DIR)/EX.sv \
    $(SRC_DIR)/EX_MEM_reg.sv \
    $(RTL_DIR)/EX_MEM_reg_tl.sv \
    $(SRC_DIR)/hazard_detection.sv \
    $(RTL_DIR)/hazard_detection_tl.sv \
    $(SRC_DIR)/forwarding_unit.sv \
    $(SRC_DIR)/branch_predictor.sv \
    $(RTL_DIR)/MEM_tl.sv \
    $(SRC_DIR)/MEM.sv \
    $(SRC_DIR)/MEM_WB_reg.sv \
    $(RTL_DIR)/MEM_WB_reg_tl.sv \
    $(SRC_DIR)/mux3_wb.sv \
    $(SRC_DIR)/WB.sv \
    $(RTL_DIR)/pipelined_tl.sv \
    $(RTL_DIR)/soc_top.sv

# =================================================================
# 4. TARGETS
# =================================================================
.PHONY: all clean gen_flist sim gui wave help

# Mặc định chạy sim với TEST đã đặt
all: sim

# Tạo common filelist
gen_flist:
	@echo.
	@echo ======== GENERATING COMMON FILELIST ========
	@if exist common.f del /q common.f
	@for %%f in ($(RTL_SOURCES)) do @echo %%f >> common.f

# TARGET SIM CHÍNH (Xử lý mọi logic)
sim: clean gen_flist
	@echo.
	@echo ======== PREPARING TEST: $(TEST) with $(HEX_FILE) ========
	@if not exist "$(TEST_DIR)" mkdir "$(TEST_DIR)"
	@copy /Y "..\..\02_test\$(HEX_FILE)" "$(TEST_DIR)" >nul 2>&1
	@echo.
	@echo ======== COMPILING ========
	@$(VLOG) $(VLOG_FLAGS) -f common.f $(TB_DIR)/tlul_test_lib.sv $(TB_SRC)
	@echo.
	@echo ======== RUNNING SIMULATION: $(TEST) ========
	@$(VSIM) -c $(TEST) $(VSIM_FLAGS) -l sim_$(TEST).log -do "log -r /*; run -all; quit -f"

# TARGET GUI (Chạy sim có giao diện)
gui: clean gen_flist
	@echo.
	@echo ======== OPENING GUI FOR: $(TEST) ========
	@if not exist "$(TEST_DIR)" mkdir "$(TEST_DIR)"
	@copy /Y "..\..\02_test\$(HEX_FILE)" "$(TEST_DIR)" >nul 2>&1
	@$(VLOG) $(VLOG_FLAGS) -f common.f $(TB_DIR)/tlul_test_lib.sv $(TB_SRC)
	@$(VSIM) -gui $(TEST) $(VSIM_FLAGS) -do "log -r /*; do wave.do"

# Open waveform viewer (sau khi đã chạy sim)
wave:
	@echo.
	@echo ======== OPENING WAVEFORM VIEWER ========
	@if exist vsim.wlf ($(VSIM) -view vsim.wlf) else @echo ERROR: No waveform file found. Run 'make sim TEST=...' first.

# Clean
clean:
	@echo.
	@echo ======== CLEANING ========
	-@del /f /q *.wlf *.log *.vcd common.f transcript 2>nul
	-@if exist work rmdir /s /q work
	-@if exist $(TEST_DIR) rmdir /s /q $(TEST_DIR)