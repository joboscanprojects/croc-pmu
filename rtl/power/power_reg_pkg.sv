// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>

package power_reg_pkg;

  // Peripheral size: 4 KB
  parameter int AddressWidth = 12;

  // ------------------------------------------------------------
  // Register → HW
  // ------------------------------------------------------------
  typedef struct packed {
    logic [1:0] pwr_mode;
  } power_reg2hw_t;

  // ------------------------------------------------------------
  // Register offsets
  // ------------------------------------------------------------
  parameter logic [AddressWidth-1:0] POWER_MODE_OFFSET = 12'h000;

endpackage
