# ================================================================================
# AD9361 Datapath Simulation (Efinix ti375) - Questa Prime Compilation Script
# ================================================================================
# Efinix counterpart of ../neorv32_sw_ad9361_dapath_sim_microchip/compile.do.
# Compiles every source from the repository. The periphery uses Efinix's
# OFFICIAL simulation models wherever possible: the project's
# gen_interface.py exports outflow/ti375c529_pt_interface.v — a pad-level
# chip wrapper instantiating EFX_FPLL_V1 / EFX_LVDS_RX_V2 / EFX_LVDS_TX_V2 /
# EFX_GPIO_V3 from $EFINITY_HOME/pt/sim_models/verilog, configured exactly
# as ti375c529.peri.xml — around the sim-local system_top_shim (the REAL
# synthesis system_top plus ties for optional pins). Only the models'
# search path depends on the Efinity install (same pattern as the Microchip
# sim's Libero polarfire.v dependency).
#
# Environment (optional):
#   EFINITY_HOME   Efinity install dir (for pt/sim_models/verilog; the
#                  dev-box default is probed when unset)
#
#   neorv32     NEORV32 core (rtl/file_list_soc.f) with the pipelined fast
#               multiplier and the generate-scope RAM patch carried in
#               deps/neorv32, plus the firmware IMEM image built by run_sim.sh
#   work        everything else: ADI axi_ad9361 (Efinix port), PULP
#               axi/common_cells, Bedrock-RTL (compiled with BR_ASSERT_ON so
#               the integration assertions are live), SmartHLS adapters, the
#               REAL ti375 project HDL including system_top.v, the exported
#               periphery netlist + official EFX_* models, shim, and TB
# ================================================================================

quit -sim

set sim_dir [pwd]

# repo root: setups/<this>/../../.. = deps/neorv32 -> ../.. = repo
set neorv32_home [file normalize "$sim_dir/../.."]
set repo_root    [file normalize "$sim_dir/../../../.."]

set lib_dir   "$repo_root/deps/hdl/library"
set ip_dir    "$lib_dir/axi_ad9361"
set ti375     "$repo_root/deps/hdl/projects/fmcomms2/ti375"
set br_dir    "$repo_root/deps/bedrock-rtl"
set cc_dir    "$repo_root/deps/common_cells"
set axi_dir   "$repo_root/deps/axi"
set hls_ad9361 "$repo_root/src/axi_ad9361_adapter_microchip/hls_output/rtl"
set hls_stream "$repo_root/src/axi_lite_to_streaming_adapter_microchip/hls_output/rtl"

# Efinity install (for the official periphery models)
if {[info exists ::env(EFINITY_HOME)]} {
    set efinity_dir $::env(EFINITY_HOME)
} else {
    set efinity_dir "/media/fpgadev/Dev_Tools/Efinity/2026.1"
}
set efx_models "$efinity_dir/pt/sim_models/verilog"
if {![file exists "$efx_models/EFX_LVDS_RX_V2.v"]} {
    error "Efinix periphery models not found: $efx_models (set EFINITY_HOME to the Efinity install dir)"
}

# Periphery sim netlist: the sim-local copy staged by run_sim.sh from the
# ti375 project's gen_interface.py export, with the LVDS FASTCLK
# connections the official models require added by patch_peri_netlist.py
set peri_netlist "$sim_dir/ti375c529_pt_interface_sim.v"
if {![file exists $peri_netlist]} {
    error "Periphery sim netlist not found: $peri_netlist\n  Run run_sim.sh (stages it), or:\n  cd $ti375 && source $efinity_dir/bin/setup.sh && efx_py scripts/gen_interface.py\n  python3 patch_peri_netlist.py $ti375/outflow/ti375c529_pt_interface.v ti375c529_pt_interface_sim.v"
}

puts "=========================================="
puts "  ti375 full-system compile (Questa)"
puts "=========================================="
puts "Sim dir:      $sim_dir"
puts "Repo root:    $repo_root"
puts "NEORV32 home: $neorv32_home"

# ================================================================================
# Libraries
# ================================================================================

foreach l {work neorv32} {
    if {[file exists $l]} { vdel -all -lib $l }
    vlib $l
    vmap $l $l
}

# ================================================================================
# NEORV32 core -> library neorv32 (VHDL-2008, order from file_list_soc.f).
# The rtl/core IMEM image entry is replaced with the sim-local image built
# from sw/ad9361_loopback (rv32im) by run_sim.sh.
# ================================================================================

puts "Compiling NEORV32 (library neorv32)..."

set local_image "$sim_dir/neorv32_imem_image.vhd"
if {![file exists $local_image]} {
    error "Firmware IMEM image not found: $local_image\n  Run run_sim.sh (builds it), or:\n  cd $neorv32_home/sw/ad9361_loopback && make MARCH=rv32im_zicsr_zifencei clean_all image && cp neorv32_imem_image.vhd $sim_dir/"
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

# integration shell + XBUS-to-AXI4 bridge + the REAL ti375 project wrapper
# (CPU_FAST_MUL_REG => true), library work — same trio/libraries as the
# Efinity synthesis project
vcom -2008 -work work -quiet $neorv32_home/rtl/system_integration/xbus2axi4_bridge.vhd
vcom -2008 -work work -quiet $neorv32_home/rtl/system_integration/neorv32_vivado_ip.vhd
vcom -2008 -work work -quiet $ti375/hdl/neorv32_ti375_top.vhd

# ================================================================================
# Bedrock-RTL components (SystemVerilog, library work). Dependency order
# (packages/leaves first). BR_ASSERT_ON arms the integration assertions
# (reset-overlap checker, handshake stability, etc.).
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
# ADI axi_ad9361 (vendor-neutral core + Efinix device interface). The
# portable arithmetic helpers come from polarfire/common (shared, no vendor
# primitives); the polarfire ad_data_* I/O modules are NOT compiled — their
# role is played by efx_periphery_sim.v.
# ================================================================================

puts "Compiling ADI axi_ad9361 (Efinix port)..."
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
vlog {*}$ADI_OPTS $ip_dir/polarfire/common/ad_dcfilter.v
vlog {*}$ADI_OPTS $ip_dir/polarfire/common/ad_mul.v
vlog {*}$ADI_OPTS $ip_dir/efinix/axi_ad9361_lvds_if.v
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
# ti375 project HDL (real synthesis sources, including the real top level)
# ================================================================================

puts "Compiling ti375 project HDL..."
vlog {*}$PULP_OPTS $ti375/hdl/axi_1to3_decoder.sv
foreach f {axi_bram_32k.v efx_reset_gen.sv axis_async_fifo.v dac_hold.v
           sys_ctrl.v lclk_reset_sync.v system_top.v} {
    vlog -sv -quiet -work work $ti375/hdl/$f
}

# ================================================================================
# Official Efinix periphery netlist + models, core shim, sim top, testbench.
# -y resolves the EFX_* periphery cells referenced by the netlist from the
# Efinity install (compiled into work on demand, Verilog-XL style).
# ================================================================================

puts "Compiling Efinix periphery netlist (official EFX_* models) + sim top..."
vlog -quiet -work work -y $efx_models +libext+.v $peri_netlist
vlog -quiet -work work $sim_dir/system_top_shim.v
vlog -quiet -work work $sim_dir/ti375_sim_top.v
vlog -sv -quiet -work work $sim_dir/ti375_tb.v

puts "=========================================="
puts "Compilation Complete!"
puts "=========================================="
