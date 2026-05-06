// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>

module power_policy_unit
import power_types::*;
(
  input  logic clk_i,
  input  logic rst_ni,

  // petición software
  input  pd_state_e sw_target_state,

  // estado del sistema
  input  logic core_idle_i,
  input  logic wakeup_i,

  // handshake con power controller
  output logic      pwr_req_valid_o,
  output pd_state_e pwr_target_state_o,

  input  logic      pwr_ack_i,
  input  pd_state_e pwr_current_state_i
);

  // ============================================================
  // FSM STATES
  // ============================================================

  typedef enum logic [2:0] {
    RUN,
    WAIT_IDLE,
    REQ_DOWN,
    WAIT_OFF,
    WAIT_WAKE,
    REQ_UP,
    WAIT_ON
  } state_e;

  state_e state_q, state_d;

  // ============================================================
  // Sticky wakeup (edge capture while domain is OFF)
  // ============================================================

  logic wakeup_pending_q, wakeup_pending_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      wakeup_pending_q <= 1'b0;
    else
      wakeup_pending_q <= wakeup_pending_d;
  end

  always_comb begin
    wakeup_pending_d = wakeup_pending_q;

    if (wakeup_i)
      wakeup_pending_d = 1'b1;

    if (state_q == REQ_UP && pwr_ack_i)
      wakeup_pending_d = 1'b0;
  end

  // ============================================================
  // Power-down servido (avoid loops infinite)
  // ============================================================

  logic powerdown_served_q, powerdown_served_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      powerdown_served_q <= 1'b0;
    else
      powerdown_served_q <= powerdown_served_d;
  end

  always_comb begin
    powerdown_served_d = powerdown_served_q;

    if (state_q == REQ_DOWN && pwr_ack_i)
      powerdown_served_d = 1'b1;

    if (sw_target_state == PD_ON)
      powerdown_served_d = 1'b0;
  end

  // ============================================================
  // FSM REGISTER
  // ============================================================

  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni)
      state_q <= RUN;
    else
      state_q <= state_d;

  // ============================================================
  // FSM NEXT STATE LOGIC
  // ============================================================

  always_comb begin
    state_d = state_q;

    pwr_req_valid_o    = 1'b0;
    pwr_target_state_o = PD_ON;

    case (state_q)

      // --------------------------------------------------------
      // RUN
      // --------------------------------------------------------
      RUN:
        if (sw_target_state == PD_OFF && !powerdown_served_q)
          state_d = WAIT_IDLE;

      // --------------------------------------------------------
      // WAIT FOR CORE IDLE
      // --------------------------------------------------------
      WAIT_IDLE:
        if (core_idle_i)
          state_d = REQ_DOWN;

      // --------------------------------------------------------
      // POWER DOWN
      // --------------------------------------------------------
      REQ_DOWN: begin
        pwr_req_valid_o    = 1'b1;
        pwr_target_state_o = PD_OFF;
        if (pwr_ack_i)
          state_d = WAIT_OFF;
      end

      // --------------------------------------------------------
      // WAIT FOR DOMAIN TO BE OFF
      // --------------------------------------------------------
      WAIT_OFF:
        if (pwr_current_state_i == PD_OFF)
          state_d = WAIT_WAKE;

      // --------------------------------------------------------
      // WAIT FOR WAKEUP
      // --------------------------------------------------------
      WAIT_WAKE:
        if (wakeup_pending_q || sw_target_state == PD_ON)
          state_d = REQ_UP;

      // --------------------------------------------------------
      // REQUEST POWER UP
      // --------------------------------------------------------
      REQ_UP: begin
        pwr_req_valid_o    = 1'b1;
        pwr_target_state_o = PD_ON;
        if (pwr_ack_i)
          state_d = WAIT_ON;
      end

      // --------------------------------------------------------
      // WAIT FOR DOMAIN TO BE ON
      // --------------------------------------------------------
      WAIT_ON:
        if (pwr_current_state_i == PD_ON)
          state_d = RUN;

    endcase
  end

endmodule