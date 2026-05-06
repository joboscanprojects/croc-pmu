// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>

#include "power.h"
#include "util.h"

void power_set_mode(power_mode_t mode)
{
    *reg32(POWER_BASE_ADDR, POWER_MODE_REG_OFFSET) = (uint32_t)mode & 0x3;
}
