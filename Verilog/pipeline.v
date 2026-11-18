/*******************************************************************************
 * Module: pipeline.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Mohamed AboElfotouh
 * Description: Pipelined RV32I (+ RV32M) processor with one single-ported
 *              memory for instructions and data. One instruction is issued
 *              every 2 cycles (CPI = 2). Each instruction takes 6 cycles in
 *              3 stages of 2 cycles (C0, C1) each:
 *                Stage 0: IF  (C0)  memory read at PC     -> IF_ID
 *                         ID  (C1)  decode, register read -> ID_EX
 *                Stage 1: EX  (C0)  ALU, branch decision  -> EX_MEM
 *                         MEM (C1)  load / store          -> MEM_WB
 *                Stage 2: WB  (C0)  register file write;   C1 unused
 *              The memory is used by IF in C0 and by MEM in C1 only, so
 *              there is no structural hazard.
 *              Branches and jumps (Bonus 4) are resolved in ID (C1). The
 *              next fetch is in the following C0, so a taken branch or
 *              jump loads its target into PC at the end of that C1 and no
 *              wrong-path instruction is ever fetched: no flush, 0 cycles
 *              lost.
 *              Data hazards: when an instruction is in ID, the instruction
 *              before it is in MEM (its result is in EX_MEM, or it is a
 *              load reading the memory in this same C1) and the one before
 *              that was written back in the previous C0. One forwarding
 *              path EX_MEM/memory -> ID therefore gives ID the right
 *              register values, for the branch compare, the JALR target
 *              and ID_EX. Nothing needs forwarding into EX and the
 *              pipeline never stalls.
 *              EBREAK (decoded in ID) freezes the PC; older instructions
 *              still complete.
 *
 * Change history:
 *   11/13/26 - Created pipelined top level from datapath.v
 *   11/16/26 - Debug/board observation ports, PROGRAM_FILE parameter
 *   11/18/26 - Rebuilt as the 3-stage, 6-cycle pipeline of the project
 *              description: one forwarding path, no stalls, branch in EX
 *   11/18/26 - Bonus 4: branch outcome and target computed in ID;
 *              forwarding moved from EX to ID; IF_ID flush only on halt
 *   11/18/26 - Debug ports and LED flag bus removed (only PC, instruction,
 *              write-back data and halt leave the CPU); signals renamed
 *              by stage (IF_, ID_, EX_, MEM_, WB_)
 *   11/18/26 - Board observation outputs for EX result, memory port,
 *              store data and write-back register
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"
`default_nettype none

module pipeline #(
    parameter PROGRAM_FILE = "",
    parameter ADDR_BITS    = `MEM_ADDR_BITS
)(
    input  wire        clk,
    input  wire        rst,

    // Board observation (read only)
    output wire [31:0] pcOut,          // IF: PC
    output wire [31:0] instOut,        // ID: instruction
    output wire [31:0] exResultOut,    // EX: result (ALU, PC + 4 or imm)
    output wire [31:0] memAddrOut,     // memory port address
    output wire [31:0] memDataOut,     // memory port data out
    output wire [31:0] storeDataOut,   // MEM: store data
    output wire [31:0] wbDataOut,      // WB: data written to the reg file
    output wire [4:0]  wbRdOut,        // WB: destination (0 = no write)
    output wire        halted
);

    // ---------------- Phase ----------------
    wire        phase;
    wire        isC0;
    wire        isC1;

    // ---------------- IF (C0) ----------------
    wire [31:0] IF_PC;
    wire [31:0] IF_PcPlus4;
    wire [31:0] IF_PcNext;
    wire        IF_PcLoad;
    wire [ADDR_BITS-1:0] memPortAddr;
    wire        memPortRead;
    wire        memPortWrite;
    wire [2:0]  memPortFunct3;
    wire [31:0] memPortDataOut;

    // ---------------- IF_ID ----------------
    wire [63:0] IF_ID_In;
    wire        IF_ID_Flush;
    wire [63:0] IF_ID_Out;
    wire [31:0] IF_ID_PC;
    wire [31:0] IF_ID_Inst;

    // ---------------- ID (C1) ----------------
    wire        ID_Valid;
    wire        ID_Branch;
    wire        ID_MemRead;
    wire        ID_MemWrite;
    wire        ID_AluSource;
    wire        ID_AluSrcA;
    wire        ID_RegWrite;
    wire        ID_IsJal;
    wire        ID_IsJalr;
    wire        ID_Halt;
    wire [1:0]  ID_MemToReg;
    wire [1:0]  ID_AluOp;
    wire [8:0]  ID_Ctrl;
    wire        ID_HaltValid;
    wire [31:0] ID_ReadData1;
    wire [31:0] ID_ReadData2;
    wire [31:0] ID_Imm;
    wire [31:0] ID_Rs1Data;
    wire [31:0] ID_Rs2Data;
    wire        ID_BranchValid;
    wire        ID_JalValid;
    wire        ID_JalrValid;
    wire        ID_TakeBranch;
    wire        ID_PcSrc;
    wire [31:0] ID_BranchTarget;
    wire [31:0] ID_JalrSum;
    wire [31:0] ID_JumpTarget;
    wire        ID_HaltSet;
    wire        haltNext;
    wire        haltState;

    // ---------------- ID_EX ----------------
    wire [168:0] ID_EX_In;
    wire [168:0] ID_EX_Out;
    wire        ID_EX_RegWrite;
    wire [1:0]  ID_EX_MemToReg;
    wire        ID_EX_MemRead;
    wire        ID_EX_MemWrite;
    wire        ID_EX_AluSource;
    wire        ID_EX_AluSrcA;
    wire [1:0]  ID_EX_AluOp;
    wire [31:0] ID_EX_PC;
    wire [31:0] ID_EX_RegR1;
    wire [31:0] ID_EX_RegR2;
    wire [31:0] ID_EX_Imm;
    wire [31:0] ID_EX_Inst;
    wire [4:0]  ID_EX_Rd;
    wire [2:0]  ID_EX_Funct3;

    // ---------------- EX (C0) ----------------
    wire [31:0] EX_AluIn1;
    wire [31:0] EX_AluIn2;
    wire [4:0]  EX_AluSel;
    wire [31:0] EX_AluOut;
    wire        EX_AluZero;
    wire [31:0] EX_PcPlus4;
    wire [31:0] EX_Result;
    wire        EX_WbFromMem;

    // ---------------- EX_MEM ----------------
    wire [75:0] EX_MEM_In;
    wire [75:0] EX_MEM_Out;
    wire        EX_MEM_RegWrite;
    wire        EX_MEM_WbFromMem;
    wire        EX_MEM_MemRead;
    wire        EX_MEM_MemWrite;
    wire [31:0] EX_MEM_Result;
    wire [31:0] EX_MEM_StoreData;
    wire [2:0]  EX_MEM_Funct3;
    wire [4:0]  EX_MEM_Rd;

    // ---------------- MEM_WB / WB (C0) ----------------
    wire [70:0] MEM_WB_In;
    wire [70:0] MEM_WB_Out;
    wire        MEM_WB_RegWrite;
    wire        MEM_WB_WbFromMem;
    wire [31:0] MEM_WB_MemOut;
    wire [31:0] MEM_WB_Result;
    wire [4:0]  MEM_WB_Rd;
    wire [31:0] WB_Data;
    wire        WB_RegWriteEn;

    // =========================================================================
    // C0 / C1 phase
    // =========================================================================
    PhaseController phaseCtrl(
        .clk(clk),
        .rst(rst),
        .phase(phase),
        .isC0(isC0),
        .isC1(isC1)
    );

    // =========================================================================
    // Stage 0, C0: IF
    // =========================================================================
    assign IF_PcPlus4 = IF_PC + `PC_STEP;
    assign IF_PcNext  = (isC1) ? ID_JumpTarget : IF_PcPlus4;

    // PC moves to PC + 4 at the end of C0 (after the fetch), and to the
    // target at the end of C1 when the branch/jump in ID is taken. EBREAK
    // freezes it.
    assign IF_PcLoad = (isC0 | (isC1 & ID_PcSrc)) & ~haltState;

    N_bit_register #(32) pcRegister(
        .clk(clk),
        .rst(rst),
        .Load(IF_PcLoad),
        .D(IF_PcNext),
        .Q(IF_PC)
    );

    // Single memory port: C0 = fetch, C1 = MEM stage access
    assign memPortAddr   = (isC0) ? IF_PC[ADDR_BITS-1:0]
                                  : EX_MEM_Result[ADDR_BITS-1:0];
    assign memPortRead   = (isC0) ? 1'b1    : EX_MEM_MemRead;
    assign memPortWrite  = (isC0) ? 1'b0    : EX_MEM_MemWrite;
    assign memPortFunct3 = (isC0) ? `MEM_LW : EX_MEM_Funct3;

    UnifiedMem #(
        .ADDR_BITS(ADDR_BITS),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) memory(
        .clk(clk),
        .memRead(memPortRead),
        .memWrite(memPortWrite),
        .funct3(memPortFunct3),
        .addr(memPortAddr),
        .dataIn(EX_MEM_StoreData),
        .dataOut(memPortDataOut)
    );

    // =========================================================================
    // IF_ID: captures at the end of C0. After EBREAK the fetched word is
    // turned into a bubble. Branches never need a flush (resolved in ID,
    // before the next fetch).
    // =========================================================================
    assign IF_ID_In    = {IF_PC, memPortDataOut};
    assign IF_ID_Flush = isC0 & haltState;

    PipelineReg #(64) IF_ID(
        .clk(clk),
        .rst(rst),
        .load(isC0),
        .flush(IF_ID_Flush),
        .D(IF_ID_In),
        .Q(IF_ID_Out)
    );

    assign {IF_ID_PC, IF_ID_Inst} = IF_ID_Out;

    // =========================================================================
    // Stage 0, C1: ID
    // =========================================================================
    // An all-zero word is a bubble (opcode 0 would otherwise decode as LB)
    assign ID_Valid = (IF_ID_Inst != 32'd0);

    control_unit controlUnit(
        .inst(IF_ID_Inst),
        .branch(ID_Branch),
        .memRead(ID_MemRead),
        .memWrite(ID_MemWrite),
        .aluSource(ID_AluSource),
        .aluSrcA(ID_AluSrcA),
        .regWrite(ID_RegWrite),
        .isJal(ID_IsJal),
        .isJalr(ID_IsJalr),
        .halt(ID_Halt),
        .memToReg(ID_MemToReg),
        .aluOp(ID_AluOp)
    );

    // Bubbles carry no control. Branch/jump bits stay in ID (resolved
    // there); JAL/JALR still reach WB through memToReg = PC + 4.
    assign ID_Ctrl      = (ID_Valid) ? {ID_RegWrite, ID_MemToReg, ID_MemRead,
                                        ID_MemWrite, ID_AluSource,
                                        ID_AluSrcA, ID_AluOp}
                                     : 9'd0;
    assign ID_HaltValid = ID_Halt & ID_Valid;

    // The register file is written in C0 (WB) and read in C1 (ID), so a
    // value written back is always visible to the next read
    assign WB_RegWriteEn = MEM_WB_RegWrite & isC0;

    RegFile #(32) RegisterFile(
        .clk(clk),
        .rst(rst),
        .regwrite(WB_RegWriteEn),
        .readreg1(IF_ID_Inst[19:15]),
        .readreg2(IF_ID_Inst[24:20]),
        .writereg(MEM_WB_Rd),
        .writedata(WB_Data),
        .readdata1(ID_ReadData1),
        .readdata2(ID_ReadData2)
    );

    ImmGen immGenerator(
        .inst(IF_ID_Inst),
        .genOut(ID_Imm)
    );

    // ---- Forwarding into ID (used in C1) ----
    // The instruction before this one is in MEM: ForwardingUnit takes its
    // EX result from EX_MEM, or for a load the memory output of this C1.
    ForwardingUnit forwarding(
        .idRs1(IF_ID_Inst[19:15]),
        .idRs2(IF_ID_Inst[24:20]),
        .regData1(ID_ReadData1),
        .regData2(ID_ReadData2),
        .exMemRd(EX_MEM_Rd),
        .exMemRegWrite(EX_MEM_RegWrite),
        .exMemIsLoad(EX_MEM_WbFromMem),
        .exMemResult(EX_MEM_Result),
        .memReadData(memPortDataOut),
        .rs1Data(ID_Rs1Data),
        .rs2Data(ID_Rs2Data)
    );

    // ---- Branch / jump resolution in ID (Bonus 4) ----
    assign ID_BranchValid = ID_Branch & ID_Valid;
    assign ID_JalValid    = ID_IsJal  & ID_Valid;
    assign ID_JalrValid   = ID_IsJalr & ID_Valid;

    BranchUnit branchComparator(
        .branch(ID_BranchValid),
        .funct3(IF_ID_Inst[14:12]),
        .readData1(ID_Rs1Data),
        .readData2(ID_Rs2Data),
        .takeBranch(ID_TakeBranch)
    );

    // Branch / JAL target = PC + imm, JALR target = (rs1 + imm), bit 0
    // cleared
    assign ID_BranchTarget = IF_ID_PC + ID_Imm;
    assign ID_JalrSum      = ID_Rs1Data + ID_Imm;
    assign ID_JumpTarget   = (ID_JalrValid) ? {ID_JalrSum[31:1], 1'b0}
                                            : ID_BranchTarget;
    assign ID_PcSrc        = ID_TakeBranch | ID_JalValid | ID_JalrValid;

    // EBREAK: once decoded, the PC never moves again
    assign ID_HaltSet = isC1 & ID_HaltValid;
    assign haltNext   = haltState | ID_HaltSet;

    DFlipFlop haltFF(
        .clk(clk),
        .rst(rst),
        .D(haltNext),
        .Q(haltState)
    );

    // =========================================================================
    // ID_EX: captures at the end of C1 (stage 0 -> stage 1 boundary)
    // =========================================================================
    // Register values are already forwarded, so EX needs no forwarding
    assign ID_EX_In = {ID_Ctrl, IF_ID_PC, ID_Rs1Data, ID_Rs2Data, ID_Imm,
                      IF_ID_Inst};

    PipelineReg #(169) ID_EX(
        .clk(clk),
        .rst(rst),
        .load(isC1),
        .flush(1'b0),
        .D(ID_EX_In),
        .Q(ID_EX_Out)
    );

    assign {ID_EX_RegWrite, ID_EX_MemToReg, ID_EX_MemRead, ID_EX_MemWrite,
            ID_EX_AluSource, ID_EX_AluSrcA, ID_EX_AluOp,
            ID_EX_PC, ID_EX_RegR1, ID_EX_RegR2, ID_EX_Imm,
            ID_EX_Inst} = ID_EX_Out;

    assign ID_EX_Rd     = ID_EX_Inst[11:7];
    assign ID_EX_Funct3 = ID_EX_Inst[14:12];

    // =========================================================================
    // Stage 1, C0: EX
    // =========================================================================
    // ID_EX already holds forwarded register values
    assign EX_AluIn1 = (ID_EX_AluSrcA)   ? ID_EX_PC  : ID_EX_RegR1;
    assign EX_AluIn2 = (ID_EX_AluSource) ? ID_EX_Imm : ID_EX_RegR2;

    alu_unit AluControl(
        .aluOp(ID_EX_AluOp),
        .inst(ID_EX_Inst),
        .aluSelection(EX_AluSel)
    );

    ALU #(32) aluModule(
        .aluSel(EX_AluSel),
        .in1(EX_AluIn1),
        .in2(EX_AluIn2),
        .result(EX_AluOut),
        .zero(EX_AluZero)
    );

    // Final non-memory result, so forwarding is right for JAL/JALR/LUI too
    assign EX_PcPlus4   = ID_EX_PC + `PC_STEP;
    assign EX_Result    = (ID_EX_MemToReg == `WB_PC4) ? EX_PcPlus4 :
                          (ID_EX_MemToReg == `WB_IMM) ? ID_EX_Imm : EX_AluOut;
    assign EX_WbFromMem = (ID_EX_MemToReg == `WB_MEM);

    // =========================================================================
    // EX_MEM: captures at the end of C0
    // =========================================================================
    assign EX_MEM_In = {ID_EX_RegWrite, EX_WbFromMem, ID_EX_MemRead,
                       ID_EX_MemWrite, EX_Result, ID_EX_RegR2, ID_EX_Funct3,
                       ID_EX_Rd};

    PipelineReg #(76) EX_MEM(
        .clk(clk),
        .rst(rst),
        .load(isC0),
        .flush(1'b0),
        .D(EX_MEM_In),
        .Q(EX_MEM_Out)
    );

    assign {EX_MEM_RegWrite, EX_MEM_WbFromMem, EX_MEM_MemRead,
            EX_MEM_MemWrite, EX_MEM_Result, EX_MEM_StoreData,
            EX_MEM_Funct3, EX_MEM_Rd} = EX_MEM_Out;

    // =========================================================================
    // Stage 1, C1: MEM (memory port, see IF above).
    // MEM_WB captures at the end of C1 (stage 1 -> stage 2 boundary)
    // =========================================================================
    assign MEM_WB_In = {EX_MEM_RegWrite, EX_MEM_WbFromMem, memPortDataOut,
                       EX_MEM_Result, EX_MEM_Rd};

    PipelineReg #(71) MEM_WB(
        .clk(clk),
        .rst(rst),
        .load(isC1),
        .flush(1'b0),
        .D(MEM_WB_In),
        .Q(MEM_WB_Out)
    );

    assign {MEM_WB_RegWrite, MEM_WB_WbFromMem, MEM_WB_MemOut,
            MEM_WB_Result, MEM_WB_Rd} = MEM_WB_Out;

    // =========================================================================
    // Stage 2, C0: WB (register file write enabled by WB_RegWriteEn above)
    // =========================================================================
    assign WB_Data = (MEM_WB_WbFromMem) ? MEM_WB_MemOut : MEM_WB_Result;

    // =========================================================================
    // Board observation
    // =========================================================================
    assign pcOut        = IF_PC;
    assign instOut      = IF_ID_Inst;
    assign exResultOut  = EX_Result;
    assign memAddrOut   = {{(32 - ADDR_BITS){1'b0}}, memPortAddr};
    assign memDataOut   = memPortDataOut;
    assign storeDataOut = EX_MEM_StoreData;
    assign wbDataOut    = WB_Data;
    assign wbRdOut      = (MEM_WB_RegWrite) ? MEM_WB_Rd : `REG_ZERO;
    assign halted       = haltState;

endmodule

`default_nettype wire
