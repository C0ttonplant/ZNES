//! The 6502 opcode table: which operation, addressing mode and base cycle
//! count every one of the 256 opcodes uses.
//!
//! `Op` and `Mode` tag names must match the function names in
//! `instructions.zig` and `addressing.zig`, `Cpu.execute` dispatches on them.

pub const Instruction = struct {
    op: Op,
    mode: Mode,
    cycles: u8,
};

pub const Mode = enum {
    /// implied / accumulator
    IMP,
    /// immediate
    IMM,
    /// zero page
    ZP0,
    /// zero page, x
    ZPX,
    /// zero page, y
    ZPY,
    /// absolute
    ABS,
    /// absolute, x
    ABX,
    /// absolute, y
    ABY,
    /// indirect (JMP only)
    IND,
    /// (indirect, x)
    IZX,
    /// (indirect), y
    IZY,
    /// relative (branches)
    REL,
};

// zig fmt: off
pub const Op = enum {
    // official
    ADC, AND, ASL, BCC, BCS, BEQ, BIT, BMI, BNE, BPL, BRK, BVC, BVS, CLC,
    CLD, CLI, CLV, CMP, CPX, CPY, DEC, DEX, DEY, EOR, INC, INX, INY, JMP,
    JSR, LDA, LDX, LDY, LSR, NOP, ORA, PHA, PHP, PLA, PLP, ROL, ROR, RTI,
    RTS, SBC, SEC, SED, SEI, STA, STX, STY, TAX, TAY, TSX, TXA, TXS, TYA,
    // illegal
    ALR, ANC, ANE, ARR, DCP, ISC, JAM, LAS, LAX, LXA, RLA, RRA, SAX, SBX,
    SHA, SHX, SHY, SLO, SRE, TAS, USB,

    /// stores and read-modify-write instructions, these always do the dummy
    /// read on indexed addressing
    pub fn writesMemory(self: Op) bool {
        return switch (self) {
            .STA, .STX, .STY, .SHA, .SHX, .SHY, .TAS,
            .ASL, .LSR, .ROL, .ROR, .INC, .DEC,
            .SLO, .RLA, .SRE, .RRA, .DCP, .ISC,
            => true,
            else => false,
        };
    }
};
// zig fmt: on

fn op(o: Op, mode: Mode, cycles: u8) Instruction {
    return .{ .op = o, .mode = mode, .cycles = cycles };
}

// zig fmt: off
pub const table = [256]Instruction{
    op(.BRK, .IMP, 7), op(.ORA, .IZX, 6), op(.JAM, .IMP, 1), op(.SLO, .IZX, 8), op(.NOP, .ZP0, 3), op(.ORA, .ZP0, 3), op(.ASL, .ZP0, 5), op(.SLO, .ZP0, 5), // 00-07
    op(.PHP, .IMP, 3), op(.ORA, .IMM, 2), op(.ASL, .IMP, 2), op(.ANC, .IMM, 2), op(.NOP, .ABS, 4), op(.ORA, .ABS, 4), op(.ASL, .ABS, 6), op(.SLO, .ABS, 6), // 08-0F
    op(.BPL, .REL, 2), op(.ORA, .IZY, 5), op(.JAM, .IMP, 1), op(.SLO, .IZY, 8), op(.NOP, .ZPX, 4), op(.ORA, .ZPX, 4), op(.ASL, .ZPX, 6), op(.SLO, .ZPX, 6), // 10-17
    op(.CLC, .IMP, 2), op(.ORA, .ABY, 4), op(.NOP, .IMP, 2), op(.SLO, .ABY, 7), op(.NOP, .ABX, 4), op(.ORA, .ABX, 4), op(.ASL, .ABX, 7), op(.SLO, .ABX, 7), // 18-1F
    op(.JSR, .ABS, 6), op(.AND, .IZX, 6), op(.JAM, .IMP, 1), op(.RLA, .IZX, 8), op(.BIT, .ZP0, 3), op(.AND, .ZP0, 3), op(.ROL, .ZP0, 5), op(.RLA, .ZP0, 5), // 20-27
    op(.PLP, .IMP, 4), op(.AND, .IMM, 2), op(.ROL, .IMP, 2), op(.ANC, .IMM, 2), op(.BIT, .ABS, 4), op(.AND, .ABS, 4), op(.ROL, .ABS, 6), op(.RLA, .ABS, 6), // 28-2F
    op(.BMI, .REL, 2), op(.AND, .IZY, 5), op(.JAM, .IMP, 1), op(.RLA, .IZY, 8), op(.NOP, .ZPX, 4), op(.AND, .ZPX, 4), op(.ROL, .ZPX, 6), op(.RLA, .ZPX, 6), // 30-37
    op(.SEC, .IMP, 2), op(.AND, .ABY, 4), op(.NOP, .IMP, 2), op(.RLA, .ABY, 7), op(.NOP, .ABX, 4), op(.AND, .ABX, 4), op(.ROL, .ABX, 7), op(.RLA, .ABX, 7), // 38-3F
    op(.RTI, .IMP, 6), op(.EOR, .IZX, 6), op(.JAM, .IMP, 1), op(.SRE, .IZX, 8), op(.NOP, .ZP0, 3), op(.EOR, .ZP0, 3), op(.LSR, .ZP0, 5), op(.SRE, .ZP0, 5), // 40-47
    op(.PHA, .IMP, 3), op(.EOR, .IMM, 2), op(.LSR, .IMP, 2), op(.ALR, .IMM, 2), op(.JMP, .ABS, 3), op(.EOR, .ABS, 4), op(.LSR, .ABS, 6), op(.SRE, .ABS, 6), // 48-4F
    op(.BVC, .REL, 2), op(.EOR, .IZY, 5), op(.JAM, .IMP, 1), op(.SRE, .IZY, 8), op(.NOP, .ZPX, 4), op(.EOR, .ZPX, 4), op(.LSR, .ZPX, 6), op(.SRE, .ZPX, 6), // 50-57
    op(.CLI, .IMP, 2), op(.EOR, .ABY, 4), op(.NOP, .IMP, 2), op(.SRE, .ABY, 7), op(.NOP, .ABX, 4), op(.EOR, .ABX, 4), op(.LSR, .ABX, 7), op(.SRE, .ABX, 7), // 58-5F
    op(.RTS, .IMP, 6), op(.ADC, .IZX, 6), op(.JAM, .IMP, 1), op(.RRA, .IZX, 8), op(.NOP, .ZP0, 3), op(.ADC, .ZP0, 3), op(.ROR, .ZP0, 5), op(.RRA, .ZP0, 5), // 60-67
    op(.PLA, .IMP, 4), op(.ADC, .IMM, 2), op(.ROR, .IMP, 2), op(.ARR, .IMM, 2), op(.JMP, .IND, 5), op(.ADC, .ABS, 4), op(.ROR, .ABS, 6), op(.RRA, .ABS, 6), // 68-6F
    op(.BVS, .REL, 2), op(.ADC, .IZY, 5), op(.JAM, .IMP, 1), op(.RRA, .IZY, 8), op(.NOP, .ZPX, 4), op(.ADC, .ZPX, 4), op(.ROR, .ZPX, 6), op(.RRA, .ZPX, 6), // 70-77
    op(.SEI, .IMP, 2), op(.ADC, .ABY, 4), op(.NOP, .IMP, 2), op(.RRA, .ABY, 7), op(.NOP, .ABX, 4), op(.ADC, .ABX, 4), op(.ROR, .ABX, 7), op(.RRA, .ABX, 7), // 78-7F
    op(.NOP, .IMM, 2), op(.STA, .IZX, 6), op(.NOP, .IMM, 2), op(.SAX, .IZX, 6), op(.STY, .ZP0, 3), op(.STA, .ZP0, 3), op(.STX, .ZP0, 3), op(.SAX, .ZP0, 3), // 80-87
    op(.DEY, .IMP, 2), op(.NOP, .IMM, 2), op(.TXA, .IMP, 2), op(.ANE, .IMM, 2), op(.STY, .ABS, 4), op(.STA, .ABS, 4), op(.STX, .ABS, 4), op(.SAX, .ABS, 4), // 88-8F
    op(.BCC, .REL, 2), op(.STA, .IZY, 6), op(.JAM, .IMP, 1), op(.SHA, .IZY, 6), op(.STY, .ZPX, 4), op(.STA, .ZPX, 4), op(.STX, .ZPY, 4), op(.SAX, .ZPY, 4), // 90-97
    op(.TYA, .IMP, 2), op(.STA, .ABY, 5), op(.TXS, .IMP, 2), op(.TAS, .ABY, 5), op(.SHY, .ABX, 5), op(.STA, .ABX, 5), op(.SHX, .ABY, 5), op(.SHA, .ABY, 5), // 98-9F
    op(.LDY, .IMM, 2), op(.LDA, .IZX, 6), op(.LDX, .IMM, 2), op(.LAX, .IZX, 6), op(.LDY, .ZP0, 3), op(.LDA, .ZP0, 3), op(.LDX, .ZP0, 3), op(.LAX, .ZP0, 3), // A0-A7
    op(.TAY, .IMP, 2), op(.LDA, .IMM, 2), op(.TAX, .IMP, 2), op(.LXA, .IMM, 2), op(.LDY, .ABS, 4), op(.LDA, .ABS, 4), op(.LDX, .ABS, 4), op(.LAX, .ABS, 4), // A8-AF
    op(.BCS, .REL, 2), op(.LDA, .IZY, 5), op(.JAM, .IMP, 1), op(.LAX, .IZY, 5), op(.LDY, .ZPX, 4), op(.LDA, .ZPX, 4), op(.LDX, .ZPY, 4), op(.LAX, .ZPY, 4), // B0-B7
    op(.CLV, .IMP, 2), op(.LDA, .ABY, 4), op(.TSX, .IMP, 2), op(.LAS, .ABY, 4), op(.LDY, .ABX, 4), op(.LDA, .ABX, 4), op(.LDX, .ABY, 4), op(.LAX, .ABY, 4), // B8-BF
    op(.CPY, .IMM, 2), op(.CMP, .IZX, 6), op(.NOP, .IMM, 2), op(.DCP, .IZX, 8), op(.CPY, .ZP0, 3), op(.CMP, .ZP0, 3), op(.DEC, .ZP0, 5), op(.DCP, .ZP0, 5), // C0-C7
    op(.INY, .IMP, 2), op(.CMP, .IMM, 2), op(.DEX, .IMP, 2), op(.SBX, .IMM, 2), op(.CPY, .ABS, 4), op(.CMP, .ABS, 4), op(.DEC, .ABS, 6), op(.DCP, .ABS, 6), // C8-CF
    op(.BNE, .REL, 2), op(.CMP, .IZY, 5), op(.JAM, .IMP, 1), op(.DCP, .IZY, 8), op(.NOP, .ZPX, 4), op(.CMP, .ZPX, 4), op(.DEC, .ZPX, 6), op(.DCP, .ZPX, 6), // D0-D7
    op(.CLD, .IMP, 2), op(.CMP, .ABY, 4), op(.NOP, .IMP, 2), op(.DCP, .ABY, 7), op(.NOP, .ABX, 4), op(.CMP, .ABX, 4), op(.DEC, .ABX, 7), op(.DCP, .ABX, 7), // D8-DF
    op(.CPX, .IMM, 2), op(.SBC, .IZX, 6), op(.NOP, .IMM, 2), op(.ISC, .IZX, 8), op(.CPX, .ZP0, 3), op(.SBC, .ZP0, 3), op(.INC, .ZP0, 5), op(.ISC, .ZP0, 5), // E0-E7
    op(.INX, .IMP, 2), op(.SBC, .IMM, 2), op(.NOP, .IMP, 2), op(.USB, .IMM, 2), op(.CPX, .ABS, 4), op(.SBC, .ABS, 4), op(.INC, .ABS, 6), op(.ISC, .ABS, 6), // E8-EF
    op(.BEQ, .REL, 2), op(.SBC, .IZY, 5), op(.JAM, .IMP, 1), op(.ISC, .IZY, 8), op(.NOP, .ZPX, 4), op(.SBC, .ZPX, 4), op(.INC, .ZPX, 6), op(.ISC, .ZPX, 6), // F0-F7
    op(.SED, .IMP, 2), op(.SBC, .ABY, 4), op(.NOP, .IMP, 2), op(.ISC, .ABY, 7), op(.NOP, .ABX, 4), op(.SBC, .ABX, 4), op(.INC, .ABX, 7), op(.ISC, .ABX, 7), // F8-FF
};
// zig fmt: on

//      ‐0          ‐1            ‐2      ‐3            ‐4           ‐5            ‐6            ‐7            ‐8              ‐9             ‐A           ‐B             ‐C            ‐D             ‐E             ‐F
// 0‐   BRK impl    ORA X,ind     JAM     SLO X,ind     NOP zpg      ORA zpg       ASL zpg       SLO zpg       PHP impl        ORA #          ASL A        ANC #          NOP abs       ORA abs        ASL abs        SLO abs
// 1‐   BPL rel     ORA ind,Y     JAM     SLO ind,Y     NOP zpg,X    ORA zpg,X     ASL zpg,X     SLO zpg,X     CLC impl        ORA abs,Y      NOP impl     SLO abs,Y      NOP abs,X     ORA abs,X      ASL abs,X      SLO abs,X
// 2‐   JSR abs     AND X,ind     JAM     RLA X,ind     BIT zpg      AND zpg       ROL zpg       RLA zpg       PLP impl        AND #          ROL A        ANC #          BIT abs       AND abs        ROL abs        RLA abs
// 3‐   BMI rel     AND ind,Y     JAM     RLA ind,Y     NOP zpg,X    AND zpg,X     ROL zpg,X     RLA zpg,X     SEC impl        AND abs,Y      NOP impl     RLA abs,Y      NOP abs,X     AND abs,X      ROL abs,X      RLA abs,X
// 4‐   RTI impl    EOR X,ind     JAM     SRE X,ind     NOP zpg      EOR zpg       LSR zpg       SRE zpg       PHA impl        EOR #          LSR A        ALR #          JMP abs       EOR abs        LSR abs        SRE abs
// 5‐   BVC rel     EOR ind,Y     JAM     SRE ind,Y     NOP zpg,X    EOR zpg,X     LSR zpg,X     SRE zpg,X     CLI impl        EOR abs,Y      NOP impl     SRE abs,Y      NOP abs,X     EOR abs,X      LSR abs,X      SRE abs,X
// 6‐   RTS impl    ADC X,ind     JAM     RRA X,ind     NOP zpg      ADC zpg       ROR zpg       RRA zpg       PLA impl        ADC #          ROR A        ARR #          JMP ind       ADC abs        ROR abs        RRA abs
// 7‐   BVS rel     ADC ind,Y     JAM     RRA ind,Y     NOP zpg,X    ADC zpg,X     ROR zpg,X     RRA zpg,X     SEI impl        ADC abs,Y      NOP impl     RRA abs,Y      NOP abs,X     ADC abs,X      ROR abs,X      RRA abs,X
// 8‐   NOP #       STA X,ind     NOP #   SAX X,ind     STY zpg      STA zpg       STX zpg       SAX zpg       DEY impl        NOP #          TXA impl     ANE #          STY abs       STA abs        STX abs        SAX abs
// 9‐   BCC rel     STA ind,Y     JAM     SHA ind,Y     STY zpg,X    STA zpg,X     STX zpg,Y     SAX zpg,Y     TYA impl        STA abs,Y      TXS impl     TAS abs,Y      SHY abs,X     STA abs,X      SHX abs,Y      SHA abs,Y
// A‐   LDY #       LDA X,ind     LDX #   LAX X,ind     LDY zpg      LDA zpg       LDX zpg       LAX zpg       TAY impl        LDA #          TAX impl     LXA #          LDY abs       LDA abs        LDX abs        LAX abs
// B‐   BCS rel     LDA ind,Y     JAM     LAX ind,Y     LDY zpg,X    LDA zpg,X     LDX zpg,Y     LAX zpg,Y     CLV impl        LDA abs,Y      TSX impl     LAS abs,Y      LDY abs,X     LDA abs,X      LDX abs,Y      LAX abs,Y
// C‐   CPY #       CMP X,ind     NOP #   DCP X,ind     CPY zpg      CMP zpg       DEC zpg       DCP zpg       INY impl        CMP #          DEX impl     SBX #          CPY abs       CMP abs        DEC abs        DCP abs
// D‐   BNE rel     CMP ind,Y     JAM     DCP ind,Y     NOP zpg,X    CMP zpg,X     DEC zpg,X     DCP zpg,X     CLD impl        CMP abs,Y      NOP impl     DCP abs,Y      NOP abs,X     CMP abs,X      DEC abs,X      DCP abs,X
// E‐   CPX #       SBC X,ind     NOP #   ISC X,ind     CPX zpg      SBC zpg       INC zpg       ISC zpg       INX impl        SBC #          NOP impl     USBC #         CPX abs       SBC abs        INC abs        ISC abs
// F‐   BEQ rel     SBC ind,Y     JAM     ISC ind,Y     NOP zpg,X    SBC zpg,X     INC zpg,X     ISC zpg,X     SED impl        SBC abs,Y      NOP impl     ISC abs,Y      NOP abs,X     SBC abs,X      INC abs,X      ISC abs,X
