// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>

#pragma once
#include <stdint.h>
#include "config.h"

/*
 * POWER peripheral
 * Single register at offset 0x000
 */

#define POWER_MODE_REG_OFFSET 0x000

typedef enum {
    POWER_LIGHT_SLEEP = 0,
    POWER_SLEEP       = 1,
    POWER_DEEP_SLEEP  = 2
} power_mode_t;

/**
 * @brief Configure power mode
 */
void power_set_mode(power_mode_t mode);
