# PMU Architecture

## System Context

The PMU is integrated as a memory-mapped peripheral inside `croc_domain.sv`,
connected to the OBI bus through the OBI Demux alongside GPIO, UART, Timer,
and SoC registers.

```
croc_soc
└── croc_domain
    ├── JTAG / Debug
    ├── CVE2 (Ibex) core
    ├── OBI Crossbar
    ├── OBI Demux
    │   ├── SoC Regs
    │   ├── GPIO
    │   ├── UART
    │   ├── Timer
    │   ├── PMU  ◄─────────────── this module
    │   └── Mem Banks
    └── user_domain
```

---

## Internal Architecture

```
                     ┌────────────────────────────────────┐
                     │       Power Management Unit        │
                     │                                    │
  OBI bus ──────────►│  ┌──────────────────────────────┐  │
  (memory-mapped)    │  │      SW/HW Firmware          │  │
                     │  │                              │  │
                     │  │  power.sv         power.c    │  │
                     │  │  power_reg_pkg.sv power.h    │  │
                     │  │  power_ret_top.sv            │  │
                     │  └──────────────┬───────────────┘  │
                     │                 │                  │
                     │   sw_target_state[1:0]             │
                     │   core_idle_i                      │
                     │   wakeup_i                         │
                     │                 │                  │
                     │  ┌──────────────▼───────────────┐  │
                     │  │    Power Policy Unit (PPU)   │  │
                     │  │                              │  │
                     │  │  power_policy_unit.sv        │  │
                     │  │  power_types.sv              │  │
                     │  │                              │  │
                     │  │  · Monitors core_idle        │  │
                     │  │  · Monitors sw_target_state  │  │
                     │  │  · Decides operating mode    │  │
                     │  │  · Issues power request      │  │
                     │  └──────────────┬───────────────┘  │
                     │                 │                  │
                     │   ◄──── Handshake Protocol ────►   │
                     │   pwr_req_valid    pwr_ack         │
                     │   target_state     current_state   │
                     │                 │                  │
                     │  ┌──────────────▼───────────────┐  │
                     │  │  Power Domain Control (PDC)  │  │
                     │  │                              │  │
                     │  │  power_domain_control.sv     │  │
                     │  │  icg_box.sv                  │  │
                     │  │                              │  │
                     │  │  · Drives physical signals   │  │
                     │  │  · Sequences PG transitions  │  │
                     │  │  · Manages wakeup            │  │
                     │  └──────────────┬───────────────┘  │
                     │                 │                  │
                     │  ┌──────────────▼───────────────┐  │
                     │  │   UPF / Physical Layer       │  │
                     │  │                              │  │
                     │  │  croc.upf  (IEEE 1801)       │  │
                     │  │                              │  │
                     │  │  · Power domain definitions  │  │
                     │  │  · Supply net declarations   │  │
                     │  │  · Isolation cell rules      │  │
                     │  │  · Retention register rules  │  │
                     │  │  · Power switch rules        │  │
                     │  └──────────────┬───────────────┘  │
                     └─────────────────┼──────────────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
              ▼                        ▼                        ▼
    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
    │   CPU (Ibex)    │    │      SRAM       │    │  Peripherals    │
    │                 │    │                 │    │  GPIO UART OBI  │
    │  PD_CPU domain  │    │  PD_AON domain  │    │  PD_CPU domain  │
    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## Power Domains

### PD_AON — Always-On Domain

Never powered down. Contains elements that must remain active
during deep sleep to detect wakeup events.

| Element  | Reason                                      |
|----------|---------------------------------------------|
| Timer    | Source of wakeup interrupt                  |
| Power    | PMU itself must stay alive                  |
| SRAM     | Retains data across power gating transitions|

### PD_CPU — Switchable Domain

Powered down during `POWER_DEEP_SLEEP` mode. Entire CPU subsystem
and peripheral fabric can be cut from the supply rail.

| Element      | Notes                                        |
|--------------|----------------------------------------------|
| Core (Ibex)  | Registers saved to retention cells before PG |
| GPIO         | Isolation cells hold last value during PG    |
| UART         | Isolation cells hold last value during PG    |
| OBI Crossbar | Isolated during PG                           |
| OBI Demux    | Isolated during PG                           |
| DM / JTAG    | Isolated during PG                           |
| SOC CTRL     | Isolated during PG                           |

---

## PPU — Power Policy Unit FSM

The PPU implements a finite state machine that monitors system
conditions and decides when to request power mode transitions.

```
                    ┌─────────────────┐
          reset ───►│     ACTIVE      │◄─── wakeup
                    │  (clk running)  │
                    └────────┬────────┘
                             │ core_idle & sw_target = SLEEP
                             ▼
                    ┌─────────────────┐
                    │  CLOCK_GATING   │
                    │  (clk gated)    │
                    └────────┬────────┘
                             │ sw_target = DEEP_SLEEP
                             ▼
                    ┌─────────────────┐
                    │  POWER_GATING   │
                    │  (domain off)   │
                    └─────────────────┘
```

### PPU Input Signals

| Signal             | Source    | Description                          |
|--------------------|-----------|--------------------------------------|
| `sw_target_state`  | Firmware  | Software-requested power mode        |
| `core_idle_i`      | CVE2 core | Core is idle (WFI executed)          |
| `wakeup_i`         | Timer/IRQ | Wakeup event detected                |
| `pwr_ack`          | PDC       | Previous transition completed        |

### PPU Output Signals

| Signal          | Destination | Description                       |
|-----------------|-------------|-----------------------------------|
| `pwr_req_valid` | PDC         | New power state requested         |
| `target_state`  | PDC         | Target power domain state         |

---

## PDC — Power Domain Control Sequencer

The PDC implements the safe power-on and power-off sequences,
ensuring all UPF rules are respected. Incorrect sequencing
(e.g. cutting power before asserting isolation) can cause
metastability or data corruption.

### Power-Off Sequence (entry into DEEP_SLEEP)

```
Step 1: assert isolate       → hold PD_CPU outputs at safe value
Step 2: assert retention     → save CPU registers to AON supply
Step 3: de-assert switch_en  → cut VDD to PD_CPU
Step 4: assert clock_en = 0  → gate clock to PD_CPU
Step 5: assert pwr_ack       → notify PPU: transition complete
```

### Power-On Sequence (wakeup from DEEP_SLEEP)

```
Step 1: assert switch_en     → restore VDD to PD_CPU
Step 2: de-assert retention  → restore CPU registers from AON
Step 3: de-assert isolate    → reconnect PD_CPU outputs
Step 4: assert clock_en = 1  → ungate clock to PD_CPU
Step 5: assert pwr_ack       → notify PPU: wakeup complete
        CPU resumes execution from WFI instruction
```
