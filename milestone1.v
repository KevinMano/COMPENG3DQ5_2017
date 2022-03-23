`timescale 1ns/100ps
`default_nettype none

`include "define_state.h"

module milestone1(
/////// board clocks                      ////////////
		input logic CLOCK_50_I,                   // 50 MHz clock
		input logic resetn,								//Reset_n signal
		input logic [15:0] read_data,					//Read data
		input logic startmilestone1,					//to start milestone1
		output logic[17:0] address,
		output logic[15:0] write_data,
		output logic we_n,
		output logic endmilestone1,
		output logic[15:0] B_OUT,
		output logic[15:0] R_OUT,
		output logic[15:0] G_OUT,
		output logic[31:0] RGB_MACODD,
		output logic[31:0] RGB_MACEVEN,
		output logic[31:0] U_MAC,
		output logic[31:0] V_MAC
);

// Misc
M1_state_type state;
logic [7:0] clip_odd, clip_even;
logic duplicate_UV;																	//Flag to check if nearing end of row. @Nicolici and Sarah

// MACs
//logic[31:0] RGB_MACEVEN, RGB_MACODD;
//logic[31:0] U_MAC, V_MAC;

// Buffers
logic[31:0] Y_EVENPARTIALPROD;													//To hold partial products for EVEN Y
logic[31:0] Y_ODDPARTIALPROD;														//To hold partial products for ODD Y
logic[31:0] U_prime, V_prime; 													//Storage for U and V MAC outputs
logic[15:0] Y_BUFF, U_BUFF, V_BUFF;												//Read buffers
//logic[15:0] R_OUT, G_OUT, B_OUT;													//RGB values to be written
logic[7:0] U_SHIFTREG [5:0];														//U[(j-5)/2] = U_SHIFTREG[0]... 
logic[7:0] V_SHIFTREG [5:0];														//V[(j-5)/2] = V_SHIFTREG[0]... 

// Address offsets
logic [17:0] row_count;
logic [17:0] column_count;
logic [17:0] write_offset;

// Mux selectors
logic [2:0] U_mux, V_mux, RGBEVEN_mux, RGBODD_mux;

// Multiplier ins and outs
logic [31:0] U_MULTOUT, V_MULTOUT, RGBEVEN_MULTOUT, RGBODD_MULTOUT;
logic [31:0] mult_in_U, mult_in_V, mult_in_RGBEVEN, mult_in_RGBODD;
logic [31:0] U_sel, V_sel, RGBEVEN_sel, RGBODD_sel;

assign clip_odd = RGB_MACODD[31] ? 8'd0 :
						|RGB_MACODD[30:24] ? 8'hff : 
						RGB_MACODD[23:16];
						
assign clip_even = RGB_MACEVEN[31] ? 8'd0 :
						|RGB_MACEVEN[30:24] ? 8'hff : 
						RGB_MACEVEN[23:16];

//Parameters for the memory
parameter U_OFFSET = 18'd38400,
	  V_OFFSET = 18'd57600,
	  RGB_OFFSET = 18'd146944;

//MUXs created here. 8 in total.
assign mult_in_U = 		(U_mux == 3'b000) ? 32'd21 : 
								(U_mux == 3'b001) ? 32'd52 :
								(U_mux == 3'b010) ? 32'd159 : 
								(U_mux == 3'b011) ? 32'd159 :
								(U_mux == 3'b100) ? 32'd52 :
								(U_mux == 3'b101) ? 32'd21 : 32'd0;
								
assign U_sel =				(U_mux == 3'b000) ? {24'b0, U_SHIFTREG[0]} :
								(U_mux == 3'b001) ? {24'b0, U_SHIFTREG[1]} :
								(U_mux == 3'b010) ? {24'b0, U_SHIFTREG[2]} :
								(U_mux == 3'b011) ? {24'b0, U_SHIFTREG[3]} :
								(U_mux == 3'b100) ? {24'b0, U_SHIFTREG[4]} :
								(U_mux == 3'b101) ? {24'b0, U_SHIFTREG[5]} : 32'd0;

assign mult_in_V = 		(V_mux == 3'b000) ? 32'd21 : 
								(V_mux == 3'b001) ? 32'd52 :
								(V_mux == 3'b010) ? 32'd159 : 
								(V_mux == 3'b011) ? 32'd159 :
								(V_mux == 3'b100) ? 32'd52 :
								(V_mux == 3'b101) ? 32'd21 : 32'd0;
							
assign V_sel =				(V_mux == 3'b000) ? {24'b0, V_SHIFTREG[0]} :
								(V_mux == 3'b001) ? {24'b0, V_SHIFTREG[1]} :
								(V_mux == 3'b010) ? {24'b0, V_SHIFTREG[2]} :
								(V_mux == 3'b011) ? {24'b0, V_SHIFTREG[3]} :
								(V_mux == 3'b100) ? {24'b0, V_SHIFTREG[4]} :
								(V_mux == 3'b101) ? {24'b0, V_SHIFTREG[5]} : 32'd0;
							
assign mult_in_RGBODD = (RGBODD_mux == 3'b000) ? 32'd76284 :
								(RGBODD_mux == 3'b001) ? 32'd104595:
								(RGBODD_mux == 3'b010) ? 32'd53281 :
								(RGBODD_mux == 3'b011) ? 32'd25624 :
								(RGBODD_mux == 3'b100) ? 32'd132251: 32'd25624;
								
assign RGBODD_sel = 		(RGBODD_mux == 3'b000) ? {24'b0, Y_BUFF[7:0]} - 32'd16 :
								(RGBODD_mux == 3'b001) ? {8'b0, V_MAC[31:8]} - 32'd128 ://////////////GET FROM ACCUMULTOR
								(RGBODD_mux == 3'b010) ? {8'b0, V_prime[31:8]} - 32'd128 ://////////////GET FROM STORAGE REG
								(RGBODD_mux == 3'b011) ? {8'b0, U_prime[31:8]} - 32'd128 :
								(RGBODD_mux == 3'b100) ? {8'b0, U_prime[31:8]} - 32'd128 : {8'b0, U_MAC[31:8]} - 32'd128;
								
						
assign mult_in_RGBEVEN = (RGBEVEN_mux == 3'b000) ? 32'd104595 :
								(RGBEVEN_mux == 3'b001) ? 32'd76284 :
								(RGBEVEN_mux == 3'b010) ? 32'd25624 :
								(RGBEVEN_mux == 3'b011) ? 32'd53281 :
								(RGBEVEN_mux == 3'b100) ? 32'd132251 :
								(RGBEVEN_mux == 3'b101) ? 32'd53281 :
								(RGBEVEN_mux == 3'b110) ? 32'd132251 : 32'd0;
								
assign RGBEVEN_sel = 	(RGBEVEN_mux == 3'b000) ? {24'b0, V_SHIFTREG[2]} - 32'd128 :
								(RGBEVEN_mux == 3'b001) ? {24'b0, Y_BUFF[15:8]} - 32'd16 :
								(RGBEVEN_mux == 3'b010) ? {24'b0, U_SHIFTREG[2]} - 32'd128 :
								(RGBEVEN_mux == 3'b011) ? {24'b0, V_SHIFTREG[1]} - 32'd128 :
								(RGBEVEN_mux == 3'b100) ? {24'b0, U_SHIFTREG[1]} - 32'd128 :
								(RGBEVEN_mux == 3'b101) ? {24'b0, V_SHIFTREG[2]} - 32'd128 :
								(RGBEVEN_mux == 3'b110) ? {24'b0, U_SHIFTREG[2]} - 32'd128 : 32'd0;
				
//Multipliers instantiated here.				
multiplier U_mult(.op1(U_sel), .op2(mult_in_U), .result(U_MULTOUT));
multiplier V_mult(.op1(V_sel), .op2(mult_in_V), .result(V_MULTOUT));
multiplier RGB_EVENMULT(.op1(RGBEVEN_sel), .op2(mult_in_RGBEVEN), .result(RGBEVEN_MULTOUT));
multiplier RGB_ODDMULT(.op1(RGBODD_sel), .op2(mult_in_RGBODD), .result(RGBODD_MULTOUT));
							
//FSM
always_ff @(posedge CLOCK_50_I or negedge resetn) begin
	if(resetn == 1'b0) begin
		state <= S_M1_IDLE;
		we_n <= 1'b1;
		write_data <= 16'd0;
		address <= 18'd0;
		row_count <= 18'd0;
		column_count <= 18'd0;
		write_offset <= 18'd0;
		duplicate_UV <= 1'b0;
		endmilestone1 <= 1'b0;
	end else begin
	
		case (state)
		S_M1_IDLE: begin
			if(startmilestone1 == 1'b1) begin
				state <= S_M1_LI0;
				column_count <= 18'd0;
				row_count <= 18'd0;
				write_offset <= 18'd0;
				duplicate_UV <= 1'b0;
			end
			endmilestone1 <= 1'b0;
		end
	
		S_M1_LI0: begin
			//Writing output
			we_n <= 1'b1;
			
			//Calculations
			
			//Other
		
			//Addressing increments
			address <= row_count + V_OFFSET;
			
			//Next state stuff
			state <= S_M1_LI1;
		end
		
		S_M1_LI1: begin
			//Writing output
			
			//Other
		
			//Addressing increments
			address <= row_count<<1;
			
			//Next state stuff
			state <= S_M1_LI2;
		end
		
		S_M1_LI2: begin
			//Writing output
			
			//Other
			
			//Addressing increments
			address <= row_count + U_OFFSET;
			column_count <= column_count + 18'd1;
			
			//Next state stuff
			state <= S_M1_LI3;
		end
		
		S_M1_LI3: begin
			//Writing output
			
			//Calculations
			V_mux <= 3'b0; 
			RGBEVEN_mux <= 3'b0;
			
			//Other
			V_SHIFTREG[0] <= read_data[15:8];
			V_SHIFTREG[1] <= read_data[15:8];
			V_SHIFTREG[2] <= read_data[15:8];
			V_SHIFTREG[3] <= read_data[7:0];
			
			//Addressing increments
			address <= row_count + column_count + V_OFFSET;
			
			//Next state stuff
			state <= S_M1_LI4;
		end
		
		S_M1_LI4: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= RGBEVEN_MULTOUT;
			V_MAC <= V_MULTOUT + 32'd128;
			V_mux <= 3'b001; 
			RGBEVEN_mux <= 3'b001;
			
			//Other 
			Y_BUFF <= read_data;
			
			//Addressing increments
			address <= row_count + column_count + U_OFFSET;
			column_count <= column_count + 18'd1;
			
			//Next state stuff
			state <= S_M1_LI5;
		end
		
		S_M1_LI5: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= RGB_MACEVEN + RGBEVEN_MULTOUT;
			Y_EVENPARTIALPROD <= RGBEVEN_MULTOUT;
			V_MAC <=  V_MAC - V_MULTOUT;
			V_mux <= 3'b010; 
			RGBEVEN_mux <= 3'b010;
			U_mux <= 3'b0;
			
			//Other
			U_SHIFTREG[0] <= read_data[15:8];
			U_SHIFTREG[1] <= read_data[15:8];
			U_SHIFTREG[2] <= read_data[15:8];
			U_SHIFTREG[3] <= read_data[7:0];
			
			//Addressing increments
			address <= row_count + column_count + V_OFFSET;
			
			//Next state stuff
			state <= S_M1_LI6;
		end
		
		S_M1_LI6: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= Y_EVENPARTIALPROD - RGBEVEN_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT; 
			U_MAC <= U_MULTOUT + 32'd128;
			V_mux <= 3'b011; 
			RGBEVEN_mux <= 3'b011;
			U_mux <= 3'b001;
			
			//Other
			V_SHIFTREG[4] <= read_data[15:8];
			V_SHIFTREG[5] <= read_data[7:0];
			R_OUT[15:8] <= clip_even;
			
			//Addressing increments
			address <= row_count + column_count + U_OFFSET;
			
			//Next state stuff
			state <= S_M1_LI7;
		end
		
		S_M1_LI7: begin
			//Writing output 
			
			//Calculations
			RGB_MACEVEN <= RGB_MACEVEN - RGBEVEN_MULTOUT;
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			V_mux <= 3'b100; 
			RGBEVEN_mux <= 3'b100;
			U_mux <= 3'b010;
			
			//Other
			U_SHIFTREG[4] <= read_data[15:8];
			U_SHIFTREG[5] <= read_data[7:0];
			
			//Addressing increments
			
			//Next state stuff
			state <= S_M1_LI8;
		end
		
		S_M1_LI8: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= RGBEVEN_MULTOUT + Y_EVENPARTIALPROD;
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC - V_MULTOUT;
			V_mux <= 3'b101; 
			U_mux <= 3'b011;
			RGBODD_mux <= 3'b0;
			
			//Other
			V_BUFF <= read_data;
			G_OUT[15:8] <= clip_even;
			
			//Addressing increments
			
			//Next state stuff
			state <= S_M1_LI9;
		end
		
		S_M1_LI9: begin
			//Writing output 
			we_n <= 1'b0;
			write_data[15:8] <= R_OUT[15:8];
			write_data[7:0] <= G_OUT[15:8];
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			V_mux <= 3'b0; 
			U_mux <= 3'b100;
			RGB_MACODD <= RGBODD_MULTOUT;
			Y_ODDPARTIALPROD <= RGBODD_MULTOUT;
			RGBODD_mux <= 3'b001;
			
			//Other
			V_SHIFTREG[0] <= V_SHIFTREG[1];
			V_SHIFTREG[1] <= V_SHIFTREG[2];
			V_SHIFTREG[2] <= V_SHIFTREG[3];
			V_SHIFTREG[3] <= V_SHIFTREG[4];
			V_SHIFTREG[4] <= V_SHIFTREG[5];
			V_SHIFTREG[5] <= V_BUFF[15:8];
			U_BUFF <= read_data;
			B_OUT[15:8] <= clip_even;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LI10;
		end
		
		S_M1_LI10: begin
			//Writing output
			we_n <= 1'b1;
			
			//Calculations
			V_prime <= V_MAC;
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MULTOUT + 32'd128;
			V_mux <= 3'b001; 
			U_mux <= 3'b101;
			RGBODD_mux <= 3'b010;
			RGB_MACODD <= RGB_MACODD + RGBODD_MULTOUT;
			
			//Other 
			
			//Addressing increments
			
			//Next state stuff
			state <= S_M1_LI11;
		end
		
		S_M1_LI11: begin
			//Writing output
			
			//Calculations
			
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC - V_MULTOUT;
			V_mux <= 3'b010; 
			U_mux <= 3'b0;
			RGB_MACODD <= Y_ODDPARTIALPROD - RGBODD_MULTOUT;
			RGBODD_mux <= 3'b111;
			
			//Other
			U_SHIFTREG[0] <= U_SHIFTREG[1];
			U_SHIFTREG[1] <= U_SHIFTREG[2];
			U_SHIFTREG[2] <= U_SHIFTREG[3];
			U_SHIFTREG[3] <= U_SHIFTREG[4];
			U_SHIFTREG[4] <= U_SHIFTREG[5];
			U_SHIFTREG[5] <= U_BUFF[15:8];
			R_OUT[7:0] <= clip_odd;
			
			//Addressing increments
			address <= ((row_count) << 1) + 18'd1;
			
			//Next state stuff
			state <= S_M1_LI12;
		end
		
		S_M1_LI12: begin
			//Writing output
			
			//Calculations
			RGB_MACODD <= RGB_MACODD - RGBODD_MULTOUT;
			U_prime <= U_MAC;
			U_MAC <= U_MULTOUT + 32'd128;
			V_MAC <= V_MAC + V_MULTOUT;
			RGBODD_mux <= 3'b100;
			V_mux <= 3'b011; 
			U_mux <= 3'b001;
			
			//Other
			
			//Addressing increments
			
			//Next state stuff
			state <= S_M1_LI13;
		end
		
		S_M1_LI13: begin
			//Writing output
			we_n <= 1'b0;
			write_data[15:8] <= B_OUT[15:8];
			write_data[7:0] <= R_OUT[7:0];

			//Other
			G_OUT[7:0] <= clip_odd;
			
			//Calculations
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD + RGBODD_MULTOUT;
			V_mux <= 3'b100; 
			U_mux <= 3'b010;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LI14;
		end
		
		S_M1_LI14: begin
			//Writing output
			we_n <= 1'b1;
			
			//Other
			Y_BUFF <= read_data;
			B_OUT[7:0] <= clip_odd;
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC - V_MULTOUT;
			V_mux <= 3'b101; 
			U_mux <= 3'b011;
			RGBEVEN_mux <= 3'b0;
			
			//Addressing increments
			
			//Next state stuff
			state <= S_M1_LI15;
		end
		
		S_M1_LI15: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= RGBEVEN_MULTOUT;
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			U_mux <= 3'b100;
			RGBODD_mux <= 3'b0;
			RGBEVEN_mux <= 3'b001;
			
			//Other
			V_SHIFTREG[0] <= V_SHIFTREG[1];
			V_SHIFTREG[1] <= V_SHIFTREG[2];
			V_SHIFTREG[2] <= V_SHIFTREG[3];
			V_SHIFTREG[3] <= V_SHIFTREG[4];
			V_SHIFTREG[4] <= V_SHIFTREG[5];
			V_SHIFTREG[5] <= V_BUFF[7:0];
			
			//Addressing increments
			
			//Next state stuff
			state <= S_M1_LI16;
		end
		
		S_M1_LI16: begin
			//Writing output
			we_n <= 1'b0;
			write_data[15:8] <= G_OUT[7:0];
			write_data[7:0] <= B_OUT[7:0];
			
			//Calculations
			RGB_MACEVEN <= RGB_MACEVEN + RGBEVEN_MULTOUT;
			RGB_MACODD <= RGBODD_MULTOUT;
			Y_EVENPARTIALPROD <= RGBEVEN_MULTOUT;
			Y_ODDPARTIALPROD <= RGBODD_MULTOUT;
			U_MAC <= U_MAC - U_MULTOUT;
			V_prime <= V_MAC; 
			U_mux <= 3'b101;
			RGBODD_mux <= 3'b001;
			RGBEVEN_mux <= 3'b010;
			V_mux <= 3'b0;
			
			//Other
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LI17;
		end
		
		S_M1_LI17: begin
			//Writing output
			we_n <= 1'b1;
			
			//Calculations
			RGB_MACODD <= RGB_MACODD + RGBODD_MULTOUT;
			RGB_MACEVEN <= Y_EVENPARTIALPROD - RGBEVEN_MULTOUT;
			U_MAC <= U_MAC + U_MULTOUT; 
			V_MAC <= V_MULTOUT + 32'd128;
			U_mux <= 3'b0;
			V_mux <= 3'b001;
			RGBODD_mux <= 3'b010;
			RGBEVEN_mux <= 3'b011;
			
			//Other
			U_SHIFTREG[0] <= U_SHIFTREG[1];
			U_SHIFTREG[1] <= U_SHIFTREG[2];
			U_SHIFTREG[2] <= U_SHIFTREG[3];
			U_SHIFTREG[3] <= U_SHIFTREG[4];
			U_SHIFTREG[4] <= U_SHIFTREG[5];
			U_SHIFTREG[5] <= U_BUFF[7:0];
			R_OUT[15:8] <= clip_even;
			
			//Addressing increments
			address <= (row_count << 1) + column_count;
			column_count <= column_count + 18'd1;
			
			//Next state stuff
			state <= S_M1_LI18;
		end
		
		S_M1_LI18: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= RGB_MACEVEN - RGBEVEN_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD - RGBODD_MULTOUT;
			U_prime <= U_MAC;
			U_MAC <= U_MULTOUT + 32'd128; 
			V_MAC <= V_MAC - V_MULTOUT;
			U_mux <= 3'b001;
			V_mux <= 3'b010;
			RGBODD_mux <= 3'b011;
			RGBEVEN_mux <= 3'b100;
			
			//Other
			R_OUT[7:0] <= clip_odd;
			
			//Addressing increments
			address <= row_count + column_count + V_OFFSET;
			
			//Next state stuff 
			state <= S_M1_LI19;
		end
		
		S_M1_LI19: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= Y_EVENPARTIALPROD + RGBEVEN_MULTOUT;
			RGB_MACODD <= RGB_MACODD - RGBODD_MULTOUT;
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT; 
			U_mux <= 3'b010;
			V_mux <= 3'b011;
			RGBODD_mux <= 3'b100;
			
			//Other 
			G_OUT[15:8] <= clip_even;
			
			//Addressing increments
			address <= row_count + column_count + U_OFFSET;
			
			//Next state stuff
			state <= S_M1_COMM0;
		end
		
		S_M1_COMM0: begin
			//Writing output
			we_n <= 1'b0;
			write_data[15:8] <= R_OUT[15:8];
			write_data[7:0] <= G_OUT[15:8];
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD + RGBODD_MULTOUT;
			U_mux <= 3'b011;
			V_mux <= 3'b100;
			RGBEVEN_mux <= 3'b0;
			
			//Other 
			G_OUT[7:0] <= clip_odd;
			B_OUT[15:8] <= clip_even;
			Y_BUFF <= read_data;
			
			//Address increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_COMM1;
		end
		
		S_M1_COMM1: begin
			//Writing output
			write_data[15:8] <= B_OUT[15:8];
			write_data[7:0] <= R_OUT[7:0];
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC - V_MULTOUT;
			RGB_MACEVEN <= RGBEVEN_MULTOUT;
			U_mux <= 3'b100;
			V_mux <= 3'b101;
			RGBEVEN_mux <= 3'b001;
			RGBODD_mux <= 3'b0;
			
			//Other
			B_OUT[7:0] <= clip_odd;
			V_BUFF <= read_data;
			
			//Address increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
		
			//Next state stuff
			state <= S_M1_COMM2;
		end
		
		S_M1_COMM2: begin
			//Writing output
			write_data[15:8] <= G_OUT[7:0];
			write_data[7:0] <= B_OUT[7:0];
			
			//Calculations
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= RGBODD_MULTOUT;
			RGB_MACEVEN <= RGB_MACEVEN + RGBEVEN_MULTOUT;
			Y_EVENPARTIALPROD <= RGBEVEN_MULTOUT;
			Y_ODDPARTIALPROD <= RGBODD_MULTOUT;
			U_mux <= 3'b101;
			V_mux <= 3'b0;
			RGBEVEN_mux <= 3'b010;
			RGBODD_mux <= 3'b001;
			
			//Other
			V_SHIFTREG[0] <= V_SHIFTREG[1];
			V_SHIFTREG[1] <= V_SHIFTREG[2];
			V_SHIFTREG[2] <= V_SHIFTREG[3];
			V_SHIFTREG[3] <= V_SHIFTREG[4];
			V_SHIFTREG[4] <= V_SHIFTREG[5];
			if (duplicate_UV == 1'b0) begin
				V_SHIFTREG[5] <= V_BUFF[15:8];
				U_BUFF <= read_data;
			end
			
			//Address increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
		
			//Next state stuff
			state <= S_M1_COMM3;
		end
		
		S_M1_COMM3: begin
			//Writing output 
			we_n <= 1'b1;
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MULTOUT + 32'd128;
			V_prime <= V_MAC;
			RGB_MACODD <= RGB_MACODD + RGBODD_MULTOUT;
			RGB_MACEVEN <= Y_EVENPARTIALPROD - RGBEVEN_MULTOUT;
			U_mux <= 3'b0;
			V_mux <= 3'b001;
			RGBEVEN_mux <= 3'b011;
			RGBODD_mux <= 3'b010;
			
			//Other
			U_SHIFTREG[0] <= U_SHIFTREG[1];
			U_SHIFTREG[1] <= U_SHIFTREG[2];
			U_SHIFTREG[2] <= U_SHIFTREG[3];
			U_SHIFTREG[3] <= U_SHIFTREG[4];
			U_SHIFTREG[4] <= U_SHIFTREG[5];
			if (duplicate_UV == 1'b0) U_SHIFTREG[5] <= U_BUFF[15:8];
			R_OUT[15:8] <= clip_even;
			
			//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
			//Addressing increments							POTENTIAL ADDRESSING PROBLEM..... LOOK TO SEE IF THERE IS ADD 1 OR NOT!!!!!
			address <= ((row_count + column_count - 18'd1) << 1) - 18'd1;
			
			//Next state stuff
			state <= S_M1_COMM4;
		end
		
		S_M1_COMM4: begin
			//Writing output
			
			//Calculations
			U_MAC <= U_MULTOUT + 32'd128;
			U_prime <= U_MAC;
			V_MAC <= V_MAC - V_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD - RGBODD_MULTOUT;
			RGB_MACEVEN <= RGB_MACEVEN - RGBEVEN_MULTOUT;
			U_mux <= 3'b001;
			V_mux <= 3'b010;
			RGBEVEN_mux <= 3'b100;
			RGBODD_mux <= 3'b011;
			
			//Other
			R_OUT[7:0] <= clip_odd;
			
			//Addressing increments
		
			//Next state stuff
			state <= S_M1_COMM5;
		end
		
		S_M1_COMM5: begin
			//Writing output

			//Calculations
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= RGB_MACODD - RGBODD_MULTOUT;
			RGB_MACEVEN <= Y_EVENPARTIALPROD + RGBEVEN_MULTOUT;
			U_mux <= 3'b010;
			V_mux <= 3'b011;
			RGBODD_mux <= 3'b100;
			
			//Other
			G_OUT[15:8] <= clip_even;
			
			//Addressing increments
		
			//Next state stuff
			state <= S_M1_COMM6;
		end
		
		S_M1_COMM6: begin
			//Writing output
			we_n <= 1'b0;
			write_data[15:8] <= R_OUT[15:8];
			write_data[7:0] <= G_OUT[15:8];
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD + RGBODD_MULTOUT;
			U_mux <= 3'b011;
			V_mux <= 3'b100;
			RGBEVEN_mux <= 3'b0;
			
			//Other
			G_OUT[7:0] <= clip_odd;
			B_OUT[15:8] <= clip_even;
			Y_BUFF <= read_data;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
		
			//Next state stuff
			state <= S_M1_COMM7;
		end
		
		S_M1_COMM7: begin
			//Writing output
			write_data[15:8] <= B_OUT[15:8];
			write_data[7:0] <= R_OUT[7:0];
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC - V_MULTOUT;
			RGB_MACEVEN <= RGBEVEN_MULTOUT;
			U_mux <= 3'b100;
			V_mux <= 3'b101;
			RGBODD_mux <= 3'b0;
			RGBEVEN_mux <= 3'b001;
			
			//Other
			B_OUT[7:0] <= clip_odd;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
		
			//Next state stuff
			state <= S_M1_COMM8;
		end
		
		S_M1_COMM8: begin
			//Writing output
			write_data[15:8] <= G_OUT[7:0];
			write_data[7:0] <= B_OUT[7:0];
			
			//Calculations
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACEVEN <= RGB_MACEVEN + RGBEVEN_MULTOUT;
			RGB_MACODD <= RGBODD_MULTOUT;
			Y_EVENPARTIALPROD <= RGBEVEN_MULTOUT;
			Y_ODDPARTIALPROD <= RGBODD_MULTOUT;
			U_mux <= 3'b101;
			V_mux <= 3'b0;
			RGBODD_mux <= 3'b001;
			RGBEVEN_mux <= 3'b010;
			
			//Other
			V_SHIFTREG[0] <= V_SHIFTREG[1];
			V_SHIFTREG[1] <= V_SHIFTREG[2];
			V_SHIFTREG[2] <= V_SHIFTREG[3];
			V_SHIFTREG[3] <= V_SHIFTREG[4];
			V_SHIFTREG[4] <= V_SHIFTREG[5];
			if (duplicate_UV == 1'b0) V_SHIFTREG[5] <= V_BUFF[7:0];
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_COMM9;
		end
		
		S_M1_COMM9: begin
			//Writing output
			we_n <= 1'b1;
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MULTOUT + 32'd128;
			V_prime <= V_MAC;
			RGB_MACEVEN <= Y_EVENPARTIALPROD - RGBEVEN_MULTOUT;
			RGB_MACODD <= RGB_MACODD + RGBODD_MULTOUT;
			U_mux <= 3'b0;
			V_mux <= 3'b001;
			RGBODD_mux <= 3'b010;
			RGBEVEN_mux <= 3'b011;
			
			//Other
			U_SHIFTREG[0] <= U_SHIFTREG[1];
			U_SHIFTREG[1] <= U_SHIFTREG[2];
			U_SHIFTREG[2] <= U_SHIFTREG[3];
			U_SHIFTREG[3] <= U_SHIFTREG[4];
			U_SHIFTREG[4] <= U_SHIFTREG[5];
			if (duplicate_UV == 1'b0) U_SHIFTREG[5] <= U_BUFF[7:0];
			R_OUT[15:8] <= clip_even;
			
			//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
			//Addressing increments							POTENTIAL ADDRESSING PROBLEM..... LOOK TO SEE IF THERE IS ADD 1 OR NOT!!!!!
			address <= (row_count + column_count - 18'd1) << 1;
			column_count <= column_count + 18'd1;
			
			//Next state stuff
			state <= S_M1_COMM10;
		end
		
		S_M1_COMM10: begin
			//Writing output
			
			//Calculations
			U_MAC <= U_MULTOUT + 32'd128;
			V_MAC <= V_MAC - V_MULTOUT;
			U_prime <= U_MAC;
			RGB_MACEVEN <= RGB_MACEVEN - RGBEVEN_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD - RGBODD_MULTOUT;
			U_mux <= 3'b001;
			V_mux <= 3'b010;
			RGBODD_mux <= 3'b011;
			RGBEVEN_mux <= 3'b100;
			
			//Other
			R_OUT[7:0] <= clip_odd;			
			
			//Addressing increments
			address <= row_count + column_count + V_OFFSET;
		
			//Next state stuff
			state <= S_M1_COMM11;
		end
		
		S_M1_COMM11: begin
			//Writing output

			//Calculations
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACEVEN <= Y_EVENPARTIALPROD + RGBEVEN_MULTOUT;
			RGB_MACODD <= RGB_MACODD - RGBODD_MULTOUT;
			U_mux <= 3'b010;
			V_mux <= 3'b011;
			RGBODD_mux <= 3'b100;
			
			//Other
			G_OUT[15:8] <= clip_even;
			
			//Addressing increments
			address <= row_count + column_count + U_OFFSET;
		
			//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@///
			//Next state stuff							//FIGURE OUT WHAT SOMETHING IS TO MAKE IT ENTER THE LEAD OUT STATE!!!!!!!
			if(column_count == 18'd81) begin
				duplicate_UV <= 1'b0;
				state <= S_M1_LO0;
			end else if(column_count == 18'd80) begin
				duplicate_UV <= 1'b1;
				state <= S_M1_COMM0;
			end else begin
				state <= S_M1_COMM0;
			end 
		end
		
		S_M1_LO0: begin
			//Writing output
			we_n <= 1'b0;
			write_data[15:8] <= R_OUT[15:8];
			write_data[7:0] <= G_OUT[15:8];
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD + RGBODD_MULTOUT;
			U_mux <= 3'b011;
			V_mux <= 3'b100;
			RGBEVEN_mux <= 3'b0;
			
			//Other 
			G_OUT[7:0] <= clip_odd;
			B_OUT[15:8] <= clip_even;
			Y_BUFF <= read_data;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO1;
		end
		
		S_M1_LO1: begin
			//Writing output
			write_data[15:8] <= B_OUT[15:8];
			write_data[7:0] <= R_OUT[7:0];
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC - V_MULTOUT;
			RGB_MACEVEN <= RGBEVEN_MULTOUT;
			U_mux <= 3'b100;
			V_mux <= 3'b101;
			RGBEVEN_mux <= 3'b001;
			RGBODD_mux <= 3'b0;
			
			//Other
			B_OUT[7:0] <= clip_odd;
			
			//Address increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO2;
		end
		
		S_M1_LO2: begin
			//Writing output
			write_data[15:8] <= G_OUT[7:0];
			write_data[7:0] <= B_OUT[7:0];
			
			//Calculations
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= RGBODD_MULTOUT;
			RGB_MACEVEN <= RGB_MACEVEN + RGBEVEN_MULTOUT;
			Y_EVENPARTIALPROD <= RGBEVEN_MULTOUT;
			Y_ODDPARTIALPROD <= RGBODD_MULTOUT;
			U_mux <= 3'b101;
			V_mux <= 3'b0;
			RGBEVEN_mux <= 3'b010;
			RGBODD_mux <= 3'b001;
			
			//Other
			V_SHIFTREG[0] <= V_SHIFTREG[1];
			V_SHIFTREG[1] <= V_SHIFTREG[2];
			V_SHIFTREG[2] <= V_SHIFTREG[3];
			V_SHIFTREG[3] <= V_SHIFTREG[4];
			V_SHIFTREG[4] <= V_SHIFTREG[5];
			
			//Address increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO3;
		end
		
		S_M1_LO3: begin
			//Writing output 
			we_n <= 1'b1;
			
			//Calculations
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MULTOUT + 32'd128;
			V_prime <= V_MAC;
			RGB_MACODD <= RGB_MACODD + RGBODD_MULTOUT;
			RGB_MACEVEN <= Y_EVENPARTIALPROD - RGBEVEN_MULTOUT;
			U_mux <= 3'b0;
			V_mux <= 3'b001;
			RGBEVEN_mux <= 3'b011;
			RGBODD_mux <= 3'b010;
			
			//Other
			U_SHIFTREG[0] <= U_SHIFTREG[1];
			U_SHIFTREG[1] <= U_SHIFTREG[2];
			U_SHIFTREG[2] <= U_SHIFTREG[3];
			U_SHIFTREG[3] <= U_SHIFTREG[4];
			U_SHIFTREG[4] <= U_SHIFTREG[5];
			R_OUT[15:8] <= clip_even;
			
			//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@//
			//Addressing increments							POTENTIAL ADDRESSING PROBLEM..... LOOK TO SEE IF THERE IS ADD 1 OR NOT!!!!!
			address <= ((row_count + column_count - 18'd1) << 1) - 18'd1;
		
			//Next state stuff
			state <= S_M1_LO4;
		end
		
		S_M1_LO4: begin
			//Writing output
			
			//Calculations
			U_MAC <= U_MULTOUT + 32'd128;
			U_prime <= U_MAC;
			V_MAC <= V_MAC - V_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD - RGBODD_MULTOUT;
			RGB_MACEVEN <= RGB_MACEVEN - RGBEVEN_MULTOUT;
			U_mux <= 3'b001;
			V_mux <= 3'b010;
			RGBEVEN_mux <= 3'b100;
			RGBODD_mux <= 3'b011;
			
			//Other
			R_OUT[7:0] <= clip_odd;
			
			//Addressing increments
			
			//Next state stuff
			state <= S_M1_LO5;
		end
		
		S_M1_LO5: begin
			//Writing output
			
			//Calculations
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			RGB_MACODD <= RGB_MACODD - RGBODD_MULTOUT;
			RGB_MACEVEN <= Y_EVENPARTIALPROD + RGBEVEN_MULTOUT;
			U_mux <= 3'b010;
			V_mux <= 3'b011;
			RGBODD_mux <= 3'b100;
			
			//Other
			G_OUT[15:8] <= clip_even;
			
			//Addressing increments
		
			//Next state stuff
			state <= S_M1_LO6;
		end
		
		S_M1_LO6: begin
			//Writing output
			we_n <= 1'b0;
			write_data[15:8] <= R_OUT[15:8];
			write_data[7:0] <= G_OUT[15:8];
			
			//Calculations
			RGB_MACODD <= Y_ODDPARTIALPROD + RGBODD_MULTOUT;
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			U_mux <= 3'b011;
			V_mux <= 3'b100;
			RGBEVEN_mux <= 3'b0;
			
			//Other
			G_OUT[7:0] <= clip_odd;
			B_OUT[15:8] <= clip_even;
			Y_BUFF <= read_data;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO7;
		end
		
		S_M1_LO7: begin
			//Writing output
			write_data[15:8] <= B_OUT[15:8];
			write_data[7:0] <= R_OUT[7:0];
			
			//Calculations
			RGB_MACEVEN <= RGBEVEN_MULTOUT;
			U_MAC <= U_MAC + U_MULTOUT;
			V_MAC <= V_MAC - V_MULTOUT;
			U_mux <= 3'b100;
			V_mux <= 3'b101;
			RGBEVEN_mux <= 3'b001;
			RGBODD_mux <= 3'b0;
			
			//Other
			B_OUT[7:0] <= clip_odd;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO8;
		end
		
		S_M1_LO8: begin
			//Writing output
			write_data[15:8] <= G_OUT[7:0];
			write_data[7:0] <= B_OUT[7:0];
			
			//Calculations
			RGB_MACEVEN <= RGB_MACEVEN + RGBEVEN_MULTOUT;
			RGB_MACODD <= RGBODD_MULTOUT;
			Y_EVENPARTIALPROD <= RGBEVEN_MULTOUT;
			Y_ODDPARTIALPROD <= RGBODD_MULTOUT;
			U_MAC <= U_MAC - U_MULTOUT;
			V_MAC <= V_MAC + V_MULTOUT;
			U_mux <= 3'b101;
			V_mux <= 3'b0;
			RGBEVEN_mux <= 3'b010;
			RGBODD_mux <= 3'b001;
			
			//Other
			
			//Addressing output
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO9;
		end
		
		S_M1_LO9: begin
			//Writing output
			we_n <= 1'b1;
			
			//Calculations
			RGB_MACEVEN <= Y_EVENPARTIALPROD - RGBEVEN_MULTOUT;
			RGB_MACODD <= RGB_MACODD + RGBODD_MULTOUT;
			V_prime <= V_MAC;
			U_MAC <= U_MAC + U_MULTOUT;
			U_mux <= 3'b0;
			RGBEVEN_mux <= 3'b101;
			RGBODD_mux <= 3'b010;
			
			//Other
			R_OUT[15:8] <= clip_even; 
			
			//Addressing increments
			
			//Next State stuff
			state <= S_M1_LO10;
		end
		
		S_M1_LO10: begin
			//Writing output 
			
			//Calculations
			RGB_MACEVEN <= RGB_MACEVEN - RGBEVEN_MULTOUT;
			RGB_MACODD <= Y_ODDPARTIALPROD - RGBODD_MULTOUT;
			U_prime <= U_MAC;
			RGBEVEN_mux <= 3'b110;
			RGBODD_mux <= 3'b011;
			
			//Other
			R_OUT[7:0] <= clip_odd;
			
			//Addressing increments
			
			//Next State stuff
			state <= S_M1_LO11;
		end
		
		S_M1_LO11: begin
			//Writing output
			
			//Calculations
			RGB_MACEVEN <= Y_EVENPARTIALPROD + RGBEVEN_MULTOUT;
			RGB_MACODD <= RGB_MACODD - RGBODD_MULTOUT;
			RGBODD_mux <= 3'b100;
			
			//Other
			G_OUT[15:8] <= clip_even;
			
			//Addressing increments
		
			//Next state stuff
			state <= S_M1_LO12;
		end
		
		S_M1_LO12: begin
			//Writing output
			we_n <= 1'b0;
			write_data[15:8] <= R_OUT[15:8];
			write_data[7:0] <= G_OUT[15:8];
			
			//Calculations
			RGB_MACODD <= Y_ODDPARTIALPROD + RGBODD_MULTOUT;
			
			//Output
			G_OUT[7:0] <= clip_odd;
			B_OUT[15:8] <= clip_even;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO13;
		end
		
		S_M1_LO13: begin
			//Writing output
			write_data[15:8] <= B_OUT[15:8];
			write_data[7:0] <= R_OUT[7:0];
			
			//Other
			B_OUT[7:0] <= clip_odd;
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			state <= S_M1_LO14;
		end
		
		S_M1_LO14: begin
			//Writing output
			write_data[15:8] <= G_OUT[7:0];
			write_data[7:0] <= B_OUT[7:0];
			
			//Other
			
			//Addressing increments
			address <= RGB_OFFSET + write_offset;
			write_offset <= write_offset + 18'd1;
			
			//Next state stuff
			if(row_count < 18'd19120) begin
				row_count <= row_count + 18'd80;
				column_count <= 18'd0;
				state <= S_M1_LI0;
			end else begin
				endmilestone1 <= 1'b1;
				state <= S_M1_IDLE;
			end
		end
		
		default: state <= S_M1_IDLE;
		endcase
	end
	
end
endmodule