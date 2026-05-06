# Power Management Module

This folder contains the hardware implementation of the power management system for the CROC chip. The module provides clock gating and power domain control capabilities.

## File Descriptions

### `power.sv`
Main power management module that implements the power control logic. It includes:
- A Finite State Machine (FSM) with three states: RUN, ARM, and SLEEP
- **RUN**: Normal execution mode
- **ARM**: Waiting for the core to become idle
- **SLEEP**: Low-power sleep mode
- OBI (Open Bus Interface) communication interface for register access
- Control signals for clock gating (`clk_gate_en_o`) and power domain control (`power_domain_on_o`)
- Integration with the core busy signal to manage sleep transitions

### `power_reg_pkg.sv`
Register package that defines the register structure and interface:
- Defines the `power_reg2hw_t` struct for register-to-hardware signals
- Contains register offset definitions (e.g., `POWER_MODE_OFFSET`)
- Specifies address width (12 bits = 4 KB address space)
- Defines the power mode register with 2-bit width for mode selection

### `power_reg_top.sv`
Register interface module that handles OBI protocol communication:
- Implements an OBI slave interface for register access
- Manages read/write transactions to power control registers
- Implements the power mode register (2-bit value controlling the power state)
- Provides pipelining for OBI requests/responses
- Always grants OBI requests and handles address decoding

### `icg_box.sv`
Integrated Clock Gating (ICG) cell implementation:
- Creates a latched clock signal to gate the main clock
- Takes enable signal (E), main clock (CLK), and test enable (TE) as inputs
- Outputs a gated clock (GCLK) that reduces dynamic power consumption
- Uses a latch-based approach for zero-overhead clock gating
- Includes reference to a standard cell library ICG cell (`LSGCPJIHDX0`)

### `iso_cell.sv`
Isolation cell for power domain crossings:
- Parametric module supporting configurable bit widths
- Isolates signals between power domains using an enable signal (`iso_en`)
- Forces output to zero when isolation is active, preventing unwanted signal propagation
- Prevents race conditions and data corruption during power domain transitions

## Usage

The power management module interfaces with the system through:
- **OBI Interface**: Register access for power mode control
- **Control Inputs**: Core busy signal for sleep decision making
- **Control Outputs**: Clock gating enable and power domain on/off signals
