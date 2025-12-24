`timescale 1ns / 1ps

module ALU_ft(
    input clk, rst,
    input [31:0] A, B,
    input [2:0] ALUControl,
    input test_en,
    input [2:0] test_counter,     // Now an input from execute_cycle
    output [31:0] Result,
    output Carry, OverFlow, Zero, Negative,
    input  force_alu_fault,       
    output fault_detected_out     
);
    // Internal Signals
    wire [31:0] res_p, res_s;
    wire c_p, v_p, z_p, n_p;
    wire c_s, v_s, z_s, n_s;
    wire use_spare;
    
    wire [31:0] test_A, test_B;   
    wire [2:0]  test_ALUControl;  

    // 1. Mapping Test Counter to Patterns (Combinational)
    // These react immediately to the test_counter input from the parent
    assign test_A = (test_counter == 3'd7) ? 32'h00000001 : // SLT Pattern A
                    (test_counter >= 3'd4) ? 32'h55555555 : 
                    (test_counter >= 3'd2) ? 32'hAAAAAAAA : 32'h00000000;
                    
    assign test_B = (test_counter == 3'd7) ? 32'h00000002 : // SLT Pattern B
                    (test_counter >= 3'd4) ? 32'hAAAAAAAA : 
                    (test_counter >= 3'd2) ? 32'h55555555 : 32'hFFFFFFFF;

 assign test_ALUControl = (test_counter <= 3'd1) ? 3'b000 : // ADD
                         (test_counter <= 3'd3) ? 3'b100 : // XOR
                         (test_counter == 3'd4) ? 3'b010 : // AND
                         (test_counter == 3'd5) ? 3'b011 : // OR 
                         (test_counter == 3'd6) ? 3'b001 : // SUB
                         3'b101;                           // SLT

    // 3. Instantiate the ORA (BIST_LUT)
    BIST_LUT ora_unit (
        .clk(clk), .rst(rst),
        .test_en(test_en),
        .test_counter(test_counter),
        .primary_res(res_p),
        .primary_carry(c_p),
        .fault_detected(), 
        .mux_sel(use_spare)
    );

    // 4. Instantiate Primary and Spare ALUs
    ALU Primary_ALU (
        .A(test_en ? test_A : A), 
        .B(test_en ? test_B : B), 
        .ALUControl(test_en ? test_ALUControl : ALUControl), 
        .Result(res_p), .Carry(c_p), .OverFlow(v_p), .Zero(z_p), .Negative(n_p)
    );

    ALU Spare_ALU (
        .A(A), .B(B), .ALUControl(ALUControl), 
        .Result(res_s), .Carry(c_s), .OverFlow(v_s), .Zero(z_s), .Negative(n_s)
    );

    // 5. Output Multiplexers
    assign Result   = (use_spare || force_alu_fault) ? res_s : res_p;
    assign Carry    = (use_spare || force_alu_fault) ? c_s   : c_p;
    assign OverFlow = (use_spare || force_alu_fault) ? v_s   : v_p;
    assign Zero     = (use_spare || force_alu_fault) ? z_s   : z_p;
    assign Negative = (use_spare || force_alu_fault) ? n_s   : n_p;
    
    assign fault_detected_out = use_spare;

endmodule