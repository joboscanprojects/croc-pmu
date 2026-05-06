// Copyright 2026 Polytechnic University of Valencia.
// SPDX-License-Identifier: Apache-2.0
//
// Authors:
// - Jose Daniel Boscá Candel <josedaniel@joboscan.es>


#include "uart.h"
#include "print.h"
#include "timer.h"
#include "gpio.h"
#include "util.h"
#include "power.h"


int main() {
    uart_init(); // setup the uart peripheral

    /****** Test 1: WFI ******/
    // printf("Test 1: WFI\n");

    // power_set_mode(POWER_SLEEP);
    // sleep_ms(4);

    // printf("Test 1: PASS\n");



    /****** Test 2: WFI with Power Gating ******/
    printf("Test 2: WFI with Power Gating\n");

    power_set_mode(POWER_LIGHT_SLEEP);
    sleep_ms(4);

    printf("Test 2: PASS\n");




    /****** Test 3: WFI with Clock Gating + Power Gating ******/
    // printf("Test 3: WFI with Clock Gating + Power Gating\n");

    // power_set_mode(POWER_DEEP_SLEEP);
    // sleep_ms(4);

    // printf("Test 3: PASS\n");


    // flush uart
    uart_write_flush();

    return 1;
}
