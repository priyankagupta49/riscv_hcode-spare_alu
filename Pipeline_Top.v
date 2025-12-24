`timescale 1ns / 1ns

module Pipeline_top(
    input clk, rst,
    input imem_we,
    input [31:0] imem_waddr, imem_wdata,
    input loader_done_in,
    input test_en_in,               // Top-level BIST control 
    output [31:0] ResultW_out,
    output s_err_imem, d_err_imem, s_err_dmem, d_err_dmem,
    output hardware_fault_flag 
);

    // --- Internal Wire Declarations ---
    wire PCSrcE, RegWriteW, RegWriteE, ALUSrcE, MemWriteE, ResultSrcE, BranchE;
    wire RegWriteM, MemWriteM, ResultSrcM, ResultSrcW;
    wire [2:0] ALUControlE;
    wire [4:0] RD_E, RD_M, RDW, RS1_E, RS2_E, RS1_D, RS2_D;
    
    wire [31:0] PC_Next, PCTargetE, InstrD, PCD, PCPlus4D, ResultW;
    wire [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E, PCPlus4M;
    wire [31:0] WriteDataM, ALU_ResultM, PCPlus4W, ALU_ResultW, ReadDataW;
    
    wire [1:0] ForwardAE, ForwardBE;
    
    // Hazard Unit Control Signals
    wire StallF, StallD, FlushE;

    // Internal ECC Error Wires
    wire s_err_i, d_err_i, s_err_d, d_err_d;

    // Output Assignments
    assign s_err_imem = s_err_i;
    assign d_err_imem = d_err_i;
    assign s_err_dmem = s_err_d;
    assign d_err_dmem = d_err_d;
    assign ResultW_out = ResultW;

    // --- 1. PC Control Mux ---
    Mux PC_Selector (
        .a(PCPlus4D), 
        .b(PCTargetE), 
        .s(PCSrcE), 
        .c(PC_Next) 
    );

    // --- 2. Fetch Stage ---
    fetch_cycle fetch (
        .clk(clk), 
        .rst(rst & ~StallF),
        .PC_Next_In(PC_Next), 
        .imem_we(imem_we), 
        .imem_waddr(imem_waddr), 
        .imem_wdata(imem_wdata),
        .loader_done_in(loader_done_in),
        .s_err(s_err_i), 
        .d_err(d_err_i),
        .InstrD(InstrD), 
        .PCPlus4D(PCPlus4D), 
        .PCD(PCD) 
    );

    // --- 3. Decode Stage ---
    decode_cycle decode (
        .clk(clk), 
        .rst(rst & ~StallD),
        .InstrD(InstrD), 
        .PCD(PCD), 
        .PCPlus4D(PCPlus4D), 
        .RegWriteW(RegWriteW), 
        .RDW(RDW), 
        .ResultW(ResultW), 
        .RegWriteE(RegWriteE), 
        .ALUSrcE(ALUSrcE), 
        .MemWriteE(MemWriteE), 
        .ResultSrcE(ResultSrcE),
        .BranchE(BranchE), 
        .ALUControlE(ALUControlE), 
        .RD1_E(RD1_E), 
        .RD2_E(RD2_E), 
        .Imm_Ext_E(Imm_Ext_E), 
        .RD_E(RD_E), 
        .PCE(PCE), 
        .PCPlus4E(PCPlus4E),
        .RS1_E(RS1_E), 
        .RS2_E(RS2_E),
        .RS1_D(RS1_D), 
        .RS2_D(RS2_D)  
    );

    // --- 4. Execute Stage (Updated for BIST) ---
    execute_cycle execute (
        .clk(clk), .rst(rst & ~FlushE),
        .RegWriteE(RegWriteE), .ALUSrcE(ALUSrcE), .MemWriteE(MemWriteE), 
        .ResultSrcE(ResultSrcE), .BranchE(BranchE), .ALUControlE(ALUControlE), 
        .RD1_E(RD1_E), .RD2_E(RD2_E), .Imm_Ext_E(Imm_Ext_E), .RD_E(RD_E), 
        .PCE(PCE), .PCPlus4E(PCPlus4E), .PCSrcE(PCSrcE), .PCTargetE(PCTargetE), 
        .RegWriteM(RegWriteM), .MemWriteM(MemWriteM), .ResultSrcM(ResultSrcM), 
        .RD_M(RD_M), .PCPlus4M(PCPlus4M), .WriteDataM(WriteDataM), 
        .ALU_ResultM(ALU_ResultM), .ResultW(ResultW), 
        .ForwardA_E(ForwardAE), .ForwardB_E(ForwardBE),
        .ALU_ResultM_In(ALU_ResultM),
        
        .test_en_in(test_en_in),    // Matches execute_cycle port name
        .hardware_fault_flag(hardware_fault_flag)
    );
    
    // --- 5. Memory Stage ---
    memory_cycle memory (
        .clk(clk), 
        .rst(rst), 
        .RegWriteM(RegWriteM), 
        .MemWriteM(MemWriteM), 
        .ResultSrcM(ResultSrcM), 
        .RD_M(RD_M), 
        .PCPlus4M(PCPlus4M), 
        .WriteDataM(WriteDataM), 
        .ALU_ResultM(ALU_ResultM), 
        .RegWriteW(RegWriteW), 
        .ResultSrcW(ResultSrcW), 
        .RD_W(RDW), 
        .PCPlus4W(PCPlus4W), 
        .ALU_ResultW(ALU_ResultW), 
        .ReadDataW(ReadDataW),
        .s_err(s_err_d), 
        .d_err(d_err_d)
    );

    // --- 6. Write Back Stage ---
    writeback_cycle writeBack (
        .clk(clk), 
        .rst(rst), 
        .ResultSrcW(ResultSrcW), 
        .PCPlus4W(PCPlus4W), 
        .ALU_ResultW(ALU_ResultW), 
        .ReadDataW(ReadDataW), 
        .ResultW(ResultW)
    );

    // --- 7. Hazard Unit ---
    hazard_unit Forwarding_Block (
        .rst(rst), 
        .RegWriteM(RegWriteM), 
        .RegWriteW(RegWriteW), 
        .ResultSrcM(ResultSrcM), 
        .RD_M(RD_M), 
        .RD_W(RDW), 
        .Rs1_E(RS1_E), 
        .Rs2_E(RS2_E), 
        .Rs1_D(RS1_D), 
        .Rs2_D(RS2_D), 
        .ForwardAE(ForwardAE), 
        .ForwardBE(ForwardBE),
        .StallF(StallF),
        .StallD(StallD),
        .FlushE(FlushE)
    );

endmodule