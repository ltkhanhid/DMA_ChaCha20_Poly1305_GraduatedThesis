# SoC Architecture with UART as Independent Crossbar Slave

## Memory Map

| Address Range           | Description           | Module            |
|-------------------------|-----------------------|-------------------|
| 0x0000_0000 - 0x0000_FFFF | Data Memory (64KB)   | tlul_adapter_mem  |
| 0x1000_0000 - 0x1000_0FFF | GPIO/LED/HEX         | tlul_adapter_peri |
| 0x1001_0000 - 0x1001_00FF | UART Registers       | tlul_uart_bridge  |

## UART Register Map (Base: 0x1001_0000)

| Offset | Register    | R/W | Description                                    |
|--------|-------------|-----|------------------------------------------------|
| 0x00   | TX_DATA     | W   | Transmit data buffer (byte)                    |
| 0x04   | RX_DATA     | R   | Receive data buffer (byte)                     |
| 0x08   | STATUS      | R   | [0]=TX_BUSY, [1]=RX_VALID, [2]=TX_DONE, [3]=RX_ERROR |
| 0x0C   | CONTROL     | R/W | [1:0]=BAUD_SEL (00=9600, 01=19200, 10=38400, 11=115200) |
| 0x10   | TX_START    | W   | Write any value to start TX                    |

## Architecture Diagram

```
                              ┌─────────────────────────────────────┐
                              │           SOC_TOP                   │
                              │                                     │
    ┌─────────────┐           │  ┌──────────────┐                   │
    │  RISC-V     │           │  │ tlul_xbar_3s │                   │
    │   CPU       │           │  │  (Crossbar)  │                   │
    │             │           │  │              │                   │
    │   ┌─────┐   │           │  │  ┌────────┐  │    ┌────────────┐ │
    │   │ LSU │───┼───────────┼──┼──│Slave 0 │──┼────│tlul_adapter│ │
    │   └─────┘   │           │  │  │  MEM   │  │    │   _mem     │ │
    │             │  TL-UL    │  │  └────────┘  │    │  (DMEM)    │ │
    │   Host      │  Bus      │  │              │    └────────────┘ │
    │   Adapter   │           │  │  ┌────────┐  │    ┌────────────┐ │
    │             │           │  │  │Slave 1 │──┼────│tlul_adapter│ │
    └─────────────┘           │  │  │  PERI  │  │    │   _peri    │──── LED/HEX/SW
                              │  │  └────────┘  │    └────────────┘ │
                              │  │              │                   │
                              │  │  ┌────────┐  │    ┌────────────┐ │
                              │  │  │Slave 2 │──┼────│tlul_uart   │──── UART TX/RX
                              │  │  │  UART  │  │    │  _bridge   │ │
                              │  │  └────────┘  │    └────────────┘ │
                              │  │              │                   │
                              │  └──────────────┘                   │
                              │                                     │
                              └─────────────────────────────────────┘
```

## Files Modified/Created

### New Files:
- `tlul_xbar_3s.sv` - 3-slave crossbar (MEM, PERI, UART)
- `tlul_uart_bridge.sv` - TileLink-UL to UART bridge

### Modified Files:
- `soc_top.sv` - Updated to use 3-slave crossbar
- `tlul_adapter_peri.sv` - Simplified (UART removed)
- `Makefile` - Added new files to compilation

### Existing UART Files:
- `uart_byte_tx.sv` - UART transmitter
- `uart_byte_rx.sv` - UART receiver

## Address Decode Logic (tlul_xbar_3s.sv)

```systemverilog
// Priority: UART checked before PERI (UART is subset of extended PERI range)
if ((address >= 0x0000_0000) && (address < 0x0001_0000))
    addr_sel = SEL_MEM;     // Memory: 0x0000_xxxx
else if ((address >= 0x1001_0000) && (address < 0x1001_0100))
    addr_sel = SEL_UART;    // UART: 0x1001_0000 - 0x1001_00FF
else if ((address >= 0x1000_0000) && (address < 0x1001_0000))
    addr_sel = SEL_PERI;    // Peripheral: 0x1000_0000 - 0x1000_FFFF
else
    addr_sel = SEL_ERROR;   // Invalid address
```

## Test Results

All 26 tests PASSED:
- Memory word write/read
- Byte access
- Peripheral (LED) access
- Invalid address handling
- Back-to-back transactions
