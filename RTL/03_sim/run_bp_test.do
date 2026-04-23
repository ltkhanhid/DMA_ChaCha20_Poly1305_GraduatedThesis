# Branch Predictor Test Script for ModelSim/QuestaSim
# Usage: vsim -do run_bp_test.do

# Clean up
if {[file exists work]} {
    vdel -all
}

# Create work library
vlib work

# Compile source files
echo "Compiling branch predictor module..."
vlog -sv +incdir+../00_src ../00_src/branch_predictor.sv

echo "Compiling testbench..."
vlog -sv +incdir+../01_bench ../01_bench/tb_branch_predictor.sv

# Run simulation
echo "Running simulation..."
vsim -c -voptargs=+acc tb_branch_predictor

# Add waves (optional, for GUI mode)
# add wave -radix hex /tb_branch_predictor/*
# add wave -radix hex /tb_branch_predictor/dut/bpt
# add wave -radix hex /tb_branch_predictor/dut/btb

# Run
run -all

# Quit
quit -f
