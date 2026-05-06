# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Authors:
# - Tobias Senti      <tsenti@ethz.ch>
# - Jannis Schönleber <janniss@iis.ee.ethz.ch>
# - Philippe Sauter   <phsauter@iis.ee.ethz.ch>

# The main OpenRoad chip flow
set proj_name $::env(PROJ_NAME)
set netlist $::env(NETLIST)
set top_design $::env(TOP_DESIGN)
set report_dir $::env(REPORTS)
set save_dir $::env(SAVE)
set time [elapsed_run_time]
set step_by_step_debug 0

# helper scripts
source scripts/reports.tcl
source scripts/checkpoint.tcl

# initialize technology data
source scripts/init_tech.tcl

set log_id 0


###############################################################################
# Initialization                                                              #
###############################################################################
set log_id_str [format "%02d" $log_id]
utl::report "###############################################################################"
utl::report "# Step ${log_id_str}: Initialization"
utl::report "###############################################################################"

# read and check design
utl::report "Read netlist"
read_verilog $netlist
link_design $top_design

utl::report "Read constraints"
read_sdc src/constraints.sdc

utl::report "Check constraints"
check_setup -verbose                                      > ${report_dir}/${log_id_str}_${proj_name}_checks.rpt
report_checks -unconstrained -format end -no_line_splits >> ${report_dir}/${log_id_str}_${proj_name}_checks.rpt
report_checks -format end -no_line_splits                >> ${report_dir}/${log_id_str}_${proj_name}_checks.rpt
report_checks -format end -no_line_splits                >> ${report_dir}/${log_id_str}_${proj_name}_checks.rpt

# Size of the chip
set chipW            1760.0
set chipH            1760.0

# thickness of annular ring for pads (length of a pad)
set padRing           180.0
set coreMargin [expr $padRing + 35]; # space for power ring

utl::report "Initialize Chip"
initialize_floorplan -die_area "0 0 $chipW $chipH" \
                     -core_area "$coreMargin $coreMargin [expr $chipW-$coreMargin] [expr $chipH-$coreMargin]" \
                     -site "CoreSite"


utl::report "Connect global nets (power)"
source scripts/power_connect.tcl

utl::report "Create Floorplan"
source scripts/floorplan.tcl

utl::report "Create Power Grid"
source scripts/power_grid.tcl
# save_checkpoint 00_${proj_name}.power_grid
# report_image "00_${proj_name}.power" true


###############################################################################
# Initial Repair Netlist                                                      #
###############################################################################
incr log_id
set log_id_str [format "%02d" $log_id]
utl::report "###############################################################################"
utl::report "# Step ${log_id_str}: Initial Repair Netlist"
utl::report "###############################################################################"

# set_default_view
# Set layers used for estimate_parasitics
set_wire_rc -clock -layer Metal4
set_wire_rc -signal -layer Metal4
# don't touch any clock-tree related nets as
# repair_timing can insert a 'split0000' buffer which then prevents CTS from running
set clock_nets [get_nets -of_objects [get_pins -of_objects "*_reg" -filter "name == CLK"]]
set_dont_touch $clock_nets
set_dont_use $dont_use_cells

utl::report "Repair tie fanout"
repair_tie_fanout sg13g2_tielo/L_LO
repair_tie_fanout sg13g2_tiehi/L_HI

utl::report "Remove buffers"
remove_buffers

utl::report "Repair design"
repair_design -verbose

save_checkpoint ${log_id_str}_${proj_name}.pre_place


###############################################################################
# GLOBAL PLACEMENT                                                            #
###############################################################################
incr log_id
set log_id_str [format "%02d" $log_id]
utl::report "###############################################################################"
utl::report "# Step ${log_id_str}: GLOBAL PLACEMENT"
utl::report "###############################################################################"

set_thread_count 8

set GPL_ARGS {  -density 0.60 }

set GPL2_ARGS { -density 0.60
                -routability_driven
                -routability_check_overflow 0.30
                -timing_driven }
# density:            In every part of the chip, about N% of the area is occupied by standard cells
# routability_driven: Reduce density target when there are a lot of wires in an area
# check_overflow:     Higher means routability starts being considered earlier in placement
#                     too early -> very dense regions, too late -> little to no effect
# inflation_ratio:    By how much the virtual area of offending cells is increased
#                     this increases the calculated density they cause, reducing physical density
# timing_driven:      Prioritize near-critical timing paths (reduce their length)
# max_phi_coef:       think step size

# rough placement to get parasitics from steiner-tree estimate so we can run repair_timing
utl::report "Global Placement (1)"
global_placement {*}$GPL_ARGS



    # ******************************************************************************************
    #                       Power report for i_croc
    # ******************************************************************************************
    # report_power -corner tt -instances [get_cells -hierarchical *i_croc*] > $pwr_filename
    # report_power -corner tt -instances i_croc > $pwr_filename
    # report_power -corner tt -instances [get_cells -hierarchical i_croc*] > $pwr_filename
    #
    # P_total_ACT = i_croc_soc _Total
    # P_total_CG = i_croc_soc.Total - i_croc_soc.i_croc.i_core_Internal - i_croc_soc.i_croc.i_core_Switching
    # P_total_PG = i_croc_soc.Total - i_croc_soc.i_croc.i_core_Tota + N_FF_in_core * P_sta_retFF_VDDAON
    # ******************************************************************************************

    puts "Reading VCD activity..."

    read_vcd ../verilator/croc.vcd -scope tb_croc_soc/i_croc_soc

    global report_dir
    set when "gpl1"
    set filename $report_dir/$when.rpt

    utl::report "###############################################################################"
    utl::report "# Step 03: CALCULATE POWER REPORTS"
    utl::report "###############################################################################"


    # Definir el nombre del reporte (usando la variable report_dir de tu script)
    if { ![info exists report_dir] } {set report_dir "reports"}

    set pwr_croc_filename "$report_dir/i_croc_power.rpt"
    set pwr_core_wrap_filename "$report_dir/i_core_wrap_power.rpt"

    set csv_croc "$report_dir/i_croc_power.csv"
    set csv_core_wrap "$report_dir/i_core_wrap_power.csv"

    # Generar el reporte de potencia para i_croc
    report_puts "\n=========================================================================="
    report_puts "Power Report for i_croc"
    report_puts "--------------------------------------------------------------------------"

    # Redirigir la salida al archivo de reportes
    report_power -corner ff -instances [get_cells -hierarchical i_croc_soc/*] > $pwr_croc_filename
    puts "Reporte de potencia generado en: $pwr_croc_filename"


    report_power -corner ff -instances [get_cells -hierarchical i_croc_soc/i_croc/i_core_wrap/*] > $pwr_core_wrap_filename
    puts "Reporte de potencia generado en: $pwr_core_wrap_filename"

    # ---------------------------------------------------------
    # Función para convertir RPT → CSV
    # ---------------------------------------------------------

        proc rpt_to_csv {rpt_file csv_file block_name} {

        set f [open $rpt_file r]
        set data [read $f]
        close $f

        set f [open $csv_file w]
        puts $f "Block,Internal_W,Switching_W,Leakage_W,Total_W"

        foreach line [split $data "\n"] {

            if {[regexp {^\s*([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+(.*)} \
                $line -> internal switching leakage total cell]} {

                puts $f "$cell,$internal,$switching,$leakage,$total"
            }
        }

        close $f
        }

        # ---------------------------------------------------------
        # Generar CSV desde los RPT
        # ---------------------------------------------------------

        rpt_to_csv $pwr_croc_filename $csv_croc "i_croc_soc"
        puts "CSV generado en: $csv_croc"

        rpt_to_csv $pwr_core_wrap_filename $csv_core_wrap "i_core_wrap"
        puts "CSV generado en: $csv_core_wrap"

        # ---------------------------------------------------------------------------------------
        # Generar resumen de potencia para el SoC y el core, y calcular P_total_ACT, P_total_CG
        # P_total_ACT = i_croc_soc_Total
        # P_total_CG  = i_croc_soc.Total - i_croc_soc.i_croc.i_core_Internal - i_croc_soc.i_croc.i_core_Switching
        # P_total_PG  = i_croc_soc.Total - i_croc_soc.i_croc.i_core_Total + N_FF_in_core * P_sta_retFF_VDDAON
        # --------------------------------------------------------------------------------------

        proc extract_power {rpt_file} {

        set internal 0
        set switching 0
        set leakage 0
        set total 0

        set f [open $rpt_file r]
        set data [read $f]
        close $f

        foreach line [split $data "\n"] {

            if {[regexp {^\s*([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)} \
                $line -> internal switching leakage total]} {

                break
            }
        }

        return [list $internal $switching $leakage $total]
        }

        # -----------------------------
        # Potencia total del SoC
        # -----------------------------

        set soc_power [extract_power $pwr_croc_filename]

        set soc_internal  [lindex $soc_power 0]
        set soc_switching [lindex $soc_power 1]
        set soc_leakage   [lindex $soc_power 2]
        set soc_total     [lindex $soc_power 3]

        # -----------------------------
        # Potencia del core
        # -----------------------------

        set core_power [extract_power $pwr_core_wrap_filename]

        set core_internal  [lindex $core_power 0]
        set core_switching [lindex $core_power 1]
        set core_leakage   [lindex $core_power 2]
        set core_total     [lindex $core_power 3]

        # -----------------------------
        # Calcular ACT y CG
        # -----------------------------

        set P_total_ACT $soc_total
        set P_total_CG [expr $soc_total - $core_internal - $core_switching]

        # -----------------------------
        # Calcular Power Gating (PG)
        # -----------------------------

        # contar flip-flops del core (sg13g2_dfrbp_* sg13g2_sdfbbp_*)
        set ff_cells [get_cells -hierarchical i_croc_soc/i_croc/i_core_wrap/* -filter "ref_name =~ *dfrbp* || ref_name =~ *sdfbbp*"]
        set N_FF_in_core [llength $ff_cells]

        # sg13g2_stdcell_typ_1p20V_25C.lib → P_sta_retFF_VDDAON = 5.38e-10 W (valor típico, ajustar según la liberty)
        # set P_sta_retFF_VDDAON 5.38e-10
        set P_sta_retFF_VDDAON 746.967e-12

        set P_total_PG [expr $soc_total - $core_total + $N_FF_in_core * $P_sta_retFF_VDDAON]

        # -----------------------------
        # Mostrar resultados
        # -----------------------------

        puts ""
        puts "================ Power Summary ================"

        puts ""
        puts "P_total_ACT"
        puts "----------------------------------------------"
        puts "P_total_ACT = i_croc_soc_Total"
        puts "            = $soc_total"

        puts ""
        puts "P_total_CG"
        puts "----------------------------------------------"
        puts "P_total_CG = i_croc_soc.Total - i_core.Internal - i_core.Switching"
        puts "           = $soc_total - $core_internal - $core_switching"
        puts "           = $P_total_CG"

        puts ""
        puts "P_total_PG"
        puts "----------------------------------------------"
        puts "P_total_PG = i_croc_soc.Total - i_core.Total + N_FF * P_retFF"
        puts "           = $soc_total - $core_total + ($N_FF_in_core * $P_sta_retFF_VDDAON)"
        puts "           = $P_total_PG"

        puts ""
        puts "Parameters"
        puts "----------------------------------------------"
        puts "N_FF_in_core        = $N_FF_in_core"
        puts "P_sta_retFF_VDDAON  = $P_sta_retFF_VDDAON"

        puts "==============================================="

        # -----------------------------
        # Guardar CSV
        # -----------------------------

        set summary_csv "$report_dir/power_summary.csv"

        set f [open $summary_csv w]
        puts $f "Metric,Power_W"
        puts $f "P_total_ACT,$P_total_ACT"
        puts $f "P_total_CG,$P_total_CG"
        puts $f "P_total_PG,$P_total_PG"
        close $f

        puts "Resumen de potencia guardado en: $summary_csv"


        # -----------------------------
        # Power breakdown por bloque (internal, switching, leakage)
        # -----------------------------

        set blocks {
            gen_sram_bank*
            i_addr_decode_periphs
            i_core_wrap
            i_dm_top
            i_dmi_jtag
            i_gpio
            i_main_xbar
            i_obi_demux
            i_power
            i_soc_ctrl
            i_timer
            i_uart
        }

        set breakdown_csv "$report_dir/power_breakdown.csv"

        set f [open $breakdown_csv w]
        puts $f "Block,Internal_W,Switching_W,Leakage_W,Total_W"

        foreach block $blocks {

            set path "i_croc_soc/i_croc/$block"

            set internal 0
            set switching 0
            set leakage 0
            set total 0

            # archivo temporal
            set tmp_file "$report_dir/tmp_power.rpt"

            report_power -corner ff \
                -instances [get_cells -hierarchical ${path}/*] \
                > $tmp_file

            # leer archivo
            set fp [open $tmp_file r]
            set data [read $fp]
            close $fp

            foreach line [split $data "\n"] {

                if {[regexp {^\s*([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)} \
                    $line -> i s l t]} {

                    set internal  [expr $internal + $i]
                    set switching [expr $switching + $s]
                    set leakage   [expr $leakage + $l]
                    set total     [expr $total + $t]
                }
            }

            puts $f "$block,$internal,$switching,$leakage,$total"
        }

        close $f

        puts "Power breakdown guardado en $breakdown_csv"


exit