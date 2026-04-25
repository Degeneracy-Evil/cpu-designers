/*
!注意：接口仅供参考，gpio_io宽度可调
*/

// (c) Copyright 1995-2026 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
// DO NOT MODIFY THIS FILE.

// IP VLNV: Asyncsys:bus:bus4LZU:1.0
// IP Revision: 4

// The following must be inserted into your Verilog file for this
// core to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
bus4LZU_0 your_instance_name (
  .clk(clk),                    // input wire clk
  .rstn(rstn),                  // input wire rstn
  .rx(rx),                      // input wire rx
  .tx(tx),                      // output wire tx
  .timer_iqr(timer_iqr),        // output wire timer_iqr
  .init_sig(init_sig),          // output wire init_sig
  .spi_miso(spi_miso),          // input wire spi_miso
  .spi_mosi(spi_mosi),          // output wire spi_mosi
  .spi_ss(spi_ss),              // output wire spi_ss
  .spi_clk(spi_clk),            // output wire spi_clk
  .gpio_io(gpio_io),            // inout wire [15 : 0] gpio_io
  .instAddr_32(instAddr_32),    // input wire [31 : 0] instAddr_32
  .instData_32(instData_32),    // output wire [31 : 0] instData_32
  .dataWen_4(dataWen_4),        // input wire [3 : 0] dataWen_4
  .dataAddr_32(dataAddr_32),    // input wire [31 : 0] dataAddr_32
  .writeData_32(writeData_32),  // input wire [31 : 0] writeData_32
  .readData_32(readData_32)    // output wire [31 : 0] readData_32
);
// INST_TAG_END ------ End INSTANTIATION Template ---------

