/*******************************************************************************
 * Module: pipeline.v
 * Project: femtoRV32
 * Author: Kareem Elramly, Mohamed AboElfotouh
 * Description: 5-stage pipelined RV32I + RV32M processor (IF, ID, EX, MEM, WB)
 *              with a single unified memory port shared by IF and MEM.
 *              A C0/C1 phase controller gives one instruction slot every two
 *              clock cycles (effective CPI = 2):
 *                C0: memory serves IF, RegFile writes the WB value
 *                C1: memory serves MEM, PC + pipeline registers advance
 *              Hazards: EX forwarding, load-use stall, and (Bonus 4) branches
 *              and jumps resolved in ID with ID-stage forwarding and stalls
 *              (HazardUnit). BTB + 2-bit BHT predictor in IF
 *              (BP_ENABLE = 0 turns it off).
 *
 * Change history:
 *   11/13/26 - Created pipelined top level from datapath.v
 *   11/13/26 - Bonus 4: branch/jump resolution moved from EX to ID, ID-stage
 *              forwarding, HazardUnit, mispredict flush of IF/ID only
 *   11/16/26 - Debug/board observation ports, PROGRAM_FILE parameter
 ******************************************************************************/

`timescale 1ns / 1ps
`include "defines.vh"
`default_nettype none

module pipeline #(
    parameter BP_ENABLE    = 1,
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

    // ---------------- Phase control ----------------
    wire        phase;
    wire        isFetch;
    wire        advance;

    // ---------------- IF ----------------
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

    // ---------------- IF/ID ----------------
    wire [31:0] IF_ID_PC;
    wire [31:0] IF_ID_Inst;
    wire [31:0] IF_ID_PredNextPC;
    wire        IF_ID_PredTaken;
    wire        ifIdLoad;
    wire        ifIdFlush;

    // ---------------- ID ----------------
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
    wire        stall;
    wire        loadUseStall;
    wire        branchStall;
    wire [1:0]  idForwardA;
    wire [1:0]  idForwardB;
    wire [31:0] idRs1Val;
    wire [31:0] idRs2Val;
    wire        idTakeBranch;
    wire        idActualTaken;
    wire [31:0] idActualTarget;
    wire [31:0] idActualNextPC;
    wire        idIsCtrlFlow;
    wire        exMemFwdEn;
    wire        haltNow;
    wire        haltSet;
    wire        haltLatch;
    wire        idExLoad;
    wire        idExFlush;

    // ---------------- ID/EX ----------------
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

    // ---------------- EX ----------------
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
    wire        redirect;
    wire        bpUpdateEn;

    // ---------------- EX/MEM ----------------
    wire        EX_MEM_RegWrite;
    wire        EX_MEM_WbFromMem;
    wire        EX_MEM_MemRead;
    wire        EX_MEM_MemWrite;
    wire [31:0] EX_MEM_Result;
    wire [31:0] EX_MEM_StoreData;
    wire [2:0]  EX_MEM_Funct3;
    wire [4:0]  EX_MEM_Rd;

    // ---------------- MEM/WB ----------------
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
    // IF stage: PC, predictor, shared memory
    // =========================================================================
    assign pcPlus4 = pcValue + 32'd4;

    BranchPredictor predictor(
        .clk(clk),
        .rst(reset),
        .pcIF(pcValue),
        .predictTaken(predictTaken),
        .predictTarget(predictTarget),
        .updateEn(bpUpdateEn),
        .updatePC(IF_ID_PC),
        .actualTaken(idActualTaken),
        .actualTarget(idActualTarget)
    );

    assign predictTakenEff = (BP_ENABLE != 0) ? predictTaken : 1'b0;
    assign predNextPC      = (predictTakenEff) ? predictTarget : pcPlus4;
    assign pcInput         = (redirect)        ? idActualNextPC : predNextPC;

    assign pcLoad = advance & (redirect | (~stall & ~haltNow));

    N_bit_register #(32) pcRegister(
        .clk(clk),
        .rst(reset),
        .Load(pcLoad),
        .D(pcInput),
        .Q(pcValue)
    );

    // Single memory port: C0 = fetch, C1 = MEM stage access
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

    // Fetched word is captured at the end of C0 and held through C1
    N_bit_register #(32) instLatchReg(
        .clk(clk),
        .rst(reset),
        .Load(isFetch),
        .D(memDataOut),
        .Q(instLatch)
    );

    // =========================================================================
    // IF/ID register
    // =========================================================================
    assign ifIdLoad  = advance & ~stall;
    assign ifIdFlush = advance & (redirect | haltNow);

    PipelineReg #(97) IF_ID(
        .clk(clk),
        .rst(reset),
        .load(ifIdLoad),
        .flush(ifIdFlush),
        .D({pcValue, instLatch, predNextPC, predictTakenEff}),
        .Q({IF_ID_PC, IF_ID_Inst, IF_ID_PredNextPC, IF_ID_PredTaken})
    );

    // =========================================================================
    // ID stage
    // =========================================================================
    assign idValid = (IF_ID_Inst != 32'd0);

    control_unit controlUnit(
        .inst(IF_ID_Inst),
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

    assign regWriteEn = MEM_WB_RegWrite & isFetch;

    RegFile #(32) RegisterFile(
        .clk(clk),
        .rst(reset),
        .regwrite(regWriteEn),
        .readreg1(IF_ID_Inst[19:15]),
        .readreg2(IF_ID_Inst[24:20]),
        .writereg(MEM_WB_Rd),
        .writedata(regWriteData),
        .readdata1(readData1),
        .readdata2(readData2),
        .dbgReadReg(dbgRegSel),
        .dbgReadData(dbgRegData)
    );

    ImmGen immGenerator(
        .inst(IF_ID_Inst),
        .genOut(immGenOut)
    );

    // Load-use hazard: one bubble between a load and its consumer
    HazardUnit hazardUnit(
        .idInst(IF_ID_Inst),
        .idValid(idValid),
        .idExMemRead(ID_EX_MemRead),
        .idExRegWrite(ID_EX_RegWrite),
        .idExRd(ID_EX_Rd),
        .exMemMemRead(EX_MEM_MemRead),
        .exMemRd(EX_MEM_Rd),
        .loadUseStall(loadUseStall),
        .branchStall(branchStall),
        .stall(stall)
    );

    // ID-stage forwarding for the branch comparator / JALR base.
    // A load in EX_MEM is never forwarded here (HazardUnit stalls instead).
    assign exMemFwdEn = EX_MEM_RegWrite & ~EX_MEM_WbFromMem;

    ForwardingUnit idForwarding(
        .idExRs1(IF_ID_Inst[19:15]),
        .idExRs2(IF_ID_Inst[24:20]),
        .exMemRd(EX_MEM_Rd),
        .memWbRd(MEM_WB_Rd),
        .exMemRegWrite(exMemFwdEn),
        .memWbRegWrite(MEM_WB_RegWrite),
        .forwardA(idForwardA),
        .forwardB(idForwardB)
    );

    assign idRs1Val = (idForwardA == 2'b10) ? EX_MEM_Result :
                      (idForwardA == 2'b01) ? regWriteData  : readData1;
    assign idRs2Val = (idForwardB == 2'b10) ? EX_MEM_Result :
                      (idForwardB == 2'b01) ? regWriteData  : readData2;

    BranchUnit branchComparator(
        .branch(idBranch),
        .funct3(IF_ID_Inst[14:12]),
        .readData1(idRs1Val),
        .readData2(idRs2Val),
        .takeBranch(idTakeBranch)
    );

    assign idActualTaken  = idTakeBranch | idIsJal | idIsJalr;
    assign idActualTarget = (idIsJalr) ? ((idRs1Val + immGenOut) & ~32'd1)
                                       : (IF_ID_PC + immGenOut);
    assign idActualNextPC = (idActualTaken) ? idActualTarget : (IF_ID_PC + 32'd4);
    assign idIsCtrlFlow   = idBranch | idIsJal | idIsJalr;
    assign redirect       = idIsCtrlFlow & ~stall &
                            (idActualNextPC != IF_ID_PredNextPC);
    assign bpUpdateEn     = advance & ~stall & (idBranch | idIsJal);

    // EBREAK: stop fetching once the halt instruction is past any
    // older branch (a wrong-path halt must not stick)
    assign haltNow = haltLatch | (idHalt & ~stall);
    assign haltSet = advance & idHalt & ~stall;

    DFlipFlop haltFF(
        .clk(clk),
        .rst(reset),
        .D(haltLatch | haltSet),
        .Q(haltLatch)
    );

    // =========================================================================
    // ID/EX register
    // =========================================================================
    assign idExLoad  = advance;
    assign idExFlush = advance & stall;

    PipelineReg #(205) ID_EX(
        .clk(clk),
        .rst(reset),
        .load(idExLoad),
        .flush(idExFlush),
        .D({idRegWrite, idMemToReg, idMemRead, idMemWrite, idBranch,
            idIsJal, idIsJalr, idAluSource, idAluSrcA, idAluOp,
            IF_ID_PC, IF_ID_PredNextPC, readData1, readData2, immGenOut,
            IF_ID_Inst, IF_ID_PredTaken}),
        .Q({ID_EX_RegWrite, ID_EX_MemToReg, ID_EX_MemRead, ID_EX_MemWrite,
            ID_EX_Branch, ID_EX_IsJal, ID_EX_IsJalr, ID_EX_AluSource,
            ID_EX_AluSrcA, ID_EX_AluOp,
            ID_EX_PC, ID_EX_PredNextPC, ID_EX_RegR1, ID_EX_RegR2, ID_EX_Imm,
            ID_EX_Inst, ID_EX_PredTaken})
    );

    assign ID_EX_Rd = ID_EX_Inst[11:7];

    // =========================================================================
    // EX stage
    // =========================================================================
    ForwardingUnit forwarding(
        .idExRs1(ID_EX_Inst[19:15]),
        .idExRs2(ID_EX_Inst[24:20]),
        .exMemRd(EX_MEM_Rd),
        .memWbRd(MEM_WB_Rd),
        .exMemRegWrite(EX_MEM_RegWrite),
        .memWbRegWrite(MEM_WB_RegWrite),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    // Forward on the register value first, then apply the ALUSrc mux
    assign fwdRs1 = (forwardA == 2'b10) ? EX_MEM_Result :
                    (forwardA == 2'b01) ? regWriteData  : ID_EX_RegR1;
    assign fwdRs2 = (forwardB == 2'b10) ? EX_MEM_Result :
                    (forwardB == 2'b01) ? regWriteData  : ID_EX_RegR2;

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

    // =========================================================================
    // EX/MEM register
    // =========================================================================
    PipelineReg #(76) EX_MEM(
        .clk(clk),
        .rst(reset),
        .load(advance),
        .flush(1'b0),
        .D({ID_EX_RegWrite, (ID_EX_MemToReg == `WB_MEM), ID_EX_MemRead,
            ID_EX_MemWrite, exResult, fwdRs2, ID_EX_Inst[14:12],
            ID_EX_Inst[11:7]}),
        .Q({EX_MEM_RegWrite, EX_MEM_WbFromMem, EX_MEM_MemRead,
            EX_MEM_MemWrite, EX_MEM_Result, EX_MEM_StoreData,
            EX_MEM_Funct3, EX_MEM_Rd})
    );

    // =========================================================================
    // MEM/WB register (load data is read from the shared port during C1)
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
    // WB stage
    // =========================================================================
    assign regWriteData = (MEM_WB_WbFromMem) ? MEM_WB_MemOut : MEM_WB_Result;

    // =========================================================================
    // Debug / board observation
    // =========================================================================
    assign dbgPC        = pcValue;
    assign dbgNextPC    = pcInput;
    assign dbgInst      = IF_ID_Inst;
    assign dbgAluResult = exResult;
    assign dbgMemAddr   = {22'd0, memAddr};
    assign dbgMemOut    = memDataOut;
    assign dbgWbData    = regWriteData;
    assign dbgStoreData = EX_MEM_StoreData;
    assign dbgHalt      = haltLatch;

    assign dbgCtrlFlags = {idBranch, idMemRead, idMemWrite, idAluSource,
                           idAluSrcA, idRegWrite, idIsJal, idIsJalr,
                           idMemToReg, idAluOp,
                           loadUseStall, branchStall, redirect, idHalt};
    assign dbgPipeFlags = {phase, advance, stall, redirect, predictTakenEff,
                           forwardA, forwardB, aluSel, aluZero, haltLatch};

endmodule

`default_nettype wire
