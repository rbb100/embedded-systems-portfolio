# O-RAN Python xApp

A Python-based xApp prototype exploring O-RAN architecture concepts including control logic, telemetry processing, and RAN resource management.

---

## Overview

This project implements a lightweight xApp targeting the O-RAN Near-Real-Time RIC (RAN Intelligent Controller). It demonstrates how an xApp subscribes to E2 node telemetry, applies control logic, and sends policy decisions back to the RAN — following the O-RAN Software Community (OSC) architecture model.

---

## O-RAN Concepts Covered

| Concept | Implementation |
|---|---|
| **xApp** | Python application running on the Near-RT RIC |
| **E2 Interface** | Subscription to RAN telemetry (KPIs, measurements) |
| **A1 Interface** | Policy input from Non-RT RIC |
| **Control Loop** | Observe → Decide → Act on RAN state |

---

## Technologies

- Python 3
- O-RAN Software Community (OSC) RIC platform concepts
- ZeroMQ (simulated E2 messaging)
- JSON-based telemetry and policy payloads

---

## Key Learnings

- O-RAN architecture layers: Non-RT RIC, Near-RT RIC, O-DU, O-RU
- xApp lifecycle: onboarding, subscription, control, teardown
- Telemetry-driven closed-loop control in disaggregated RAN
- Systems-level thinking: decoupling data plane from control plane

---

> Code and simulation scripts coming soon.
