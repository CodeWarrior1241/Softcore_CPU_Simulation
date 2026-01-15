//==============================================================================
// axi_ad9361_adapter_tb.cpp
//
// Testbench for AXI AD9361 Adapter HLS IP v3.0
// Verifies:
// - Free-running operation
// - TX BRAM continuous cycling (software-loaded)
// - RX BRAM continuous capture with fill level tracking
// - RX clear functionality
// - Loopback mode
// - Control registers
//
// Target: Vitis HLS 2025.2
//==============================================================================

#include <iostream>
#include <iomanip>
#include <cstdlib>
#include <cmath>
#include "axi_ad9361_adapter.hpp"

//==============================================================================
// Test Configuration
//==============================================================================

constexpr int NUM_TEST_SAMPLES = 100;

//==============================================================================
// QPSK COE Data (from sim/qpsk_bram_init.coe)
// 1024 x 32-bit words: {Q[31:16], I[15:0]} signed 16-bit IQ pairs
// QPSK constellation at +/- 16384 with +/- 256 noise
//==============================================================================

static const uint32_t QPSK_COE_DATA[1024] = {
    0xBFB640BC, 0x3FDBBFF3, 0xC06FC0CE, 0x40BEC03B, 0xBFFB3FEC, 0x40EE40B1, 0xC0BBBFC7, 0xBFEFC01E,
    0x40BCBF7B, 0xBFF340ED, 0xC0CEC0B6, 0x403B3FD8, 0x3FEC4060, 0x40B14080, 0x3FC73F00, 0x401EBF02,
    0x3F7BBF0A, 0x40EDBF2B, 0xC0B63FAD, 0xBFD8BFB6, 0x4060BFDA, 0x40804069, 0xBF0040A4, 0x3F02BF93,
    0xBF0ABF4F, 0xBF2B403C, 0x3FAD3FF0, 0x3FB6C0C3, 0xBFDAC00F, 0xC0693F3C, 0x40A4BFF3, 0xBF9340CD,
    0xBF4F4034, 0x403CBFD2, 0x3FF04048, 0x40C34021, 0xC00F3F85, 0xBF3CBF17, 0xBFF3BF5F, 0xC0CD407D,
    0xC03440F4, 0x3FD2C0D2, 0x4048C04A, 0x40214029, 0xBF85BFA7, 0xBF173F9D, 0xBF5F3F75, 0xC07DC0D6,
    0x40F44059, 0xC0D2C067, 0xC04A409C, 0x40293F71, 0xBFA740C4, 0x3F9D4011, 0xBF753F45, 0xC0D64015,
    0xC059BF57, 0xC067C05F, 0xC09C407D, 0xBF71C0F6, 0x40C4C0DB, 0xC011406C, 0x3F4540B0, 0x4015BFC3,
    0xBF57400D, 0xC05F3F35, 0xC07DBFD7, 0xC0F6C05E, 0x40DB4079, 0xC06CC0E6, 0x40B04099, 0xBFC33F65,
    0xC00D4094, 0x3F35BF52, 0x3FD74048, 0x405EC022, 0x40793F88, 0x40E6BF22, 0x40993F88, 0x3F65BF23,
    0xC094BF8F, 0xBF523F3D, 0xC0483FF5, 0xC02240D5, 0xBF884054, 0x3F22C053, 0xBF88C04F, 0xBF23403C,
    0x3F8FBFF3, 0xBF3DC0CE, 0x3FF54039, 0xC0D5BFE7, 0xC054409C, 0x4053BF72, 0x404FC0CA, 0x403C4029,
    0xBFF3BFA6, 0x40CE3F98, 0x40393F61, 0xBFE74085, 0xC09C3F15, 0xBF723F55, 0xC0CAC056, 0x4029C05B,
    0xBFA6406C, 0x3F9840B0, 0x3F613FC0, 0x40854001, 0xBF15BF06, 0x3F553F19, 0xC0563F64, 0x405B4090,
    0x406CBF42, 0x40B04008, 0x3FC0BF23, 0xC0013F8C, 0x3F063F31, 0xBF19BFC7, 0xBF64C01F, 0xC0903F7C,
    0x3F4240F1, 0xC008C0C6, 0x3F23C01B, 0xBF8CBF6F, 0xBF31C0BE, 0x3FC73FF8, 0x401F40E0, 0x3F7C4081,
    0xC0F1BF07, 0xC0C6BF1F, 0xC01BBF7F, 0xBF6F40FC, 0x40BEC0F2, 0x3FF8C0CB, 0xC0E0402D, 0xC0813FB5,
    0xBF07BFD7, 0xBF1FC05E, 0x3F7F4078, 0x40FC40E0, 0x40F24081, 0xC0CB3F04, 0x402D3F10, 0x3FB5BF42,
    0x3FD7C00B, 0xC05EBF2E, 0x40783FB8, 0x40E0BFE2, 0x4081C08B, 0xBF04BF2F, 0xBF103FBC, 0x3F423FF0,
    0x400BC0C2, 0x3F2E4008, 0x3FB8BF23, 0xBFE2BF8F, 0xC08BBF3F, 0xBF2F3FFD, 0xBFBC40F5, 0xBFF0C0D7,
    0xC0C2405D, 0xC0084075, 0xBF23C0D6, 0x3F8FC05B, 0xBF3FC06F, 0xBFFD40BD, 0xC0F53FF4, 0x40D7C0D2,
    0x405D4049, 0xC075C027, 0xC0D63F9D, 0xC05B3F75, 0xC06F40D5, 0xC0BD4054, 0x3FF4C053, 0xC0D2404D,
    0xC049C036, 0x4027BFDA, 0x3F9DC06B, 0xBF75C0AE, 0x40D5BFBB, 0xC0543FED, 0xC053C0B7, 0xC04DBFDF,
    0xC036407C, 0x3FDA40F0, 0x406B40C0, 0x40AEC002, 0x3FBB3F09, 0xBFED3F24, 0x40B73F91, 0xBFDF3F45,
    0xC07C4014, 0x40F03F51, 0xC0C0C046, 0x40024018, 0x3F09BF62, 0x3F24C08A, 0x3F91BF2A, 0x3F453FA8,
    0x40143FA0, 0x3F513F81, 0xC046BF07, 0xC018BF1E, 0x3F62BF7B, 0xC08AC0EE, 0x3F2AC0BA, 0x3FA83FE9,
    0xBFA040A5, 0xBF813F94, 0x3F07BF53, 0xBF1E404D, 0xBF7B4034, 0x40EE3FD1, 0xC0BAC046, 0x3FE94019,
    0xC0A53F65, 0xBF944094, 0x3F53BF53, 0xC04DC04F, 0xC034C03F, 0xBFD13FFC, 0x4046C0F2, 0x4019C0CA,
    0x3F65C02B, 0xC094BFAE, 0x3F533FB8, 0x404F3FE0, 0x403F4080, 0x3FFCBF03, 0xC0F23F0C, 0x40CABF33,
    0xC02B3FCC, 0x3FAEC033, 0xBFB83FCC, 0x3FE04030, 0x40803FC1, 0xBF03C006, 0x3F0C3F18, 0x3F33BF63,
    0xBFCC408D, 0xC0333F35, 0xBFCC3FD4, 0x40304050, 0x3FC1C042, 0x40064009, 0xBF18BF26, 0x3F633F98,
    0x408DBF63, 0xBF35C08F, 0xBFD4BF3F, 0xC0503FFC, 0x404240F0, 0x4009C0C3, 0xBF26400D, 0xBF98BF37,
    0xBF633FDD, 0xC08F4074, 0x3F3F40D0, 0x3FFCC042, 0x40F0C00A, 0x40C33F28, 0x400DBF43, 0xBF373F8D,
    0xBFDDBF36, 0x40743FD8, 0x40D04060, 0x40424081, 0xC00ABF06, 0x3F283F19, 0xBFA33F64, 0x3F8D4091,
    0xBF36BF47, 0xBFD8C01F, 0xC0603F7C, 0x408140F0, 0x3F06C0C3, 0xBF19400D, 0xBF643F35, 0xC0913FD4,
    0x3F47C052, 0x401FC04B, 0xBF7C402C, 0x40F0BFB3, 0xC0C33FCC, 0x400D4031, 0xBF35BFC6, 0x3FD44018,
    0x4052BF63, 0xC04BC08E, 0x402CBF3B, 0xBFB3BFEE, 0x3FCCC0BB, 0xC0313FEC, 0x3FC6C0B3, 0xC0183FCD,
    0xBF634034, 0x408E3FD1, 0xBF3BC046, 0x3FEEC01B, 0xC0BBBF6E, 0x3FEC40B8, 0x40B33FE0, 0x3FCDC082,
    0x40343F09, 0xBFD1BF27, 0xC046BF9E, 0x401B3F78, 0x3F6EC0E3, 0xC0B8C08E, 0x3FE0BF3B, 0xC082BFEF,
    0xBF0940BD, 0xBF27BFF7, 0xBF9E40DD, 0xBF784075, 0xC0E3C0D7, 0xC08EC05E, 0x3F3BC07B, 0xBFEF40EC,
    0x40BDC0B2, 0x3FF7BFCB, 0xC0DD402C, 0x40753FB1, 0xC0D7BFC6, 0x405E4019, 0xC07B3F65, 0xC0ECC096,
    0x40B23F59, 0xBFCBC066, 0x402CC09A, 0x3FB13F69, 0xBFC6C0A6, 0x40193F98, 0x3F65BF63, 0xC096C08E,
    0x3F593F39, 0xC0663FE5, 0xC09A4095, 0xBF69BF56, 0x40A6C05B, 0xBF98C06F, 0xBF6340BD, 0xC08EBFF6,
    0x3F39C0DA, 0x3FE5C06A, 0x4095C0AB, 0xBF563FAD, 0xC05B3FB4, 0x406F3FD1, 0xC0BDC047, 0xBFF6401C,
    0x40DABF73, 0xC06A40CD, 0xC0AB4034, 0x3FAD3FD0, 0x3FB44041, 0xBFD1C006, 0x4047BF1B, 0xC01CBF6E,
    0x3F7340B9, 0xC0CDBFE7, 0xC034C09F, 0xBFD0BF7E, 0x4041C0FA, 0x4006C0EA, 0x3F1B40A9, 0xBF6EBFA7,
    0xC0B93F9C, 0x3FE7BF73, 0xC09FC0CE, 0x3F7EC03A, 0x40FA3FE8, 0x40EA40A1, 0xC0A9BF87, 0xBFA73F1D,
    0xBF9C3F74, 0x3F73C0D3, 0xC0CE404D, 0xC03A4035, 0xBFE8BFD7, 0xC0A1405D, 0xBF874074, 0x3F1DC0D2,
    0x3F74C04A, 0x40D3C02B, 0xC04DBFAF, 0xC035BFBE, 0x3FD73FF9, 0xC05DC0E6, 0x40744098, 0x40D2BF63,
    0xC04A408C, 0x402BBF32, 0x3FAF3FC9, 0xBFBE4024, 0x3FF93F90, 0x40E6BF43, 0xC098C00E, 0x3F633F39,
    0xC08CBFE6, 0x3F324099, 0xBFC9BF66, 0x40244098, 0x3F90BF62, 0x3F434089, 0xC00EBF26, 0x3F393F99,
    0xBFE63F64, 0x40994090, 0x3F663F40, 0x4098C003, 0xBF623F0C, 0x40893F31, 0xBF263FC5, 0xBF994014,
    0x3F64BF52, 0x40904049, 0xBF404024, 0x40033F90, 0x3F0CBF43, 0xBF31400C, 0x3FC53F31, 0xC014BFC7,
    0xBF52401C, 0x40493F71, 0xC024C0C6, 0x3F90C01A, 0x3F43BF6A, 0x400CC0AA, 0x3F31BFAA, 0x3FC73FA9,
    0xC01C3FA5, 0xBF71BF96, 0x40C63F59, 0xC01AC066, 0x3F6A4098, 0x40AABF63, 0xBFAAC08F, 0xBFA93F3C,
    0x3FA5BFF3, 0xBF96C0CF, 0xBF59C03F, 0xC066BFFF, 0xC09840FD, 0xBF6340F4, 0x408F40D0, 0x3F3C4041,
    0xBFF34005, 0xC0CFBF17, 0xC03F3F5C, 0x3FFF4071, 0xC0FD40C4, 0x40F44010, 0x40D03F40, 0x40414001,
    0xC0053F04, 0x3F17BF12, 0x3F5C3F48, 0x4071C023, 0xC0C4BF8E, 0x4010BF3B, 0xBF403FEC, 0x400140B1,
    0xBF04BFC7, 0xBF12C01F, 0xBF483F7C, 0x402340F1, 0xBF8E40C5, 0xBF3BC016, 0x3FEC3F59, 0xC0B14064,
    0x3FC7C092, 0x401F3F48, 0x3F7C4021, 0xC0F1BF86, 0x40C5BF1A, 0x40163F69, 0xBF59C0A7, 0xC0643F9D,
    0xC092BF77, 0xBF48C0DE, 0x4021C07B, 0xBF86C0EF, 0xBF1A40BC, 0x3F69BFF2, 0x40A740C9, 0xBF9D4025,
    0xBF773F94, 0x40DEBF52, 0x407BC04B, 0xC0EF402C, 0x40BC3FB0, 0x3FF2BFC3, 0xC0C9400D, 0xC025BF37,
    0xBF943FDC, 0x3F52C072, 0x404B40C8, 0x402CC022, 0x3FB03F88, 0x3FC33F21, 0xC00DBF87, 0xBF373F1C,
    0x3FDCBF72, 0x407240C9, 0xC0C8C026, 0x4022BF9B, 0xBF88BF6E, 0x3F2140B9, 0xBF873FE4, 0x3F1CC092,
    0x3F72BF4A, 0x40C9C02A, 0x4026BFAB, 0xBF9B3FAD, 0xBF6EBFB7, 0xC0B9BFDF, 0xBFE4407D, 0xC09240F5,
    0xBF4A40D4, 0x402A4051, 0xBFABC046, 0x3FADC01A, 0x3FB7BF6B, 0xBFDFC0AE, 0x407DBFBA, 0x40F5BFEA,
    0x40D4C0AA, 0x40513FA9, 0xC0463FA5, 0xC01ABF97, 0xBF6BBF5E, 0x40AEC07A, 0x3FBA40E9, 0xBFEA40A5,
    0xC0AA3F95, 0xBFA93F54, 0x3FA54050, 0x3F974040, 0x3F5EC003, 0xC07ABF0F, 0xC0E93F3C, 0x40A53FF0,
    0x3F9540C0, 0x3F544000, 0x40503F00, 0x4040BF03, 0xC003BF0E, 0x3F0F3F38, 0x3F3C3FE1, 0xBFF04085,
    0xC0C03F15, 0xC000BF56, 0x3F00C05B, 0xBF03406D, 0xBF0E40B4, 0x3F38BFD2, 0x3FE14049, 0xC0854025,
    0xBF15BF96, 0x3F56BF5A, 0x405BC06A, 0x406D40A8, 0x40B43FA0, 0x3FD2BF82, 0x4049BF0B, 0xC0253F2C,
    0x3F96BFB2, 0x3F5A3FC9, 0xC06A4025, 0xC0A83F94, 0x3FA0BF53, 0xBF82404D, 0xBF0BC037, 0xBF2C3FDC,
    0x3FB24070, 0x3FC940C1, 0xC0254005, 0xBF943F15, 0xBF53BF57, 0xC04DC05F, 0xC037C07F, 0xBFDCC0FF,
    0xC070C0FF, 0xC0C1C0FE, 0x4005C0FA, 0x3F15C0EB, 0xBF57C0AE, 0x405FBFBB, 0xC07FBFEE, 0x40FF40B9,
    0xC0FF3FE4, 0x40FEC093, 0xC0FABF4E, 0x40EB4038, 0x40AE3FE1, 0xBFBBC087, 0xBFEE3F1D, 0xC0B9BF77,
    0xBFE440DD, 0xC093C076, 0x3F4E40D9, 0xC0384064, 0x3FE14091, 0xC087BF47, 0xBF1DC01E, 0x3F77BF7B,
    0xC0DDC0EF, 0xC076C0BE, 0x40D9BFFA, 0x4064C0EA, 0x409140A9, 0xBF473FA5, 0xC01EBF97, 0xBF7BBF5E,
    0x40EF4078, 0x40BE40E0, 0x3FFAC083, 0xC0EABF0F, 0xC0A9BF3F, 0xBFA53FFC, 0x3F9740F0, 0x3F5EC0C3,
    0xC078C00E, 0x40E0BF3A, 0x4083BFEB, 0xBF0FC0AE, 0x3F3FBFBA, 0x3FFC3FE8, 0x40F040A0, 0x40C33F81,
    0xC00EBF06, 0x3F3ABF1B, 0xBFEB3F6D, 0xC0AEC0B7, 0xBFBA3FDC, 0x3FE8C072, 0x40A040C8, 0x3F814021,
    0xBF063F85, 0xBF1B3F15, 0xBF6D3F55, 0xC0B7C056, 0x3FDCC05A, 0x4072C06A, 0x40C840A9, 0xC021BFA7,
    0xBF853F9D, 0xBF153F74, 0x3F5540D0, 0x4056C043, 0xC05A400C, 0x406ABF32, 0x40A93FC8, 0x3FA7C022,
    0x3F9D3F89, 0xBF74BF26, 0x40D03F98, 0x4043BF62, 0x400C4088, 0x3F32BF23, 0xBFC8BF8E, 0x40223F39,
    0xBF893FE4, 0x3F264090, 0x3F98BF43, 0xBF62C00E, 0x40883F38, 0x3F23BFE3, 0xBF8EC08E, 0x3F393F38,
    0x3FE4BFE3, 0xC090408D, 0xBF43BF37, 0xC00EBFDE, 0x3F38C07B, 0xBFE340ED, 0xC08EC0B6, 0x3F38BFDA,
    0x3FE34069, 0xC08D40A5, 0xBF373F94, 0x3FDE3F51, 0xC07BC047, 0xC0ED401D, 0xC0B6BF76, 0x3FDA40D9,
    0xC0694065, 0xC0A54094, 0x3F943F51, 0xBF514044, 0x4047C013, 0xC01D3F4C, 0x3F76C032, 0x40D9BFCA,
    0x4065C02B, 0xC094BFAF, 0xBF513FBC, 0x40443FF0, 0x4013C0C2, 0x3F4CC00B, 0xC032BF2E, 0x3FCA3FB8,
    0x402B3FE1, 0xBFAF4085, 0xBFBC3F14, 0x3FF0BF52, 0x40C2C04B, 0xC00B402D, 0xBF2E3FB5, 0xBFB8BFD6,
    0x3FE1C05B, 0xC085406C, 0x3F1440B0, 0x3F523FC1, 0xC04B4004, 0x402DBF12, 0x3FB5BF4B, 0xBFD6C02F,
    0xC05B3FBD, 0xC06CBFF6, 0x40B040D8, 0x3FC14061, 0xC0044084, 0x3F123F11, 0xBF4BBF46, 0x402F4018,
    0x3FBD3F61, 0xBFF64084, 0x40D8BF12, 0x4061BF4B, 0xC084C02E, 0x3F113FB8, 0x3F46BFE3, 0xC018C08F,
    0xBF613F3D, 0xC084BFF6, 0x3F12C0DB, 0xBF4B406D, 0xC02EC0B6, 0x3FB83FD9, 0xBFE3C067, 0xC08FC09E,
    0x3F3DBF7A, 0x3FF640E9, 0xC0DBC0A7, 0xC06DBF9E, 0x40B6BF7B, 0xBFD9C0EF, 0xC067C0BE, 0x409EBFFA,
    0x3F7AC0EB, 0xC0E940AC, 0x40A73FB1, 0xBF9E3FC4, 0x3F7BC012, 0x40EF3F48, 0x40BE4021, 0xBFFABF87,
    0xC0EB3F1C, 0x40ACBF72, 0x3FB1C0CA, 0x3FC4C02A, 0x40123FA9, 0xBF483FA5, 0xC0213F95, 0xBF87BF56,
    0x3F1C4059, 0xBF72C067, 0xC0CAC09E, 0x402ABF7B, 0xBFA940ED, 0xBFA540B5, 0xBF953FD4, 0x3F56C053,
    0xC059404C, 0x4067C032, 0x409EBFCB, 0xBF7BC02F, 0xC0EDBFBE, 0x40B53FF9, 0xBFD440E5, 0xC0534094,
    0x404C3F50, 0x4032C042, 0x3FCBC00A, 0x402F3F29, 0xBFBE3FA4, 0x3FF9BF93, 0xC0E5BF4F, 0xC094403C,
    0x3F503FF1, 0xC04240C4, 0x400AC012, 0x3F293F49, 0xBFA4C026, 0x3F933F99, 0xBF4FBF66, 0x403CC09B,
    0xBFF1BF6F, 0xC0C440BC, 0x4012BFF3, 0xBF4940CD, 0xC026C036, 0x3F99BFDA, 0x3F664068, 0x409BC0A3,
    0xBF6F3F8D, 0xC0BC3F35, 0xBFF3BFD7, 0xC0CDC05E, 0x40364078, 0x3FDAC0E3, 0xC068C08F, 0xC0A33F3C,
    0x3F8D3FF1, 0xBF35C0C6, 0x3FD7C01B, 0xC05E3F6D, 0xC07840B4, 0x40E33FD1, 0xC08F4045, 0xBF3C4014,
    0x3FF1BF53, 0xC0C6C04E, 0x401B4039, 0xBF6D3FE4, 0x40B4C093, 0xBFD13F4D, 0xC0454035, 0xC014BFD6,
    0x3F53C05B, 0xC04EC06F, 0xC039C0BF, 0xBFE4BFFE, 0x409340F8, 0x3F4D40E0, 0x40354081, 0xBFD63F04,
    0x405BBF13, 0xC06FBF4F, 0xC0BFC03F, 0xBFFEBFFF, 0xC0F840FD, 0xC0E040F5, 0xC08140D4, 0x3F04C053,
    0xBF13C04F, 0xBF4FC03E, 0x403F3FF9, 0xBFFFC0E7, 0xC0FDC09F, 0xC0F5BF7F, 0xC0D4C0FE, 0x4053C0FA,
    0x404F40E8, 0x403EC0A2, 0x3FF9BF8B, 0xC0E73F2D, 0xC09F3FB4, 0x3F7F3FD0, 0x40FEC042, 0x40FAC00B,
    0xC0E83F2D, 0xC0A2BFB6, 0x3F8B3FD9, 0xBF2D4064, 0x3FB44091, 0xBFD0BF46, 0x40424019, 0xC00B3F65,
    0xBF2DC096, 0x3FB6BF5B, 0xBFD9406D, 0xC064C0B6, 0x40913FD8, 0x3F464061, 0xC0194085, 0xBF653F15,
    0xC0963F54, 0x3F5BC052, 0x406DC04B, 0xC0B6C02E, 0x3FD83FB8, 0x4061BFE2, 0x40854089, 0xBF15BF27,
    0xBF54BF9F, 0xC052BF7E, 0x404BC0FB, 0xC02EC0EE, 0x3FB840B8, 0x3FE2BFE3, 0xC089C08F, 0xBF273F3C,
    0x3F9FBFF3, 0xBF7EC0CF, 0xC0FB403D, 0xC0EEBFF7, 0xC0B8C0DE, 0x3FE3C07A, 0x408F40E9, 0xBF3C40A4,
    0x3FF33F90, 0x40CF3F41, 0xC03D4004, 0x3FF73F11, 0xC0DE3F44, 0x407AC013, 0xC0E93F4D, 0xC0A44035,
    0xBF90BFD7, 0xBF41C05E, 0x4004C07A, 0x3F1140E9, 0xBF4440A4, 0x4013BF93, 0xBF4D3F4D, 0xC035C036,
    0x3FD73FD9, 0xC05EC066, 0x407AC09A, 0x40E93F68, 0x40A4C0A3, 0xBF933F8C, 0x3F4D3F30, 0x40363FC1,
    0xBFD9C006, 0x40663F19, 0xC09ABF66, 0x3F68C09B, 0xC0A3BF6E, 0x3F8CC0BA, 0x3F30BFEA, 0x3FC1C0AA,
    0x4006BFAA, 0x3F193FA8, 0x3F66BFA2, 0x409B3F88, 0x3F6EBF23, 0xC0BABF8E, 0x3FEA3F39, 0xC0AA3FE4,
    0x3FAA4090, 0x3FA8BF42, 0x3FA2C00B, 0xBF883F2C, 0x3F23BFB3, 0xBF8E3FCD, 0xBF394035, 0xBFE4BFD7,
    0xC090405D, 0xBF42C077, 0xC00BC0DE, 0x3F2CC07B, 0xBFB340EC, 0x3FCD40B1, 0xC035BFC7, 0xBFD7C01F,
    0xC05D3F7C, 0x4077C0F2, 0x40DEC0CB, 0xC07B402C, 0x40EC3FB0, 0x40B1BFC2, 0x3FC74008, 0x401FBF22,
    0x3F7CBF8B, 0xC0F23F2D, 0xC0CBBFB7, 0xC02CBFDF, 0xBFB0C07E, 0x3FC240F8, 0x4008C0E2, 0x3F224089,
    0xBF8B3F25, 0xBF2D3F95, 0xBFB7BF57, 0xBFDFC05F, 0xC07E407C, 0x40F840F1, 0xC0E240C4, 0x40894010,
    0x3F25BF42, 0x3F954009, 0xBF573F25, 0xC05F3F95, 0xC07C3F54, 0x40F1C052, 0x40C4C04A, 0x4010C02A,
    0x3F42BFAB, 0xC0093FAC, 0x3F25BFB2, 0x3F95BFCA, 0x3F54C02A, 0x4052BFAB, 0xC04A3FAC, 0x402A3FB0,
    0x3FAB3FC0, 0x3FACC002, 0x3FB23F09, 0xBFCA3F25, 0xC02ABF96, 0x3FABBF5B, 0xBFAC406D, 0xBFB0C0B6,
    0x3FC0BFDB, 0xC002406D, 0xBF0940B5, 0xBF253FD5, 0xBF96C056, 0x3F5B4058, 0x406D4061, 0xC0B64085,
    0xBFDB3F14, 0x406DBF52, 0x40B54049, 0xBFD54025, 0xC0563F94, 0x4058BF53, 0xC061404D, 0xC085C036
};

//==============================================================================
// Test Storage (simulates AXI-Lite accessible memory)
//==============================================================================

// TX and RX BRAMs
static iq_pair_t tx_bram[IPInfo::BRAM_DEPTH];
static iq_pair_t rx_bram[IPInfo::BRAM_DEPTH];

// Control/Status registers
static axi_reg_t reg_ctrl = 0;
static axi_reg_t reg_status = 0;
static axi_reg_t reg_scratch = 0;
static axi_reg_t reg_rx_ctrl = 0;
static axi_reg_t reg_rx_status = 0;
static axi_reg_t reg_rx_fill = 0;
static axi_reg_t reg_tx_ctrl = 0;
static axi_reg_t reg_tx_status = 0;
static axi_reg_t reg_loopback = 0;

//==============================================================================
// Helper Functions
//==============================================================================

// Call adapter once (simulates one clock cycle)
void run_adapter_cycle(
    iq_sample_t adc_i0, iq_sample_t adc_q0,
    iq_sample_t adc_i1, iq_sample_t adc_q1,
    valid_t adc_valid,
    iq_sample_t& dac_i0, iq_sample_t& dac_q0,
    iq_sample_t& dac_i1, iq_sample_t& dac_q1,
    valid_t& dac_valid_i0, valid_t& dac_valid_q0,
    valid_t& dac_valid_i1, valid_t& dac_valid_q1
) {
    valid_t adc_enable_i0 = 1, adc_enable_q0 = 1, adc_enable_i1 = 1, adc_enable_q1 = 1;
    valid_t dac_enable_i0 = 1, dac_enable_q0 = 1, dac_enable_i1 = 1, dac_enable_q1 = 1;
    valid_t adc_dovf = 0, dac_dunf;

    axi_ad9361_adapter(
        tx_bram, rx_bram,
        reg_ctrl, reg_status, reg_scratch,
        reg_rx_ctrl, reg_rx_status, reg_rx_fill,
        reg_tx_ctrl, reg_tx_status,
        reg_loopback,
        adc_i0, adc_q0, adc_i1, adc_q1,
        adc_valid, adc_valid, adc_valid, adc_valid,
        adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1,
        dac_i0, dac_q0, dac_i1, dac_q1,
        dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1,
        dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1,
        adc_dovf, dac_dunf
    );
}


// Load TX BRAM with test data (simulates software loading via AXI-Lite)
// Uses simple ramp pattern: I = index, Q = -index
void load_tx_bram_test_data() {
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        int16_t i_val = (int16_t)(i & 0x7FFF);       // Ramp 0 to 1023
        int16_t q_val = (int16_t)(-(i & 0x7FFF));    // Ramp 0 to -1023
        tx_bram[i] = ((uint32_t)(q_val & 0xFFFF) << 16) | (uint32_t)(i_val & 0xFFFF);
    }
}

// Load TX BRAM with QPSK COE data (simulates software loading via AXI-Lite)
void load_tx_bram_coe_data() {
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        tx_bram[i] = iq_pair_t(QPSK_COE_DATA[i]);
    }
}

// Initialize adapter with soft reset
void reset_adapter() {
    reg_ctrl = (1 << CtrlBits::SOFT_RESET);
    reg_rx_ctrl = 0;
    reg_tx_ctrl = 0;
    reg_loopback = 0;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);
}

// Print sample values
void print_samples(const char* label, int sample_num,
                   iq_sample_t i0, iq_sample_t q0,
                   iq_sample_t i1, iq_sample_t q1) {
    std::cout << label << " [" << std::setw(4) << sample_num << "]: "
              << "I0=" << std::setw(6) << i0.to_int()
              << " Q0=" << std::setw(6) << q0.to_int()
              << " I1=" << std::setw(6) << i1.to_int()
              << " Q1=" << std::setw(6) << q1.to_int()
              << std::endl;
}

//==============================================================================
// Test 1: TX BRAM Software Load and Continuous Cycling
//==============================================================================

int test_tx_continuous_cycling() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 1: TX BRAM Continuous Cycling" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Step 1: Load TX BRAM with test data (software operation via AXI-Lite)
    std::cout << "Loading TX BRAM with test data (ramp pattern)..." << std::endl;
    load_tx_bram_test_data();

    // Step 2: Enable TX path and channels
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::TX_ENABLE);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    std::cout << "Running TX continuous cycling..." << std::endl;

    // Run for more than BRAM_DEPTH to verify wrap-around
    int wrap_count = 0;
    iq_sample_t first_i = 0, first_q = 0;
    bool first_captured = false;

    for (int i = 0; i < IPInfo::BRAM_DEPTH * 2 + 100; i++) {
        run_adapter_cycle(0, 0, 0, 0, 0,
                          dac_i0, dac_q0, dac_i1, dac_q1,
                          dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

        // Capture first sample
        if (!first_captured && dac_valid_i0) {
            first_i = dac_i0;
            first_q = dac_q0;
            first_captured = true;
        }

        // Detect wrap-around (when we see first sample again)
        if (first_captured && i > 10 && dac_i0 == first_i && dac_q0 == first_q) {
            wrap_count++;
            std::cout << "  Wrap-around detected at cycle " << i << std::endl;
        }

        // Print first few and samples around wrap point
        if (i < 5 || (i >= IPInfo::BRAM_DEPTH - 2 && i < IPInfo::BRAM_DEPTH + 3)) {
            print_samples("TX", i, dac_i0, dac_q0, dac_i1, dac_q1);
        }
    }

    // Verify TX BRAM contains expected ramp pattern
    std::cout << "\nVerifying TX BRAM contains loaded test data..." << std::endl;
    bool init_ok = true;
    for (int i = 0; i < 5; i++) {
        // Expected: I = i, Q = -i (ramp pattern from load_tx_bram_test_data)
        int16_t expected_i = (int16_t)(i & 0x7FFF);
        int16_t expected_q = (int16_t)(-(i & 0x7FFF));
        uint32_t expected = ((uint32_t)(expected_q & 0xFFFF) << 16) | (uint32_t)(expected_i & 0xFFFF);
        if (tx_bram[i].to_uint() != expected) {
            std::cout << "  ERROR: TX BRAM[" << i << "] = 0x" << std::hex << tx_bram[i].to_uint()
                      << " expected 0x" << expected << std::dec << std::endl;
            init_ok = false;
            errors++;
        }
    }
    if (init_ok) {
        std::cout << "  PASS: TX BRAM contains correct test data" << std::endl;
    }

    if (wrap_count >= 2) {
        std::cout << "PASS: TX continuous mode wraps correctly (" << wrap_count << " wraps)" << std::endl;
    } else {
        std::cout << "ERROR: TX continuous mode did not wrap as expected (wraps=" << wrap_count << ")" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Test 2: RX BRAM Capture with Fill Level
//==============================================================================

int test_rx_fill_level() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 2: RX BRAM Capture with Fill Level" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Clear RX BRAM
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        rx_bram[i] = 0;
    }

    // Enable RX path
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    std::cout << "Starting RX capture with ramp pattern..." << std::endl;

    // Feed test data into RX until buffer fills
    for (int i = 0; i < IPInfo::BRAM_DEPTH + 100; i++) {
        iq_sample_t adc_i0 = (i * 5) & 0x7FFF;
        iq_sample_t adc_q0 = ((i * 5) + 2) & 0x7FFF;

        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1,
                          dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

        // Print fill level at key points
        if (i < 5 || i == IPInfo::BRAM_DEPTH - 1 || i == IPInfo::BRAM_DEPTH || i == IPInfo::BRAM_DEPTH + 10) {
            std::cout << "  Cycle " << std::setw(4) << i
                      << ": fill_level=" << std::setw(4) << reg_rx_fill.to_uint()
                      << " RX_FULL=" << reg_status[StatusBits::RX_FULL] << std::endl;
        }
    }

    // Check fill level is 1024 (full)
    if (reg_rx_fill == IPInfo::BRAM_DEPTH) {
        std::cout << "PASS: RX fill level is 1024 (buffer full)" << std::endl;
    } else {
        std::cout << "ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 1024)" << std::endl;
        errors++;
    }

    // Check RX_FULL status bit
    if (reg_status[StatusBits::RX_FULL]) {
        std::cout << "PASS: RX_FULL status bit is set" << std::endl;
    } else {
        std::cout << "ERROR: RX_FULL status bit not set" << std::endl;
        errors++;
    }

    // Verify captured data
    std::cout << "\nVerifying RX BRAM contents (first 5 samples)..." << std::endl;
    int verify_errors = 0;
    for (int i = 0; i < 5; i++) {
        iq_pair_t sample = rx_bram[i];
        iq_sample_t rx_i = sample.range(15, 0);
        iq_sample_t rx_q = sample.range(31, 16);

        iq_sample_t expected_i = (i * 5) & 0x7FFF;
        iq_sample_t expected_q = ((i * 5) + 2) & 0x7FFF;

        std::cout << "  RX BRAM[" << std::setw(4) << i << "]: "
                  << "I=" << std::setw(6) << rx_i.to_int()
                  << " Q=" << std::setw(6) << rx_q.to_int();

        if (rx_i != expected_i || rx_q != expected_q) {
            std::cout << " ERROR (expected I=" << expected_i.to_int()
                      << " Q=" << expected_q.to_int() << ")";
            verify_errors++;
        }
        std::cout << std::endl;
    }

    if (verify_errors == 0) {
        std::cout << "PASS: RX BRAM data verified correctly" << std::endl;
    } else {
        std::cout << "ERROR: " << verify_errors << " verification errors" << std::endl;
        errors += verify_errors;
    }

    return errors;
}

//==============================================================================
// Test 3: RX Clear Functionality
//==============================================================================

int test_rx_clear() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 3: RX Clear Functionality" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    // Continue from previous state (buffer should be full)

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    std::cout << "Before clear: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    // Clear RX buffer
    reg_ctrl |= (1 << CtrlBits::RX_CLEAR);

    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    std::cout << "After clear: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    if (reg_rx_fill == 0) {
        std::cout << "PASS: RX fill level cleared to 0" << std::endl;
    } else {
        std::cout << "ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 0)" << std::endl;
        errors++;
    }

    // Verify RX_CLEAR bit is self-clearing
    if (!reg_ctrl[CtrlBits::RX_CLEAR]) {
        std::cout << "PASS: RX_CLEAR bit is self-clearing" << std::endl;
    } else {
        std::cout << "ERROR: RX_CLEAR bit did not self-clear" << std::endl;
        errors++;
    }

    // Feed more data and verify capture resumes
    std::cout << "\nVerifying capture resumes after clear..." << std::endl;
    for (int i = 0; i < 100; i++) {
        iq_sample_t adc_i0 = 8000 + i;
        iq_sample_t adc_q0 = 9000 + i;

        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1,
                          dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);
    }

    if (reg_rx_fill == 100) {
        std::cout << "PASS: RX capture resumed, fill_level=" << reg_rx_fill.to_uint() << std::endl;
    } else {
        std::cout << "ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 100)" << std::endl;
        errors++;
    }

    // Verify new data captured correctly
    iq_pair_t first_sample = rx_bram[0];
    iq_sample_t first_i = first_sample.range(15, 0);
    iq_sample_t first_q = first_sample.range(31, 16);

    if (first_i == 8000 && first_q == 9000) {
        std::cout << "PASS: New data captured correctly after clear" << std::endl;
    } else {
        std::cout << "ERROR: First sample after clear is I=" << first_i.to_int()
                  << " Q=" << first_q.to_int() << " (expected I=8000 Q=9000)" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Test 4: Loopback Mode
//==============================================================================

int test_loopback() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 4: Loopback Mode" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Enable loopback
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE) | (1 << CtrlBits::TX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);
    reg_loopback = (1 << CtrlBits::LOOPBACK_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    std::cout << "Testing loopback (RX -> TX)..." << std::endl;

    for (int i = 0; i < NUM_TEST_SAMPLES; i++) {
        iq_sample_t adc_i0 = 1000 + i * 100;
        iq_sample_t adc_q0 = 2000 + i * 100;

        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1,
                          dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

        // In loopback, TX should match RX
        if (i < 10) {
            std::cout << "  Sample " << i << ": ADC I=" << adc_i0.to_int()
                      << " Q=" << adc_q0.to_int()
                      << " -> DAC I=" << dac_i0.to_int()
                      << " Q=" << dac_q0.to_int();

            if (dac_i0 != adc_i0 || dac_q0 != adc_q0) {
                std::cout << " MISMATCH!";
                errors++;
            }
            std::cout << std::endl;
        }
    }

    if (errors == 0) {
        std::cout << "PASS: Loopback data matches" << std::endl;
    }

    return errors;
}

//==============================================================================
// Test 5: Register Access
//==============================================================================

int test_registers() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 5: Register Access" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Test scratch register
    std::cout << "Testing scratch register..." << std::endl;
    reg_scratch = 0x12345678;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    if (reg_scratch == 0x12345678) {
        std::cout << "  PASS: Scratch register readback correct" << std::endl;
    } else {
        std::cout << "  ERROR: Scratch register mismatch" << std::endl;
        errors++;
    }

    // Test soft reset clears state
    std::cout << "Testing soft reset..." << std::endl;

    // First fill some RX data
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN);
    for (int i = 0; i < 50; i++) {
        run_adapter_cycle(100, 200, 0, 0, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1,
                          dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);
    }

    std::cout << "  Before reset: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    // Apply soft reset
    reg_ctrl = (1 << CtrlBits::SOFT_RESET);
    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    std::cout << "  After reset: fill_level=" << reg_rx_fill.to_uint() << std::endl;

    if (reg_rx_fill == 0) {
        std::cout << "  PASS: Soft reset cleared RX fill level" << std::endl;
    } else {
        std::cout << "  ERROR: RX fill level not cleared by soft reset" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Test 6: TX and RX Simultaneous Operation
//==============================================================================

int test_simultaneous_txrx() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 6: Simultaneous TX and RX" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;
    reset_adapter();

    // Clear RX BRAM
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        rx_bram[i] = 0;
    }

    // Enable both TX and RX (no loopback)
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE) | (1 << CtrlBits::TX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    std::cout << "Running simultaneous TX cycling and RX capture..." << std::endl;

    // Run for some cycles
    for (int i = 0; i < 500; i++) {
        // Feed RX with distinct pattern
        iq_sample_t adc_i0 = 30000 - i;
        iq_sample_t adc_q0 = 31000 - i;

        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1,
                          dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

        if (i < 5) {
            std::cout << "  Cycle " << i << ": TX out I=" << dac_i0.to_int()
                      << " Q=" << dac_q0.to_int()
                      << ", RX in I=" << adc_i0.to_int()
                      << " Q=" << adc_q0.to_int()
                      << ", fill=" << reg_rx_fill.to_uint() << std::endl;
        }
    }

    // Verify RX captured correct data (first 5 samples)
    std::cout << "\nVerifying RX captured data (first 5 samples)..." << std::endl;
    bool rx_ok = true;
    for (int i = 0; i < 5; i++) {
        iq_pair_t sample = rx_bram[i];
        iq_sample_t rx_i = sample.range(15, 0);
        iq_sample_t rx_q = sample.range(31, 16);

        iq_sample_t expected_i = 30000 - i;
        iq_sample_t expected_q = 31000 - i;

        std::cout << "  RX BRAM[" << i << "]: I=" << rx_i.to_int()
                  << " Q=" << rx_q.to_int();

        if (rx_i != expected_i || rx_q != expected_q) {
            std::cout << " ERROR";
            rx_ok = false;
            errors++;
        }
        std::cout << std::endl;
    }

    // Verify TX is outputting from BRAM (not RX data since loopback is off)
    // TX should be cycling through initialized BRAM
    std::cout << "\nVerifying TX is cycling independently from RX..." << std::endl;
    if (dac_valid_i0 && reg_status[StatusBits::TX_ACTIVE]) {
        std::cout << "PASS: TX is active and outputting data" << std::endl;
    } else {
        std::cout << "ERROR: TX not active" << std::endl;
        errors++;
    }

    if (rx_ok) {
        std::cout << "PASS: Simultaneous TX/RX operation completed" << std::endl;
    }

    return errors;
}

//==============================================================================
// Test 7: Full Flow with COE Data (TX->RX via Loopback)
//==============================================================================

int test_full_flow_coe_data() {
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test 7: Full Flow with COE Data" << std::endl;
    std::cout << "========================================" << std::endl;

    int errors = 0;

    // Step 1: Disable TX via register write
    std::cout << "Step 1: Disabling TX..." << std::endl;
    reg_ctrl = 0;  // Clear all enables
    reg_tx_ctrl = 0;

    iq_sample_t dac_i0, dac_q0, dac_i1, dac_q1;
    valid_t dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;

    // Run a cycle to apply the change
    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    std::cout << "  TX disabled (reg_ctrl=0x" << std::hex << reg_ctrl.to_uint()
              << ", reg_tx_ctrl=0x" << reg_tx_ctrl.to_uint() << ")" << std::dec << std::endl;

    // Step 2: Disable RX via register write
    std::cout << "Step 2: Disabling RX..." << std::endl;
    reg_rx_ctrl = 0;

    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    std::cout << "  RX disabled (reg_rx_ctrl=0x" << std::hex << reg_rx_ctrl.to_uint() << ")" << std::dec << std::endl;

    // Apply soft reset to clear any previous state
    std::cout << "  Applying soft reset..." << std::endl;
    reg_ctrl = (1 << CtrlBits::SOFT_RESET);
    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    // Clear RX BRAM
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        rx_bram[i] = 0;
    }

    // Step 3: Load TX BRAM with COE file data
    std::cout << "Step 3: Loading TX BRAM with COE data (1024 QPSK samples)..." << std::endl;
    load_tx_bram_coe_data();

    // Verify first few samples loaded correctly
    std::cout << "  Verifying TX BRAM load (first 5 samples):" << std::endl;
    bool load_ok = true;
    for (int i = 0; i < 5; i++) {
        if (tx_bram[i].to_uint() != QPSK_COE_DATA[i]) {
            std::cout << "  ERROR: TX BRAM[" << i << "] = 0x" << std::hex << tx_bram[i].to_uint()
                      << " expected 0x" << QPSK_COE_DATA[i] << std::dec << std::endl;
            load_ok = false;
            errors++;
        } else {
            int16_t i_val = (int16_t)(QPSK_COE_DATA[i] & 0xFFFF);
            int16_t q_val = (int16_t)((QPSK_COE_DATA[i] >> 16) & 0xFFFF);
            std::cout << "    TX BRAM[" << i << "] = 0x" << std::hex << tx_bram[i].to_uint()
                      << std::dec << " (I=" << i_val << ", Q=" << q_val << ")" << std::endl;
        }
    }
    if (load_ok) {
        std::cout << "  PASS: TX BRAM loaded correctly" << std::endl;
    }

    // Step 4: Enable RX via register write
    std::cout << "Step 4: Enabling RX..." << std::endl;
    reg_ctrl = (1 << CtrlBits::ENABLE) | (1 << CtrlBits::RX_ENABLE);
    reg_rx_ctrl = (1 << CtrlBits::RX_CH0_EN) | (1 << CtrlBits::RX_CH1_EN);

    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    std::cout << "  RX enabled (reg_ctrl=0x" << std::hex << reg_ctrl.to_uint()
              << ", reg_rx_ctrl=0x" << reg_rx_ctrl.to_uint() << ")" << std::dec << std::endl;

    // Step 5: Enable TX via register write (with loopback for TX->RX path)
    std::cout << "Step 5: Enabling TX with loopback..." << std::endl;
    reg_ctrl |= (1 << CtrlBits::TX_ENABLE);
    reg_tx_ctrl = (1 << CtrlBits::TX_CH0_EN) | (1 << CtrlBits::TX_CH1_EN);
    reg_loopback = (1 << CtrlBits::LOOPBACK_EN);

    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    std::cout << "  TX enabled with loopback (reg_ctrl=0x" << std::hex << reg_ctrl.to_uint()
              << ", reg_tx_ctrl=0x" << reg_tx_ctrl.to_uint()
              << ", reg_loopback=0x" << reg_loopback.to_uint() << ")" << std::dec << std::endl;

    // Run cycles until RX buffer fills (1024 samples)
    // In loopback mode, TX output goes to RX input
    std::cout << "\nRunning loopback transfer (TX BRAM -> RX BRAM)..." << std::endl;
    int cycle_count = 0;
    const int MAX_CYCLES = IPInfo::BRAM_DEPTH + 100;

    while (reg_rx_fill < IPInfo::BRAM_DEPTH && cycle_count < MAX_CYCLES) {
        // In loopback, we don't need external ADC data - the IP loops TX to RX internally
        // But we need valid ADC inputs to trigger RX capture
        // Actually, in loopback mode the TX data is used directly

        // Read current TX output and feed it back as RX input
        iq_pair_t tx_sample = tx_bram[cycle_count % IPInfo::BRAM_DEPTH];
        iq_sample_t adc_i0 = tx_sample.range(15, 0);
        iq_sample_t adc_q0 = tx_sample.range(31, 16);

        run_adapter_cycle(adc_i0, adc_q0, 0, 0, 1,
                          dac_i0, dac_q0, dac_i1, dac_q1,
                          dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

        // Print progress at key points
        if (cycle_count < 5 || cycle_count == 512 || cycle_count == 1023 ||
            (reg_rx_fill.to_uint() == IPInfo::BRAM_DEPTH && cycle_count > 0)) {
            std::cout << "  Cycle " << std::setw(4) << cycle_count
                      << ": fill_level=" << std::setw(4) << reg_rx_fill.to_uint()
                      << " TX I=" << std::setw(6) << adc_i0.to_int()
                      << " Q=" << std::setw(6) << adc_q0.to_int() << std::endl;
        }

        cycle_count++;
    }

    // Step 6: Check if RX memory fill level is 1024
    std::cout << "\nStep 6: Checking RX fill level..." << std::endl;
    if (reg_rx_fill == IPInfo::BRAM_DEPTH) {
        std::cout << "  PASS: RX fill level is 1024 (buffer full)" << std::endl;
    } else {
        std::cout << "  ERROR: RX fill level is " << reg_rx_fill.to_uint() << " (expected 1024)" << std::endl;
        errors++;
    }

    // Check RX_FULL status bit
    if (reg_status[StatusBits::RX_FULL]) {
        std::cout << "  PASS: RX_FULL status bit is set" << std::endl;
    } else {
        std::cout << "  ERROR: RX_FULL status bit not set" << std::endl;
        errors++;
    }

    // Step 7: Read RX memory (verify data matches TX BRAM / COE data)
    std::cout << "\nStep 7: Reading and verifying RX memory..." << std::endl;
    std::cout << "  (Comparing RX BRAM to original COE data)" << std::endl;

    int verify_errors = 0;
    for (int i = 0; i < IPInfo::BRAM_DEPTH; i++) {
        iq_pair_t rx_sample = rx_bram[i];
        uint32_t expected = QPSK_COE_DATA[i];

        if (rx_sample.to_uint() != expected) {
            if (verify_errors < 10) {  // Limit error output
                int16_t rx_i = (int16_t)(rx_sample.range(15, 0).to_int());
                int16_t rx_q = (int16_t)(rx_sample.range(31, 16).to_int());
                int16_t exp_i = (int16_t)(expected & 0xFFFF);
                int16_t exp_q = (int16_t)((expected >> 16) & 0xFFFF);

                std::cout << "  ERROR: RX BRAM[" << i << "] = 0x" << std::hex << rx_sample.to_uint()
                          << " (I=" << std::dec << rx_i << ", Q=" << rx_q << ")"
                          << " expected 0x" << std::hex << expected
                          << " (I=" << std::dec << exp_i << ", Q=" << exp_q << ")" << std::endl;
            }
            verify_errors++;
        }
    }

    if (verify_errors == 0) {
        std::cout << "  PASS: All 1024 RX samples match original COE data" << std::endl;
    } else {
        std::cout << "  ERROR: " << verify_errors << " samples did not match" << std::endl;
        errors += verify_errors;
    }

    // Print first and last few samples for inspection
    std::cout << "\n  First 5 RX samples:" << std::endl;
    for (int i = 0; i < 5; i++) {
        int16_t rx_i = (int16_t)(rx_bram[i].range(15, 0).to_int());
        int16_t rx_q = (int16_t)(rx_bram[i].range(31, 16).to_int());
        std::cout << "    RX[" << std::setw(4) << i << "]: I=" << std::setw(6) << rx_i
                  << " Q=" << std::setw(6) << rx_q
                  << " (0x" << std::hex << rx_bram[i].to_uint() << ")" << std::dec << std::endl;
    }

    std::cout << "  Last 5 RX samples:" << std::endl;
    for (int i = IPInfo::BRAM_DEPTH - 5; i < IPInfo::BRAM_DEPTH; i++) {
        int16_t rx_i = (int16_t)(rx_bram[i].range(15, 0).to_int());
        int16_t rx_q = (int16_t)(rx_bram[i].range(31, 16).to_int());
        std::cout << "    RX[" << std::setw(4) << i << "]: I=" << std::setw(6) << rx_i
                  << " Q=" << std::setw(6) << rx_q
                  << " (0x" << std::hex << rx_bram[i].to_uint() << ")" << std::dec << std::endl;
    }

    // Clear RX buffer after reading (optional step to demonstrate RX_CLEAR)
    std::cout << "\n  Clearing RX buffer after read..." << std::endl;
    reg_ctrl |= (1 << CtrlBits::RX_CLEAR);
    run_adapter_cycle(0, 0, 0, 0, 0,
                      dac_i0, dac_q0, dac_i1, dac_q1,
                      dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1);

    if (reg_rx_fill == 0) {
        std::cout << "  PASS: RX buffer cleared (fill_level=0)" << std::endl;
    } else {
        std::cout << "  ERROR: RX buffer not cleared (fill_level=" << reg_rx_fill.to_uint() << ")" << std::endl;
        errors++;
    }

    return errors;
}

//==============================================================================
// Main Test Program
//==============================================================================

int main() {
    std::cout << "========================================" << std::endl;
    std::cout << "AXI AD9361 Adapter HLS Testbench" << std::endl;
    std::cout << "Version: " << IPInfo::VERSION_MAJOR << "."
              << IPInfo::VERSION_MINOR << "."
              << IPInfo::VERSION_PATCH << std::endl;
    std::cout << "BRAM Depth: " << IPInfo::BRAM_DEPTH << " samples" << std::endl;
    std::cout << "========================================" << std::endl;

    int total_errors = 0;

    // Run all tests
    total_errors += test_tx_continuous_cycling();
    total_errors += test_rx_fill_level();
    total_errors += test_rx_clear();
    total_errors += test_loopback();
    total_errors += test_registers();
    total_errors += test_simultaneous_txrx();
    total_errors += test_full_flow_coe_data();

    // Summary
    std::cout << "\n========================================" << std::endl;
    std::cout << "Test Summary" << std::endl;
    std::cout << "========================================" << std::endl;

    if (total_errors == 0) {
        std::cout << "ALL TESTS PASSED!" << std::endl;
        return 0;
    } else {
        std::cout << "TESTS FAILED: " << total_errors << " errors" << std::endl;
        return 1;
    }
}
