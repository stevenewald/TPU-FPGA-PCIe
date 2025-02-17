`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/23/2025 03:34:12 PM
// Design Name: 
// Module Name: axi_stim
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import axi_vip_pkg::*;
import design_2_axi_vip_0_0_pkg::*;
import design_2_axi_vip_1_0_pkg::*;

module axi_stim();

design_2_axi_vip_0_0_passthrough_t  pt_agent;
design_2_axi_vip_1_0_mst_t  mst_agent;


  axi_transaction                                          wr_trans;            // Write transaction
  axi_transaction                                          rd_trans;            // Read transaction
  xil_axi_uint                                             mtestWID;            // Write ID  
  xil_axi_ulong                                            mtestWADDR;          // Write ADDR  
  xil_axi_len_t                                            mtestWBurstLength;   // Write Burst Length   
  xil_axi_size_t                                           mtestWDataSize;      // Write SIZE  
  xil_axi_burst_t                                          mtestWBurstType;     // Write Burst Type  
  xil_axi_uint                                             mtestRID;            // Read ID  
  xil_axi_ulong                                            mtestRADDR;          // Read ADDR  
  xil_axi_len_t                                            mtestRBurstLength;   // Read Burst Length   
  xil_axi_size_t                                           mtestRDataSize;      // Read SIZE  
  xil_axi_burst_t                                          mtestRBurstType;     // Read Burst Type  

  xil_axi_data_beat [255:0]                                mtestWUSER;         // Write user  
  xil_axi_data_beat                                        mtestAWUSER;        // Write Awuser 
  xil_axi_data_beat                                        mtestARUSER;        // Read Aruser 

  bit [31:0]                                               mtestWData;         // Write Data
  bit[8*4096-1:0]                                          Rdatablock;        // Read data block
  xil_axi_data_beat                                        Rdatabeat[];       // Read data beats
  bit[8*4096-1:0]                                          Wdatablock;        // Write data block
  xil_axi_data_beat                                        Wdatabeat[];       // Write data beats
  bit [31:0] read_data;
  
  
  initial begin
  
  pt_agent = new("passthrough vip agent",dut.design_2_i.axi_vip_0.inst.IF);
  pt_agent.start_monitor(); 
  
  mst_agent = new("master vip agent",dut.design_2_i.axi_vip_1.inst.IF);
  mst_agent.start_master(); 
  
  for(int i = 0; i < 50; i++) begin
      mtestWID = $urandom_range(0,(1<<(0)-1)); 
      mtestWADDR = 64'h4 + i*4;
      mtestWBurstLength = 0;
      mtestWDataSize = xil_axi_size_t'(xil_clog2((32)/8));
      mtestWBurstType = XIL_AXI_BURST_TYPE_INCR;
      mtestWData = 32'd1 * (i+1);
      
      wr_trans = mst_agent.wr_driver.create_transaction("write transaction");
      wr_trans.set_write_cmd(mtestWADDR,mtestWBurstType,mtestWID,
                                   mtestWBurstLength,mtestWDataSize);
      wr_trans.set_data_block(mtestWData);
      mst_agent.wr_driver.send(wr_trans);
  end
  
  mtestWID = $urandom_range(0,(1<<(0)-1)); 
  mtestWADDR = 64'h0;
  mtestWBurstLength = 0;
  mtestWDataSize = xil_axi_size_t'(xil_clog2((32)/8));
  mtestWBurstType = XIL_AXI_BURST_TYPE_INCR;
  mtestWData = 32'd5;
  
  wr_trans = mst_agent.wr_driver.create_transaction("write transaction");
  wr_trans.set_write_cmd(mtestWADDR,mtestWBurstType,mtestWID,
                               mtestWBurstLength,mtestWDataSize);
  wr_trans.set_data_block(mtestWData);
  mst_agent.wr_driver.send(wr_trans);

  mst_agent.wait_drivers_idle(); 
  
  #20000
  $display("STARTING AGAIN");
  mtestWID = $urandom_range(0,(1<<(0)-1)); 
  mtestWADDR = 64'h0;
  mtestWBurstLength = 0;
  mtestWDataSize = xil_axi_size_t'(xil_clog2((32)/8));
  mtestWBurstType = XIL_AXI_BURST_TYPE_INCR;
  mtestWData = 32'd5;
  
  wr_trans = mst_agent.wr_driver.create_transaction("write transaction");
  wr_trans.set_write_cmd(mtestWADDR,mtestWBurstType,mtestWID,
                               mtestWBurstLength,mtestWDataSize);
  wr_trans.set_data_block(mtestWData);
  mst_agent.wr_driver.send(wr_trans);

  mst_agent.wait_drivers_idle(); 
  
  #1000000
  /*
  $display ("Sending read");
    mtestRID = $urandom_range(0,(1<<(0)-1)); 
    mtestRADDR = 64'hc;
    mtestRBurstLength = 0;
    mtestRDataSize = xil_axi_size_t'(xil_clog2((32)/8));
    mtestRBurstType = XIL_AXI_BURST_TYPE_INCR;
    
    rd_trans = mst_agent.rd_driver.create_transaction("read transaction");
    rd_trans.set_read_cmd(mtestRADDR,mtestRBurstType,mtestRID,
    mtestRBurstLength,mtestRDataSize);
    rd_trans.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
    mst_agent.rd_driver.send(rd_trans);
    mst_agent.rd_driver.wait_rsp(rd_trans);
    Rdatablock = rd_trans.get_data_block();
    assert(Rdatablock[31:0]==32'h1c4) else $fatal("Unexpected mutliplication result");
    
    $display("Product: %x\n", Rdatablock[31:0]);
    
    $display ("Sending read");
    mtestRID = $urandom_range(0,(1<<(0)-1)); 
    mtestRADDR = 64'h10;
    mtestRBurstLength = 0;
    mtestRDataSize = xil_axi_size_t'(xil_clog2((32)/8));
    mtestRBurstType = XIL_AXI_BURST_TYPE_INCR;
    
    rd_trans = mst_agent.rd_driver.create_transaction("read transaction");
    rd_trans.set_read_cmd(mtestRADDR,mtestRBurstType,mtestRID,
    mtestRBurstLength,mtestRDataSize);
    rd_trans.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
    mst_agent.rd_driver.send(rd_trans);
    mst_agent.rd_driver.wait_rsp(rd_trans);
    Rdatablock = rd_trans.get_data_block();
    assert(Rdatablock[31:0]==32'h0) else $fatal("Status register not reset");
    
*/

  $display("TEST DONE : Test Completed Successfully");
  $finish;
  end  
endmodule