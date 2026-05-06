// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>


module power #(
    parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
    parameter type obi_req_t = logic,
    parameter type obi_rsp_t = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    // OBI
    input  obi_req_t obi_req_i,
    output obi_rsp_t obi_rsp_o,

    // desde core
    input  logic core_busy_i,

    // towards croc_domain (real politics is there)
    output power_types::pd_state_e sw_target_state_o,
    output logic clk_gate_en_o
);

  import power_reg_pkg::*;
  import power_types::*;

  // ------------------------------------------------------------
  // Register bank (software interface)
  // ------------------------------------------------------------

  power_reg2hw_t reg2hw;

  power_reg_top #(
    .ObiCfg    (ObiCfg),
    .obi_req_t (obi_req_t),
    .obi_rsp_t (obi_rsp_t)
  ) i_power_reg (
    .clk_i,
    .rst_ni,
    .obi_req_i,
    .obi_rsp_o,
    .reg2hw
  );

  // ------------------------------------------------------------
  // Core idle
  // ------------------------------------------------------------

  logic core_idle;
  assign core_idle = !core_busy_i;

  // ------------------------------------------------------------
  // Software target power state
  // ------------------------------------------------------------

  always_comb begin
    if (reg2hw.pwr_mode == 2'b10)
      sw_target_state_o = PD_OFF;
    else
      sw_target_state_o = PD_ON;
  end

  // ------------------------------------------------------------
  // Clock gating request (simple policy)
  // ------------------------------------------------------------

  assign clk_gate_en_o =
      (reg2hw.pwr_mode == 2'b01) && core_idle;

endmodule