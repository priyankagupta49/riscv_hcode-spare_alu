`timescale 1ns / 1ps

module tb();
    reg clk = 0;
    reg rst = 0;
    reg [11:0] operand1, operand2;
    reg [2:0] opcode;
    wire [31:0] imem_waddr, imem_wdata;
    wire imem_we;
    wire done_signal; 
    wire [31:0] result_w;
    wire s_err_imem, d_err_imem;
    wire s_err_dmem, d_err_dmem;
    wire alu_fault_active; 

    always #5 clk = ~clk; 

    instr_loader loader (
        .clk(clk), .rst(rst), .op1(operand1), .op2(operand2), .alu_op(opcode),
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
        .hardware_fault_flag(alu_fault_active) 
    );

    // --- DEBUG MONITOR: Track the Internal Mux Switch ---
    initial begin
        wait(done_signal === 1'b1);
        forever @(posedge clk) begin
            // Check the values inside the Execute Stage to see why math is wrong
            if (dut.execute.ALUControlE == 3'b000) begin
                $display("INTERNAL: Time=%0t | Primary_Out=%d | Spare_Out=%d | Mux_Selected=%d", 
                          $time, dut.execute.ResultE_Primary, dut.execute.ResultE_Spare, dut.execute.Final_ResultE);
            end
        end
    end

    initial begin
        $monitor("Time=%0t | S_ERR=%b | ALU_Fault=%b | ResultW=%d", $time, s_err_dmem, alu_fault_active, result_w);
    end

    initial begin
        rst = 0;
        operand1 = 12'd5; operand2 = 12'd3; opcode = 3'd0; // ADD (25)
        #15; rst = 1; 
        wait(done_signal === 1'b1);
        $display("--- Program Loaded. Starting Execution ---");

        // ==========================================================
        // TEST 1: ALU DYNAMIC RECONFIGURATION (ALU FAULT)
        // ==========================================================
        wait(dut.execute.ALUControlE == 3'b000); 
        
        $display("Injecting Hard Fault into Primary ALU...");
        // 1. Force the fault
        force dut.execute.primary_alu.Result = 32'hDEADBEEF;
        force dut.execute.primary_alu.force_alu_fault = 1'b1;
        
        // 2. WAIT for the synchronous latch to capture the fault
          @(posedge clk); 
          #1;
//        repeat(2) @(posedge clk);
//        #1;
      release dut.execute.primary_alu.Result;
        release dut.execute.primary_alu.force_alu_fault;

        $display("Status: Fault Latch=%b", alu_fault_active);

        // 3. WAIT for data to propagate through pipeline registers (Execute -> Memory -> Writeback)
      
// OLD: repeat(3) @(posedge clk);
        
        // NEW: Wait until the specific result reaches the END of the pipeline
        wait(result_w == 32'd8); 
         
        #2; // Settle time
        
        if (result_w == 32'd8 && alu_fault_active == 1'b1)
            $display("ALU TEST SUCCESS: Spare maintained 25.");
        else
            $display("ALU TEST FAILURE: Result is %d", result_w);


        // ==========================================================
        // TEST 2: DATA MEMORY ECC (SINGLE BIT ERROR)
        // ==========================================================
        wait(dut.execute.ALU_ResultM_In == 32'd4);                   
        
        $display("Injecting Single-Bit Error into Data Memory...");
        dut.memory.dmem.mem[1][30] = ~dut.memory.dmem.mem[1][30];     
        
        wait(s_err_dmem === 1'b1);
        $display("S_ERR Flag Status: %b", s_err_dmem);

        repeat(2) @(posedge clk);
        #2;      
        $display("Final Corrected Result: %d", result_w);
        
        if (result_w == 32'd8)
            $display("VERDICT: ALL FAULT TOLERANT SYSTEMS FUNCTIONAL");
        else
            $display("VERDICT: SYSTEM FAILURE");

        $finish;
    end
endmodule