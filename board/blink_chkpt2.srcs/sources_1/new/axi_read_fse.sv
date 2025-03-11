`include "memory_states.vh"
module axi_read_fse
(
    input                         clk,
    input                         resetn,  
    input                         start,     
    input      [15:0]   addr, 

    output reg [AXI_MAX_READ_BURST_LEN-1:0][255:0]   read_data, 
    input wire [7:0]     num_reads,
    output reg                  read_done,



    // AXI-Lite Read Address Channel
    output reg [15:0]   m_axi_araddr,
    output reg                  m_axi_arvalid,
    input                       m_axi_arready,
    output reg [7:0]            m_axi_arlen,
    output reg [2:0]            m_axi_arsize,

    // AXI-Lite Read Data Channel
    input      [255:0]   m_axi_rdata,
    input       [1:0]           m_axi_rresp,
    input                       m_axi_rvalid,
    output reg                  m_axi_rready,
    input wire                  m_axi_rlast
);

// State encoding
localparam STATE_IDLE       = 3'd0;
localparam STATE_READ_ADDR  = 3'd1;
localparam STATE_READ_DATA  = 3'd2;
localparam STATE_DONE       = 3'd3;

reg [2:0] state;
reg [$clog2(AXI_MAX_READ_BURST_LEN+1)-1:0] arg_num;
reg truncated_burst;

//---------------------------------------------------------------------
// Output Logic
//---------------------------------------------------------------------
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin

        m_axi_araddr  <= 0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready  <= 1'b0;
        m_axi_arlen <= 8'b0;
        m_axi_arsize <= 3'b0;
        read_data <= 0;

        read_done <= 1'b0;
        state <= STATE_IDLE;
        arg_num <= 0;
        truncated_burst <= 0;
    end else begin
        case (state)
            STATE_IDLE: begin
                if (start) begin
                    truncated_burst <= (addr&16'h1000) != ((addr+32*num_reads)&32'h1000);
                    arg_num <= 0;
                    state <= STATE_READ_ADDR;
                    m_axi_araddr  <= addr;
                    m_axi_arvalid <= 1'b1;
                    m_axi_arlen <= (addr&16'h1000) != ((addr+32*num_reads)&32'h1000) ? 0 : num_reads-1;
                    m_axi_arsize <= 5;
                end
            end

            
            // Read Transaction Sequence
            STATE_READ_ADDR: begin
                if(m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 0;
                    state <= STATE_READ_DATA;
                    m_axi_rready <= 1'b1;
                end else begin
                    m_axi_araddr  <= addr + 32*arg_num;
                    m_axi_arvalid <= 1'b1;
                    m_axi_arlen <= truncated_burst ? 0 : num_reads-1;
                    m_axi_arsize <= 5;
                end
            end
            
            STATE_READ_DATA: begin
                if(m_axi_rvalid && m_axi_rready) begin
                    arg_num <= arg_num + 1;
                    read_data[arg_num] <= m_axi_rdata;
                    if(m_axi_rlast && arg_num==num_reads-1) begin
                        m_axi_rready <= 0;
                        state <= STATE_DONE;
                        read_done <= 1'b1;
                        state <= STATE_DONE;
                    end else if(m_axi_rlast && truncated_burst) begin
                        m_axi_rready <= 0;
                        state <= STATE_READ_ADDR;
                    end
                end
            end
            
            STATE_DONE: begin
                read_done <= 0;
                state <= STATE_IDLE;
            end
            
            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
