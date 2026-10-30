`timescale 1ns / 1ps

module datapath(input clk, input reset);
    wire [31:0] pcValue;
    wire [31:0] readData1, readData2;
    wire [31:0] data_memory_out;
    wire [31:0] inst_memory_out;
    wire [31:0] AluOutput;
    wire [31:0] immGenOut;
    wire [3:0] AluSel;
    wire AluZero;

    // Control wires
    wire branch, memRead, memWrite, ALUsource, ALUSrcA, regWrite, halt;
    wire [1:0] memToReg;
    wire [1:0] AluOp;
    wire isJal, isJalr;
    wire takeBranch;

    // Datapath routing wires
    reg [31:0] regWriteData;
    wire [31:0] aluInputData1;
    wire [31:0] aluInputData2;
    wire [31:0] pcPlus4;
    wire [31:0] jumpTarget;
    wire [31:0] jalrTarget;
    reg [31:0] pcInput;

    // Submodules
    DataMem DataMemory(
        .clk(clk), .MemRead(memRead), .MemWrite(memWrite),
        .funct3(inst_memory_out[14:12]),
        .addr(AluOutput[7:0]),
        .data_in(readData2),
        .data_out(data_memory_out)
    );

    InstMem InstructionMemory(
        pcValue[8:2], inst_memory_out
    );

    RegFile #(32) RegisterFile(
        clk, reset, 
        inst_memory_out[19:15], inst_memory_out[24:20], inst_memory_out[11:7], 
        regWriteData, regWrite, 
        readData1, readData2
    );

    ImmGen immGenerator(
        inst_memory_out, immGenOut
    );

    control_unit controlUnit(
        inst_memory_out, branch, memRead, memToReg, memWrite, 
        ALUsource, ALUSrcA, regWrite, AluOp, isJal, isJalr, halt
    );

    alu_unit AluControl(
        inst_memory_out, AluOp, AluSel
    );

    // ALU input multiplexers
    assign aluInputData1 = (ALUSrcA) ? pcValue : readData1;
    assign aluInputData2 = (ALUsource) ? immGenOut : readData2;

    ALU #(32) aluModule(
        aluInputData1, aluInputData2, AluSel, AluOutput, AluZero
    );

    BranchUnit branchComparator(
        branch, inst_memory_out[14:12], readData1, readData2, takeBranch
    );

    // Register Writeback 4-to-1 Multiplexer
    always @(*) begin
        case (memToReg)
            2'b00: regWriteData = AluOutput;        // ALU
            2'b01: regWriteData = data_memory_out;  // Memory Load
            2'b10: regWriteData = pcPlus4;          // JAL / JALR Link
            2'b11: regWriteData = immGenOut;        // LUI
        endcase
    end

    // PC calculations
    assign pcPlus4    = pcValue + 32'd4;
    assign jumpTarget = pcValue + immGenOut;                    // JAL & Branches
    assign jalrTarget = (readData1 + immGenOut) & ~32'd1;       // JALR (LSB forced to 0)

    // Next PC 3-to-1 Multiplexer
    always @(*) begin
        if (isJalr)
            pcInput = jalrTarget;
        else if (isJal || takeBranch)
            pcInput = jumpTarget;
        else
            pcInput = pcPlus4;
    end

    N_bit_register pcRegister(
        ~halt, clk, reset, pcInput, pcValue
    );

endmodule
