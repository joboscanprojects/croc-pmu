# croc-pmu — Power Management Unit for RISC-V Croc SoC

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-PULP_Croc_SoC-orange)](https://github.com/pulp-platform/croc)
[![ISA](https://img.shields.io/badge/ISA-RISC--V_RV32IMC-green)](https://riscv.org)
[![EDA](https://img.shields.io/badge/EDA-OpenROAD_|_Yosys_|_OpenSTA-purple)](https://openroad.readthedocs.io)
[![Technology](https://img.shields.io/badge/Technology-IHP_130nm-red)](https://github.com/IHP-GmbH/IHP-Open-PDK)

A modular, open-source **Power Management Unit (PMU)** integrated into the
[PULP Croc SoC](https://github.com/pulp-platform/croc) — an open-source
RISC-V SoC based on the CVE2 (Ibex) core. Implements **clock gating** and
**power gating** via UPF (IEEE 1801), using a fully open-source RTL-to-GDSII
flow.

> Developed as part of the thesis *"Power Management Unit for RISC-V SoC"*
> at Universitat Politècnica de València (UPV), within the EU PERTE Chip-funded
> NANO Chair programme. April 2026.

---

## Key Results

Measured with **OpenSTA** (`report_power`) on synthesised netlist.
Technology corner: Fast / Vmax / Tmin (IHP 130nm).

| Mode                        | Total Power | Reduction vs Active |
|-----------------------------|-------------|---------------------|
| Active (WFI)                | 2.95 mW     | —                   |
| Clock Gating                | 1.53 mW     | **~48 %**           |
| Clock Gating + Power Gating | 4.27 µW     | **~99.86 %**        |

> ⚠️ Results obtained at Fast/Vmax/Tmin corner — not the worst-case power
> scenario. Typical and slow corners will show higher absolute values.

---

## Architecture Overview

The PMU is integrated as a **memory-mapped peripheral** in `croc_domain.sv`,
connected to the system via the OBI bus through the OBI Demux.

```
┌──────────────────────────────────────────────────────┐
│                  Power Management Unit               │
│                                                      │
│   ┌─────────────────────┐                            │
│   │   SW/HW Firmware    │  power.sv / power.c        │
│   │  (OBI registers)    │  power_reg_pkg.sv          │
│   └──────────┬──────────┘                            │
│              │ sw_target_state / core_idle / wakeup  │
│   ┌──────────▼──────────┐                            │
│   │  Power Policy Unit  │  power_policy_unit.sv      │
│   │       (PPU)         │  → decides which mode      │
│   └──────────┬──────────┘                            │
│              │ pwr_req_valid / target_state          │
│   ┌──────────▼──────────┐                            │
│   │ Power Domain Control│  power_domain_control.sv   │
│   │       (PDC)         │  → drives physical signals │
│   └──────────┬──────────┘                            │
│              │ clock_en / isolate / retention /      │
│              │ reset_n / switch_en                   │
│   ┌──────────▼──────────┐                            │
│   │  UPF / Physical     │  croc.upf (IEEE 1801)      │
│   │  Implementation     │  → ICG cells, isolation,   │
│   └──────────┬──────────┘    retention registers     │
│              │                                       │
│    ┌─────────┼─────────┐                             │
│    ▼         ▼         ▼                             │
│  CPU       SRAM   Peripherals                        │
│ (Ibex)           (GPIO, UART, OBI...)                │
└──────────────────────────────────────────────────────┘
```

### Power Domains

| Domain       | Type              | Contents                                    |
|--------------|-------------------|---------------------------------------------|
| `PD_AON`     | Always-On         | Timer, Power, SRAM                          |
| `PD_CPU`     | Switchable        | Core (Ibex), GPIO, UART, OBI Crossbar/Demux, DM/JTAG, SOC CTRL |

### Operating Modes

| Mode              | SW Call                        | Clock  | Power Domain | Wakeup Latency |
|-------------------|--------------------------------|--------|--------------|----------------|
| Active (WFI)      | `power_set_mode(POWER_LIGHT_SLEEP)` | ON     | ON           | ~0 cycles      |
| Clock Gating      | `power_set_mode(POWER_SLEEP)` | GATED  | ON           | Low            |
| Power Gating      | `power_set_mode(POWER_DEEP_SLEEP)` | GATED  | OFF          | High           |

---

## RTL Components

| File                        | Description                                              |
|-----------------------------|----------------------------------------------------------|
| `rtl/power.sv`              | Top-level PMU module — OBI interface, register map       |
| `rtl/power_reg_pkg.sv`      | Register package — memory-mapped register definitions    |
| `rtl/power_ret_top.sv`      | Retention register top — state preservation across PG   |
| `rtl/power_policy_unit.sv`  | PPU — power mode decision engine (FSM)                  |
| `rtl/power_domain_control.sv` | PDC — drives isolation/retention/switch signals        |
| `rtl/icg_box.sv`            | Integrated Clock Gating cell wrapper                     |
| `rtl/power_types.sv`        | Shared types and enumerations                            |
| `upf/croc.upf`              | UPF file — power domains, supply nets, isolation rules  |
| `sw/power.h`                | Firmware header — mode definitions and API               |
| `sw/power.c`                | Firmware driver — power_set_mode(), sleep_ms()          |

---

## PPU ↔ PDC Handshake Protocol

The PPU and PDC communicate via a synchronous handshake:

```
PPU → PDC:   pwr_req_valid  (request to change power state)
             target_state   (desired power domain state)

PDC → PPU:   pwr_ack        (transition complete)
             current_state  (actual power domain state)
```

Power gating sequence (entry):
```
1. PPU asserts pwr_req_valid + target_state = DEEP_SLEEP
2. PDC asserts isolate → isolates PD_CPU outputs
3. PDC asserts retention → saves registers to always-on retention cells
4. PDC de-asserts switch_en → cuts power to PD_CPU
5. PDC gates clock (clock_en = 0)
6. PDC asserts pwr_ack
```

Power gating sequence (exit / wakeup):
```
1. Wakeup interrupt received (always-on domain)
2. PDC asserts switch_en → restores power to PD_CPU
3. PDC de-asserts retention → restores register state
4. PDC de-asserts isolate → re-enables PD_CPU outputs
5. PDC restores clock (clock_en = 1)
6. Core resumes execution from WFI instruction
```

---

## Verification

Three independent verification flows were used:

```
Software Tests & RTL
        │
        ├──► Verilator Simulation (no UPF) ──► GTKWave signal analysis
        │
        ├──► Xcelium Simulation  (with UPF) ──► GTKWave signal analysis
        │                                        (isolation/retention/switch)
        │
        └──► Yosys Synthesis ──► OpenSTA Power Analysis
```

### Test Cases

| Test | Mode | Result |
|------|------|--------|
| Test 1 | WFI (no clock gating) — `POWER_LIGHT_SLEEP` | ✅ PASS |
| Test 2 | Clock Gating — `POWER_SLEEP` | ✅ PASS |
| Test 3 | Clock Gating + Power Gating — `POWER_DEEP_SLEEP` | ✅ PASS |
| UPF sequence | Isolation → retention → switch → wakeup | ✅ PASS |
| Wake-up | Register restore → clock restore → execution resume | ✅ PASS |

---

## Getting Started

### Prerequisites

```bash
# RTL simulation (no UPF)
verilator --version   # >= 5.0

# UPF-aware simulation
xcelium -version      # Cadence Xcelium (license required)

# Synthesis + power analysis
yosys --version       # >= 0.36
openroad -version     # >= 3.0
opensta               # included with OpenROAD
```

### Clone and Setup

```bash
git clone https://github.com/[your-handle]/croc-pmu.git
cd croc-pmu

# Clone the base Croc SoC (required for full integration)
git clone https://github.com/pulp-platform/croc.git ../croc
```


---

## Integration into Croc SoC

The PMU connects to `croc_domain.sv` as a memory-mapped peripheral on the OBI bus:

```systemverilog
// In croc_domain.sv — add PMU to peripheral list
power_top #(
  .DataWidth  ( 32 ),
  .AddrWidth  ( 32 )
) i_pmu (
  .clk_i         ( clk_i          ),
  .rst_ni        ( rst_ni         ),
  .obi_req_i     ( pmu_obi_req    ),
  .obi_rsp_o     ( pmu_obi_rsp    ),
  .core_idle_i   ( core_idle      ),
  .wakeup_i      ( timer_irq      ),
  .clk_gate_en_o ( clk_gate_en    ),
  .isolate_o     ( core_isolate   ),
  .retention_o   ( core_retention ),
  .switch_en_o   ( core_switch_en )
);
```

---

## Firmware API

```c
#include "power.h"

// Set power mode
power_set_mode(POWER_LIGHT_SLEEP);  // WFI only
power_set_mode(POWER_SLEEP);        // Clock gating
power_set_mode(POWER_DEEP_SLEEP);   // Clock + power gating

// Timed sleep (wakeup via timer interrupt)
sleep_ms(10);
```

---

## Citation

If you use this work in your research, please cite:

```bibtex
@mastersthesis{bosca2026pmu,
  author  = {Bosca Candel, Jose Daniel},
  title   = {Power Management Unit for {RISC-V} {SoC}},
  school  = {Universitat Politecnica de Valencia},
  year    = {2026},
  month   = {April},
  note    = {NANO Chair, EU PERTE Chip programme},
  url     = {https://github.com/joboscanprojects/croc-pmu}
}
```

---

## Contributing

Contributions welcome — bug reports, test cases, ports to other RISC-V SoCs.
See [CONTRIBUTING.md](.github/CONTRIBUTING.md).

If you are using this PMU in a commercial or research project, I would love
to hear about it — open an issue or reach out directly.

---

## License

This work is licensed under the **Apache License 2.0** — see [LICENSE](LICENSE).

The base [Croc SoC](https://github.com/pulp-platform/croc) by ETH Zürich /
PULP Platform is also Apache 2.0 licensed.


---

## Author

**José Daniel Boscá Candel**
RISC-V SoC IP Designer & Embedded Linux Consultant
Valencia, Spain · Available for remote consulting

- GitHub: [@joboscanprojects](https://github.com/joboscanprojects)
- LinkedIn: [linkedin.com/jobs](https://www.linkedin.com/jobs/)
- Email: josedaniel@joboscan.es

*Open to consulting contracts, IP licensing, and research collaboration
in RISC-V SoC design, low-power IP, and embedded Linux.*