`timescale 1ns / 1ps
`include "memory_states.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/10/2025 02:08:21 PM
// Design Name: 
// Module Name: matrix_multiplier
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


module matrix_multiplier    #(
    parameter SYS_DIM
    ) (
    input wire aclk,
    input wire aresetn,
    
    output reg [2:0] matrix_command,
    output reg [MATRIX_NUM_NBITS-1:0] matrix_num,
    input wire [31:0] status_read_data,
    input wire [TILE_NUM_ELEMENTS-1:0][15:0] matrix_read_data,
    output reg [TILE_NUM_ELEMENTS-1:0][31:0] matrix_write_data,
    input wire matrix_done,
    output reg [31:0] cycles_elapsed
    );
    
    
    
    localparam S_IDLE      = 4'd0,
           S_CHECK_STATUS    = 4'd1,
           S_DECIDE        = 4'd2,
           S_START_TILE    = 4'd3,
           S_READ_A      = 4'd4,
           S_READ_B     = 4'd5,
           S_COMPUTE       = 4'd6,
           S_COMPLETE_TILE  = 4'd7,
           S_WRITE_RESULTS = 4'd8,
           S_WRITE_STATUS    = 4'd9,
           S_INTERRUPT     = 4'd10;
    
reg [3:0] current_state;

reg [TILE_NUM_ELEMENTS-1:0][15:0] mat_a;
reg [TILE_NUM_ELEMENTS-1:0][15:0] mat_b;

reg start_mul;
wire mul_done;

reg [BITS_PER_TILE_CNT-1:0] m_tiles;
reg [BITS_PER_TILE_CNT-1:0] k_tiles;
reg [BITS_PER_TILE_CNT-1:0] n_tiles;

reg accumulate;

systolic_array #(
    .DIM(SYS_DIM)) multiplier (
    .clk(aclk),
    .rst(aresetn),
    .mat_a(mat_a),
    .mat_b(mat_b),
    .out(matrix_write_data),
    .accumulate(accumulate),
    .start(start_mul),
    .done(mul_done)
    );
    
reg increment_tile;
wire [MATRIX_NUM_NBITS-1:0] matrix_num_a_prev;
wire [MATRIX_NUM_NBITS-1:0] matrix_num_b_prev;
wire [MATRIX_NUM_NBITS-1:0] matrix_num_result_prev;
wire [MATRIX_NUM_NBITS-1:0] matrix_num_a;
wire [MATRIX_NUM_NBITS-1:0] matrix_num_b;
wire [MATRIX_NUM_NBITS-1:0] matrix_num_result;
wire last_subtile;
wire all_tiles_complete;
wire last_subtile_prev;
wire all_tiles_complete_prev;
reg a_ready;

matrix_num_calculator calc(
    .arstn(aresetn),
    .aclk(aclk),
    .increment(increment_tile),
    .m_tiles(m_tiles),
    .k_tiles(k_tiles),
    .n_tiles(n_tiles),
    .matrix_num_a(matrix_num_a),
    .matrix_num_b(matrix_num_b),
    .matrix_num_result(matrix_num_result),
    .matrix_num_a_prev(matrix_num_a_prev),
    .matrix_num_b_prev(matrix_num_b_prev),
    .matrix_num_result_prev(matrix_num_result_prev),
    .last_subtile(last_subtile),
    .all_tiles_complete(all_tiles_complete),
    .last_subtile_prev(last_subtile_prev),
    .all_tiles_complete_prev(all_tiles_complete_prev));

////////////////////////////////////////////////////////////////////////////////
// Output and Data Handling
////////////////////////////////////////////////////////////////////////////////
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        current_state <= S_IDLE;
        start_mul <= 1'b0;
        accumulate <= 0;
        matrix_num <= 0;
        matrix_command <= MHS_IDLE;
        m_tiles <= 0;
        k_tiles <= 0;
        n_tiles <= 0;
        increment_tile <= 0;
        cycles_elapsed <= 0;
        for (int init = 0; init < SYS_DIM*SYS_DIM; init = init + 1) begin
            mat_a[init] <= 32'h0;
            mat_b[init] <= 32'h0;
        end
        a_ready <= 0;
    end else begin
        matrix_command <= MHS_IDLE;
        increment_tile <= 0;
        cycles_elapsed <= cycles_elapsed + 1;
        if(matrix_done) a_ready <= 1;
        
        case (current_state)
            S_IDLE: begin
                current_state <= S_CHECK_STATUS;
            end

            S_CHECK_STATUS: begin
                if(matrix_done) begin
                    current_state <= S_DECIDE;
                 end else begin
                    matrix_command <= MHS_READ_STATUS;
                 end
            end

            S_DECIDE: begin
                if(status_read_data == 32'd0) begin
                    current_state <= S_CHECK_STATUS;
                end else begin
                    m_tiles <= status_read_data[9:0] / SYS_DIM;
                    k_tiles <= status_read_data[19:10] / SYS_DIM;
                    n_tiles <= status_read_data[29:20] / SYS_DIM;
                    current_state <= S_START_TILE;
                    cycles_elapsed <= 0;
                    a_ready <= 0;
                end
            end
            
            S_START_TILE: begin
                if(all_tiles_complete) begin
                    increment_tile <= 1;
                    current_state <= S_WRITE_STATUS;
                end else begin
                    accumulate <= 1;
                    current_state <= S_READ_A;
                    if(!a_ready) begin
                        matrix_num <= matrix_num_a;
                        matrix_command <= MHS_READ_MATRIX;
                    end
                end
            end

            // Read from 0x0 -> reg_A
            S_READ_A: begin
                if (a_ready) begin
                    mat_a <= matrix_read_data;
                    current_state <= S_READ_B;
                    matrix_num <= matrix_num_b;
                    matrix_command <= MHS_READ_MATRIX;
                    increment_tile <= 1;
                end
            end
            
            S_READ_B: begin
                if (matrix_done) begin
                    mat_b <= matrix_read_data;
                    current_state <= S_COMPUTE;
                    start_mul <= 1;
                    
                    a_ready <= 0;
                    matrix_num <= matrix_num_a; // next
                    matrix_command <= MHS_READ_MATRIX;
                end
            end
            
            S_COMPUTE: begin
                if(mul_done) begin
                    start_mul <= 0;
                    current_state <= S_COMPLETE_TILE;
                end
            end
            
            S_COMPLETE_TILE: begin
                if(last_subtile_prev) begin // all sub tiles complete
                    if(a_ready) begin // skip waiting for update
                        current_state <= S_WRITE_RESULTS;
                        matrix_num <= matrix_num_result_prev;
                        matrix_command <= MHS_WRITE_RESULT;
                    end
                end else begin
                    current_state <= S_START_TILE;
                end
            end

            S_WRITE_RESULTS: begin
                if(matrix_done) begin
                    current_state <= S_START_TILE;
                    accumulate <= 0;
                end
            end
            
            S_WRITE_STATUS: begin
                if(matrix_done) begin
                    current_state <= S_INTERRUPT;
                end else begin
                    matrix_command <= MHS_RESET_STATUS;
                end
            end
            
            S_INTERRUPT: begin
                if(matrix_done) begin
                    current_state <= S_IDLE;
                end else begin
                    matrix_command <= MHS_INTERRUPT;
                end
            end
            default: current_state <= S_IDLE;
        endcase
    end
end 
endmodule
