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
 *              Data hazards: the only producer not yet written back when an
 *              instruction reads its registers is the instruction just
 *              before it, which is in WB while the consumer is in EX.
 *              MEM_WB -> EX forwarding covers it (loads included), so the
 *              pipeline never stalls.
 *              Control hazards: branches and jumps are resolved in EX. A
 *              taken branch/jump loads the target into PC and flushes the
 *              one wrong-path instruction in IF_ID (1 slot = 2 cycles).
 *              EBREAK (decoded in ID) freezes the PC; older instructions
 *              still complete.
 *
 * Change history:
 *   11/13/26 - Created pipelined top level from datapath.v
 *   11/16/26 - Debug/board observation ports, PROGRAM_FILE parameter
 *   11/18/26 - Rebuilt as the 3-stage, 6-cycle pipeline of the project
 *              description: one forwarding path, no stalls, branch in EX
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

    // Debug / board observation ports (read only, no effect on the CPU)
    input  wire [4:0]  dbgRegSel,
    output wire [31:0] dbgRegData,
    output wire [31:0] dbgPC,
    output wire [31:0] dbgInst,
    output wire [31:0] dbgAluResult,
    output wire [31:0] dbgMemAddr,
    output wire [31:0] dbgMemOut,
    output wire [31:0] dbgWbData,
    output wire [31:0] dbgStoreData,
    output wire [15:0] dbgFlags,
    output wire        dbgHalt
);

    // ---------------- Phase ----------------
    wire        phase;
    wire        isC0;
    wire        isC1;

    // ---------------- IF (C0) ----------------
    wire [31:0] pcValue;
    wire [31:0] pcPlus4;
    wire [31:0] pcNext;
    wire        pcLoad;
    wire [ADDR_BITS-1:0] memAddr;
    wire        memReadEn;
    wire        memWriteEn;
    wire [2:0]  memFunct3;
    wire [31:0] memDataOut;

    // ---------------- IF_ID ----------------
    wire [63:0] ifIdIn;
    wire        ifIdFlush;
    wire [63:0] ifIdOut;
    wire [31:0] IF_ID_PC;
    wire [31:0] IF_ID_Inst;

    // ---------------- ID (C1) ----------------
    wire        idValid;
    wire        cBranch;
    wire        cMemRead;
    wire        cMemWrite;
    wire        cAluSource;
    wire        cAluSrcA;
    wire        cRegWrite;
    wire        cIsJal;
    wire        cIsJalr;
    wire        cHalt;
    wire [1:0]  cMemToReg;
    wire [1:0]  cAluOp;
    wire [11:0] idCtrl;
    wire        idHalt;
    wire [31:0] readData1;
    wire [31:0] readData2;
    wire [31:0] immGenOut;
    wire        haltSet;
    wire        haltNext;
    wire        haltLatch;

    // ---------------- ID_EX ----------------
    wire [171:0] idExIn;
    wire [171:0] idExOut;
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
    wire [31:0] ID_EX_RegR1;
    wire [31:0] ID_EX_RegR2;
    wire [31:0] ID_EX_Imm;
    wire [31:0] ID_EX_Inst;
    wire [4:0]  ID_EX_Rs1;
    wire [4:0]  ID_EX_Rs2;
    wire [4:0]  ID_EX_Rd;
    wire [2:0]  ID_EX_Funct3;

    // ---------------- EX (C0) ----------------
    wire        forwardA;
    wire        forwardB;
    wire [31:0] fwdRs1;
    wire [31:0] fwdRs2;
    wire [31:0] aluInputData1;
    wire [31:0] aluInputData2;
    wire [4:0]  aluSel;
    wire [31:0] aluOutput;
    wire        aluZero;
    wire        takeBranch;
    wire        pcSrc;
    wire [31:0] branchTarget;
    wire [31:0] jumpTarget;
    wire [31:0] exPcPlus4;
    wire [31:0] exResult;
    wire        exWbFromMem;

    // ---------------- EX_MEM ----------------
    wire [75:0] exMemIn;
    wire [75:0] exMemOut;
    wire        EX_MEM_RegWrite;
    wire        EX_MEM_WbFromMem;
    wire        EX_MEM_MemRead;
    wire        EX_MEM_MemWrite;
    wire [31:0] EX_MEM_Result;
    wire [31:0] EX_MEM_StoreData;
    wire [2:0]  EX_MEM_Funct3;
    wire [4:0]  EX_MEM_Rd;

    // ---------------- MEM_WB / WB (C0) ----------------
    wire [70:0] memWbIn;
    wire [70:0] memWbOut;
    wire        MEM_WB_RegWrite;
    wire        MEM_WB_WbFromMem;
    wire [31:0] MEM_WB_MemOut;
    wire [31:0] MEM_WB_Result;
    wire [4:0]  MEM_WB_Rd;
    wire [31:0] regWriteData;
    wire        regWriteEn;

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
    assign pcPlus4 = pcValue + `PC_STEP;
    assign pcNext  = (pcSrc) ? jumpTarget : pcPlus4;

    // PC moves at the end of C0 (after the fetch) unless EBREAK halted it
    assign pcLoad = isC0 & ~haltLatch;

    N_bit_register #(32) pcRegister(
        .clk(clk),
        .rst(rst),
        .Load(pcLoad),
        .D(pcNext),
        .Q(pcValue)
    );

    // Single memory port: C0 = fetch, C1 = MEM stage access
    assign memAddr    = (isC0) ? pcValue[ADDR_BITS-1:0]
                               : EX_MEM_Result[ADDR_BITS-1:0];
    assign memReadEn  = (isC0) ? 1'b1    : EX_MEM_MemRead;
    assign memWriteEn = (isC0) ? 1'b0    : EX_MEM_MemWrite;
    assign memFunct3  = (isC0) ? `MEM_LW : EX_MEM_Funct3;

    UnifiedMem #(
        .ADDR_BITS(ADDR_BITS),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) memory(
        .clk(clk),
        .memRead(memReadEn),
        .memWrite(memWriteEn),
        .funct3(memFunct3),
        .addr(memAddr),
        .dataIn(EX_MEM_StoreData),
        .dataOut(memDataOut)
    );

    // =========================================================================
    // IF_ID: captures at the end of C0. A taken branch/jump in EX (same C0)
    // or a halted CPU turns the fetched instruction into a bubble.
    // =========================================================================
    assign ifIdIn    = {pcValue, memDataOut};
    assign ifIdFlush = isC0 & (pcSrc | haltLatch);

    PipelineReg #(64) IF_ID(
        .clk(clk),
        .rst(rst),
        .load(isC0),
        .flush(ifIdFlush),
        .D(ifIdIn),
        .Q(ifIdOut)
    );

    assign {IF_ID_PC, IF_ID_Inst} = ifIdOut;

    // =========================================================================
    // Stage 0, C1: ID
    // =========================================================================
    // An all-zero word is a bubble (opcode 0 would otherwise decode as LB)
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

    // Bubbles carry no control
    assign idCtrl = (idValid) ? {cRegWrite, cMemToReg, cMemRead, cMemWrite,
                                 cBranch, cIsJal, cIsJalr, cAluSource,
                                 cAluSrcA, cAluOp}
                              : 12'd0;
    assign idHalt = cHalt & idValid;

    // The register file is written in C0 (WB) and read in C1 (ID), so a
    // value written back is always visible to the next read
    assign regWriteEn = MEM_WB_RegWrite & isC0;

    RegFile #(32) RegisterFile(
        .clk(clk),
        .rst(rst),
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

    // EBREAK: once decoded, the PC never moves again
    assign haltSet  = isC1 & idHalt;
    assign haltNext = haltLatch | haltSet;

    DFlipFlop haltFF(
        .clk(clk),
        .rst(rst),
        .D(haltNext),
        .Q(haltLatch)
    );

    // =========================================================================
    // ID_EX: captures at the end of C1 (stage 0 -> stage 1 boundary)
    // =========================================================================
    assign idExIn = {idCtrl, IF_ID_PC, readData1, readData2, immGenOut,
                     IF_ID_Inst};

    PipelineReg #(172) ID_EX(
        .clk(clk),
        .rst(rst),
        .load(isC1),
        .flush(1'b0),
        .D(idExIn),
        .Q(idExOut)
    );

    assign {ID_EX_RegWrite, ID_EX_MemToReg, ID_EX_MemRead, ID_EX_MemWrite,
            ID_EX_Branch, ID_EX_IsJal, ID_EX_IsJalr, ID_EX_AluSource,
            ID_EX_AluSrcA, ID_EX_AluOp,
            ID_EX_PC, ID_EX_RegR1, ID_EX_RegR2, ID_EX_Imm,
            ID_EX_Inst} = idExOut;

    assign ID_EX_Rd     = ID_EX_Inst[11:7];
    assign ID_EX_Funct3 = ID_EX_Inst[14:12];
    assign ID_EX_Rs1    = ID_EX_Inst[19:15];
    assign ID_EX_Rs2    = ID_EX_Inst[24:20];

    // =========================================================================
    // Stage 1, C0: EX
    // =========================================================================
    ForwardingUnit forwarding(
        .exRs1(ID_EX_Rs1),
        .exRs2(ID_EX_Rs2),
        .memWbRd(MEM_WB_Rd),
        .memWbRegWrite(MEM_WB_RegWrite),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    // Forward on the register value first, then apply the ALU source muxes
    assign fwdRs1 = (forwardA) ? regWriteData : ID_EX_RegR1;
    assign fwdRs2 = (forwardB) ? regWriteData : ID_EX_RegR2;

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

    BranchUnit branchComparator(
        .branch(ID_EX_Branch),
        .funct3(ID_EX_Funct3),
        .readData1(fwdRs1),
        .readData2(fwdRs2),
        .takeBranch(takeBranch)
    );

    // Branch / JAL target = PC + imm, JALR target = (rs1 + imm) with bit 0
    // cleared (rs1 + imm comes out of the ALU)
    assign branchTarget = ID_EX_PC + ID_EX_Imm;
    assign jumpTarget   = (ID_EX_IsJalr) ? {aluOutput[31:1], 1'b0}
                                         : branchTarget;
    assign pcSrc        = takeBranch | ID_EX_IsJal | ID_EX_IsJalr;

    // Final non-memory result, so forwarding is right for JAL/JALR/LUI too
    assign exPcPlus4   = ID_EX_PC + `PC_STEP;
    assign exResult    = (ID_EX_MemToReg == `WB_PC4) ? exPcPlus4 :
                         (ID_EX_MemToReg == `WB_IMM) ? ID_EX_Imm : aluOutput;
    assign exWbFromMem = (ID_EX_MemToReg == `WB_MEM);

    // =========================================================================
    // EX_MEM: captures at the end of C0
    // =========================================================================
    assign exMemIn = {ID_EX_RegWrite, exWbFromMem, ID_EX_MemRead,
                      ID_EX_MemWrite, exResult, fwdRs2, ID_EX_Funct3,
                      ID_EX_Rd};

    PipelineReg #(76) EX_MEM(
        .clk(clk),
        .rst(rst),
        .load(isC0),
        .flush(1'b0),
        .D(exMemIn),
        .Q(exMemOut)
    );

    assign {EX_MEM_RegWrite, EX_MEM_WbFromMem, EX_MEM_MemRead,
            EX_MEM_MemWrite, EX_MEM_Result, EX_MEM_StoreData,
            EX_MEM_Funct3, EX_MEM_Rd} = exMemOut;

    // =========================================================================
    // Stage 1, C1: MEM (memory port, see IF above).
    // MEM_WB captures at the end of C1 (stage 1 -> stage 2 boundary)
    // =========================================================================
    assign memWbIn = {EX_MEM_RegWrite, EX_MEM_WbFromMem, memDataOut,
                      EX_MEM_Result, EX_MEM_Rd};

    PipelineReg #(71) MEM_WB(
        .clk(clk),
        .rst(rst),
        .load(isC1),
        .flush(1'b0),
        .D(memWbIn),
        .Q(memWbOut)
    );

    assign {MEM_WB_RegWrite, MEM_WB_WbFromMem, MEM_WB_MemOut,
            MEM_WB_Result, MEM_WB_Rd} = memWbOut;

    // =========================================================================
    // Stage 2, C0: WB (register file write enabled by regWriteEn above)
    // =========================================================================
    assign regWriteData = (MEM_WB_WbFromMem) ? MEM_WB_MemOut : MEM_WB_Result;

    // =========================================================================
    // Debug / board observation
    // =========================================================================
    assign dbgPC        = pcValue;
    assign dbgInst      = IF_ID_Inst;
    assign dbgAluResult = exResult;
    assign dbgMemAddr   = {{(32 - ADDR_BITS){1'b0}}, memAddr};
    assign dbgMemOut    = memDataOut;
    assign dbgWbData    = regWriteData;
    assign dbgStoreData = EX_MEM_StoreData;
    assign dbgHalt      = haltLatch;
    // LD14 phase, LD13 ID valid, LD12/11 forward A/B, LD10 pcSrc (flush),
    // LD9 branch taken, LD8/7 JAL/JALR in EX, LD6/5 memory read/write,
    // LD4 register write, LD3..0 ALU select (bit 15 is ALU zero; the
    // board shows the halt flag on LD15 instead)
    assign dbgFlags     = {aluZero, phase, idValid, forwardA, forwardB,
                           pcSrc, takeBranch, ID_EX_IsJal, ID_EX_IsJalr,
                           memReadEn, memWriteEn, regWriteEn, aluSel[3:0]};

endmodule

`default_nettype wire
