`timescale 1ns / 1ps

module SramTop(
i_addr_13,i_data_32,i_WEB_4,i_sramTrig,o_data_32	
    );

input[12:0] i_addr_13;
input[31:0] i_data_32;
input       i_sramTrig;
input[3:0] i_WEB_4;
output[31:0] o_data_32;   
//---------------------------------------------------------

SHTB110_8192X8X4CM16 Sram(
    .A0   ( i_addr_13[0]  ),  .A1   ( i_addr_13[1]  ),  .A2  ( i_addr_13[2] ),  .A3  ( i_addr_13[3] ),  .A4  ( i_addr_13[4]   ),  
    .A5   ( i_addr_13[5]  ),  .A6   ( i_addr_13[6]  ),  .A7  ( i_addr_13[7] ),  .A8  ( i_addr_13[8] ),  .A9  ( i_addr_13[9]   ),  
    .A10  ( i_addr_13[10] ),  .A11  ( i_addr_13[11] ),  .A12  ( i_addr_13[12] ),                                
    .DO0  ( o_data_32[0]  ),  .DO1  ( o_data_32[1]  ),  .DO2  ( o_data_32[2]  ),  .DO3  ( o_data_32[3]  ),  .DO4  ( o_data_32[4]  ), 
    .DO5  ( o_data_32[5]  ),  .DO6  ( o_data_32[6]  ),  .DO7  ( o_data_32[7]  ),  .DO8  ( o_data_32[8]  ),  .DO9  ( o_data_32[9]  ),  
    .DO10 ( o_data_32[10] ),  .DO11 ( o_data_32[11] ),  .DO12 ( o_data_32[12] ),  .DO13 ( o_data_32[13] ),  .DO14 ( o_data_32[14] ), 
    .DO15 ( o_data_32[15] ),  .DO16 ( o_data_32[16] ),  .DO17 ( o_data_32[17] ),  .DO18 ( o_data_32[18] ),  .DO19 ( o_data_32[19] ), 
    .DO20 ( o_data_32[20] ),  .DO21 ( o_data_32[21] ),  .DO22 ( o_data_32[22] ),  .DO23 ( o_data_32[23] ),  .DO24 ( o_data_32[24] ),  
    .DO25 ( o_data_32[25] ),  .DO26 ( o_data_32[26] ),  .DO27 ( o_data_32[27] ),  .DO28 ( o_data_32[28] ),  .DO29 ( o_data_32[29] ),  
    .DO30 ( o_data_32[30] ),  .DO31 ( o_data_32[31] ),  
    .DI0  ( i_data_32[0]  ),  .DI1  ( i_data_32[1]  ),  .DI2  ( i_data_32[2]  ),  .DI3  ( i_data_32[3]  ),  .DI4  ( i_data_32[4]  ), 
    .DI5  ( i_data_32[5]  ),  .DI6  ( i_data_32[6]  ),  .DI7  ( i_data_32[7]  ),  .DI8  ( i_data_32[8]  ),  .DI9  ( i_data_32[9]  ),  
    .DI10 ( i_data_32[10] ),  .DI11 ( i_data_32[11] ),  .DI12 ( i_data_32[12] ),  .DI13 ( i_data_32[13] ),  .DI14 ( i_data_32[14] ), 
    .DI15 ( i_data_32[15] ),  .DI16 ( i_data_32[16] ),  .DI17 ( i_data_32[17] ),  .DI18 ( i_data_32[18] ),  .DI19 ( i_data_32[19] ), 
    .DI20 ( i_data_32[20] ),  .DI21 ( i_data_32[21] ),  .DI22 ( i_data_32[22] ),  .DI23 ( i_data_32[23] ),  .DI24 ( i_data_32[24] ),  
    .DI25 ( i_data_32[25] ),  .DI26 ( i_data_32[26] ),  .DI27 ( i_data_32[27] ),  .DI28 ( i_data_32[28] ),  .DI29 ( i_data_32[29] ),  
    .DI30 ( i_data_32[30] ),  .DI31 ( i_data_32[31] ),  
    .WEB0 ( i_WEB_4[0]  ), .WEB1 ( i_WEB_4[1]  ), .WEB2 ( i_WEB_4[2]  ), .WEB3 ( i_WEB_4[3]  ),
    .DVSE ( 1'b0 ),  .DVS0 ( 1'b0 ),  .DVS1 ( 1'b0 ),  .DVS2 ( 1'b0 ),  .DVS3 ( 1'b0 ),  .CK ( i_sramTrig ),
    .CSB  ( 1'b0 ),
    .OE   ( 1'b1 )
);



endmodule
