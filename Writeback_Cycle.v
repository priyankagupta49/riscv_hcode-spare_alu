`timescale 1ns / 1ps

module writeback_cycle(
    input clk, 
    input rst, 
    input ResultSrcW,           // 0 for ALU, 1 for Memory
    input [31:0] PCPlus4W,      // Used for JAL/JALR (if supported)
    input [31:0] ALU_ResultW,   // From ALU path
    input [31:0] ReadDataW,     // From ECC-corrected Memory path
    output [31:0] ResultW
);

    // Mux to choose between ALU result and Memory data
    Mux result_mux (    
        .a(ALU_ResultW),
        .b(ReadDataW),
        .s(ResultSrcW),
        .c(ResultW)
    );

endmodule