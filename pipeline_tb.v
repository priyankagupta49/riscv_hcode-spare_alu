`timescale 1ns / 1ps

module tb_pipeline_time_redundancy();
    // --- Clock and Reset ---
    reg clk = 0;
    reg rst = 0;
    
    // --- Inputs to Instruction Loader ---
    reg [11:0] operand1, operand2;
    reg [2:0] opcode;
    
    // --- Interconnect Wires ---
    wire [31:0] imem_waddr, imem_wdata;
    wire imem_we;
    wire done_signal; 
    wire [31:0] result_w;
    wire s_err_imem, d_err_imem;
    wire s_err_dmem, d_err_dmem;
    wire alu_fault_detected; 

    // Hierarchy References for monitoring
    `define ALU_PATH dut.execute.time_redundant_alu
    `define REG_FILE dut.decode.rf.Register
    `define HAZARD   dut.Forwarding_Block

    // --- Clock Generation (100MHz) ---
    always #5 clk = ~clk; 

    // --- Module Instantiations ---
    instr_loader loader (
        .clk(clk), .rst(rst), 
        .op1(operand1), .op2(operand2), .alu_op(opcode),
        .imem_we(imem_we), .imem_addr(imem_waddr), .imem_wdata(imem_wdata), 
        .done(done_signal)
    );

    Pipeline_top dut (
        .clk(clk), .rst(rst), 
        .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata), 
        .loader_done_in(done_signal), 
        .ResultW_out(result_w),
        .s_err_imem(s_err_imem), .d_err_imem(d_err_imem),
        .s_err_dmem(s_err_dmem), .d_err_dmem(d_err_dmem),
        .hardware_fault_flag(alu_fault_detected) 
    );

    // ==========================================================
    // 1. DYNAMIC MONITORING
    // ==========================================================
//    always @(posedge clk) begin
//        if (rst && done_signal) begin
//            // Track the ALU FSM and Pipeline Stall status
//            if (`ALU_PATH.state != 2'b00) begin
//                $display("[Time=%0t] ALU State=%b | StallF=%b | PC=%h", 
//                         $time, `ALU_PATH.state, `HAZARD.StallF, dut.fetch.PCF);
//            end
//        end
//    end

    // ==========================================================
    // 2. MAIN SIMULATION Stimulus
    // ==========================================================
    initial begin
        // --- Step 1: System Reset & Load ---
        rst = 0;
        // Setting operands to 10 and 5 as per your top_fpga defaults
        operand1 = 12'd10; 
        operand2 = 12'd8; 
        opcode   = 3'b000; // ADD operation (10 + 5 = 15)
        
        #20 rst = 1;
        
        wait(done_signal === 1'b1);
        $display("\n Program Loaded. Pipeline Starting ");

        // --- Step 2: Fault Injection Test ---
        // We wait until the ADD instruction is in the ALU (PC should be around 0x8)
        wait(dut.fetch.PCF == 32'h8);
        wait(`ALU_PATH.state == 2'b01); // Wait for Stage 2 (Redundant Execute)
        
        $display("\nTEST 1: Injecting Transient Fault in Execute Stage-2");
        #1 force `ALU_PATH.u_alu.Result =~`ALU_PATH.u_alu.Result;
        // 32'hFFFFFFFF; // Corrupt the result
        
        @(posedge clk); 
        #1 release `ALU_PATH.u_alu.Result;
        $display(" Fault Injected and Released. Waiting for Stage-3 Clean Re-compute");

        // Verify recovery triggered
        wait(`ALU_PATH.state == 2'b10);
        $display(" SUCCESS: ALU detected mismatch and entered STAGE-3 (Recovery).");

        // --- Step 3: Memory ECC Test ---
        #100;
        $display("\nTEST 2: Injecting Single-Bit Error into Data Memory");
        // Flip bit 0 of the stored result in Data Memory (Addr 4 -> Index 1)
        wait(dut.memory.MemWriteM == 1'b1); // Wait for the SW instruction
        #20; // Allow write to complete
        dut.memory.dmem.mem[1][10] = ~dut.memory.dmem.mem[1][10]; 
        $display(">>> Bit flipped in memory. Waiting for LW instruction to correct it...");

        // --- Step 4: Final Verdict (Synchronized) ---
        // Instead of a fixed timer, we wait until the final register (r12) is updated
        // Register 12 is 'r_load' in your instr_loader
        wait(`REG_FILE[12] !== 32'h0); 
        
        #100;
      
        $display("FINAL REPORT");
        $display("Register 9  (Op1): %d", `REG_FILE[9]);
        $display("Register 10 (Op2): %d", `REG_FILE[10]);
        $display("Register 11 (Res): %d", `REG_FILE[11]);
       // $display("Register 12 (Final): %d", `REG_FILE[12]);
        
        // Logical check: 10 + 5 = 15 (0xF)
//        if (`REG_FILE[12] == 32'd15) begin
//            $display("VERDICT: SYSTEM PASSED");
//            $display("Fault Tolerance: Time Redundancy corrected ALU fault.");
//            $display("Fault Tolerance: Hamming ECC corrected Memory fault.");
//        end else begin
//            $display("VERDICT: SYSTEM FAILED - Final Result Incorrect.");
//        end
//        $display("==================================================\n");

        $finish;
    end


endmodule



////***
`timescale 1ns / 1ps

module tb_pipeline_time_redundancy;

    // --------------------------------------------------
    // Clock and Reset
    // --------------------------------------------------
    reg clk = 0;
    reg rst = 0;
    always #5 clk = ~clk;   // 100 MHz

    // --------------------------------------------------
    // Loader Inputs
    // --------------------------------------------------
    reg [11:0] operand1, operand2;
    reg [2:0]  opcode;

    // --------------------------------------------------
    // Wires
    // --------------------------------------------------
    wire [31:0] imem_waddr, imem_wdata;
    wire        imem_we;
    wire        done_signal;

    wire [31:0] result_w;
    wire        alu_fault_detected;

    // --------------------------------------------------
    // VERIFIED HIERARCHY MACROS
    // --------------------------------------------------
    `define ALU_FT    dut.execute.time_redundant_alu
    `define ALU_CORE  dut.execute.time_redundant_alu.u_alu
    `define REG_FILE dut.decode.rf.Register

    // --------------------------------------------------
    // Instruction Loader
    // --------------------------------------------------
    instr_loader loader (
        .clk(clk),
        .rst(rst),
        .op1(operand1),
        .op2(operand2),
        .alu_op(opcode),
        .imem_we(imem_we),
        .imem_addr(imem_waddr),
        .imem_wdata(imem_wdata),
        .done(done_signal)
    );

    // --------------------------------------------------
    // Pipeline DUT
    // --------------------------------------------------
    Pipeline_top dut (
        .clk(clk),
        .rst(rst),
        .imem_we(imem_we),
        .imem_waddr(imem_waddr),
        .imem_wdata(imem_wdata),
        .loader_done_in(done_signal),
        .ResultW_out(result_w),
        .hardware_fault_flag(alu_fault_detected)
    );

    // ==================================================
    // MAIN TEST
    // ==================================================
    initial begin

        // --------------------------------------------------
        // Reset & Program Load
        // --------------------------------------------------
        rst = 0;
        operand1 = 12'd10;
        operand2 = 12'd8;
        opcode   = 3'b000;   // ADD
        #20 rst = 1;

        wait (done_signal);
        $display("\n--- PROGRAM LOADED ---");

        // --------------------------------------------------
        // DISPLAY TIME-REDUNDANT ALU STAGES
        // --------------------------------------------------
        $display("\n--- TIME REDUNDANT ALU STAGES ---");

        // ---- Time Stage 1 ----
        wait (`ALU_FT.state == 2'b00);
        @(posedge clk);
        #1;
        $display("ALU Time Stage T1 Result : %0d", `ALU_FT.res_t1);

        // ---- Time Stage 2 ----
        wait (`ALU_FT.state == 2'b01);
        @(posedge clk);
           force `ALU_CORE.Result = ~`ALU_CORE.Result;
        #1;
        $display("ALU Time Stage T2 Result : %0d", `ALU_FT.res_t2);

        // --------------------------------------------------
        // Inject transient ALU fault (during T2)
        // --------------------------------------------------
        $display("\n--- Injecting Transient ALU Fault ---");
//        force `ALU_CORE.Result = ~`ALU_CORE.Result;
        @(posedge clk);
        release `ALU_CORE.Result;

        // ---- Time Stage 3 (Voted Result) ----
        wait (`ALU_FT.state == 2'b10);
        @(posedge clk);
        #1;
        $display("ALU Time Stage T3 Result : %0d", `ALU_FT.Result);

        // --------------------------------------------------
        // WAIT FOR ARCHITECTURAL COMMIT
        // --------------------------------------------------
        wait (`REG_FILE[11] == 32'd18);
        #1;
        $display("\nWriteback Result (Recovered): %0d", `REG_FILE[11]);

        // --------------------------------------------------
        // Memory ECC Fault Injection
        // --------------------------------------------------
        #100;
        wait (dut.memory.MemWriteM);
        #20;
        dut.memory.dmem.mem[1][7] = ~dut.memory.dmem.mem[1][7];
        $display("Memory bit flipped");

        // --------------------------------------------------
        // Final Report
        // --------------------------------------------------
        #50;
        $display("\n=========== FINAL REPORT ===========");
        $display("Register x9  (Op1): %0d", `REG_FILE[9]);
        $display("Register x10 (Op2): %0d", `REG_FILE[10]);
        $display("Register x11 (Result): %0d", `REG_FILE[11]);
        $display("ALU Fault Flag: %b", alu_fault_detected);
        $display("===================================");

        $finish;
    end

endmodule
