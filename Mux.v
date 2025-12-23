// 2-to-1 Mux
`timescale 1ns / 1ps
module Mux (input [31:0] a, b, input s, output [31:0] c);
    assign c = (s == 1'b0) ? a : b;
endmodule

// 3-to-1 Mux for Forwarding
module Mux_3_by_1 (input [31:0] a, b, c, input [1:0] s, output [31:0] d);
    assign d = (s == 2'b00) ? a : 
               (s == 2'b01) ? b : 
               (s == 2'b10) ? c : 32'h00000000;
endmodule


