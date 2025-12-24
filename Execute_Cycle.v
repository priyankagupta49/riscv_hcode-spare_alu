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
    input test_en_in,              

    output PCSrcE, RegWriteM, MemWriteM, ResultSrcM,
    output [4:0] RD_M,
    output [31:0] PCPlus4M, WriteDataM, ALU_ResultM,
    output [31:0] PCTargetE,
    output reg hardware_fault_flag 
);

    // Internal Wires
    wire [31:0] Src_A, Src_B_interim, Src_B;
    wire [31:0] ResultE_Primary, ResultE_Spare, Final_ResultE;
    wire ZeroE_P, ZeroE_S, Final_ZeroE;
    wire Carry_P;
    
    // Test Controller and BIST Signals
    reg [15:0] test_timer;   
    reg [2:0]  test_counter; 
    reg        internal_test_en;   
    wire       test_en;            
    wire       bist_fault_detected;
    wire       use_spare_mux;

    assign test_en = test_en_in | internal_test_en;

    // 1. Source Muxes
    Mux_3_by_1 srca_mux (.a(RD1_E), .b(ResultW), .c(ALU_ResultM_In), .s(ForwardA_E), .d(Src_A));
    Mux_3_by_1 srcb_mux (.a(RD2_E), .b(ResultW), .c(ALU_ResultM_In), .s(ForwardB_E), .d(Src_B_interim));
    Mux alu_src_mux (.a(Src_B_interim), .b(Imm_Ext_E), .s(ALUSrcE), .c(Src_B));

    // 2. TEST CONTROLLER (Mixed-Operation BIST Trigger)
    // This block manages the timing for both the Primary ALU and the ORA
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            test_timer       <= 16'b0;
            test_counter     <= 3'b0;
            internal_test_en <= 1'b0;
        end else if (!hardware_fault_flag) begin 
            if (!internal_test_en) begin
                test_timer <= test_timer + 1;
                if (test_timer == 16'hFFFF) internal_test_en <= 1'b1;
            end else begin
                test_counter <= test_counter + 1;
                if (test_counter == 3'd7) begin 
                    internal_test_en <= 1'b0;
                    test_timer       <= 16'b0;
                end
            end
        end
    end

    // 3. INTEGRATED BIST_LUT (Output Response Analyzer)
    BIST_LUT alu_checker (
        .clk(clk), .rst(rst),
        .test_en(test_en),
        .test_counter(test_counter),
        .primary_res(ResultE_Primary),
        .primary_carry(Carry_P),
        .fault_detected(bist_fault_detected),
        .mux_sel(use_spare_mux)
    );

    always @(*) hardware_fault_flag = bist_fault_detected;

    // 4. MODULE-LEVEL REPLACEMENT (Hot-Standby)
    ALU_ft primary_alu (
        .clk(clk), .rst(rst),
        .A(Src_A), .B(Src_B), .ALUControl(ALUControlE),
        .test_en(test_en), 
        .test_counter(test_counter), // Passing the centrally managed counter
        .Result(ResultE_Primary), .Carry(Carry_P), .Zero(ZeroE_P),
        .force_alu_fault(1'b0), .fault_detected_out() 
    );

    ALU_ft spare_alu (
        .clk(clk), .rst(rst),
        .A(Src_A), .B(Src_B), .ALUControl(ALUControlE),
        .test_en(1'b0), 
        .test_counter(3'b000),       // Spare is not in test mode, keep counter 0
        .Result(ResultE_Spare), .Zero(ZeroE_S)
    );

    // 5. RECONFIGURATION MUX 
    wire final_mux_control = use_spare_mux | test_en; 
    assign Final_ResultE = (final_mux_control) ? ResultE_Spare : ResultE_Primary;
    assign Final_ZeroE   = (final_mux_control) ? ZeroE_S : ZeroE_P;

    // 6. Pipeline Registers
    reg RegWriteM_r, MemWriteM_r, ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [31:0] PCPlus4M_r, WriteDataM_r, ALU_ResultM_r;

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            RegWriteM_r <= 1'b0; MemWriteM_r <= 1'b0; ResultSrcM_r <= 1'b0;
            RD_M_r <= 5'b0; PCPlus4M_r <= 32'b0; WriteDataM_r <= 32'b0; ALU_ResultM_r <= 32'b0;
        end else begin
            RegWriteM_r <= RegWriteE; MemWriteM_r <= MemWriteE; ResultSrcM_r <= ResultSrcE;
            RD_M_r <= RD_E; PCPlus4M_r <= PCPlus4E; WriteDataM_r <= Src_B_interim; 
            ALU_ResultM_r <= Final_ResultE; 
        end
    end

    PC_Adder branch_adder (.a(PCE), .b(Imm_Ext_E), .c(PCTargetE));
    assign PCSrcE = Final_ZeroE & BranchE;
    assign RegWriteM = RegWriteM_r; assign MemWriteM = MemWriteM_r;
    assign ResultSrcM = ResultSrcM_r; assign RD_M = RD_M_r;
    assign PCPlus4M = PCPlus4M_r; assign WriteDataM = WriteDataM_r;
    assign ALU_ResultM = ALU_ResultM_r;

endmodule