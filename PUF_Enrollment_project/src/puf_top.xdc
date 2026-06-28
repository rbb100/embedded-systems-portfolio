## Clock
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { clk_125mhz }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clk_125mhz }];

## Reset
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { btn_rst }];

## LEDs
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];

## JB UART PMOD
## PMOD TXD -> FPGA uart_rx
set_property -dict { PACKAGE_PIN V20   IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];

## FPGA uart_tx -> PMOD RXD
set_property -dict { PACKAGE_PIN U20   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

## Optional handshake lines, unused for now
# set_property -dict { PACKAGE_PIN T20   IOSTANDARD LVCMOS33 } [get_ports { rts }];
# set_property -dict { PACKAGE_PIN W20   IOSTANDARD LVCMOS33 } [get_ports { cts }];