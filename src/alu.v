`default_nettype none

module alu (
    input wire [7:0] a,
    input wire [7:0] b,
    input wire [3:0] op,
    input wire       cin,

    output reg [7:0] result,
    output wire      z,
    output reg       c_out
);

    // ALU op-codes
    localparam [3:0]
        ALU_PASS   = 4'h0,
        ALU_ADD    = 4'h1,
        ALU_ADC    = 4'h2,
        ALU_SUB    = 4'h3,
        ALU_AND    = 4'h4,
        ALU_OR     = 4'h5,
        ALU_XOR    = 4'h6,
        //           4'h7 is unused
        ALU_SHL    = 4'h8,
        ALU_SHR    = 4'h9,
        ALU_ROL    = 4'hA,
        ALU_ROR    = 4'hB,
        ALU_INC    = 4'hC,
        ALU_DEC    = 4'hD,
        ALU_NOT    = 4'hE,
        ALU_CLC    = 4'hF;

    // operations
    wire [8:0] add_result;
    assign add_result = {1'b0, a} + {1'b0, b};

    wire [8:0] adc_result;
    assign adc_result = add_result + {8'b0, cin};

    wire [8:0] sub_result;
    assign sub_result = {1'b0, a} - {1'b0, b};

    wire [7:0] and_result;
    assign and_result = (a & b);

    wire [7:0] or_result;
    assign or_result = (a | b);

    wire [7:0] xor_result;
    assign xor_result = (a ^ b);

    wire [7:0] shl_result;
    assign shl_result = a << 1;

    wire [7:0] shr_result;
    assign shr_result = a >> 1;

    wire [7:0] rol_result;
    assign rol_result = {a[6:0], cin};

    wire [7:0] ror_result;
    assign ror_result = {cin, a[7:1]};

    wire [7:0] inc_result;
    assign inc_result = a + 8'd1;

    wire [7:0] dec_result;
    assign dec_result = a - 8'd1;

    wire [7:0] not_result;
    assign not_result = ~a;

    wire [7:0] clc_result;
    assign clc_result = a;

    always @(*) begin
        // default values
        result = 8'h00;
        c_out = cin;

        // multiplexer that outputs the right operation result
        case (op)
            ALU_PASS: result = b;
            ALU_ADD: begin result = add_result[7:0]; c_out = add_result[8]; end
            ALU_ADC: begin result = adc_result[7:0]; c_out = adc_result[8]; end
            ALU_SUB: begin result = sub_result[7:0]; c_out = sub_result[8]; end 
            ALU_AND: result = and_result;
            ALU_OR:  result = or_result;
            ALU_XOR: result = xor_result;
            ALU_SHL: begin result = shl_result; c_out = a[7]; end
            ALU_SHR: begin result = shr_result; c_out = a[0]; end
            ALU_ROL: begin result = rol_result; c_out = a[7]; end
            ALU_ROR: begin result = ror_result; c_out = a[0]; end
            ALU_INC: result = inc_result;
            ALU_DEC: result = dec_result;
            ALU_NOT: result = not_result;
            ALU_CLC: begin result = clc_result; c_out = 1'b0; end
        default: ;

        endcase
    end

    assign z = (result == 8'h00);

endmodule
