`include "memory_states.vh"
module axi_write_fse
(
    input                         clk,
    input                         resetn,      // Active low reset
    input                         start,       // Transaction start trigger
    input      [15:0]   addr,        // Transaction address
    input      [AXI_MAX_WRITE_BURST_LEN-1:0][255:0]   write_data,  
    input wire [7:0]    num_writes,

    output reg                  write_done,         // Transaction completion flag

    // AXI-Lite Write Address Channel
    output reg [15:0]   m_axi_awaddr,
    output reg                  m_axi_awvalid,
    input                       m_axi_awready,
    output reg [7:0]            m_axi_awlen,
    output reg [2:0]            m_axi_awsize,

    // AXI-Lite Write Data Channel
    output reg [255:0]   m_axi_wdata,
    output reg [31:0] m_axi_wstrb,
    output reg                  m_axi_wvalid,
    input                   m_axi_wready,
    output reg                  m_axi_wlast,

    // AXI-Lite Write Response Channel
    input       [1:0]           m_axi_bresp,
    input                       m_axi_bvalid,
    output reg                  m_axi_bready
);

// State encoding
localparam STATE_IDLE       = 3'd0;
localparam STATE_WRITE_ADDR = 3'd1;
localparam STATE_WRITE_DATA = 3'd2;
localparam STATE_WRITE_RESP = 3'd3;
localparam STATE_DONE       = 3'd4;

reg [2:0] state;
reg [$clog2(AXI_MAX_WRITE_BURST_LEN+1)-1:0] arg_num;
reg truncated_burst;

//---------------------------------------------------------------------
// Output Logic
//---------------------------------------------------------------------
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        m_axi_awaddr  <= 0;
        m_axi_awvalid <= 1'b0;
        m_axi_wdata   <= 0;
        m_axi_wstrb   <= 0;
        m_axi_wvalid  <= 1'b0;
        m_axi_bready  <= 1'b0;


        m_axi_awlen <= 8'b0;
        m_axi_awsize <= 3'b0;
        m_axi_wlast <= 0;
        write_done          <= 1'b0;
        state         <= STATE_IDLE;
        arg_num <= 0;
        truncated_burst <= 0;
    end else begin
        case (state)
            STATE_IDLE: begin
                // !done to ensure buffer
                if (start) begin
                    truncated_burst <= (addr&16'h1000) != ((addr+32*num_writes)&16'h1000);
                    arg_num <= 0;
                    state <= STATE_WRITE_ADDR;
                    m_axi_awaddr  <= addr;
                    m_axi_awvalid <= 1'b1;
                    m_axi_awsize <= 5;
                    m_axi_awlen <= (addr&16'h1000) != ((addr+32*num_writes)&16'h1000) ? 0 : num_writes-1;
                end
            end
            
            // Write Transaction Sequence
            STATE_WRITE_ADDR: begin
                if(m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 0;
                    state <= STATE_WRITE_DATA;
                    m_axi_wlast <= truncated_burst || num_writes==1;
                    m_axi_wdata  <= write_data[arg_num];
                    m_axi_wstrb  <= 32'hFFFFFFFF;  // Full word write
                    m_axi_wvalid <= 1'b1;
                end else begin
                    m_axi_awaddr  <= addr + 32*arg_num;
                    m_axi_awvalid <= 1'b1;
                    m_axi_awsize <= 5;
                    m_axi_awlen <= truncated_burst ? 0 : num_writes-1;
                end
            end
            
            STATE_WRITE_DATA: begin
                if(m_axi_wvalid && m_axi_wready) begin
                    arg_num <= arg_num + 1;
                    if(arg_num == num_writes-1 || truncated_burst) begin
                        m_axi_wvalid <= 0;
                        state <= STATE_WRITE_RESP;
                        m_axi_bready <= 1'b1;
                    end else begin
                        m_axi_wdata <= write_data[arg_num+1];
                        m_axi_wlast <= arg_num==num_writes-2;
                    end
                end
            end
            
            STATE_WRITE_RESP: begin
                if(m_axi_bready && m_axi_bvalid) begin
                    m_axi_bready <= 0;
                    if(arg_num==num_writes) begin
                        state <= STATE_DONE;
                        write_done <= 1;
                    end else begin
                        state <= STATE_WRITE_ADDR;
                    end
                end
            end
            
            STATE_DONE: begin
                write_done <= 0;
                state <= STATE_IDLE;
            end
            
            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
