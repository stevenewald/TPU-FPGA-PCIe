`timescale 1ns / 1ps
`include "memory_states.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/26/2025 01:13:49 PM
// Design Name: 
// Module Name: matrix_num_calculator
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


module matrix_num_calculator(
    input wire arstn,
    input wire aclk,
    input wire increment,
    input wire [BITS_PER_TILE_CNT-1:0] m_tiles,
    input wire [BITS_PER_TILE_CNT-1:0] k_tiles,
    input wire [BITS_PER_TILE_CNT-1:0] n_tiles,
    output reg [MATRIX_NUM_NBITS-1:0] matrix_num_a_prev,
    output reg [MATRIX_NUM_NBITS-1:0] matrix_num_b_prev,
    output reg [MATRIX_NUM_NBITS-1:0] matrix_num_result_prev,
    output wire [MATRIX_NUM_NBITS-1:0] matrix_num_a,
    output wire [MATRIX_NUM_NBITS-1:0] matrix_num_b,
    output wire [MATRIX_NUM_NBITS-1:0] matrix_num_result,
    output reg last_subtile_prev,
    output reg all_tiles_complete_prev,
    output wire last_subtile,
    output wire all_tiles_complete
    );
    
    reg [BITS_PER_OUTPUT_TILE_NUM-1:0] output_tile_num;
    
    localparam BITS_PER_TMP1 = $clog2(MAX_TILE_NUM/SYS_DIM+1);
    reg [BITS_PER_TILE_CNT-1:0] output_tile_num_mod_tile_span;
    reg [BITS_PER_TMP1-1:0] output_tile_num_div_tile_span;
    
    localparam BITS_PER_SUB_TILE = $clog2(MAX_TILE_SPAN);
    reg [BITS_PER_SUB_TILE-1:0] sub_tile_num;
    
    assign matrix_num_a = k_tiles*output_tile_num_div_tile_span+sub_tile_num;
    assign matrix_num_b = n_tiles*sub_tile_num + output_tile_num_mod_tile_span + m_tiles*k_tiles;
    assign matrix_num_result = 2*output_tile_num + (m_tiles*k_tiles+k_tiles*n_tiles);
    
    assign last_subtile = sub_tile_num==k_tiles-1;
    assign all_tiles_complete = output_tile_num == m_tiles*n_tiles;
    
    always @(posedge aclk) begin
        if(!arstn) begin
            sub_tile_num <= 0;
            output_tile_num <= 0;
            output_tile_num_mod_tile_span <= 0;
            output_tile_num_div_tile_span <= 0;
            matrix_num_a_prev <= 0;
            matrix_num_b_prev <= 0;
            matrix_num_result_prev <= 0;
            last_subtile_prev <= 0;
            all_tiles_complete_prev <= 0;
        end else if(increment) begin
            matrix_num_a_prev <= matrix_num_a;
            matrix_num_b_prev <= matrix_num_b;
            matrix_num_result_prev <= matrix_num_result;
            last_subtile_prev <= last_subtile;
            all_tiles_complete_prev <= all_tiles_complete;
            if(all_tiles_complete) begin
                sub_tile_num <= 0;
                output_tile_num <= 0;
                output_tile_num_mod_tile_span <= 0;
                output_tile_num_div_tile_span <= 0;
            end else if(last_subtile) begin
                sub_tile_num <= 0;
                if(output_tile_num_mod_tile_span+1==n_tiles) begin
                    output_tile_num_div_tile_span <= output_tile_num_div_tile_span + 1;
                    output_tile_num_mod_tile_span <= 0;
                end else begin
                    output_tile_num_mod_tile_span <= output_tile_num_mod_tile_span + 1;
                end
                output_tile_num <= output_tile_num + 1;
            end else begin
                sub_tile_num <= sub_tile_num + 1;
            end
        end
    end
endmodule
