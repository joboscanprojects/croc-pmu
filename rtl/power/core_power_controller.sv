// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>

module core_power_controller
  import power_types::*;
(
  input  logic clk_i,
  input  logic rst_ni,

  input  logic       pwr_req_valid_i,
  input  pd_state_e  pwr_target_state_i,

  output logic       pwr_ack_o,
  output pd_state_e  pwr_current_state_o,

  output logic core_clk_en_o,
  output logic isolate_o,
  output logic retain_o,
  output logic pg_rst_n_o,
  output logic switch_en_o
);

  // =================================================
  // TIMING CONFIG
  // =================================================
  localparam int CLK_OFF_DELAY   = 3;
  localparam int ISOLATE_DELAY   = 3;
  localparam int SAVE_DELAY      = 4;

  localparam int POWERUP_DELAY   = 6;
  localparam int RESET_RELEASE_DELAY = 4;
  localparam int RESTORE_DELAY   = 3;
  localparam int UNISO_DELAY     = 2;
  localparam int CLK_ON_DELAY    = 2;

  // =================================================
  // FSM
  // =================================================
  typedef enum logic [3:0] {
    ACTIVE,
    CLK_OFF_WAIT,
    ISOLATE_WAIT,
    SAVE_WAIT,
    RESET_ASSERT_WAIT,
    POWER_OFF,

    POWER_ON_WAIT,
    RESET_RELEASE_WAIT,
    RESTORE_WAIT,
    UNISOLATE_WAIT,
    CLK_ON_WAIT
  } state_e;

  state_e state_q, state_d;
  pd_state_e current_state_q, current_state_d;

  logic [3:0] delay_cnt_q, delay_cnt_d;

  // =================================================
  // REGISTERS
  // =================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= ACTIVE;
      current_state_q <= PD_ON;
      delay_cnt_q     <= '0;
    end else begin
      state_q         <= state_d;
      current_state_q <= current_state_d;
      delay_cnt_q     <= delay_cnt_d;
    end
  end

  // =================================================
  // FSM TRANSITIONS
  // =================================================
  always_comb begin
    state_d         = state_q;
    current_state_d = current_state_q;
    delay_cnt_d     = delay_cnt_q;
    pwr_ack_o       = 1'b0;

    case (state_q)

      ACTIVE: begin
        current_state_d = PD_ON;
        if (pwr_req_valid_i && pwr_target_state_i == PD_OFF)
          state_d = CLK_OFF_WAIT;
      end

      // ---------------- POWER DOWN ----------------
      CLK_OFF_WAIT:
        if (delay_cnt_q == CLK_OFF_DELAY)
          state_d = ISOLATE_WAIT;

      ISOLATE_WAIT:
        if (delay_cnt_q == ISOLATE_DELAY)
          state_d = SAVE_WAIT;

      SAVE_WAIT:
        if (delay_cnt_q == SAVE_DELAY)
          state_d = RESET_ASSERT_WAIT;

      RESET_ASSERT_WAIT:
          if (delay_cnt_q == SAVE_DELAY)
            state_d = POWER_OFF;

      POWER_OFF: begin
        current_state_d = PD_OFF;
        pwr_ack_o = 1'b1;
        if (pwr_req_valid_i && pwr_target_state_i == PD_ON)
          state_d = POWER_ON_WAIT;
      end

      // ---------------- POWER UP ----------------
      POWER_ON_WAIT:
        if (delay_cnt_q == POWERUP_DELAY)
          state_d = RESET_RELEASE_WAIT;

      RESET_RELEASE_WAIT:
          if (delay_cnt_q == RESET_RELEASE_DELAY)
            state_d = RESTORE_WAIT;

      RESTORE_WAIT:
        if (delay_cnt_q == RESTORE_DELAY)
          state_d = UNISOLATE_WAIT;

      UNISOLATE_WAIT:
        if (delay_cnt_q == UNISO_DELAY)
          state_d = CLK_ON_WAIT;

      CLK_ON_WAIT: begin
        if (delay_cnt_q == CLK_ON_DELAY) begin
          current_state_d = PD_ON;
          pwr_ack_o = 1'b1;
          state_d = ACTIVE;
        end
      end
    endcase

    // =================================================
    // FIX CRÍTICO: reset counter on state change
    // =================================================
    if (state_d != state_q)
      delay_cnt_d = 0;
    else
      delay_cnt_d = delay_cnt_q + 1;
  end

  assign pwr_current_state_o = current_state_q;

  // =================================================
  // OUTPUT DECODE
  // =================================================
  always_comb begin
    // SAFE DEFAULTS
    core_clk_en_o = 1'b0;
    isolate_o     = 1'b0;
    retain_o      = 1'b0;
    pg_rst_n_o    = 1'b1;
    switch_en_o   = 1'b1;
  
    case (state_q)
  
      ACTIVE: begin
        core_clk_en_o = 1'b1;
      end
  
      CLK_OFF_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b0;
        retain_o      = 1'b0;
        pg_rst_n_o    = 1'b1;
        switch_en_o   = 1'b1;
      end
  
      ISOLATE_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b1;
        retain_o      = 1'b0;
        pg_rst_n_o    = 1'b1;
        switch_en_o   = 1'b1;
      end
  
      SAVE_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b1;
        retain_o      = 1'b1;
        pg_rst_n_o    = 1'b1;
        switch_en_o   = 1'b1;
      end

      RESET_ASSERT_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b1;
        retain_o      = 1'b1;
        pg_rst_n_o    = 1'b0;
        switch_en_o   = 1'b1;
      end
  
      POWER_OFF: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b1;
        retain_o      = 1'b1;
        pg_rst_n_o    = 1'b0;
        switch_en_o   = 1'b0;
      end
  
      POWER_ON_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b1;
        retain_o      = 1'b1;
        pg_rst_n_o    = 1'b0;
        switch_en_o   = 1'b1;
      end

      RESET_RELEASE_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b1;
        retain_o      = 1'b1;
        pg_rst_n_o    = 1'b1;
        switch_en_o   = 1'b1;
      end
  
      RESTORE_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b1;
        retain_o      = 1'b0;
        pg_rst_n_o    = 1'b1;
        switch_en_o   = 1'b1;
      end
  
      UNISOLATE_WAIT: begin
        core_clk_en_o = 1'b0;
        isolate_o     = 1'b0;
        retain_o      = 1'b0;
        pg_rst_n_o    = 1'b1;
        switch_en_o   = 1'b1;
      end
  
      CLK_ON_WAIT: begin
        core_clk_en_o = 1'b1;
      end
  
    endcase
  end

endmodule