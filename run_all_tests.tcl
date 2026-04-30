
# ==============================================================
# TCL Automation Script - UART Verification
# Team 12 - BEVD205L Scripting Languages & Verification
# ==============================================================
# Usage (ModelSim / QuestaSim):
#   vsim -do run_all_tests.tcl
#
# Usage (Synopsys VCS):
#   Set SIMULATOR variable to "vcs" below.
#
# This script:
#   1. Compiles all SV source and testbench files
#   2. Runs directed testbenches (RX block, TX block)
#   3. Runs the top-level random testbench with multiple seeds
#   4. Collects all log files into a results/ directory
#   5. Prints a final summary
# ==============================================================

# ---- Configuration ----
set SIMULATOR   "modelsim"    ;# "modelsim" or "vcs"
set NUM_SEEDS   5             ;# Number of random seeds to run
set SEEDS       {42 123 7777 99999 31415}  ;# Explicit seed list (length = NUM_SEEDS)
set RESULTS_DIR "results"

# Source files (in compilation order)
set SRC_FILES {
    uart_rx.sv
    uart_tx.sv
    uart_top.sv
}

# Testbench files
set TB_DIRECTED_RX  tb_uart_rx_directed.sv
set TB_DIRECTED_TX  tb_uart_tx_directed.sv
set TB_TOP_RANDOM   tb_uart_top_random.sv

# Top-level module names
set TOP_RX   tb_uart_rx_directed
set TOP_TX   tb_uart_tx_directed
set TOP_RAND tb_uart_top_random

# ==============================================================
# Helper procs
# ==============================================================

proc make_dir {dir} {
    if {![file isdirectory $dir]} {
        file mkdir $dir
        puts "Created directory: $dir"
    }
}

proc log {msg} {
    puts "\n\[TCL\] $msg"
}

proc run_sim_modelsim {top_name plusargs log_file} {
    set cmd "vsim -c -do \"run -all; quit -f\" $plusargs $top_name"
    log "Running: $cmd"
    set rc [catch {eval exec $cmd} output]
    set fd [open $log_file w]
    puts $fd $output
    close $fd
    if {$rc != 0} {
        puts "\[WARN\] $top_name returned non-zero exit (check $log_file)"
    }
    return $output
}

proc run_sim_vcs {top_name plusargs log_file} {
    set cmd "./simv $plusargs +vcs+finish+200ms"
    log "Running: $cmd"
    set rc [catch {eval exec $cmd} output]
    set fd [open $log_file w]
    puts $fd $output
    close $fd
    return $output
}

proc compile_modelsim {src_files} {
    log "Compiling with vlog..."
    exec vlib work
    foreach f $src_files {
        log "  vlog $f"
        exec vlog -sv $f
    }
}

proc compile_vcs {src_files} {
    log "Compiling with VCS..."
    set file_list [join $src_files " "]
    exec vcs -sverilog -debug_all -timescale=1ns/1ps {*}$src_files
}

# ==============================================================
# Main Script Body
# ==============================================================

log "Simulator : $SIMULATOR"
log "Seeds     : $SEEDS"
log "Results   : $RESULTS_DIR"

make_dir $RESULTS_DIR


set all_files [concat $SRC_FILES $TB_DIRECTED_RX $TB_DIRECTED_TX $TB_TOP_RANDOM]

if {$SIMULATOR eq "modelsim"} {
    compile_modelsim $all_files
} else {
    compile_vcs $all_files
}
log "Compilation complete."

log "Directed RX Testbench"
set rx_log "$RESULTS_DIR/directed_rx.log"

if {$SIMULATOR eq "modelsim"} {
    run_sim_modelsim $TOP_RX "" $rx_log
} else {
    run_sim_vcs $TOP_RX "" $rx_log
}
log "RX directed results saved to $rx_log"

log "Directed TX Testbench"
set tx_log "$RESULTS_DIR/directed_tx.log"

if {$SIMULATOR eq "modelsim"} {
    run_sim_modelsim $TOP_TX "" $tx_log
} else {
    run_sim_vcs $TOP_TX "" $tx_log
}
log "TX directed results saved to $tx_log"

log "Random Top-Level Testbench (multiple seeds)"

set random_pass_total 0
set random_fail_total 0

foreach seed $SEEDS {
    log "  Running with seed=$seed ..."
    set rlog "$RESULTS_DIR/random_seed${seed}.log"
    set plusarg "+seed=$seed"

    if {$SIMULATOR eq "modelsim"} {
        run_sim_modelsim $TOP_RAND $plusarg $rlog
    } else {
        run_sim_vcs $TOP_RAND $plusarg $rlog
    }

    # Copy scoreboard log if it was generated in working directory
    set sb_src "scoreboard_seed${seed}.log"
    if {[file exists $sb_src]} {
        file copy -force $sb_src "$RESULTS_DIR/"
        log "  Scoreboard: $RESULTS_DIR/$sb_src"
    }

    # Quick grep for PASS/FAIL counts in the log
    set fd [open $rlog r]
    set content [read $fd]
    close $fd
    set pass_hits [regexp -all {\[PASS\]} $content]
    set fail_hits [regexp -all {\[FAIL\]} $content]
    incr random_pass_total $pass_hits
    incr random_fail_total $fail_hits
    log "  Seed=$seed => PASS=$pass_hits  FAIL=$fail_hits"
}

log "Summary"

# Count directed test results
proc count_results {logfile} {
    if {![file exists $logfile]} { return {0 0} }
    set fd [open $logfile r]
    set content [read $fd]
    close $fd
    set p [regexp -all {\[PASS\]} $content]
    set f [regexp -all {\[FAIL\]} $content]
    return [list $p $f]
}

lassign [count_results $rx_log] rx_pass rx_fail
lassign [count_results $tx_log] tx_pass tx_fail

set total_pass [expr {$rx_pass + $tx_pass + $random_pass_total}]
set total_fail [expr {$rx_fail + $tx_fail + $random_fail_total}]

set summary_file "$RESULTS_DIR/master_summary.log"
set fd [open $summary_file w]

set lines [list \
    "================================================" \
    " UART VERIFICATION SUMMARY - Team 12"             \
    "================================================" \
    " Directed RX   : PASS=$rx_pass  FAIL=$rx_fail"   \
    " Directed TX   : PASS=$tx_pass  FAIL=$tx_fail"   \
    " Random (all)  : PASS=$random_pass_total  FAIL=$random_fail_total" \
    "------------------------------------------------" \
    " TOTAL         : PASS=$total_pass  FAIL=$total_fail" \
    "================================================" \
]

foreach l $lines {
    puts $l
    puts $fd $l
}

if {$total_fail == 0} {
    set verdict "** ALL TESTS PASSED - Design Verified **"
} else {
    set verdict "** FAILURES FOUND - Run Perl parser for details **"
}
puts $verdict
puts $fd $verdict
close $fd

log "Run perl parse_scoreboard.pl to get detailed error analysis."
