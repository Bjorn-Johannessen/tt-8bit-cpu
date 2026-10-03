`default_nettype none

module cpu (
    input wire        clk,
    input wire        rst_n,
    input wire  [7:0] mem_rdata,

    output wire [6:0] mem_addr,
    output wire       mem_we,
    output wire [7:0] mem_wdata,
    output wire       halted,
    output wire       sync,
    output wire       flag_z,
    output wire       flag_c
);

    // states
    localparam [1:0]
        S_FETCH   = 2'd0,
        S_OPERAND = 2'd1,
        S_EXEC    = 2'd2,
        S_HALT    = 2'd3;

    localparam [3:0]
        OPC_NOP   = 4'h0,
        OPC_LD    = 4'h1,
        OPC_STA   = 4'h2,
        OPC_ADD   = 4'h3,
        OPC_ADC   = 4'h4,
        OPC_SUB   = 4'h5,
        OPC_CMP   = 4'h6,
        OPC_AND   = 4'h7,
        OPC_OR    = 4'h8,
        OPC_XOR   = 4'h9,
        OPC_UNARY = 4'hA,
        OPC_JMP   = 4'hB,
        OPC_JCC   = 4'hC,
        //          4'hD is reserved
        //          4'hE is reserved
        OPC_HLT   = 4'hF;

    reg [7:0] a;   // accumulator
    reg [6:0] pc;  // program counter
    reg [7:0] ir;  // instruction register
    reg [6:0] mar; // memory address register
    reg       z;   // zero flag
    reg       c;   // carry flag
    reg [1:0] state;
    
    assign mem_wdata = a;
    assign flag_z = z;
    assign flag_c = c;
    assign halted = (state == S_HALT);
    assign sync = (state == S_FETCH);
    assign mem_addr = pc; // TODO
    assign mem_we = 1'b0; // TODO

    always @(posedge clk) begin
        if (!rst_n) begin
            a     <= 8'h00;
            pc    <= 7'h00;
            ir    <= 8'h00;
            mar   <= 7'h00;
            z     <= 1'b0;
            c     <= 1'b0;
            state <= S_FETCH;            
        end else begin

        end
    end

endmodule
