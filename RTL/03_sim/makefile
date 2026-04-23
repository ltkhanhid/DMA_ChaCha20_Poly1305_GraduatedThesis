

QUESTA  = C:/questasim64_2024.1/win64
VLOG    = $(QUESTA)/vlog
VSIM    = $(QUESTA)/vsim
FLAGS   = -sv -timescale 1ns/100ps -quiet +access+rwc

# sim: batch (log all signals, save wlf, then quit)
# gui: open waveform viewer from saved wlf
SIM_DO  = sim_run.do

.PHONY: all clean help \
        sim_isa sim_dma sim_aead sim_aead_dma sim_demo sim_corner \
        sim_7seg sim_2m6s sim_pipe_tl \
        sim_chacha20 sim_poly1305 sim_dma_unit sim_dma_mod sim_dma_rr sim_uart_byte \
        sim_aead_algo sim_aead_corner sim_pipe \
        gui_isa gui_dma gui_aead gui_aead_dma gui_demo gui_corner \
        gui_7seg gui_2m6s gui_pipe_tl \
        gui_chacha20 gui_poly1305 gui_dma_unit gui_dma_mod gui_dma_rr gui_uart_byte \
        gui_aead_algo gui_aead_corner gui_pipe \
        wave_isa wave_dma wave_aead wave_aead_dma wave_demo wave_corner \
        wave_7seg wave_2m6s wave_pipe_tl \
        wave_chacha20 wave_poly1305 wave_dma_unit wave_dma_mod wave_dma_rr wave_uart_byte \
        wave_aead_algo wave_aead_corner wave_pipe \
        sim_soc_all sim_unit_all sim_all

all: help

# ════════════════════════════════════════════════════════════════════════
#  SOC-LEVEL TESTS  (DUT = soc_top_2m6s)
#  Compile flist_soc_base + individual testbench file
# ════════════════════════════════════════════════════════════════════════

sim_isa:
	@echo.
	@echo ======== [SOC] soc_isa_tb — ISA regression (38 instr) ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_isa_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_isa_tb.wlf soc_isa_tb

sim_dma:
	@echo.
	@echo ======== [SOC] soc_dma_tb — DMA memory-copy (100 words) ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_dma_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_dma_tb.wlf soc_dma_tb

sim_aead:
	@echo.
	@echo ======== [SOC] soc_aead_tb — AEAD RFC 8439 ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_aead_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_aead_tb.wlf soc_aead_tb

sim_aead_dma:
	@echo.
	@echo ======== [SOC] soc_aead_dma_tb — AEAD+DMA (2 SoC) ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_aead_dma_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_aead_dma_tb.wlf soc_aead_dma_tb

sim_demo:
	@echo.
	@echo ======== [SOC] soc_demo_tb — ChaCha20 UART demo ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_demo_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_demo_tb.wlf soc_demo_tb

sim_corner:
	@echo.
	@echo ======== [SOC] soc_corner_tb — Corner cases ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_corner_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_corner_tb.wlf soc_corner_tb

sim_7seg:
	@echo.
	@echo ======== [SOC] soc_7seg_tb — UART + 7-Segment ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_7seg_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_7seg_tb.wlf soc_7seg_tb

sim_2m6s:
	@echo.
	@echo ======== [SOC] soc_2m6s_tb — 2M6S bus test ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_2m6s_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf soc_2m6s_tb.wlf soc_2m6s_tb

sim_pipe_tl:
	@echo.
	@echo ======== [SOC] pipelined_tb — Pipelined CPU (TL-UL) ========
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/pipelined_tb.sv
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf pipelined_tb.wlf pipelined_tb

# ════════════════════════════════════════════════════════════════════════
#  UNIT-LEVEL TESTS  (individual peripherals)
# ════════════════════════════════════════════════════════════════════════

sim_chacha20:
	@echo.
	@echo ======== [UNIT] chacha20_tb — RFC 8439 test vectors ========
	$(VLOG) $(FLAGS) -f flist_chacha
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf chacha20_tb.wlf chacha20_tb

sim_poly1305:
	@echo.
	@echo ======== [UNIT] poly1305_tb — 11 test vectors ========
	$(VLOG) $(FLAGS) -f flist_poly1305
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf poly1305_tb.wlf poly1305_tb

sim_dma_unit:
	@echo.
	@echo ======== [UNIT] dma_tb — TL-UL interface test ========
	$(VLOG) $(FLAGS) -f flist_dma_unit
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf dma_unit_tb.wlf dma_tb

sim_dma_mod:
	@echo.
	@echo ======== [UNIT] dma_tb — Modular (7 sub-tests) ========
	$(VLOG) $(FLAGS) -f flist_dma_mod
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf dma_mod_tb.wlf dma_tb

sim_dma_rr:
	@echo.
	@echo ======== [UNIT] dma_rr_tb — Round-Robin Arbitration (5 TCs) ========
	$(VLOG) $(FLAGS) -f flist_dma_rr
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf dma_rr_tb.wlf dma_rr_tb

sim_uart_byte:
	@echo.
	@echo ======== [UNIT] uart_byte_tb — TX/RX loopback ========
	$(VLOG) $(FLAGS) -f flist_uart_byte
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf uart_byte_tb.wlf uart_byte_tb

# ════════════════════════════════════════════════════════════════════════
#  ALGORITHM-LEVEL TESTS  (core-only, no TL-UL wrappers)
# ════════════════════════════════════════════════════════════════════════

sim_aead_algo:
	@echo.
	@echo ======== [ALGO] aead_chacha20_poly1305_tb — RFC 8439 ========
	$(VLOG) $(FLAGS) -f flist_aead_algo
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf aead_algo_tb.wlf aead_chacha20_poly1305_tb

sim_aead_corner:
	@echo.
	@echo ======== [ALGO] aead_corner_tb — 12 corner cases ========
	$(VLOG) $(FLAGS) -f flist_aead_corner
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf aead_corner_tb.wlf aead_corner_tb

# ════════════════════════════════════════════════════════════════════════
#  LEGACY PIPELINE TEST  (non-TL-UL, original 5-stage)
# ════════════════════════════════════════════════════════════════════════

sim_pipe:
	@echo.
	@echo ======== [LEGACY] tbench — Original pipeline ========
	$(VLOG) $(FLAGS) -f flist_pipe
	$(VSIM) -c -voptargs=+acc -do $(SIM_DO) -wlf tbench.wlf tbench

# ════════════════════════════════════════════════════════════════════════
#  GUI MODE  (compile + open QuestaSim GUI directly, all signals visible)
#  Usage: make gui_<name>
# ════════════════════════════════════════════════════════════════════════

gui_isa:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_isa_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_isa_tb

gui_dma:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_dma_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_dma_tb

gui_aead:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_aead_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_aead_tb

gui_aead_dma:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_aead_dma_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_aead_dma_tb

gui_demo:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_demo_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_demo_tb

gui_corner:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_corner_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_corner_tb

gui_7seg:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_7seg_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_7seg_tb

gui_2m6s:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/soc_2m6s_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) soc_2m6s_tb

gui_pipe_tl:
	$(VLOG) $(FLAGS) -f flist_soc_base ../000_tlul/tb/pipelined_tb.sv
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) pipelined_tb

gui_chacha20:
	$(VLOG) $(FLAGS) -f flist_chacha
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) chacha20_tb

gui_poly1305:
	$(VLOG) $(FLAGS) -f flist_poly1305
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) poly1305_tb

gui_dma_unit:
	$(VLOG) $(FLAGS) -f flist_dma_unit
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) dma_tb

gui_dma_mod:
	$(VLOG) $(FLAGS) -f flist_dma_mod
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) dma_tb

gui_dma_rr:
	$(VLOG) $(FLAGS) -f flist_dma_rr
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) dma_rr_tb

gui_uart_byte:
	$(VLOG) $(FLAGS) -f flist_uart_byte
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) uart_byte_tb

gui_aead_algo:
	$(VLOG) $(FLAGS) -f flist_aead_algo
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) aead_chacha20_poly1305_tb

gui_aead_corner:
	$(VLOG) $(FLAGS) -f flist_aead_corner
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) aead_corner_tb

gui_pipe:
	$(VLOG) $(FLAGS) -f flist_pipe
	@cmd /c start "" "$(VSIM)" -gui -voptargs=+acc -do $(WAVE_DO) tbench

# ════════════════════════════════════════════════════════════════════════
#  WAVEFORM VIEWERS  (open QuestaSim GUI from saved .wlf)
#  Usage: make wave_<name>   (run after the corresponding sim_<name>)
# ════════════════════════════════════════════════════════════════════════

WAVE_DO = view_wave.do

wave_isa:
	@cmd /c start "" "$(VSIM)" -gui -view soc_isa_tb.wlf -do $(WAVE_DO)
wave_dma:
	@cmd /c start "" "$(VSIM)" -gui -view soc_dma_tb.wlf -do $(WAVE_DO)
wave_aead:
	@cmd /c start "" "$(VSIM)" -gui -view soc_aead_tb.wlf -do $(WAVE_DO)
wave_aead_dma:
	@cmd /c start "" "$(VSIM)" -gui -view soc_aead_dma_tb.wlf -do $(WAVE_DO)
wave_demo:
	@cmd /c start "" "$(VSIM)" -gui -view soc_demo_tb.wlf -do $(WAVE_DO)
wave_corner:
	@cmd /c start "" "$(VSIM)" -gui -view soc_corner_tb.wlf -do $(WAVE_DO)
wave_7seg:
	@cmd /c start "" "$(VSIM)" -gui -view soc_7seg_tb.wlf -do $(WAVE_DO)
wave_2m6s:
	@cmd /c start "" "$(VSIM)" -gui -view soc_2m6s_tb.wlf -do $(WAVE_DO)
wave_pipe_tl:
	@cmd /c start "" "$(VSIM)" -gui -view pipelined_tb.wlf -do $(WAVE_DO)
wave_chacha20:
	@cmd /c start "" "$(VSIM)" -gui -view chacha20_tb.wlf -do $(WAVE_DO)
wave_poly1305:
	@cmd /c start "" "$(VSIM)" -gui -view poly1305_tb.wlf -do $(WAVE_DO)
wave_dma_unit:
	@cmd /c start "" "$(VSIM)" -gui -view dma_unit_tb.wlf -do $(WAVE_DO)
wave_dma_mod:
	@cmd /c start "" "$(VSIM)" -gui -view dma_mod_tb.wlf -do $(WAVE_DO)
wave_dma_rr:
	@cmd /c start "" "$(VSIM)" -gui -view dma_rr_tb.wlf -do $(WAVE_DO)
wave_uart_byte:
	@cmd /c start "" "$(VSIM)" -gui -view uart_byte_tb.wlf -do $(WAVE_DO)
wave_aead_algo:
	@cmd /c start "" "$(VSIM)" -gui -view aead_algo_tb.wlf -do $(WAVE_DO)
wave_aead_corner:
	@cmd /c start "" "$(VSIM)" -gui -view aead_corner_tb.wlf -do $(WAVE_DO)
wave_pipe:
	@cmd /c start "" "$(VSIM)" -gui -view tbench.wlf -do $(WAVE_DO)

# ════════════════════════════════════════════════════════════════════════
#  BATCH TARGETS
# ════════════════════════════════════════════════════════════════════════

sim_soc_all:  sim_isa sim_dma sim_aead sim_aead_dma sim_demo sim_corner sim_7seg sim_2m6s sim_pipe_tl
sim_unit_all: sim_chacha20 sim_poly1305 sim_dma_unit sim_uart_byte sim_aead_algo sim_aead_corner
sim_all:      sim_soc_all sim_unit_all sim_pipe

# ════════════════════════════════════════════════════════════════════════
#  CLEAN
# ════════════════════════════════════════════════════════════════════════

clean:
	@echo.
	@echo ======== CLEAN ========
	-@del /f /q *.wlf *.log transcript 2>nul
	-@if exist work rmdir /s /q work
	@echo CLEAN COMPLETED

# ════════════════════════════════════════════════════════════════════════
#  HELP
# ════════════════════════════════════════════════════════════════════════

help:
	@echo.
	@echo ================================================================
	@echo   DATN RISC-V SoC (2M6S) — QuestaSim Simulation Makefile
	@echo ================================================================
	@echo.
	@echo  SOC-LEVEL (9 tests, DUT = soc_top_2m6s):
	@echo    make sim_isa          ISA regression (38 instructions)
	@echo    make sim_dma          DMA memory-copy (100 words)
	@echo    make sim_aead         AEAD ChaCha20-Poly1305 (RFC 8439)
	@echo    make sim_aead_dma     AEAD with DMA (2 SoC comparison)
	@echo    make sim_demo         ChaCha20 UART demo
	@echo    make sim_corner       Corner cases (ChaCha/DMA/IRQ)
	@echo    make sim_7seg         UART + 7-Segment display
	@echo    make sim_2m6s         2-Master 6-Slave bus test
	@echo    make sim_pipe_tl      Pipelined CPU (TileLink)
	@echo.
	@echo  UNIT-LEVEL (5 tests):
	@echo    make sim_chacha20     ChaCha20 peripheral (RFC 8439 TV)
	@echo    make sim_poly1305     Poly1305 MAC core (11 TVs)
	@echo    make sim_dma_unit     DMA controller (TL-UL interface)
	@echo    make sim_dma_mod      DMA modular (7 sub-tests)
	@echo    make sim_dma_rr       DMA round-robin arbitration (5 TCs)
	@echo    make sim_uart_byte    UART TX/RX loopback
	@echo.
	@echo  ALGORITHM-LEVEL (2 tests):
	@echo    make sim_aead_algo    AEAD encrypt/decrypt round-trip
	@echo    make sim_aead_corner  AEAD corner cases (12 tests)
	@echo.
	@echo  LEGACY:
	@echo    make sim_pipe         Original pipeline (non-TL-UL)
	@echo.
	@echo  BATCH:
	@echo    make sim_soc_all      Run all 9 SoC tests
	@echo    make sim_unit_all     Run all unit + algo tests
	@echo    make sim_all          Run ALL 17 tests
	@echo.
	@echo  GUI (compile + open GUI directly, all signals):
	@echo    make gui_[name]       e.g. make gui_dma_unit
	@echo.
	@echo  WAVEFORM (open saved .wlf after batch sim):
	@echo    make wave_[name]      e.g. make wave_isa
	@echo.
	@echo  UTILITY:
	@echo    make clean            Remove work/ and all .wlf files
	@echo    make help             Show this help
	@echo.