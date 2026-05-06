// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>

package power_types;

  typedef enum logic [1:0] {
    PD_ON        = 2'b00,
    PD_RETENTION = 2'b01,
    PD_OFF       = 2'b10
  } pd_state_e;

endpackage