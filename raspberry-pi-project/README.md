# Eco-RIC: O-RAN-Inspired Embedded Power Controller

## Overview
Eco-RIC is an embedded system prototype inspired by the O-RAN architecture, designed to demonstrate autonomous and energy-aware control of a simulated 5G Radio Unit.

The system runs on a Raspberry Pi and dynamically adjusts power states based on real-time network telemetry and environmental sensor inputs, mimicking Near-Real-Time RIC behavior.

---

## System Architecture
The design follows a distributed control model:

- **RIC (Controller):** Raspberry Pi 4 running a Python backend
- **E2 Interface (Simulated):** ZeroMQ-based publisher/subscriber model
- **Radio Unit (Simulated):** GPIO-controlled LEDs representing power states

Network telemetry is generated externally and sent over ZMQ, ensuring the controller logic is decoupled from the data source.

---

## Hardware Components
- Raspberry Pi 4 Model B
- ADC0832 (Analog-to-Digital Converter)
- LDR (Light sensor for day/night context)
- DHT11 (Temperature & humidity monitoring)
- LEDs:
  - Green: Active / scaled power mode (PWM)
  - Red: Sleep mode indicator

---

## Software & Technologies
- Python (Flask backend)
- GPIO & PWM control
- ZeroMQ (ZMQ) for distributed messaging
- Linear Regression (traffic trend prediction)
- Linux-based embedded execution

---

## Control Logic
The controller executes one of three power policies:

- **Active Mode:** Load between 30–85%, LED brightness scales via PWM
- **Predictive Boost:** Traffic surge detected, power forced to 100%
- **Sleep Mode:** Load < 30%, system enters low-power state

A lightweight linear regression model predicts traffic surges using recent telemetry to avoid reactive behavior.

---

## Debugging & Validation
Key engineering challenges addressed:

- **ADC Timing Errors:** Fixed bit-banging misalignment causing invalid readings
- **ZMQ Socket Conflicts:** Implemented proper socket teardown to avoid port reuse issues
- **Sensor Reliability:** Added safe-read logic for DHT11 timing instability

All control decisions were physically validated through immediate LED response on hardware.

---

## Key Learnings
- Embedded Linux system integration
- GPIO, PWM, and sensor interfacing on Raspberry Pi
- Distributed system design using publish-subscribe models
- Translating telecom architecture concepts into embedded prototypes
- Debugging timing-sensitive hardware and networked software

## Project Demonstration

### Hardware Setup
![Hardware Setup](screenshots/hardware_setup.jpg)
Raspberry Pi connected to external sensors, ADC, and LEDs used to simulate Radio Unit power states.

---

### Distributed Traffic Simulation (ZMQ)
![ZMQ Traffic](screenshots/zmq_traffic_simulator.png)
External traffic simulator publishing real-time network load to the RIC over ZeroMQ.

---

### Sleep Mode (Low Traffic)
![Sleep Mode](screenshots/dashboard_sleep_mode.png)
System enters low-power sleep mode when traffic load drops below threshold.

---

### Active Mode (Normal Traffic)
![Active Mode](screenshots/dashboard_active_mode.png)
Dynamic power scaling during normal traffic conditions.

---

### Predictive Boost (AI Detected Surge)
![Predictive Boost](screenshots/dashboard_predictive_boost.png)
Predictive AI logic detects traffic surge and proactively boosts power.


---

## Scope Note
This project is a functional prototype intended to demonstrate architecture, control logic, and validation methodology rather than production-grade O-RAN deployment.
