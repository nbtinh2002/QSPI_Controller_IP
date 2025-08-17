# QSPI Controller IP

## Overview

The **Quad Serial Peripheral Interface (QSPI) Controller** is a high-performance IP core designed to interface with serial NOR flash memories using **single, dual, and quad SPI protocols**.  
It supports **command-based access**, **DMA transfers**, and **XIP (Execute-In-Place) mode**, enabling efficient boot, firmware update, and high-speed data transactions in SoC and FPGA designs.

The controller provides:

- **APB slave interface** for configuration and control registers (CSR)  
- **AXI4 master interface** for DMA operations to/from system memory  
- **AXI4 slave interface** for memory-mapped XIP access  
- **QSPI I/O interface** for direct communication with flash devices  

Integrated **TX/RX FIFOs** decouple system bus and QSPI flash speeds, allowing flexible operation under various performance requirements.  

---

## Key Features

- **Multi-Mode QSPI Flash Support**
  - Standard SPI (1-1-1), Dual SPI (1-1-2), Quad SPI (1-1-4 / 1-4-4)  
  - Configurable **opcode, address, mode bits, and dummy cycles**  
  - Supports common flash commands: **Read, Fast Read, Page Program, Erase**

- **Flexible System Integration**
  - **APB Slave** for CSR access and FIFO read/write in non-DMA mode  
  - **AXI4 Master** for high-speed **DMA transfers** between Flash and DRAM  
  - **AXI4 Slave** for **XIP (Execute-In-Place)** memory-mapped flash access

- **High-Performance Data Transfers**
  - **TX/RX FIFOs** to buffer data and handle speed mismatch  
  - **Configurable burst length** for DMA to improve throughput  
  - **Quad SPI mode** to maximize read performance

- **Command Engine (CE)**
  - Automates opcode, address, dummy, and data phases  
  - Supports **CPU-driven** and **DMA-driven** transfers  
  - Provides **BUSY/DONE flags** for software polling

- **DMA Engine (AXI Master)**
  - Automatic data movement between FIFO and system memory  
  - Supports **block read/write with INCR bursts**  
  - Offloads CPU for large transfers

- **XIP Mode (AXI Slave)**
  - Execute code directly from external QSPI flash  
  - Handles fast-read with dummy cycles and optional mode bits  
  - Transparent AXI read → QSPI transaction translation

- **FIFO Management**
  - **Separate TX and RX FIFOs** (default 16B depth)  
  - Exposes **empty/full/level flags** to CSR  
  - Supports **polling or interrupt-driven** data handling

- **Interrupts and Error Handling**
  - CMD_DONE, DMA_DONE, FIFO events, and error flags  
  - **RW1C interrupt status register** for easy software clear  
  - Detects **FIFO overrun/underrun**, **AXI errors**, and **timeout conditions**

---

## System Architecture

---

## Interface Description

### 1. APB Slave Interface (Configuration & Control)
The APB slave interface is used for **configuration and status monitoring** of the QSPI Controller.  
The CPU or system control block accesses the **Control/Status Registers (CSR)** through APB to:
- Configure operating modes (SPI/Dual/Quad, XIP, DMA, etc.)
- Read status flags (BUSY/DONE, FIFO level, errors)
- Write data into the TX FIFO or read data from the RX FIFO (in non-DMA mode)

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

---

### 2. AXI4 Master Interface (DMA Transfers)
The AXI4 master interface enables the QSPI Controller to **directly access system memory (e.g., DRAM)** for large block transfers via the internal DMA engine.  
This offloads the CPU by handling high-throughput data movement with burst support for optimal bandwidth.

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

---

### 3. AXI4 Slave Interface (XIP Mode)
The AXI4 slave interface allows the CPU or system bus masters to **execute code directly from external QSPI flash** (XIP mode) or read data in a memory-mapped fashion.  
The controller translates AXI read requests into QSPI transactions transparently.

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

---

### 4. QSPI Flash Interface
This interface connects directly to the external QSPI NOR flash device.  
It supports **single, dual, and quad data lines** for command, address, and data phases.

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

The QSPI Controller operates through several modes depending on system requirements:

1. **Register Configuration (APB Interface)**  
   - The CPU configures the controller via the APB slave interface.  
   - Control registers define the flash command, addressing mode, data width (1/2/4 lines), clock frequency, and DMA/XIP enable.  

2. **Command Execution**  
   - In **manual mode**, the CPU issues a command (e.g., READ, PAGE PROGRAM, ERASE) and transfers data via the APB data registers or FIFOs.  
   - In **DMA mode**, the DMA engine uses the AXI4 master interface to fetch/store data directly to/from system memory without CPU intervention.

3. **Execute-In-Place (XIP)**  
   - In XIP mode, the AXI4 slave interface exposes the QSPI flash as a memory-mapped region to the CPU or other masters.  
   - Instruction fetches and data reads are transparently converted into QSPI transactions.

4. **Interrupt Handling**  
   - The controller can signal completion, errors, or FIFO thresholds via the `irq` output, allowing event-driven firmware operation.

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

## Authors

- **Bảo Tính Nguyễn** – RTL Developer – [nbtinh2002@gmail.com](mailto:nbtinh2002@gmail.com)  
- **Mr. Quang Le** – Technical Support  
- **VNCHIP TRAINING PROGRAM 2025 – Final Lab**
## License

This project is licensed under the **MIT License** – see the [LICENSE](LICENSE) file for details.
