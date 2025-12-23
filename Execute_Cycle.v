`timescale 1ns / 1ps

module execute_cycle(
    input clk, rst,
    input RegWriteE, ALUSrcE, MemWriteE, ResultSrcE, BranchE,
    input [2:0] ALUControlE,
    input [31:0] RD1_E, RD2_E, Imm_Ext_E,
    input [4:0] RD_E,
    input [31:0] PCE, PCPlus4E,
    input [31:0] ResultW,
    input [1:0] ForwardA_E, ForwardB_E,
    input [31:0] ALU_ResultM_In, 

    output PCSrcE, RegWriteM, MemWriteM, ResultSrcM,
    output [4:0] RD_M,
    output [31:0] PCPlus4M, WriteDataM, ALU_ResultM,
    output [31:0] PCTargetE,
    output reg hardware_fault_flag // Signal to top level that reconfiguration occurred
);

    wire [31:0] Src_A, Src_B_interim, Src_B;
    wire [31:0] ResultE_Primary, ResultE_Spare, Final_ResultE;
    wire ZeroE_P, ZeroE_S, Final_ZeroE;
    
    // Fault Signal from Primary ALU
    wire primary_alu_fault;
    reg use_spare;

    // 1. Source A Mux
    Mux_3_by_1 srca_mux (
        .a(RD1_E), .b(ResultW), .c(ALU_ResultM_In),
        .s(ForwardA_E), .d(Src_A)
    );

    // 2. Source B Interim Mux
    Mux_3_by_1 srcb_mux (
        .a(RD2_E), .b(ResultW), .c(ALU_ResultM_In),
        .s(ForwardB_E), .d(Src_B_interim)
    );

    // 3. ALU Source B Mux
    Mux alu_src_mux (
        .a(Src_B_interim), .b(Imm_Ext_E),
        .s(ALUSrcE), .c(Src_B)
    );

    // 4. MODULE-LEVEL REPLACEMENT: Dual ALU Instantiation
    
    // Primary ALU (Equipped with Fault Detection/BIST)
    // In a real implementation, this unit includes parity or residue checkers
 // Primary ALU
    ALU_ft primary_alu (
    .clk(clk), .rst(rst),
        .A(Src_A), .B(Src_B), .ALUControl(ALUControlE),
        .Result(ResultE_Primary), 
        .Zero(ZeroE_P),
        .Carry(Carry_P),        // Ensure these wires are declared
        .OverFlow(OverFlow_P),
        .Negative(Negative_P),
        .force_alu_fault(1'b0), // Primary doesn't need to force itself
        .fault_detected_out(primary_alu_fault) // FIX: Match port name in ALU_ft
    );

    // Spare ALU (The redundant unit)
    ALU_ft spare_alu (
    .clk(clk), .rst(rst),
        .A(Src_A), .B(Src_B), .ALUControl(ALUControlE),
        .Result(ResultE_Spare), .Zero(ZeroE_S)
        // Spare doesn't need a checker to save area
    );

    // 5. DYNAMIC RECONFIGURATION LOGIC
    // This block "remembers" if the primary unit ever failed
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            use_spare <= 1'b0;
            hardware_fault_flag <= 1'b0;
        end else if (primary_alu_fault) begin
            use_spare <= 1'b1;         // Latch the reconfiguration
            hardware_fault_flag <= 1'b1;
        end
    end

    // Routing Multiplexers: Choose result based on reconfiguration state
    assign Final_ResultE = (use_spare) ? ResultE_Spare : ResultE_Primary;
    assign Final_ZeroE   = (use_spare) ? ZeroE_S : ZeroE_P;

    // 6. Branch Target Adder
    PC_Adder branch_adder (
        .a(PCE), .b(Imm_Ext_E), .c(PCTargetE)
    );

    // 7. EX/MEM Pipeline Registers
    reg RegWriteM_r, MemWriteM_r, ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [31:0] PCPlus4M_r, WriteDataM_r, ALU_ResultM_r;

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            RegWriteM_r <= 1'b0; MemWriteM_r <= 1'b0; ResultSrcM_r <= 1'b0;
            RD_M_r <= 5'b0; PCPlus4M_r <= 32'b0; WriteDataM_r <= 32'b0; ALU_ResultM_r <= 32'b0;
        end else begin
            RegWriteM_r <= RegWriteE;
            MemWriteM_r <= MemWriteE;
            ResultSrcM_r <= ResultSrcE;
            RD_M_r <= RD_E;
            PCPlus4M_r <= PCPlus4E;
            WriteDataM_r <= Src_B_interim; 
            ALU_ResultM_r <= Final_ResultE; // Using the selected (Primary or Spare) result
        end
    end

    // Final Outputs
    assign PCSrcE = Final_ZeroE & BranchE;
    assign RegWriteM = RegWriteM_r;
    assign MemWriteM = MemWriteM_r;
    assign ResultSrcM = ResultSrcM_r;
    assign RD_M = RD_M_r;
    assign PCPlus4M = PCPlus4M_r;
    assign WriteDataM = WriteDataM_r;
    assign ALU_ResultM = ALU_ResultM_r;

endmodule