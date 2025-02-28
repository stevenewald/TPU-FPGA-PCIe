`timescale 1ns / 1ps
`include "memory_states.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/10/2025 04:25:02 PM
// Design Name: 
// Module Name: matrix_memory_handle
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


module matrix_memory_handle #(
    parameter STATUS_ADDR = 32'h0
    ) (
    output reg axi_start,
    output reg axi_write,
    output reg [31:0] axi_addr,
    output reg [AXI_MAX_WRITE_BURST_LEN-1:0][31:0] axi_write_data,
    output reg [7:0] axi_num_writes,
    input wire [AXI_MAX_READ_BURST_LEN-1:0][31:0] axi_read_data,
    output reg [7:0] axi_num_reads,
    input wire axi_write_done,
    input wire [1:0] axi_read_done,
    input wire axi_read_ready,
    
    output reg msi_interrupt_req,
    input wire msi_interrupt_ack,
    
    input wire clk,
    input wire rstn,
    
    input wire [MATRIX_NUM_NBITS-1:0] matrix_num,
    input wire [TILE_NUM_ELEMENTS-1:0][31:0] matrix_write_data,
    output reg [TILE_NUM_ELEMENTS-1:0][15:0] matrix_read_data,
    output reg [31:0] status_read_data,
    input wire [2:0] command,
    output reg matrix_done
    );
    
    reg [2:0] state;
    
    reg rip;
    
    // /2 because packed matrices
    wire [31:0] matrix_offset = 2*TILE_NUM_ELEMENTS*matrix_num + 4; //+1 for status_addr
    
    wire [TILE_NUM_ELEMENTS-1:0][15:0] matrix_tmp_rdata;
    
    genvar i;
    generate
        for (i = 0; i < TILE_NUM_ELEMENTS/2; i++) begin
            assign matrix_tmp_rdata[2*i] = axi_read_data[i][15:0];
            assign matrix_tmp_rdata[2*i+1] = axi_read_data[i][31:16];
        end
    endgenerate
    
   
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            msi_interrupt_req <= 0;
            axi_start <= 0;
            axi_write <= 0;
            axi_addr <= 0;
            matrix_read_data <= 0;
            axi_num_reads <= 0;
            matrix_done <= 0;
            state <= MHS_IDLE;
            status_read_data <= 0;
            axi_num_writes <= 0;
            axi_write_data <= 0;
            rip <= 0;
        end else begin
            axi_start <= 0;
            case (state)
                MHS_IDLE: begin
                    if(matrix_done) begin
                        // Give time for higher level module to process done signal
                        // Can maybe remove?
                        matrix_done <= 0;
                    end else begin
                        state <= command;
                    end
                end
                MHS_READ_STATUS: begin
                    if(axi_read_done[0]) begin
                        status_read_data <= axi_read_data[0];
                        matrix_done <= 1;
                        axi_start <= 0;
                        state <= MHS_IDLE;
                        rip <= 0;
                    end else if(axi_read_ready && !rip) begin
                        axi_addr <= STATUS_ADDR;
                        axi_num_reads <= 1;
                        axi_write <= 0;
                        axi_start <= 1;
                        rip <= 1;
                    end
                end
                MHS_READ_MATRIX: begin
                    if(axi_read_done[0]) begin
                        matrix_read_data <= matrix_tmp_rdata;
                        state <= MHS_IDLE;
                        matrix_done <= 1;
                        axi_start <= 0;
                        rip <= 0;
                    end else if(axi_read_ready && !rip) begin
                        axi_num_reads <= TILE_NUM_ELEMENTS/2;
                        axi_start <= 1;
                        axi_addr <= matrix_offset;
                        axi_write <= 0;
                        rip <= 1;
                    end
                end
                MHS_WRITE_RESULT: begin
                    if(axi_write_done) begin
                        state <= MHS_IDLE;
                        matrix_done <= 1;
                        axi_write <= 0;
                        axi_start <= 0;
                    end else begin
                        axi_num_writes <= TILE_NUM_ELEMENTS;
                        axi_start <= 1;
                        axi_write <= 1;
                        axi_write_data <= matrix_write_data;
                        axi_addr <= matrix_offset;
                    end
                end
                MHS_INTERRUPT: begin
                    if(msi_interrupt_req && msi_interrupt_ack) begin
                        msi_interrupt_req <= 1'b0;
                        matrix_done <= 1;
                        state <= MHS_IDLE;
                    end else begin
                        msi_interrupt_req <= 1'b1;
                    end
                end
                MHS_RESET_STATUS: begin
                    if(axi_write_done) begin
                        axi_start <= 0;
                        state <= MHS_IDLE;
                        matrix_done <= 1;
                        axi_write <= 0;
                    end else begin
                        axi_addr <= STATUS_ADDR;
                        axi_num_writes <= 1;
                        axi_write_data[0] <= 0;
                        axi_write <= 1;
                        axi_start <= 1;
                    end
                end
            endcase
        end
    end
endmodule
