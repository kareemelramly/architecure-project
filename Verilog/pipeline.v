/*******************************************************************************
 * Module: pipeline.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Mohamed AboElfotouh
 * Description: 3-stage pipelined RV32I + RV32M processor with one single-ported
 *              unified memory. Every stage takes one slot of two cycles
 *              (C0, C1), so one instruction issues every 2 cycles (CPI = 2):
 *
 *                         C0                      C1
 *                Stage 0  IF  (memory: fetch)     ID  (decode, register read)
 *                Stage 1  EX  (ALU)               MEM (memory: load / store)
 *                Stage 2  WB  (RegFile write)     -
 *
 *              Registers: instLatch (IF -> ID, end of C0), ID_EX (Stage 0 ->
 *              Stage 1, end of C1), EX_MEM (EX -> MEM inside Stage 1, end of
 *              C0), MEM_WB (Stage 1 -> Stage 2, end of C1). PC loads at the
 *              end of C1.
 *
 *              Data hazards: the instruction one ahead is in Stage 2 while
 *              this one is in EX, so EX forwards from MEM_WB (ALU result or
 *              load data); the instruction two ahead has already written the
 *              RegFile in C0. No load-use stall exists.
 *
 *              BRANCH_IN_ID = 0: branches and jumps resolve in EX. A wrong
 *                prediction squashes the Stage 0 instruction (1 slot). The
 *                BTB + 2-bit BHT predictor (Bonus 3, BP_ENABLE) removes the
 *                penalty on learned branches.
 *              BRANCH_IN_ID = 1 (Bonus 4): branches and jumps resolve in ID
 *                (C1 of Stage 0), so the next fetch already uses the right
 *                PC (0 penalty). Operands are forwarded from EX_MEM; a load
 *                directly before the branch costs one stall slot.
 *
 * Change history:
 *   11/13/26 - Created pipelined top level from datapath.v (5 stages)
 *   11/13/26 - Bonus 4: branch/jump resolution in ID, HazardUnit
 *   11/16/26 - Debug/board observation ports, PROGRAM_FILE parameter
 *   11/16/26 - Converted to the 3-stage organization of the project
 *              description; IF_ID removed, EX_MEM is the EX -> MEM latch,
 *              single forwarding source, BRANCH_IN_ID parameter
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"
`default_nettype none

module pipeline #(
    parameter BP_ENABLE    = 1,
    parameter BRANCH_IN_ID = 1,
    parameter PROGRAM_FILE = ""
)(
    input  wire        clk,
    input  wire        reset,

    // Debug / board observation ports (read only, no effect on the CPU)
    input  wire [4:0]  dbgRegSel,
    output wire [31:0] dbgRegData,
    output wire [31:0] dbgPC,
    output wire [31:0] dbgNextPC,
    output wire [31:0] dbgInst,
    output wire [31:0] dbgAluResult,
    output wire [31:0] dbgMemAddr,
    output wire [31:0] dbgMemOut,
    output wire [31:0] dbgWbData,
    output wire [31:0] dbgStoreData,
    output wire [15:0] dbgCtrlFlags,
    output wire [15:0] dbgPipeFlags,
    output wire        dbgHalt
);

    localparam ID_MODE = (BRANCH_IN_ID != 0);

    // ---------------- Phase control ----------------
    wire        phase;
    wire        isFetch;
    wire        advance;

    // ---------------- Stage 0: IF ----------------
    wire [31:0] pcValue;
    wire [31:0] pcInput;
    wire [31:0] pcPlus4;
    wire [31:0] predNextPC;
    wire        predictTaken;
    wire        predictTakenEff;
    wire [31:0] predictTarget;
    wire [31:0] instLatch;
    wire [9:0]  memAddr;
    wire        memReadEn;
    wire        memWriteEn;
    wire [2:0]  memFunct3;
    wire [31:0] memDataOut;
    wire        pcLoad;

    // ---------------- Stage 0: ID ----------------
    wire [31:0] idInst;
    wire        idValid;
    wire        cBranch, cMemRead, cMemWrite, cAluSource, cAluSrcA;
    wire        cRegWrite, cIsJal, cIsJalr, cHalt;
    wire [1:0]  cMemToReg;
    wire [1:0]  cAluOp;
    wire        idBranch, idMemRead, idMemWrite, idAluSource, idAluSrcA;
    wire        idRegWrite, idIsJal, idIsJalr, idHalt;
    wire [1:0]  idMemToReg;
    wire [1:0]  idAluOp;
    wire [31:0] readData1;
    wire [31:0] readData2;
    wire [31:0] immGenOut;
    wire        hazardStall;
    wire        stall;
    wire [1:0]  idForwardA;
    wire [1:0]  idForwardB;
    wire [31:0] idRs1Val;
    wire [31:0] idRs2Val;
    wire        idTakeBranch;
    wire        idActualTaken;
    wire [31:0] idActualTarget;
    wire [31:0] idActualNextPC;
    wire        idIsCtrlFlow;
    wire        idRedirect;
    wire        exMemFwdEn;
    wire        squash;
    wire        haltNow;
    wire        haltSet;
    wire        haltLatch;
    wire        idExFlush;

    // ---------------- ID_EX (Stage 0 -> Stage 1) ----------------
    wire        ID_EX_RegWrite;
    wire [1:0]  ID_EX_MemToReg;
    wire        ID_EX_MemRead;
    wire        ID_EX_MemWrite;
    wire        ID_EX_Branch;
    wire        ID_EX_IsJal;
    wire        ID_EX_IsJalr;
    wire        ID_EX_AluSource;
    wire        ID_EX_AluSrcA;
    wire [1:0]  ID_EX_AluOp;
    wire [31:0] ID_EX_PC;
    wire [31:0] ID_EX_PredNextPC;
    wire [31:0] ID_EX_RegR1;
    wire [31:0] ID_EX_RegR2;
    wire [31:0] ID_EX_Imm;
    wire [31:0] ID_EX_Inst;
    wire        ID_EX_PredTaken;
    wire [4:0]  ID_EX_Rd;

    // ---------------- Stage 1: EX ----------------
    wire [1:0]  forwardA;
    wire [1:0]  forwardB;
    wire [31:0] fwdRs1;
    wire [31:0] fwdRs2;
    wire [31:0] aluInputData1;
    wire [31:0] aluInputData2;
    wire [4:0]  aluSel;
    wire [31:0] aluOutput;
    wire        aluZero;
    wire [31:0] exResult;
    wire        exTakeBranch;
    wire        exActualTaken;
    wire [31:0] exActualTarget;
    wire [31:0] exActualNextPC;
    wire        exIsCtrlFlow;
    wire        exRedirect;

    // ---------------- Branch resolution (selected by BRANCH_IN_ID) -------
    wire        redirect;
    wire [31:0] resolvedNextPC;
    wire        bpUpdateEn;
    wire [31:0] bpUpdatePC;
    wire        bpActualTaken;
    wire [31:0] bpActualTarget;

    // ---------------- EX_MEM (EX -> MEM latch inside Stage 1) ------------
    wire        EX_MEM_RegWrite;
    wire        EX_MEM_WbFromMem;
    wire        EX_MEM_MemRead;
    wire        EX_MEM_MemWrite;
    wire [31:0] EX_MEM_Result;
    wire [31:0] EX_MEM_StoreData;
    wire [2:0]  EX_MEM_Funct3;
    wire [4:0]  EX_MEM_Rd;

    // ---------------- MEM_WB (Stage 1 -> Stage 2) ----------------
    wire        MEM_WB_RegWrite;
    wire        MEM_WB_WbFromMem;
    wire [31:0] MEM_WB_MemOut;
    wire [31:0] MEM_WB_Result;
    wire [4:0]  MEM_WB_Rd;
    wire [31:0] regWriteData;
    wire        regWriteEn;

    // =========================================================================
    // C0/C1 phase controller
    // =========================================================================
    PhaseController phaseCtrl(
        .clk(clk),
        .rst(reset),
        .phase(phase),
        .isFetch(isFetch),
        .advance(advance)
    );

    // =========================================================================
    // Stage 0, C0: IF (PC, predictor, shared memory port)
    // =========================================================================
    assign pcPlus4 = pcValue + 32'd4;

    BranchPredictor predictor(
        .clk(clk),
        .rst(reset),
        .pcIF(pcValue),
        .predictTaken(predictTaken),
        .predictTarget(predictTarget),
        .updateEn(bpUpdateEn),
        .updatePC(bpUpdatePC),
        .actualTaken(bpActualTaken),
        .actualTarget(bpActualTarget)
    );

    assign predictTakenEff = (BP_ENABLE != 0) ? predictTaken : 1'b0;
    assign predNextPC      = (predictTakenEff) ? predictTarget : pcPlus4;
    assign pcInput         = (redirect)        ? resolvedNextPC : predNextPC;

    // A stall keeps the PC, so the next C0 fetches the same word again
    assign pcLoad = advance & (redirect | (~stall & ~haltNow));

    N_bit_register #(32) pcRegister(
        .clk(clk),
        .rst(reset),
        .Load(pcLoad),
        .D(pcInput),
        .Q(pcValue)
    );

    // Single memory port: C0 = fetch, C1 = MEM access of Stage 1
    assign memAddr    = (isFetch) ? pcValue[9:0]    : EX_MEM_Result[9:0];
    assign memReadEn  = (isFetch) ? 1'b1            : EX_MEM_MemRead;
    assign memWriteEn = (isFetch) ? 1'b0            : EX_MEM_MemWrite;
    assign memFunct3  = (isFetch) ? `MEM_LW         : EX_MEM_Funct3;

    UnifiedMem #(10, PROGRAM_FILE) memory(
        .clk(clk),
        .memRead(memReadEn),
        .memWrite(memWriteEn),
        .funct3(memFunct3),
        .addr(memAddr),
        .dataIn(EX_MEM_StoreData),
        .dataOut(memDataOut)
    );

    // IF -> ID boundary inside Stage 0: fetched word captured at end of C0
    N_bit_register #(32) instLatchReg(
        .clk(clk),
        .rst(reset),
        .Load(isFetch),
        .D(memDataOut),
        .Q(instLatch)
    );

    // =========================================================================
    // Stage 0, C1: ID (instruction from instLatch, its PC is pcValue)
    // =========================================================================
    // After EBREAK the refetched words are turned into bubbles
    assign idInst  = (haltLatch) ? 32'd0 : instLatch;
    assign idValid = (idInst != 32'd0);

    control_unit controlUnit(
        .inst(idInst),
        .branch(cBranch),
        .memRead(cMemRead),
        .memWrite(cMemWrite),
        .aluSource(cAluSource),
        .aluSrcA(cAluSrcA),
        .regWrite(cRegWrite),
        .isJal(cIsJal),
        .isJalr(cIsJalr),
        .halt(cHalt),
        .memToReg(cMemToReg),
        .aluOp(cAluOp)
    );

    // Bubbles (all-zero instruction) carry no control
    assign idBranch    = cBranch    & idValid;
    assign idMemRead   = cMemRead   & idValid;
    assign idMemWrite  = cMemWrite  & idValid;
    assign idAluSource = cAluSource & idValid;
    assign idAluSrcA   = cAluSrcA   & idValid;
    assign idRegWrite  = cRegWrite  & idValid;
    assign idIsJal     = cIsJal     & idValid;
    assign idIsJalr    = cIsJalr    & idValid;
    assign idHalt      = cHalt      & idValid;
    assign idMemToReg  = (idValid) ? cMemToReg : `WB_ALU;
    assign idAluOp     = (idValid) ? cAluOp    : `ALUOP_ADD;

    // Stage 2 (WB) writes at the end of C0, before the ID read in C1
    assign regWriteEn = MEM_WB_RegWrite & isFetch;

    RegFile #(32) RegisterFile(
        .clk(clk),
        .rst(reset),
        .regwrite(regWriteEn),
        .readreg1(idInst[19:15]),
        .readreg2(idInst[24:20]),
        .writereg(MEM_WB_Rd),
        .writedata(regWriteData),
        .readdata1(readData1),
        .readdata2(readData2),
        .dbgReadReg(dbgRegSel),
        .dbgReadData(dbgRegData)
    );

    ImmGen immGenerator(
        .inst(idInst),
        .genOut(immGenOut)
    );

    // Bonus 4 only: a branch / JALR in ID whose operand is being loaded by
    // the Stage 1 instruction (data arrives in the same C1) waits one slot
    HazardUnit hazardUnit(
        .idInst(idInst),
        .idValid(idValid),
        .stage1MemRead(ID_EX_MemRead),
        .stage1Rd(ID_EX_Rd),
        .stall(hazardStall)
    );

    assign stall = (ID_MODE) ? hazardStall : 1'b0;

    // ID-stage operands: the Stage 1 ALU result sits in EX_MEM during C1.
    // The instruction two ahead is already in the RegFile.
    assign exMemFwdEn = EX_MEM_RegWrite & ~EX_MEM_WbFromMem;

    ForwardingUnit idForwarding(
        .idExRs1(idInst[19:15]),
        .idExRs2(idInst[24:20]),
        .exMemRd(EX_MEM_Rd),
        .memWbRd(5'd0),
        .exMemRegWrite(exMemFwdEn),
        .memWbRegWrite(1'b0),
        .forwardA(idForwardA),
        .forwardB(idForwardB)
    );

    assign idRs1Val = (idForwardA == 2'b10) ? EX_MEM_Result : readData1;
    assign idRs2Val = (idForwardB == 2'b10) ? EX_MEM_Result : readData2;

    BranchUnit idBranchComparator(
        .branch(idBranch),
        .funct3(idInst[14:12]),
        .readData1(idRs1Val),
        .readData2(idRs2Val),
        .takeBranch(idTakeBranch)
    );

    assign idActualTaken  = idTakeBranch | idIsJal | idIsJalr;
    assign idActualTarget = (idIsJalr) ? ((idRs1Val + immGenOut) & ~32'd1)
                                       : (pcValue + immGenOut);
    assign idActualNextPC = (idActualTaken) ? idActualTarget : pcPlus4;
    assign idIsCtrlFlow   = idBranch | idIsJal | idIsJalr;
    assign idRedirect     = idIsCtrlFlow & ~stall & (idActualNextPC != predNextPC);

    // EX mode: a redirect means the Stage 0 instruction is on the wrong path
    assign squash = (ID_MODE) ? 1'b0 : exRedirect;

    // EBREAK stops fetching once no older branch can still redirect
    assign haltNow = haltLatch | (idHalt & ~stall & ~squash);
    assign haltSet = advance & haltNow & ~haltLatch;

    DFlipFlop haltFF(
        .clk(clk),
        .rst(reset),
        .D(haltLatch | haltSet),
        .Q(haltLatch)
    );

    // =========================================================================
    // ID_EX register (Stage 0 -> Stage 1, end of C1)
    // =========================================================================
    assign idExFlush = advance & (stall | squash);

    PipelineReg #(205) ID_EX(
        .clk(clk),
        .rst(reset),
        .load(advance),
        .flush(idExFlush),
        .D({idRegWrite, idMemToReg, idMemRead, idMemWrite, idBranch,
            idIsJal, idIsJalr, idAluSource, idAluSrcA, idAluOp,
            pcValue, predNextPC, readData1, readData2, immGenOut,
            idInst, predictTakenEff}),
        .Q({ID_EX_RegWrite, ID_EX_MemToReg, ID_EX_MemRead, ID_EX_MemWrite,
            ID_EX_Branch, ID_EX_IsJal, ID_EX_IsJalr, ID_EX_AluSource,
            ID_EX_AluSrcA, ID_EX_AluOp,
            ID_EX_PC, ID_EX_PredNextPC, ID_EX_RegR1, ID_EX_RegR2, ID_EX_Imm,
            ID_EX_Inst, ID_EX_PredTaken})
    );

    assign ID_EX_Rd = ID_EX_Inst[11:7];

    // =========================================================================
    // Stage 1, C0: EX
    // =========================================================================
    // Only source: the Stage 2 instruction in MEM_WB (ALU result or load data)
    ForwardingUnit forwarding(
        .idExRs1(ID_EX_Inst[19:15]),
        .idExRs2(ID_EX_Inst[24:20]),
        .exMemRd(5'd0),
        .memWbRd(MEM_WB_Rd),
        .exMemRegWrite(1'b0),
        .memWbRegWrite(MEM_WB_RegWrite),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    assign fwdRs1 = (forwardA == 2'b01) ? regWriteData : ID_EX_RegR1;
    assign fwdRs2 = (forwardB == 2'b01) ? regWriteData : ID_EX_RegR2;

    assign aluInputData1 = (ID_EX_AluSrcA)   ? ID_EX_PC  : fwdRs1;
    assign aluInputData2 = (ID_EX_AluSource) ? ID_EX_Imm : fwdRs2;

    alu_unit AluControl(
        .aluOp(ID_EX_AluOp),
        .inst(ID_EX_Inst),
        .aluSelection(aluSel)
    );

    ALU #(32) aluModule(
        .aluSel(aluSel),
        .in1(aluInputData1),
        .in2(aluInputData2),
        .result(aluOutput),
        .zero(aluZero)
    );

    // Final non-memory result (so forwarding is right for JAL/JALR/LUI too)
    assign exResult = (ID_EX_MemToReg == `WB_PC4) ? ID_EX_PC + 32'd4 :
                      (ID_EX_MemToReg == `WB_IMM) ? ID_EX_Imm        : aluOutput;

    // EX-stage branch resolution (used when BRANCH_IN_ID = 0)
    BranchUnit exBranchComparator(
        .branch(ID_EX_Branch),
        .funct3(ID_EX_Inst[14:12]),
        .readData1(fwdRs1),
        .readData2(fwdRs2),
        .takeBranch(exTakeBranch)
    );

    assign exActualTaken  = exTakeBranch | ID_EX_IsJal | ID_EX_IsJalr;
    assign exActualTarget = (ID_EX_IsJalr) ? ((fwdRs1 + ID_EX_Imm) & ~32'd1)
                                           : (ID_EX_PC + ID_EX_Imm);
    assign exActualNextPC = (exActualTaken) ? exActualTarget : (ID_EX_PC + 32'd4);
    assign exIsCtrlFlow   = ID_EX_Branch | ID_EX_IsJal | ID_EX_IsJalr;
    assign exRedirect     = exIsCtrlFlow & (exActualNextPC != ID_EX_PredNextPC);

    // =========================================================================
    // Branch resolution point and predictor update
    // =========================================================================
    assign redirect       = (ID_MODE) ? idRedirect     : exRedirect;
    assign resolvedNextPC = (ID_MODE) ? idActualNextPC : exActualNextPC;

    assign bpUpdateEn     = (ID_MODE) ? (advance & ~stall & (idBranch | idIsJal))
                                      : (advance & (ID_EX_Branch | ID_EX_IsJal));
    assign bpUpdatePC     = (ID_MODE) ? pcValue        : ID_EX_PC;
    assign bpActualTaken  = (ID_MODE) ? idActualTaken  : exActualTaken;
    assign bpActualTarget = (ID_MODE) ? idActualTarget : exActualTarget;

    // =========================================================================
    // EX_MEM latch (EX -> MEM inside Stage 1, end of C0)
    // =========================================================================
    PipelineReg #(76) EX_MEM(
        .clk(clk),
        .rst(reset),
        .load(isFetch),
        .flush(1'b0),
        .D({ID_EX_RegWrite, (ID_EX_MemToReg == `WB_MEM), ID_EX_MemRead,
            ID_EX_MemWrite, exResult, fwdRs2, ID_EX_Inst[14:12],
            ID_EX_Inst[11:7]}),
        .Q({EX_MEM_RegWrite, EX_MEM_WbFromMem, EX_MEM_MemRead,
            EX_MEM_MemWrite, EX_MEM_Result, EX_MEM_StoreData,
            EX_MEM_Funct3, EX_MEM_Rd})
    );

    // =========================================================================
    // MEM_WB register (Stage 1 -> Stage 2, end of C1; load data read in C1)
    // =========================================================================
    PipelineReg #(71) MEM_WB(
        .clk(clk),
        .rst(reset),
        .load(advance),
        .flush(1'b0),
        .D({EX_MEM_RegWrite, EX_MEM_WbFromMem, memDataOut, EX_MEM_Result,
            EX_MEM_Rd}),
        .Q({MEM_WB_RegWrite, MEM_WB_WbFromMem, MEM_WB_MemOut, MEM_WB_Result,
            MEM_WB_Rd})
    );

    // =========================================================================
    // Stage 2, C0: WB
    // =========================================================================
    assign regWriteData = (MEM_WB_WbFromMem) ? MEM_WB_MemOut : MEM_WB_Result;

    // =========================================================================
    // Debug / board observation
    // =========================================================================
    assign dbgPC        = pcValue;
    assign dbgNextPC    = pcInput;
    assign dbgInst      = idInst;
    assign dbgAluResult = exResult;
    assign dbgMemAddr   = {22'd0, memAddr};
    assign dbgMemOut    = memDataOut;
    assign dbgWbData    = regWriteData;
    assign dbgStoreData = EX_MEM_StoreData;
    assign dbgHalt      = haltLatch;

    assign dbgCtrlFlags = {idBranch, idMemRead, idMemWrite, idAluSource,
                           idAluSrcA, idRegWrite, idIsJal, idIsJalr,
                           idMemToReg, idAluOp,
                           stall, squash, redirect, idHalt};
    assign dbgPipeFlags = {phase, advance, stall, redirect, predictTakenEff,
                           forwardA, forwardB, aluSel, aluZero, haltLatch};

endmodule

`default_nettype wire
