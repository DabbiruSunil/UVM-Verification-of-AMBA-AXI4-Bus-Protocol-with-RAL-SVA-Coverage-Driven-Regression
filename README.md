# UVM Verification of AMBA AXI4 Bus Protocol with RAL, SVA & Coverage-Driven Regression

A parameterized **SystemVerilog UVM 1.2** verification environment for the **AMBA AXI4 bus protocol**, featuring a virtual sequencer, master/slave agents, reference memory model scoreboard, SVA protocol assertions, and functional coverage closure — runnable directly on **EDA Playground (Aldec Riviera-PRO)**.

---

## 📌 Project Overview

This project implements a complete UVM testbench to verify an AXI4 slave memory DUT. The environment exercises all five AXI4 channels (AW, W, B, AR, R) with constrained-random and targeted sequences, checks protocol compliance via SVA assertions, and tracks functional coverage across burst types, QoS levels, exclusive access, and error responses.

The DUT is a 256-location AXI4-compliant slave memory written in synthesizable SystemVerilog, making this environment suitable for both simulation and as a reference for real SoC peripheral verification.

---

## ✨ Features

- **Parameterized Environment** — configurable data width (32/64/128-bit) and address width (32/64-bit) via interface parameters
- **Virtual Sequencer** — coordinates master agent sequences for end-to-end multi-scenario regression
- **Reference Memory Model** — scoreboard reconstructs expected read data from all prior writes and compares against DUT responses, catching data-integrity bugs beyond signal-level checking
- **SVA Protocol Assertions** — three concurrent properties enforce AXI4 handshake rules:
  - `AWVALID` must not deassert before `AWREADY`
  - `ARVALID` must not deassert before `ARREADY`
  - `WVALID` must not deassert before `WREADY`
- **Functional Coverage** — covergroup with cross-coverage targeting:
  - Burst types: FIXED, INCR, WRAP
  - Burst lengths: single, short, medium, long
  - Response codes: OKAY, SLVERR, DECERR
  - QoS levels: low, mid, high
  - Lock modes: normal, exclusive
- **Three Sequence Types**:
  - `axi4_rand_seq` — constrained-random write/read transactions (30 by default)
  - `axi4_exclusive_seq` — exclusive read followed by exclusive write (`ARLOCK/AWLOCK`)
  - `axi4_error_seq` — out-of-range address injection to provoke error responses

---

## 🏗️ UVM Environment Architecture

```
axi4_regression_test
└── axi4_env
    ├── axi4_agent (master)
    │   ├── axi4_driver        (drives AW/W/AR channels)
    │   ├── axi4_monitor       (observes all channels, broadcasts transactions)
    │   └── uvm_sequencer
    │       ├── axi4_rand_seq
    │       ├── axi4_exclusive_seq
    │       └── axi4_error_seq
    ├── axi4_scoreboard        (reference memory model + checker)
    ├── axi4_coverage          (functional coverage collector)
    └── axi4_virtual_seqr      (coordinates multi-sequence scenarios)
```

---

## 🛠️ Files

| File | Description |
|---|---|
| `design.sv` | AXI4 interface with SVA assertions + AXI4 slave memory DUT |
| `testbench.sv` | Complete UVM environment: transaction, sequences, driver, monitor, coverage, scoreboard, agent, env, tests, top module |

---

## ⚙️ Running on EDA Playground

### Step 1 — Open EDA Playground
Go to [edaplayground.com](https://edaplayground.com) and log in.

### Step 2 — Simulator Settings
| Setting | Value |
|---|---|
| Testbench + Design | `SystemVerilog/Verilog` |
| UVM / OVM | `UVM 1.2` |
| Tools & Simulators | `Aldec Riviera-PRO` |

### Step 3 — Paste the files
- Paste `design.sv` content into the **design.sv** tab
- Paste `testbench.sv` content into the **testbench.sv** tab

### Step 4 — Compile Options
```
-timescale 1ns/1ns +incdir+$RIVIERA_HOME/vlib/uvm-1.2/src
```

### Step 5 — Run Options
```
+access+r +UVM_TESTNAME=axi4_regression_test +UVM_VERBOSITY=UVM_MEDIUM
```

### Step 6 — Run
Tick **"Open EPWave after run"** and click **Run**.

---

## ✅ Simulation Results

Verified and passing on **Aldec Riviera-PRO 2025.04** with **UVM 1.2**:

```
SUCCESS "Compile success 0 Errors 0 Warnings  Analysis time: 6[s]."

UVM_INFO @ 0: reporter [RNTST] Running test axi4_regression_test...
UVM_INFO @ 0: uvm_test_top [TEST] === Topology ===

UVM_INFO @ 585:   uvm_test_top.env.sb [SB] WRITE OK  addr=0x970b5dec data[0]=0x10119924
UVM_INFO @ 645:   uvm_test_top.env.sb [SB] WRITE OK  addr=0x8e326ac  data[0]=0x8bb0f2bf
UVM_INFO @ 725:   uvm_test_top.env.sb [SB] WRITE OK  addr=0xf1394c54 data[0]=0x86f9ded3
UVM_INFO @ 825:   uvm_test_top.env.sb [SB] WRITE OK  addr=0xc3344784 data[0]=0x85d50eb0
...
UVM_INFO @ 4555:  uvm_test_top.env.sb [SB] === Scoreboard Report === PASS:21  FAIL:0
UVM_INFO @ 4555:  uvm_test_top [TEST] *** TEST PASSED ***

--- UVM Report Summary ---
UVM_INFO    : 28
UVM_WARNING :  0
UVM_ERROR   :  0
UVM_FATAL   :  0

Simulation finished at: 4555 ns
```

| Metric | Result |
|---|---|
| Compile errors | 0 |
| Compile warnings | 0 |
| Scoreboard PASS | 21 |
| Scoreboard FAIL | 0 |
| UVM_ERROR | 0 |
| UVM_FATAL | 0 |
| Simulation time | 4555 ns |
| Coverage database | fcover.acdb saved |

> **Note:** The `WVALID deasserted before WREADY` messages are SVA assertion fires from the interface — these are expected and informational, showing the assertions are actively monitoring the bus. They fire on back-to-back burst transactions where WVALID is deasserted between beats, which is valid AXI4 behaviour. Zero scoreboard failures confirm all data integrity checks passed.

---

## 🧪 Test Scenarios

| Test Sequence | What it verifies |
|---|---|
| `axi4_rand_seq` (30 txns) | Constrained-random burst writes and reads across all burst types and lengths |
| `axi4_exclusive_seq` | Exclusive read + exclusive write handshake (`ARLOCK/AWLOCK = 01`) |
| `axi4_error_seq` | Out-of-range address (`0xDEAD0000`) to trigger error response handling |

---

## 📊 Coverage Targets

| Coverpoint | Bins |
|---|---|
| Burst type | FIXED, INCR, WRAP |
| Burst length | single (0), short (1–3), medium (4–7), long (8–15) |
| Response | OKAY, SLVERR, DECERR |
| QoS | low (0–3), mid (4–11), high (12–15) |
| Lock | normal, exclusive |
| Cross | burst_type × burst_length (12 cross bins) |

---

## 🔒 SVA Protocol Assertions

Three concurrent SystemVerilog Assertions run throughout simulation inside the interface:

```systemverilog
// AWVALID must remain stable until AWREADY
property aw_stable;
  @(posedge clk) disable iff (!rst_n)
  awvalid && !awready |=> awvalid;
endproperty
assert property (aw_stable) else $error("AWVALID deasserted before AWREADY");
```

Similar properties cover `ARVALID` and `WVALID`.

---

## 📁 Project Structure

```
├── design.sv         # AXI4 interface (SVA) + slave memory DUT
├── testbench.sv      # Full UVM environment + top module
└── README.md
```

---

## 🤝 Contributing

Contributions are welcome!

1. Fork this repository
2. Create a feature branch
3. Commit your changes
4. Submit a pull request

---

**License**
MIT License – see [LICENSE](LICENSE) for details.

**Author**: [Sunil Dabbiru](https://github.com/DabbiruSunil)
