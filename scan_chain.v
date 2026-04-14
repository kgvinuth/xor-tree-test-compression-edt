`timescale 1ns/1ps

module scan_chain #(
    parameter DEPTH = 4          // number of flip-flops in chain
)(
    input  wire clk,
    input  wire rst,
    input  wire scan_en,
    input  wire scan_in,         // from XOR phase shifter
    input  wire func_in,         // from circuit under test (CUT)
    output wire scan_out         // to XOR compactor
);

    reg [DEPTH-1:0] ff;

    always @(posedge clk or posedge rst) begin
        if (rst)
            ff <= {DEPTH{1'b0}};
        else if (scan_en)
            // SHIFT MODE: shift scan_in from LSB to MSB
            ff <= {ff[DEPTH-2:0], scan_in};
        else
            // CAPTURE MODE: CUT response into MSB, shift right
            ff <= {func_in, ff[DEPTH-1:1]};
    end

    // scan_out is the MSB - appears after DEPTH shift cycles
    assign scan_out = ff[DEPTH-1];

endmodule
