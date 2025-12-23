module ALU_ft(
    input clk, rst,               // Standard System Clock and Reset
    input [31:0] A, B,
    input [2:0] ALUControl,
    output [31:0] Result,
    output Carry, OverFlow, Zero, Negative,
    input  force_alu_fault,       // Fault injection signal
    output fault_detected_out     // Reconfiguration status
);
    wire [31:0] res_p, res_s;
    wire c_p, v_p, z_p, n_p;
    wire c_s, v_s, z_s, n_s;
    reg use_spare;

    // 1. Instantiate Primary and Spare ALUs
    ALU Primary_ALU (.A(A), .B(B), .ALUControl(ALUControl), .Result(res_p), .Carry(c_p), .OverFlow(v_p), .Zero(z_p), .Negative(n_p));
    ALU Spare_ALU   (.A(A), .B(B), .ALUControl(ALUControl), .Result(res_s), .Carry(c_s), .OverFlow(v_s), .Zero(z_s), .Negative(n_s));

    // 2. SYNTHESIZABLE LATCH LOGIC
    // We check the fault signal on every clock edge
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            use_spare <= 1'b0; // Reset to Primary ALU
        end else if (force_alu_fault) begin
            use_spare <= 1'b1; // Permanently switch to Spare if fault detected
        end
    end

    // 3. Reconfiguration Multiplexers
    assign Result   = use_spare ? res_s : res_p;
    assign Carry    = use_spare ? c_s   : c_p;
    assign OverFlow = use_spare ? v_s   : v_p;
    assign Zero     = use_spare ? z_s   : z_p;
    assign Negative = use_spare ? n_s   : n_p;
    
    assign fault_detected_out = use_spare;

endmodule