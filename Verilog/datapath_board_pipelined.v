`timescale 1ns / 1ps
/*******************************
Module: UnifiedMem.v
Project:femtoRV32
Author: Moustafa Fayed 
Description: Top module for our pipelined processor and handles hazards 

Change History:
11/14/26 - Updated preious single-cycle board top module to have unified mem, hazard unit, forwarding unit, e.t.c
*************************************/

`include "defines.vh"
`default_nettype none

module datapath_board_pipelined #(
    parameter BP_ENABLE = 1
)(
    input  wire        clk,
    input  wire        reset,
    input  wire [1:0]  ledSel,
    input  wire [3:0]  ssdSel,
    input  wire        ssdClk,
    output wire [15:0] leds,
    output wire [3:0]  Anode,
    output wire [6:0]  LED_out
);

    // Phase control 
    wire        phase;
    wire        isFetch;
    wire        advance;

    // IF 
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

    // IF/ID
    wire [31:0] IF_ID_PC;
    wire [31:0] IF_ID_Inst;
    wire [31:0] IF_ID_PredNextPC;
    wire        IF_ID_PredTaken;
    wire        ifIdLoad;
    wire        ifIdFlush;

    // ID 
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

    // ID/EX 
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

    // EX 
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

    // EX/MEM 
    wire        EX_MEM_RegWrite;
    wire        EX_MEM_WbFromMem;
    wire        EX_MEM_MemRead;
    wire        EX_MEM_MemWrite;
    wire [31:0] EX_MEM_Result;
    wire [31:0] EX_MEM_StoreData;
    wire [2:0]  EX_MEM_Funct3;
    wire [4:0]  EX_MEM_Rd;

    // MEM/WB 
    wire        MEM_WB_RegWrite;
    wire        MEM_WB_WbFromMem;
    wire [31:0] MEM_WB_MemOut;
    wire [31:0] MEM_WB_Result;
    wire [4:0]  MEM_WB_Rd;
    wire [31:0] regWriteData;
    wire        regWriteEn;

    // phase controller
    PhaseController phaseCtrl(
        .clk(clk),
        .rst(reset),
        .phase(phase),
        .isFetch(isFetch),
        .advance(advance)
    );

    // IF stage: PC, predictor, shared memory
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

    // Single memory port
    assign memAddr    = (isFetch) ? pcValue[9:0]    : EX_MEM_Result[9:0];
    assign memReadEn  = (isFetch) ? 1'b1            : EX_MEM_MemRead;
    assign memWriteEn = (isFetch) ? 1'b0            : EX_MEM_MemWrite;
    assign memFunct3  = (isFetch) ? `MEM_LW         : EX_MEM_Funct3;

    UnifiedMem #(10) memory(
        .clk(clk),
        .memRead(memReadEn),
        .memWrite(memWriteEn),
        .funct3(memFunct3),
        .addr(memAddr),
        .dataIn(EX_MEM_StoreData),
        .dataOut(memDataOut)
    );

    N_bit_register #(32) instLatchReg(
        .clk(clk),
        .rst(reset),
        .Load(isFetch),
        .D(memDataOut),
        .Q(instLatch)
    );


    // IF/ID register
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

    // ID stage
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

    // Bubbles 
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
        .readdata2(readData2)
    );

    ImmGen immGenerator(
        .inst(IF_ID_Inst),
        .genOut(immGenOut)
    );

    // Load-use hazard
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

    // ID-stage forwarding for the branch comparator / JALR base
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

    // ECALL / EBREAK
    assign haltNow = haltLatch | (idHalt & ~stall);
    assign haltSet = advance & idHalt & ~stall;

    DFlipFlop haltFF(
        .clk(clk),
        .rst(reset),
        .D(haltLatch | haltSet),
        .Q(haltLatch)
    );

    // ID/EX register
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


    // EX stage
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


    // EX/MEM register
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

    // MEM/WB register 
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


    // WB stage
    assign regWriteData = (MEM_WB_WbFromMem) ? MEM_WB_MemOut : MEM_WB_Result;

    // Board outputs: LEDs
    reg [15:0] ledOut;
    always @(*) begin
        case (ledSel)
            2'b00:   ledOut = IF_ID_Inst[15:0];
            2'b10:   ledOut = IF_ID_Inst[31:16];
            2'b01:   ledOut = {idBranch, idMemRead, idMemWrite, idAluSource,
                               idAluSrcA, idRegWrite, idIsJal, idIsJalr,
                               idMemToReg, idAluOp,
                               loadUseStall, branchStall, redirect, idHalt};
            default: ledOut = {phase, advance, stall, redirect, predictTakenEff,
                               forwardA, forwardB, aluSel, aluZero, haltLatch};
        endcase
    end
    assign leds = ledOut;


    // Board outputs: seven-segment display
    reg [12:0] ssd_output;
    always @(*) begin
        case (ssdSel)
            4'd0:    ssd_output = pcValue[12:0];
            4'd1:    ssd_output = pcInput[12:0];
            4'd2:    ssd_output = predNextPC[12:0];
            4'd3:    ssd_output = IF_ID_Inst[12:0];
            4'd4:    ssd_output = readData1[12:0];
            4'd5:    ssd_output = readData2[12:0];
            4'd6:    ssd_output = immGenOut[12:0];
            4'd7:    ssd_output = idActualNextPC[12:0];
            4'd8:    ssd_output = aluInputData1[12:0];
            4'd9:    ssd_output = aluInputData2[12:0];
            4'd10:   ssd_output = exResult[12:0];
            4'd11:   ssd_output = EX_MEM_Result[12:0];
            4'd12:   ssd_output = EX_MEM_StoreData[12:0];
            4'd13:   ssd_output = memDataOut[12:0];
            4'd14:   ssd_output = regWriteData[12:0];
            default: ssd_output = ID_EX_Inst[12:0];
        endcase
    end

    Four_Digit_Seven_Segment_Driver_Optimized ssdDriver(
        ssdClk, ssd_output, Anode, LED_out
    );

endmodule

`default_nettype wire