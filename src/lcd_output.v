/*Description: Initializes the 20x4 LCD.
Then displays the main menu mode. Depending
on the pushbutton pressed, it can display 
celsius  mode, fahrenheit mode, kelvin mode 
and all mode. Any data send to the R/S line 
of the LCD needs the Enable line of the LCD to
be pulsed at least 40ns low then 230ns
high (240ns was used). Since LCD is only
being used to display, RW will always be
in Write mode, so it is always low. 

Parameters: System Clock: 50 MHZ (20ns)
*/

module lcd_output(
input clk,
input reset,
input cmode,
input fmode,
input kmode,
input allmode,
input [11:0] BCD_celsius,
input [11:0] BCD_fahrenheit,
input [11:0] BCD_kelvin,
input [7:0] bcd_tenth_hundreth_c,
input [7:0] bcd_tenth_hundreth_f,
input [7:0] bcd_tenth_hundreth_k,
input [7:0] sign,
input [3:0] test,
output reg RS,
output reg RW,
output reg E,
output reg [7:0] D,
output reg led);

parameter INITIALIZE0 = 0;	//initialization process: no instruction for 100ms
parameter INITIALIZE1 = 1;	//initialization process: 0x30 for 5.4ms
parameter INITIALIZE2 = 2;	//initialization process: 0x38 for 60us
parameter INITIALIZE3 = 3;	//initialization process: 0x08 for 60us
parameter INITIALIZE4 = 4;	//initialization process: 0x01 for 5ms
parameter INITIALIZE5 = 5;	//initialization process: 0x06 for 60us
parameter INITIALIZE6 = 6;	//initialization process: 0x0C for 60us
parameter DISPLAYFIRSTLINE = 7;	//Display '**SELECT  MODE**'
parameter DISPLAYnextLine = 8;	//Go to next row, instruction 0xC0
parameter DISPLAYSECONDLINE = 9;//Display "  °C  °F  K  ALL"
parameter DISPLAYMODESELECT0 = 10;//Wait for user to press a mode
parameter DISPLAYMODESELECT1 = 11;//Once detected a press, clear screen, instruction 0x01 for 60us
parameter DISPLAYCMODE = 12;	//Mode will display celsius temperature 
parameter DISPLAYFMODE = 13;	//Mode will display fahrenheit temperature
parameter DISPLAYKMODE = 14;	//Mode will display kelvin temperature
parameter DISPLAYALLMODE = 15;	//Mode will display all 3 temperatures
parameter DISPLAYMODELOOP = 16;	//Wait for user to press a different mode

reg [6:0] STATE = INITIALIZE0;
reg [23:0] delay_counter = 24'h000000;
reg [4:0] i; 		//counter for displaying words with different characters
reg [1:0] mode_reg;	//register to tell which display mode system is in
reg [1:0] all_mode_track;//if in all_mode, this register will be used to loop and keep track which temperature displays at a time 

//various delays parameterized
parameter delay_40ns = 2;
parameter delay_280ns = 14;
parameter delay_1us = 50;
parameter delay_60us  = 3000;
parameter delay_200us = 10000;
parameter delay_5ms = 250000;
parameter delay_6004ns = 3002; //600us+40ns
parameter delay_6028ns = 3014; //600+40ns+240ns
parameter delay_20004ns = 10002;//200us+40ns
parameter delay_20028ns = 10014;//200us+40ns+240ns
parameter delay_500004ns = 250002;//5ms+40ns
parameter delay_500028ns = 250014;//5ms+40ns+240ns
parameter delay_500024ns = 250012;//5ms+240ns
parameter delay_520024ns = 260012;//5ms+200us+240ns
parameter delay_520048ns = 260024;//5ms+200us+240ns+240ns
parameter delay_540024ns = 270012;//5ms+200us+200us+240ns
parameter delay_540048ns = 270024;//5ms+200us+200us+40ns+240ns
parameter delay_100ms = 5000000;  
parameter delay_10000004ns = 5000002; //100ms+40ns
parameter delay_10000028ns = 5000014; //100ms+40ns_240ns

//task to display main menu, task is used to keep the instruction's centralized
task d_menu;
	input [4:0] count;
	output [7:0] D;
	begin
	D <=  (count === 5'b00000) ? 8'h2A : //*
		(count === 5'b00001) ? 8'h2A : //*
		(count === 5'b00010) ? 8'h53 : //S
		(count === 5'b00011) ? 8'h45 : //E
		(count === 5'b00100) ? 8'h4C : //L
		(count === 5'b00101) ? 8'h45 : //E
		(count === 5'b00110) ? 8'h43 : //C
		(count === 5'b00111) ? 8'h54 : //T
		(count === 5'b01000) ? 8'hFE : //space
		(count === 5'b01001) ? 8'hFE : //space 
		(count === 5'b01010) ? 8'h4D : //M
		(count === 5'b01011) ? 8'h4F : //O
		(count === 5'b01100) ? 8'h44 : //D
		(count === 5'b01101) ? 8'h45 : //E
		(count === 5'b01110) ? 8'h2A : //*
		(count === 5'b01111) ? 8'h2A : //*
		(count === 5'b10000) ? 8'hFE : //space
		(count === 5'b10001) ? 8'hFE : //space
		(count === 5'b10010) ? 8'hDF : //°
		(count === 5'b10011) ? 8'h43 : //C
		(count === 5'b10100) ? 8'hFE : //space
		(count === 5'b10101) ? 8'hFE : //space
		(count === 5'b10110) ? 8'hDF : //°
		(count === 5'b10111) ? 8'h46 : //F
		(count === 5'b11000) ? 8'hFE : //space
		(count === 5'b11001) ? 8'hFE : //space
		(count === 5'b11010) ? 8'h4B : //K
		(count === 5'b11011) ? 8'hFE : //space
		(count === 5'b11100) ? 8'hFE : //space
		(count === 5'b11101) ? 8'h41 : //A
		(count === 5'b11110) ? 8'h4C : //L
		(count === 5'b11111) ? 8'h4C ://L
		8'hB0;
	end
endtask

//task to display celsius
task d_cmode;
	input [4:0] count;
	output [7:0] D;
	begin
	D <=  (count === 5'b00000) ? sign :
		(count === 5'b00001) ? {4'b0011,BCD_celsius [11:8]} :
		(count === 5'b00010) ? {4'b0011,BCD_celsius [7:4]} : 
		(count === 5'b00011) ? {4'b0011,BCD_celsius [3:0]} : 
		(count === 5'b00100) ? 8'h2E : // .
		(count === 5'b00101) ? {4'b0011,bcd_tenth_hundreth_c [7:4]} :
		(count === 5'b00110) ? {4'b0011,bcd_tenth_hundreth_c [3:0]} : 
		(count === 5'b00111) ? 8'hDF : //°
		(count === 5'b01000) ? 8'h43 : //C
		8'hB0;
	end
endtask
//task to display fahrenheit
task d_fmode;
	input [4:0] count;
	output [7:0] D;
	begin
	D <=  (count === 5'b00000) ? sign :
		(count === 5'b00001) ? {4'b0011,BCD_fahrenheit [11:8]} :
		(count === 5'b00010) ? {4'b0011,BCD_fahrenheit [7:4]} : 
		(count === 5'b00011) ? {4'b0011,BCD_fahrenheit [3:0]} : 
		(count === 5'b00100) ? 8'h2E : // .
		(count === 5'b00101) ? {4'b0011,bcd_tenth_hundreth_f [7:4]} :
		(count === 5'b00110) ? {4'b0011,bcd_tenth_hundreth_f [3:0]} : 
		(count === 5'b00111) ? 8'hDF : //°
		(count === 5'b01000) ? 8'h46 : //F
		8'hB0;
	end
endtask
//task to display kelvin
task d_kmode;
	input [4:0] count;
	output [7:0] D;
	begin
	D <=  (count === 5'b00000) ? 8'hFE :
		(count === 5'b00001) ? {4'b0011,BCD_kelvin [11:8]} :
		(count === 5'b00010) ? {4'b0011,BCD_kelvin [7:4]} : 
		(count === 5'b00011) ? {4'b0011,BCD_kelvin [3:0]} : 
		(count === 5'b00100) ? 8'h2E : // .
		(count === 5'b00101) ? {4'b0011,bcd_tenth_hundreth_k [7:4]} :
		(count === 5'b00110) ? {4'b0011,bcd_tenth_hundreth_k [3:0]} : 
		(count === 5'b00111) ? 8'h4B : //K
		8'hB0;
	end
endtask

always @(posedge clk) begin

if (!reset) begin
		STATE <= INITIALIZE0;//if resetted, start at beginning. i.e. LCD initialization
		RS <= 1'b0;	//set to instruction/command
		RW <= 1'b0;	//set to write, will always write
		//led <= 1'b0;
		delay_counter <= 24'h000000;//reset delay counter
		E <= 1'b0;	
		i <= 0;
		all_mode_track <= 0;
end 
else begin

RW <= 1'b0;	//write mode

case (STATE)
	INITIALIZE0 : begin
		//led <= 1'b0;
		if (delay_counter === delay_100ms) begin //initial 100ms for lcd initialization
			RS <= 1'b0;		//set D here, then pulse E low 40ns, E high 240ns, go to next state once done
			delay_counter <= delay_counter + 24'h000001;
			E <= 1'b0;
			D <= 8'h30;
		end
		else if (delay_counter === delay_10000004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_10000028ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;
			STATE <= INITIALIZE1;
		end
		else
			delay_counter <= delay_counter + 24'h000001;	
	end
	INITIALIZE1 : begin
		if (delay_counter === delay_5ms | delay_counter === delay_520024ns) begin //delay 5ms or 200us+5ms or 200+200us+5ms with instruction 0x30
			E <= 1'b1;							//for each delay, need to pulse E
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_500028ns) begin 
			E <= 1'b0;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_520048ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;
			STATE <= INITIALIZE2;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	INITIALIZE2: begin
		if (delay_counter === delay_200us) begin//send instruction 0x38, pulse E, then go to next state
			D <= 8'h38;			
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_20004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if(delay_counter === delay_20028ns) begin
			E <= 1'b0;
			STATE <= INITIALIZE3;
			delay_counter <= 24'h000000;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	INITIALIZE3: begin	//send instruction 0x08, pulse E, then go to next state
		if (delay_counter === delay_60us) begin
			D <= 8'h08;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if(delay_counter === delay_6028ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;
			STATE <= INITIALIZE4;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	INITIALIZE4: begin		//send instruction 0x01, pulse E, then go to next state
		if (delay_counter === delay_60us) begin
			D <= 8'h01;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if(delay_counter === delay_6028ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;
			STATE <= INITIALIZE5;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	INITIALIZE5 : begin	//send instruction 0x06, pulse E, then go to next state
		if (delay_counter === delay_5ms) begin 
			D <= 8'h06;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_500004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_500028ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;			
			STATE <= INITIALIZE6;
		end
		else 
			delay_counter <= delay_counter + 24'h000001;
	end
	INITIALIZE6: begin	//send instruction 0x0C, pulse E, then go to next state
		if (delay_counter === delay_60us) begin
			D <= 8'h0C;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if(delay_counter === delay_6028ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;
			i <= 5'b00000;
			STATE <= DISPLAYFIRSTLINE;
			RS <= 1'b1;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYFIRSTLINE: begin		//Displays '**SELECT  MODE** on first row of LCD. Uses task d_menu
		if (delay_counter === delay_60us) begin//pulses E after each letter/character, then goes to next state
			RS <= 1'b1;
			d_menu(i,D);
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if(delay_counter === delay_6028ns) begin//pulse E
			E <= 1'b0;
			delay_counter <= 24'h000000;
			i <= i + 5'b00001;
			if (i === 5'b01111) begin
				STATE <= DISPLAYnextLine;
			end
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYnextLine : begin		//goes to next line by sending instruction 0xC0, then pulses E, then go to next state
		if (delay_counter === delay_60us ) begin
			RS <= 1'b0;	
			D <= 8'hC0;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6028ns) begin
			E <= 1'b0;
			STATE <= DISPLAYSECONDLINE;
			delay_counter <= 24'h000000;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYSECONDLINE: begin	//Display "  °C  °F  K  ALL" pulses E after every letter/character, then goes to next state
		if (delay_counter === delay_60us) begin
			RS <= 1'b1;
			d_menu(i,D);
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if(delay_counter === delay_6028ns) begin//pulse E
			E <= 1'b0;
			delay_counter <= 24'h000000;
			i <= i + 5'b00001;
			if (i === 5'b11111) begin
				STATE <= DISPLAYMODESELECT0;
			end
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYMODESELECT0 : begin//waits until user pushes one of the buttons, each button represents a mode
		//led <= 1'b1;		//will store the mode as a register, mode_reg
		if (!cmode) begin
			mode_reg <= 2'b00;
			STATE <= DISPLAYMODESELECT1;
		end
		else if (!fmode) begin
			mode_reg <= 2'b01;
			STATE <= DISPLAYMODESELECT1;
		end
		else if (!kmode) begin
			mode_reg <= 2'b10;
			STATE <= DISPLAYMODESELECT1;
		end
		else if (!allmode) begin
			mode_reg <= 2'b11;
			STATE <= DISPLAYMODESELECT1;
		end
		else
			STATE <= DISPLAYMODESELECT0;
		end
	DISPLAYMODESELECT1 : begin	//Clear's screen after button has been pressed, using instruction 0x01
		if (delay_counter === delay_60us) begin
			RS <= 1'b0;
			D <= 8'h01;
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;				
		end
		else if (delay_counter === delay_6028ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;
			if (mode_reg == 2'b00)
				STATE <= DISPLAYCMODE;
			else if (mode_reg == 2'b01)
				STATE <= DISPLAYFMODE;
			else if (mode_reg == 2'b10)
				STATE <= DISPLAYKMODE;
			else if (mode_reg == 2'b11)
				STATE <= DISPLAYCMODE;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYCMODE : begin		//displays the ambient celsius temperature value. temperature ranges from -25.00C to +100.00C
		if (delay_counter === delay_5ms | delay_counter === delay_500028ns + delay_60us) begin//using task d_cmode, pulses E after every digit/letter
			RS <= 1'b1;
			d_cmode(i,D);
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_500004ns | delay_counter === delay_500028ns + delay_60us + delay_40ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;	
			i <= i + 5'b00001;			
		end
		else if (delay_counter === delay_500028ns | delay_counter === delay_500028ns + delay_60us + delay_40ns + delay_280ns) begin
			E <= 1'b0;
			delay_counter <= delay_500028ns + 24'h000001;
			if (i === 5'b01001) begin
				i <= 5'b00000;
				STATE <= DISPLAYMODELOOP;
				if (mode_reg == 2'b11)
					all_mode_track <= 2'b01;
			end
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYFMODE : begin//displays the ambient fahrenheit temperature value. temperature ranges from -13.00F to +212.00F
		if (delay_counter === delay_5ms | delay_counter === delay_500028ns + delay_60us) begin//using task d_fmode, pulses E after every digit/letter
			RS <= 1'b1;
			d_fmode(i,D);
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_500004ns | delay_counter === delay_500028ns + delay_60us + delay_40ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;	
			i <= i + 5'b00001;			
		end
		else if (delay_counter === delay_500028ns | delay_counter === delay_500028ns + delay_60us + delay_40ns + delay_280ns) begin
			E <= 1'b0;
			delay_counter <= delay_500028ns + 24'h000001;
			if (i === 5'b01001) begin
				i <= 5'b00000;
				STATE <= DISPLAYMODELOOP;
				if (mode_reg == 2'b11)
					all_mode_track <= 2'b10;
			end
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYKMODE : begin	//displays the ambient kelvin temperature value. temperature ranges from -248.15K to +373.15K
		if (delay_counter === delay_5ms | delay_counter === delay_500028ns + delay_60us) begin//using task d_kmode, pulses E after every digit/letter
			RS <= 1'b1;
			d_kmode(i,D);
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_500004ns | delay_counter === delay_500028ns + delay_60us + delay_40ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;	
			i <= i + 5'b00001;			
		end
		else if (delay_counter === delay_500028ns | delay_counter === delay_500028ns + delay_60us + delay_40ns + delay_280ns) begin
			E <= 1'b0;
			delay_counter <= delay_500028ns + 24'h000001;
			if (i === 5'b01000) begin
				i <= 5'b00000;
				STATE <= DISPLAYMODELOOP;
				if (mode_reg == 2'b11)
					all_mode_track <= 2'b00;
			end
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	DISPLAYMODELOOP : begin//If in all_mode, will display all 3 modes
		if (delay_counter === delay_60us) begin//it first needs to set the cursor on the respective rows, 1st row celsius, 2nd row fahrenheit, 3rd row kelvin
			RS <= 1'b0;			//then it pulses E after each address set, then it'll display the temperature value. 
			if (all_mode_track == 2'b00) begin//This is kept track using all_mode_track
				D <= 8'h80;
			end
			else if (all_mode_track == 2'b01) begin
				D <= 8'hC0;
			end
			else if (all_mode_track == 2'b10) begin
				D <= 8'h94;
			end
			delay_counter <= delay_counter + 24'h000001;
		end
		else if (delay_counter === delay_6004ns) begin
			E <= 1'b1;
			delay_counter <= delay_counter + 24'h000001;				
		end
		else if (delay_counter === delay_6028ns) begin
			E <= 1'b0;
			delay_counter <= 24'h000000;
			if (mode_reg === 2'b00)
				STATE <= DISPLAYCMODE;
			else if (mode_reg === 2'b01)
				STATE <= DISPLAYFMODE;
			else if (mode_reg === 2'b10)
				STATE <= DISPLAYKMODE;
			else if (mode_reg === 2'b11) begin
				if (all_mode_track == 2'b00) begin
					STATE <= DISPLAYCMODE;
					all_mode_track <= 2'b01;
				end
				else if (all_mode_track == 2'b01) begin
					STATE <= DISPLAYFMODE;
					all_mode_track <= 2'b10;
				end
				else if (all_mode_track == 2'b10) begin
					STATE <= DISPLAYKMODE;
					all_mode_track <= 2'b00;
				end
			end
			else
				STATE <= DISPLAYMODELOOP;
		end
		else
			delay_counter <= delay_counter + 24'h000001;
	end
	default : ;
endcase
end
end
endmodule

