## ============================================================
## Trusted Sensor Validation Console - Shared Sensor Port Version
## Board: Zybo old / Rev B
## Top: trusted_sensor_console_final_hw
##
## KYPD PMOD -> JA
## OLED PMOD -> JD
## Sensor Port -> JB
##
## Supported on JB:
##   ALS  normal top-row placement
##   TMP3 shifted-right placement
## ============================================================


## ============================================================
## Clock: 125 MHz
## ============================================================
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4} [get_ports { clk }]


## ============================================================
## Reset button BTN0
## ============================================================
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { rst_btn }]


## ============================================================
## Board LEDs
## ============================================================
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]


## ============================================================
## KYPD on JA
## ============================================================
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports { kypd_col[0] }]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports { kypd_col[1] }]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { kypd_col[2] }]
set_property -dict { PACKAGE_PIN K14 IOSTANDARD LVCMOS33 } [get_ports { kypd_col[3] }]

set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { kypd_row[0] }]
set_property -dict { PACKAGE_PIN L15 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { kypd_row[1] }]
set_property -dict { PACKAGE_PIN J16 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { kypd_row[2] }]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { kypd_row[3] }]


## ============================================================
## OLED on JD
## ============================================================
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { oled_cs   }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { oled_sdin }]
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports { oled_sclk }]

set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { oled_dc   }]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports { oled_res  }]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { oled_vbat }]
set_property -dict { PACKAGE_PIN V18 IOSTANDARD LVCMOS33 } [get_ports { oled_vdd  }]


## ============================================================
## Shared Sensor Port on JB
##
## Correct JB top-row mapping:
## JB1 = T20
## JB2 = U20
## JB3 = V20
## JB4 = W20
##
## ALS on JB:
##   ALS pin 1 ~CS   -> JB1
##   ALS pin 3 MISO  -> JB3
##   ALS pin 4 SCLK  -> JB4
##   ALS pin 5 GND   -> JB5
##   ALS pin 6 VCC   -> JB6
##
## TMP3 on JB shifted-right:
##   JB1 empty
##   JB2 empty
##   TMP3 SCL -> JB3
##   TMP3 SDA -> JB4
##   TMP3 GND -> JB5
##   TMP3 3V3 -> JB6
## ============================================================

set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports { sensor_jb1_cs }]
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sensor_jb3_scl_miso }]
set_property -dict { PACKAGE_PIN W20 IOSTANDARD LVCMOS33 PULLUP true } [get_ports { sensor_jb4_sda_sclk }]