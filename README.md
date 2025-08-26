# QSPI Controller IP

## Overview

The **Quad Serial Peripheral Interface (QSPI) Controller** is a high-performance IP core designed to interface with serial NOR flash memories using **single, dual, and quad SPI protocols**.  
It supports **command-based access**, **DMA transfers**, and **XIP (Execute-In-Place) mode**, enabling efficient boot, firmware update, and high-speed data transactions in SoC and FPGA designs.

---

## Features

- Supports **Standard, Dual, and Quad SPI protocols** (1-1-1, 1-1-2, 1-1-4, 1-4-4).
- **APB slave interface** for CSR access and FIFO read/write.
- **AXI4 master interface** for DMA block transfers.
- **AXI4 slave interface** for memory-mapped XIP mode.
- Configurable transaction format: opcode, address lanes, data lanes, dummy cycles, mode bits.
- FIFO buffers (default 16 bytes) for TX/RX decoupling.
- **Interrupts**: command done, DMA done, FIFO events, error flags.
- **Error detection**: timeout, overrun, underrun, AXI error.
- **Power management**: clock gating, low-power mode.

---

## Architecture

- **CSR Register Bank** (APB slave) – configuration, status, and interrupt handling.
- **Command Engine (CE)** – executes programmable commands.
- **DMA Engine** – AXI master for block transfers.
- **XIP Engine** – AXI slave to support memory-mapped flash access.
- **QSPI FSM** – manages command/address/data serialization, clocking, CS#, and IO lines.
- **FIFO Buffers** – TX and RX FIFOs.

---

## Configuration Parameters

| Parameter           | Type    | Default | Description                 |
| ------------------- | ------- | ------- | --------------------------- |
| DATA_WIDTH          | Integer | 32      | AXI data bus width (32/64). |
| AXI_ADDR_WIDTH      | Integer | 32      | AXI address width.          |
| FIFO_DEPTH          | Integer | 16      | FIFO depth in bytes.        |
| SUPPORT_XIP_WRITE   | Boolean | False   | Enable write in XIP mode.   |
| SUPPORT_HOLD_WP     | Boolean | False   | Enable HOLD# and WP# pins.  |
| MAX_BURST_LEN       | Integer | 16      | Max AXI burst length.       |
| APB_ADDR_WIDTH      | Integer | 12      | APB address width (4KB).    |

--- 

## Interface Description

### Clock, Reset, and Interrupt

This interface provides the basic control signals for synchronous operation and system-level event notification. The controller runs on the system clock (`clk`), resets with `rst_n`, and reports status/events through an interrupt line (`irq`).

### APB Slave Interface (Configuration & Control)

The APB slave interface allows the CPU or system controller to configure and monitor the QSPI IP through Control/Status Registers (CSRs). All operation modes, command triggers, and status checks are managed via APB transactions.

| Signal     | Dir    | Width | Description |
|------------|--------|-------|-------------|
| `pclk`     | Input  | 1     | APB clock for register access |
| `presetn`  | Input  | 1     | APB active-low reset |
| `psel`     | Input  | 1     | APB peripheral select |
| `penable`  | Input  | 1     | APB enable signal |
| `pwrite`   | Input  | 1     | APB write control |
| `paddr`    | Input  | 12    | APB address (4 KB space) |
| `pwdata`   | Input  | 32    | APB write data |
| `prdata`   | Output | 32    | APB read data |
| `pready`   | Output | 1     | APB ready response |
| `pslverr`  | Output | 1     | APB slave error |

### AXI4 Master Interface (DMA Transfers)

The AXI4 master interface is used for high-speed data block transfers between the QSPI flash and system memory (e.g., DRAM). The controller autonomously generates AXI4 transactions for read/write, minimizing CPU overhead.

| Signal           | Dir    | Width | Description |
|------------------|--------|-------|-------------|
| `m_axi_aclk`     | Input  | 1     | AXI master clock |
| `m_axi_aresetn`  | Input  | 1     | AXI master active-low reset |
| `m_axi_awaddr`   | Output | 32    | Write address |
| `m_axi_awlen`    | Output | 8     | Burst length |
| `m_axi_awsize`   | Output | 3     | Burst size |
| `m_axi_awburst`  | Output | 2     | Burst type |
| `m_axi_awvalid`  | Output | 1     | Write address valid |
| `m_axi_awready`  | Input  | 1     | Write address ready |
| `m_axi_wdata`    | Output | 32/64 | Write data |
| `m_axi_wstrb`    | Output | 4/8   | Write strobes |
| `m_axi_wlast`    | Output | 1     | Last write transfer |
| `m_axi_wvalid`   | Output | 1     | Write data valid |
| `m_axi_wready`   | Input  | 1     | Write data ready |
| `m_axi_bresp`    | Input  | 2     | Write response |
| `m_axi_bvalid`   | Input  | 1     | Write response valid |
| `m_axi_bready`   | Output | 1     | Write response ready |
| `m_axi_araddr`   | Output | 32    | Read address |
| `m_axi_arlen`    | Output | 8     | Burst length |
| `m_axi_arsize`   | Output | 3     | Burst size |
| `m_axi_arburst`  | Output | 2     | Burst type |
| `m_axi_arvalid`  | Output | 1     | Read address valid |
| `m_axi_arready`  | Input  | 1     | Read address ready |
| `m_axi_rdata`    | Input  | 32/64 | Read data |
| `m_axi_rresp`    | Input  | 2     | Read response |
| `m_axi_rlast`    | Input  | 1     | Last read transfer |
| `m_axi_rvalid`   | Input  | 1     | Read data valid |
| `m_axi_rready`   | Output | 1     | Read data ready |

### AXI4 Slave Interface (XIP Mode)

The AXI4 slave interface enables **Execute-In-Place (XIP)** functionality, where the system processor can directly fetch instructions or access data from flash memory as if it were regular memory-mapped space.

| Signal          | Dir    | Width | Description |
|-----------------|--------|-------|-------------|
| `s_axi_aclk`    | Input  | 1     | AXI slave clock |
| `s_axi_aresetn` | Input  | 1     | AXI slave active-low reset |
| `s_axi_araddr`  | Input  | 32    | Read address from CPU/SoC |
| `s_axi_arlen`   | Input  | 8     | Burst length |
| `s_axi_arsize`  | Input  | 3     | Burst size |
| `s_axi_arburst` | Input  | 2     | Burst type |
| `s_axi_arvalid` | Input  | 1     | Read address valid |
| `s_axi_arready` | Output | 1     | Read address ready |
| `s_axi_rdata`   | Output | 32/64 | Read data from flash |
| `s_axi_rresp`   | Output | 2     | Read response |
| `s_axi_rlast`   | Output | 1     | Last read transfer |
| `s_axi_rvalid`  | Output | 1     | Read data valid |
| `s_axi_rready`  | Input  | 1     | Read data ready |

### QSPI Flash Interface

This is the physical interface connecting directly to the external QSPI flash device. It includes the serial clock (`sclk`), chip select (`cs_n`), data lines (`io0–io3`), and optional control pins (`hold_n`, `wp_n`). It supports standard, dual, and quad modes for flexible performance trade-offs.

| Signal       | Dir   | Width | Description |
|--------------|-------|-------|-------------|
| `qspi_cs_n`  | Output| 1     | Chip select (active low) |
| `qspi_sck`   | Output| 1     | Serial clock |
| `qspi_io0`   | InOut | 1     | Data line 0 / MOSI |
| `qspi_io1`   | InOut | 1     | Data line 1 / MISO |
| `qspi_io2`   | InOut | 1     | Data line 2 |
| `qspi_io3`   | InOut | 1     | Data line 3 |

---

## Register Map

The QSPI Controller register map provides access to control, status, DMA, XIP, and FIFO registers via the **APB slave interface**. All registers are **32-bit aligned** with a **4 KB address space**.

| Offset | Register   | Bits   | Field Name        | Access | Description                                      | Default |
|--------|------------|--------|-------------------|--------|--------------------------------------------------|---------|
| 0x000  | ID         | 31:16  | VENDOR_ID         | RO     | Vendor ID (e.g., 0x0A10)                         | -       |
|        |            | 15:8   | DEVICE_ID         | RO     | Device ID (e.g., 0x01)                           | -       |
|        |            | 7:0    | VERSION           | RO     | Version (e.g., 0x01)                             | -       |
| 0x004  | CTRL       | 0      | ENABLE            | RW     | Enable controller                                | 0       |
|        |            | 1      | XIP_EN            | RW     | Enable XIP mode                                  | 0       |
|        |            | 2      | QUAD_EN           | RW     | Enable quad mode                                 | 0       |
|        |            | 3      | CPOL              | RW     | Clock polarity (0: idle low)                     | 0       |
|        |            | 4      | CPHA              | RW     | Clock phase (0: sample first edge)               | 0       |
|        |            | 5      | LSB_FIRST         | RW     | Bit order (1: LSB first)                         | 0       |
|        |            | 8      | CMD_TRIGGER       | RW     | Start Command mode (self-clear)                  | 0       |
|        |            | 9      | DMA_EN            | RW     | Enable DMA for Command mode                      | 0       |
| 0x008  | STATUS     | 0      | BUSY              | RO     | Operation in progress                            | -       |
|        |            | 1      | XIP_ACTIVE        | RO     | XIP mode active                                  | -       |
|        |            | 2      | CMD_DONE          | RO     | Command completed                                | -       |
|        |            | 3      | DMA_DONE          | RO     | DMA completed                                    | -       |
| 0x00C  | INT_EN     | 0      | CMD_DONE_EN       | RW     | Interrupt on CMD done                            | 0       |
|        |            | 1      | DMA_DONE_EN       | RW     | Interrupt on DMA done                            | 0       |
|        |            | 2      | ERR_EN            | RW     | Interrupt on error                               | 0       |
|        |            | 3      | FIFO_TX_EMPTY_EN  | RW     | Interrupt on TX FIFO empty                       | 0       |
|        |            | 4      | FIFO_RX_FULL_EN   | RW     | Interrupt on RX FIFO full                        | 0       |
| 0x010  | INT_STAT   | 0      | CMD_DONE          | RW1C   | Command completed (write 1 to clear)             | -       |
|        |            | 1      | DMA_DONE          | RW1C   | DMA completed (write 1 to clear)                 | -       |
|        |            | 2      | ERR               | RW1C   | Error occurred (write 1 to clear)                 | -       |
|        |            | 3      | FIFO_TX_EMPTY     | RW1C   | TX FIFO empty (write 1 to clear)                  | -       |
|        |            | 4      | FIFO_RX_FULL      | RW1C   | RX FIFO full (write 1 to clear)                   | -       |
| 0x014  | CLK_DIV    | 7:0    | DIV               | RW     | Clock divider value (0–255)                       | 0       |
| 0x018  | CS_CTRL    | 0      | CS_AUTO           | RW     | Automatic CS# control                             | 0       |
|        |            | 1      | CS_LEVEL          | RW     | Manual CS# level                                  | 0       |
|        |            | 3:2    | CS_DELAY          | RW     | CS# delay cycles                                  | 0       |
| 0x01C  | XIP_CFG    | 1:0    | CMD_LANES         | RW     | Command lanes (0: S, 1: D, 2: Q)                  | 0       |
|        |            | 3:2    | ADDR_LANES        | RW     | Address lanes                                     | 0       |
|        |            | 5:4    | DATA_LANES        | RW     | Data lanes                                        | 0       |
|        |            | 7:6    | ADDR_BYTES        | RW     | Address bytes                                     | 0       |
|        |            | 8      | MODE_EN           | RW     | Enable mode bits                                  | 0       |
|        |            | 12:9   | DUMMY_CYCLES      | RW     | Dummy cycles                                      | 0       |
|        |            | 13     | CONT_READ         | RW     | Continuous read                                   | 0       |
|        |            | 14     | WRITE_EN          | RW     | Allow writes in XIP                               | 0       |
| 0x020  | XIP_CMD    | 7:0    | READ_OP           | RW     | Read opcode                                       | 0       |
|        |            | 15:8   | WRITE_OP          | RW     | Write opcode                                      | 0       |
|        |            | 23:16  | MODE_BITS         | RW     | Mode bits after address                           | 0       |
| 0x024  | CMD_CFG    | 1:0    | CMD_LANES         | RW     | Command lanes                                     | 0       |
|        |            | 3:2    | ADDR_LANES        | RW     | Address lanes                                     | 0       |
|        |            | 5:4    | DATA_LANES        | RW     | Data lanes                                        | 0       |
|        |            | 7:6    | ADDR_BYTES        | RW     | Address bytes                                     | 0       |
|        |            | 8      | MODE_EN           | RW     | Enable mode bits                                  | 0       |
|        |            | 12:9   | DUMMY_CYCLES      | RW     | Dummy cycles                                      | 0       |
|        |            | 13     | DIR               | RW     | Direction (0: write, 1: read)                     | 0       |
| 0x028  | CMD_OP     | 7:0    | OPCODE            | RW     | Command opcode                                    | 0       |
|        |            | 15:8   | MODE_BITS         | RW     | Mode bits (if enabled)                            | 0       |
| 0x02C  | CMD_ADDR   | 31:0   | ADDR              | RW     | Flash address                                     | 0       |
| 0x030  | CMD_LEN    | 31:0   | LEN               | RW     | Number of bytes in data phase                     | 0       |
| 0x034  | CMD_DUMMY  | 7:0    | EXTRA_DUMMY       | RW     | Extra dummy cycles                                | 0       |
| 0x038  | DMA_CFG    | 3:0    | BURST_SIZE        | RW     | Burst length (0:1, 1:2, ..., 4:16)                 | 0       |
|        |            | 4      | DIR               | RW     | DMA direction (0: write to flash, 1: read)         | 0       |
|        |            | 5      | INCR_ADDR         | RW     | Increment DRAM address                            | 0       |
| 0x03C  | DMA_ADDR   | 31:0   | ADDR              | RW     | DRAM start address                                 | 0       |
| 0x040  | DMA_LEN    | 31:0   | LEN               | RW     | Number of bytes to transfer                        | 0       |
| 0x044  | FIFO_TX    | 31:0   | DATA              | WO     | Write data (byte-packed)                           | -       |
| 0x048  | FIFO_RX    | 31:0   | DATA              | RO     | Read data (byte-packed)                            | -       |
| 0x04C  | FIFO_STAT  | 3:0    | TX_LEVEL          | RO     | TX FIFO level (0–16)                               | -       |
|        |            | 7:4    | RX_LEVEL          | RO     | RX FIFO level (0–16)                               | -       |
|        |            | 8      | TX_EMPTY          | RO     | TX FIFO empty                                      | -       |
|        |            | 9      | RX_FULL           | RO     | RX FIFO full                                       | -       |
| 0x050  | ERR_STAT   | 0      | TIMEOUT           | RO     | Transaction timeout                                | -       |
|        |            | 1      | OVERRUN           | RO     | RX FIFO overrun                                    | -       |
|        |            | 2      | UNDERRUN          | RO     | TX FIFO underrun                                   | -       |
|        |            | 3      | AXI_ERR           | RO     | AXI bus error                                      | -       |

**Notes:**
- **RO**: Read-Only  
- **WO**: Write-Only  
- **RW**: Read/Write  
- **RW1C**: Read/Write 1 to Clear  
- **Reserved bits** must return 0 on read and be ignored on write.

---

## Typical Operation

- **Command Mode**: CPU sets command registers via APB, triggers execution. Data via FIFO or DMA.
- **DMA Mode**: DMA engine transfers data blocks via AXI master.
- **XIP Mode**: CPU fetches instructions/data directly from flash via AXI slave.
- **Interrupts**: signals completion, FIFO events, or errors.

---

## Directory Structure

```directory file
 qspi/
├── LICENSE
├── Makefile
├── NguyenBaotinh_QSPI_Controller_IP.png
├── README.md
└── RTL/
    ├── csr.v
    ├── tx_fifo.v
    ├── rx_fifo.v
    ├── qpsi_fsm.v
    ├── qpsi_controller_ip.v    
    └── tb_qspi_controller_ip.v
 
```
---

## Build & Simulation Guide

### Prerequisites

- Verilog simulator (Icarus, Verilator, ModelSim, or VCS).
- GTKWave for waveform viewing (optional).

### Run Simulation

```bash
make run
make wave
```

---

## Verification

Testbench includes:

- Basic command mode tests (read/write/erase).

- DMA transfer validation.

- XIP memory-mapped read test.

- FIFO functionality tests.

---

## Limitations

- Current version does not support XIP write (requires SUPPORT_XIP_WRITE = 1).

- Limited AXI burst length (default max 16).

- Advanced power management features may be simplified.

---

## Authors

- **Bảo Tính Nguyễn** – RTL Developer – [nbtinh2002@gmail.com](mailto:nbtinh2002@gmail.com)  
- **Mr. Quang Le** – Technical Support  
- **Thái Hải Đăng** – Project Collaborator / Support  
- **VNCHIP TRAINING PROGRAM 2025 – Final Lab**
## License

This project is licensed under the **MIT License** – see the [LICENSE](LICENSE) file for details.
