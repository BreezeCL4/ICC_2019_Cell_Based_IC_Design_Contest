# ICC 2019 IoT Data Filtering (IOTDF) - Verilog RTL

This project implements the **IoT Data Filtering (IOTDF)** RTL design for the [2019 ICC Cell-Based IC Design Contest](https://www.iccad-contest.org/).  
It supports **7 functional modes** defined by the contest, processing 96 IoT sensor data inputs (128 bits each) via streaming, and outputs processed results based on the selected function.

---

## 🔍 Project Overview

- 📦 96 packets of IoT data (128 bits each) are streamed in
- 📊 Functional Modes:
  | fn_sel | Function    | Description                                      |
  |--------|-------------|--------------------------------------------------|
  | `001`  | F1 - Max    | Output max of every 8 data                      |
  | `010`  | F2 - Min    | Output min of every 8 data                      |
  | `011`  | F3 - Avg    | Output average (truncated) of every 8 data     |
  | `100`  | F4 - Extract| Output if within range [`low` < data < `high`] |
  | `101`  | F5 - Exclude| Output if data outside the range               |
  | `110`  | F6 - PeakMax| Output if greater than all previous outputs    |
  | `111`  | F7 - PeakMin| Output if smaller than all previous outputs    |

---

## 📁 File Structure

