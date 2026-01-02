module hazard_unit(
    input rst,
    input RegWriteM, RegWriteW,
    input ResultSrcM,
    input [4:0] RD_M, RD_W, Rs1_E, Rs2_E, Rs1_D, Rs2_D,
    input ALU_Busy_Stall,       // From Time Redundancy FSM
    output [1:0] ForwardAE, ForwardBE,
    output StallF, StallD, FlushE
);
    // Forwarding logic remains standard
    assign ForwardAE = (rst == 1'b0) ? 2'b00 :
        ((RegWriteM && (RD_M != 0) && (RD_M == Rs1_E))) ? 2'b10 :
        ((RegWriteW && (RD_W != 0) && (RD_W == Rs1_E))) ? 2'b01 : 2'b00;

    assign ForwardBE = (rst == 1'b0) ? 2'b00 :
        ((RegWriteM && (RD_M != 0) && (RD_M == Rs2_E))) ? 2'b10 :
        ((RegWriteW && (RD_W != 0) && (RD_W == Rs2_E))) ? 2'b01 : 2'b00;

    // Load-Use Hazard Stall logic
    wire lwStall;
    assign lwStall = ResultSrcM && ((RD_M == Rs1_D) || (RD_M == Rs2_D));

    // Time Redundancy Logic Integration:
    // We stall Fetch (StallF) and Decode (StallD) for BOTH LW hazards and ALU re-execution.
    assign StallF = lwStall || ALU_Busy_Stall; 
    assign StallD = lwStall || ALU_Busy_Stall; 

    // We only flush Execute (FlushE) for LW stalls. 
    // For ALU_Busy_Stall, we DO NOT flush, because flushing would clear the 
    // instruction currently inside the ALU re-execution loop.
   // Execute should only be flushed for a Load-Use hazard, 
// NEVER when the ALU itself is requesting a stall for redundancy.
assign FlushE = lwStall && !ALU_Busy_Stall;

endmodule