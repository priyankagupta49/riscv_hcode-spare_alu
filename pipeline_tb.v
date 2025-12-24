`timescale 1ns / 1ps

module tb();
    // --- Clock and Reset ---
    reg clk = 0;
    reg rst = 0;
    
    // --- Inputs to Instruction Loader ---
    reg [11:0] operand1, operand2;
    reg [2:0] opcode;
    reg test_en_in = 0;      // Manual BIST Trigger
    
    // --- Interconnect Wires ---
    wire [31:0] imem_waddr, imem_wdata;
    wire imem_we;
    wire done_signal; 
    wire [31:0] result_w;
    wire s_err_imem, d_err_imem;
    wire s_err_dmem, d_err_dmem;
    wire alu_fault_active; 

    // --- Clock Generation (100MHz) ---
    always #5 clk = ~clk; 

    // --- Module Instantiations ---
    instr_loader loader (
        .clk(clk), .rst(rst), .op1(operand1), .op2(operand2), .alu_op(opcode),
        .imem_we(imem_we), .imem_addr(imem_waddr), .imem_wdata(imem_wdata), 
        .done(done_signal)
    );

    Pipeline_top dut (
        .clk(clk), .rst(rst), 
        .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata), 
        .loader_done_in(done_signal), 
        .test_en_in(test_en_in),       
        .ResultW_out(result_w),
        .s_err_imem(s_err_imem), .d_err_imem(d_err_imem),
        .s_err_dmem(s_err_dmem), .d_err_dmem(d_err_dmem),
        .hardware_fault_flag(alu_fault_active) 
    );

    // --- Real-time Monitor ---
    initial begin
        $monitor("Time=%0t | BIST_EN=%b | ALU_Fault=%b | ResultW=%d | S_ERR=%b", 
                 $time, test_en_in, alu_fault_active, result_w, s_err_dmem);
    end

    // --- Main Simulation Stimulus ---
    initial begin
        // 1. Reset and Load Program
        rst = 0;
        operand1 = 12'd5; operand2 = 12'd3; opcode = 3'd0; // Expect 5 + 3 = 8
        #15; rst = 1; 
        wait(done_signal === 1'b1);
        $display(" Program Loaded. Starting Execution ");

        // ==========================================================
        // TEST 1: BIST & DYNAMIC RECONFIGURATION (ALU)
        // ==========================================================
        // Wait for ADD instruction to hit Execute Stage
        wait(dut.execute.ALUControlE == 3'b000); 
        #1; 
        
        $display("Step 1: Injecting Primary ALU Fault and Starting Mixed-Op BIST");
        
        // Force a fault in the primary unit's internal result wire
        force dut.execute.primary_alu.res_p = 32'hDEADBEEF; 
        test_en_in = 1; // Assert manual BIST trigger
        
        // Wait for the autonomous logic to detect the fault and latch it
        wait(alu_fault_active === 1'b1); 
        $display("SUCCESS: BIST detected fault and switched to Spare ALU.");
        
        // Release BIST trigger and the forced fault
        test_en_in = 0;
        release dut.execute.primary_alu.res_p;

        // Verify that the Spare ALU maintained the correct mathematical result
        wait(result_w == 32'd8);
        $display("SUCCESS: Pipeline recovered correct ALU result using Spare.");

        // ==========================================================
        // TEST 2: DATA MEMORY ECC (Information Redundancy)
        // ==========================================================
        // Wait for a memory access (RegWrite in Memory stage indicates Write-back is coming)
        wait(dut.execute.RegWriteM == 1'b1);
        #1; 
        
        $display("Step 2: Injecting Single-Bit Error into Data Memory");
        
        // Perform a bit-flip in the memory location being read (index 1)
        dut.memory.dmem.mem[1][30] = ~dut.memory.dmem.mem[1][30]; 
        
        // Wait for the ECC hardware to flip the S_ERR status bit
        wait(s_err_dmem === 1'b1);
        $display("SUCCESS: ECC detected single-bit error (S_ERR=1).");

        // CRITICAL: Sample the result exactly as it reaches the end of the pipeline
        @(posedge clk); 
        #2; // Small settle time to allow logic to stabilize
        
        $display("Final System Result Sampled: %d", result_w);
        
        // Check if the ECC corrected the bit back to 8
        if (result_w == 32'd8)
            $display("VERDICT: ALL FAULT TOLERANT SYSTEMS (ALU & ECC) FUNCTIONAL");
        else
            $display("VERDICT: SYSTEM FAILURE - Data corruption detected at Time %0t", $time);

        $finish;
    end
endmodule