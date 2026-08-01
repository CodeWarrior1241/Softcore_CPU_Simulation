# ================================================================================
# AD9361 Datapath Simulation (Microchip mpf300) - Questa Prime Compilation Script
# ================================================================================
# Microchip counterpart of ../neorv32_sw_ad9361_datapath_sim/sim/compile.do.
# Fully self-contained: compiles every source from the repository (no Vivado or
# Libero project output products are needed) for Questa Prime 2025.1 — NOT the
# QuestaSim bundled with Libero.
#
#   polarfire   PolarFire primitive models (INBUF/OUTBUF_DIFF/CLKINT/...)
#               compiled from the Libero installation source
#   neorv32     NEORV32 core (rtl/file_list_soc.f) with the PR #1603
#               pipelined-multiplier change applied in deps/neorv32, plus the
#               firmware IMEM image built by run_sim.sh
#   work        everything else: ADI axi_ad9361 (PolarFire port), PULP
#               axi/common_cells, Bedrock-RTL (CDC FIFO ctrl + bit sync,
#               compiled with BR_ASSERT_ON so the integration assertions --
#               including the FIFO reset-overlap checker -- are live),
#               SmartHLS adapters, mpf300 project HDL, sim-local top/TB
#
# Environment (optional):
#   LIBERO_INSTALL_DIR   Libero_SoC install dir (for the PolarFire primitive
#                        source only; default below)
# ================================================================================

quit -sim

set sim_dir [pwd]

# repo root: setups/<this>/../../.. = deps/neorv32 -> ../.. = repo
set neorv32_home [file normalize "$sim_dir/../.."]
set repo_root    [file normalize "$sim_dir/../../../.."]

set lib_dir   "$repo_root/deps/hdl/library"
set ip_dir    "$lib_dir/axi_ad9361"
set mpf300    "$repo_root/deps/hdl/projects/fmcomms2/mpf300"
set br_dir    "$repo_root/deps/bedrock-rtl"
set cc_dir    "$repo_root/deps/common_cells"
set axi_dir   "$repo_root/deps/axi"
set hls_ad9361 "$repo_root/src/axi_ad9361_adapter_microchip/hls_output/rtl"
set hls_stream "$repo_root/src/axi_lite_to_streaming_adapter_microchip/hls_output/rtl"

if {[info exists ::env(LIBERO_INSTALL_DIR)]} {
    set libero_dir $::env(LIBERO_INSTALL_DIR)
} else {
    set libero_dir "/media/fpgadev/Dev_Tools/Microchip/Libero_SoC"
}
set pf_prims "$libero_dir/Designer/lib/vlog/polarfire.v"
if {![file exists $pf_prims]} {
    error "PolarFire primitive models not found: $pf_prims (set LIBERO_INSTALL_DIR)"
}

puts "=========================================="
puts "  mpf300 full-system compile (Questa)"
puts "=========================================="
puts "Sim dir:      $sim_dir"
puts "Repo root:    $repo_root"
puts "NEORV32 home: $neorv32_home"

# ================================================================================
# Libraries
# ================================================================================

foreach l {work neorv32 polarfire} {
    if {[file exists $l]} { vdel -all -lib $l }
    vlib $l
    vmap $l $l
}

# ================================================================================
# PolarFire primitive models (-sv: the RAM ECC models use SV queues)
# ================================================================================

puts "Compiling PolarFire primitive library..."
vlog -sv -work polarfire $pf_prims

# ================================================================================
# NEORV32 core -> library neorv32 (VHDL-2008, order from file_list_soc.f).
# The rtl/core IMEM image entry is replaced with the sim-local image built
# from sw/ad9361_loopback (SMARTHLS_BRIDGE_MAP=1, rv32im) by run_sim.sh.
# ================================================================================

puts "Compiling NEORV32 (library neorv32)..."

set local_image "$sim_dir/neorv32_imem_image.vhd"
if {![file exists $local_image]} {
    error "Firmware IMEM image not found: $local_image\n  Run run_sim.sh (builds it), or:\n  cd $neorv32_home/sw/ad9361_loopback && make SMARTHLS_BRIDGE_MAP=1 MARCH=rv32im_zicsr_zifencei clean_all image && cp neorv32_imem_image.vhd $sim_dir/"
}

# file_list_soc.f was renamed to file_list_core.f upstream (PR #1611,
# post-v1.13.3); accept either name so the sim survives the bump
set fl_path "$neorv32_home/rtl/file_list_soc.f"
if {![file exists $fl_path]} {
    set fl_path "$neorv32_home/rtl/file_list_core.f"
}
set fl [open $fl_path r]
while {[gets $fl line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} { continue }
    set f [string map [list {$NEORV32_HOME} $neorv32_home] $line]
    if {[string match "*neorv32_imem_image.vhd" $f]} {
        set f $local_image
    }
    vcom -2008 -work neorv32 -quiet $f
}
close $fl

# integration shell + XBUS-to-AXI4 bridge + this sim's NEORV32 wrapper
# (CPU_FAST_MUL_PIPELINE => true), library work
vcom -2008 -work work -quiet $neorv32_home/rtl/system_integration/xbus2axi4_bridge.vhd
vcom -2008 -work work -quiet $neorv32_home/rtl/system_integration/neorv32_vivado_ip.vhd
vcom -2008 -work work -quiet $sim_dir/neorv32_mpf300_top.vhd

# ================================================================================
# Bedrock-RTL components (SystemVerilog, library work). Dependency order
# (packages/leaves first) -- same list as build_all.tcl and the Verilator
# Makefile. BR_ASSERT_ON arms the integration assertions (reset-overlap
# checker, handshake stability, etc.); synthesis and Verilator never
# define it. See doc/MPF300-Splash-Kit/bedrock_migration_design.md.
# ================================================================================

puts "Compiling Bedrock-RTL components..."
set BR_OPTS [list -sv -quiet +incdir+$br_dir/macros +define+BR_ASSERT_ON -work work]
foreach f {
    pkg/br_math_pkg.sv
    gate/rtl/br_gate_mock.sv
    misc/rtl/br_misc_unused.sv
    misc/rtl/br_misc_tieoff_zero.sv
    misc/rtl/br_misc_tieoff_one.sv
    cdc/rtl/br_cdc_pkg.sv
    cdc/rtl/br_cdc_bit_toggle.sv
    counter/rtl/br_counter_incr.sv
    flow/rtl/internal/br_flow_checks_valid_data_intg.sv
    fifo/rtl/internal/br_fifo_push_ctrl_core.sv
    enc/rtl/br_enc_bin2gray.sv
    delay/rtl/br_delay_nr.sv
    cdc/rtl/internal/br_cdc_fifo_reset_overlap_checks.sv
    enc/rtl/br_enc_gray2bin.sv
    cdc/rtl/internal/br_cdc_fifo_push_flag_mgr.sv
    cdc/rtl/internal/br_cdc_fifo_push_ctrl.sv
    cdc/rtl/internal/br_cdc_fifo_gray_count_sync.sv
    cdc/rtl/br_cdc_fifo_ctrl_push_1r1w.sv
    cdc/rtl/internal/br_cdc_fifo_pop_flag_mgr.sv
    delay/rtl/br_delay_valid.sv
    delay/rtl/br_delay_shift_reg.sv
    counter/rtl/br_counter.sv
    flow/rtl/internal/br_flow_checks_valid_data_impl.sv
    flow/rtl/br_flow_reg_fwd.sv
    mux/rtl/br_mux_onehot.sv
    fifo/rtl/internal/br_fifo_staging_buffer.sv
    fifo/rtl/internal/br_fifo_pop_ctrl_core.sv
    cdc/rtl/internal/br_cdc_fifo_pop_ctrl.sv
    cdc/rtl/br_cdc_fifo_ctrl_pop_1r1w.sv
    cdc/rtl/br_cdc_fifo_ctrl_1r1w.sv
    cdc/rtl/br_cdc_rst_sync.sv
} {
    vlog {*}$BR_OPTS $br_dir/$f
}

# ================================================================================
# PULP common_cells + axi (SystemVerilog, packages first)
# ================================================================================

puts "Compiling PULP common_cells + axi..."
set PULP_OPTS [list -sv -quiet +incdir+$axi_dir/include +incdir+$cc_dir/include -work work]
foreach f {
    cf_math_pkg.sv addr_decode_dync.sv addr_decode.sv
    spill_register_flushable.sv spill_register.sv fifo_v3.sv lzc.sv
    rr_arb_tree.sv counter.sv delta_counter.sv stream_register.sv
} {
    vlog {*}$PULP_OPTS $cc_dir/src/$f
}
foreach f {
    axi_pkg.sv axi_intf.sv axi_lite_demux.sv axi_lite_mux.sv
    axi_lite_to_axi.sv axi_err_slv.sv axi_lite_xbar.sv
} {
    vlog {*}$PULP_OPTS $axi_dir/src/$f
}

# ================================================================================
# ADI axi_ad9361 (vendor-neutral core + PolarFire device interface)
# ================================================================================

puts "Compiling ADI axi_ad9361 (PolarFire port)..."
set ADI_OPTS [list -sv -quiet +incdir+$lib_dir/common +incdir+$ip_dir -work work]
foreach f {
    ad_addsub.v ad_datafmt.v ad_dds.v ad_dds_1.v ad_dds_2.v
    ad_dds_cordic_pipe.v ad_dds_sine.v ad_dds_sine_cordic.v ad_iqcor.v
    ad_pnmon.v ad_pps_receiver.v ad_rst.v ad_tdd_control.v
    up_adc_channel.v up_adc_common.v up_axi.v up_clock_mon.v
    up_dac_channel.v up_dac_common.v up_delay_cntrl.v up_tdd_cntrl.v
    up_xfer_cntrl.v up_xfer_status.v
} {
    vlog {*}$ADI_OPTS $lib_dir/common/$f
}
foreach f {
    common/ad_data_clk.v common/ad_data_in.v common/ad_data_out.v
    common/ad_dcfilter.v common/ad_mul.v axi_ad9361_lvds_if.v
} {
    vlog {*}$ADI_OPTS $ip_dir/polarfire/$f
}
foreach f {
    axi_ad9361.v axi_ad9361_rx.v axi_ad9361_rx_channel.v
    axi_ad9361_rx_pnmon.v axi_ad9361_tx.v axi_ad9361_tx_channel.v
    axi_ad9361_tdd.v axi_ad9361_tdd_if.v
} {
    vlog {*}$ADI_OPTS $ip_dir/$f
}

# ================================================================================
# SmartHLS adapters (generated RTL; RAM init files staged into the sim dir)
# ================================================================================

puts "Compiling SmartHLS adapters..."
foreach d [list $hls_ad9361 $hls_stream] {
    foreach f [glob -nocomplain $d/mem_init/*.mem] {
        file copy -force $f $sim_dir/
    }
}
vlog -quiet -work work "+define+MEM_INIT_DIR=\"./\"" \
    $hls_ad9361/axi_ad9361_adapter_axi_ad9361_adapter.v \
    $hls_stream/axi_lite_to_streaming_adapter_axi_lite_to_streaming_adapter.v

# ================================================================================
# mpf300 project HDL (real synthesis sources)
# ================================================================================

puts "Compiling mpf300 project HDL..."
vlog {*}$PULP_OPTS $mpf300/hdl/axi_1to3_decoder.sv
foreach f {axi_bram_32k.v mpf300_reset_gen.sv axis_async_fifo.v dac_hold.v
           sys_ctrl.v lclk_reset_sync.v refclk_ibuf.v} {
    vlog -sv -quiet -work work $mpf300/hdl/$f
}

# ================================================================================
# Sim-local top + testbench
# ================================================================================

puts "Compiling sim top and testbench..."
vlog -quiet -work work $sim_dir/pf_ccc_sim.v
vlog -quiet -work work $sim_dir/mpf300_sim_top.v
vlog -sv -quiet -work work $sim_dir/mpf300_tb.v

puts "=========================================="
puts "Compilation Complete!"
puts "=========================================="
