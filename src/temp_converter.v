/*Description: This module receives the 
raw 12-bit ambient temperature value from
'i2c_data'. Once toggle is set high, the
converted 12-bit ambient temperature will be 
set into respective registers. The raw 12-bit ambient
temperature is converted into binary then into BCD
celsius, fahrenheit and kelvin using Double Dabble. 
The fractional BCD temperature values of celsius, 
fahrenheit and kelvin will be obtained using modulus. 
To get the tenth place of the fractional value, 1 cycle 
of modulus is needed. i.e. the remainder of the 1st 
division operation, multiply by 10, then divide by the 
same divisor used  in the first division operation. To 
get the hundredth place of the fractional value, 2 
cycles of modulus is needed. Then with the BCD values, an 
ASCII value of each digit will be sent out to 'lcd.ouput'.

Parameters: System Clock: 50 MHZ (20ns)

Notes: According to MCP9808, formula to get
raw ambient temperature value into Celsius is:
If temperature >= 0: (UPPER * 16) + (LOWER / 16)
If temperature < 0 : 256 - (UPPER * 16) + (LOWER / 16)
*/
module temp_converter(
input clk,
input reset,
input [7:0] upper,
input [7:0] lower,
input toggle,
output reg [11:0] BCD_celsius,
output reg [11:0] BCD_fahrenheit,
output reg [11:0] BCD_kelvin,
output reg [7:0] bcd_tenth_hundreth_c,
output reg [7:0] bcd_tenth_hundreth_f,
output reg [7:0] bcd_tenth_hundreth_k,
output reg [7:0] sign,
output [3:0] test2);


integer celsius = 0;			//binary celsius value
//reg [7:0] temp_bcd_tenth_hundreth_c = 8'h00;  
reg [11:0] temp_bcd_celsius = 12'h000;	//BCD celsius value (11 MSB, 0 LSB), bits 11-8: hundreds place, bits 7-4: tens place, bits 3-0 ones place
integer bcd_hundreth_c = 0;		//BCD hundredth place of the fractional celsius value
integer bcd_tenth_c = 0;		//BCD tenth place of the fractional celsius value

integer fahrenheit = 0;			//binary fahrenheit value
//reg [7:0] temp_bcd_tenth_hundreth_f = 8'h00;
reg [11:0] temp_bcd_fahrenheit = 12'h000;//BCD fahrenheit value (11 MSB, 0 LSB), bits 11-8: hundreds place, bits 7-4: tens place, bits 3-0 ones place
integer bcd_hundreth_f = 0;		//BCD hundredth place of the fractional fahrenheit value
integer bcd_tenth_f = 0;		//BCD tenth place of the fractional fahrenheit value

integer kelvin = 0;			//binary kelvin value
//reg [7:0] temp_bcd_tenth_hundreth_k = 8'h00;
reg [11:0] temp_bcd_kelvin = 12'h000;	//BCD kelvin value (11 MSB, 0 LSB), bits 11-8: hundreds place, bits 7-4: tens place, bits 3-0 ones place
integer bcd_hundreth_k = 0;		//BCD hundredth place of the fractional kelvin value
integer bcd_tenth_k = 0;		//BCD hundredth place of the fractional kelvin value
integer f_offset = 0;			//variable to check if the fractional fahrenheit values exceed 0.99. If it does, it needs to be added to be accounted for in the integer fahrenheit value. 


integer i = 0;
reg [2:0] STATE = 3'b101;

parameter binary_temps = 0;	//calculates the binary values of celsius, fahrenheit and kelvin
parameter shift = 1;		//Double Dabble portion: shifting the binary bits into the BCD registers
parameter shift_check = 2;	//Double Dabble portion: check if shifting from the binary to BCD is done
parameter add3 = 3;		//Double Dabble portion: to see if the BCD values after the shifting are greater than 5. If they are, add 3 to it, if not, leave values as is. 
//parameter bit_check = 4; not used
parameter fractional_bcd = 5;	//calculates the fractional tenth and hundredth values of celsius, fahrenheit and kelvin in BCD
parameter set = 6;		//checks to see if the new temperature value should be set and outputted by checking toggle. If toggle is high, then set/output new temperature value, if not, then retain the old temperature values. 

//This process will 
always @(posedge clk) begin
case (STATE) 
	fractional_bcd : begin	//Using modulus, the fractional tenth and hundredth values of celsius, fahrenheit and kelvin will be calculated in BCD. 
		bcd_tenth_c <= ((lower % 16) * 10) / 16;	//bcd of tenth place of celsius, 1 cycle of modulus used
		bcd_hundreth_c <= ((((lower % 16) * 10) % 16) * 10) / 16; //bcd of hundreth place of celsius, 2 cycles of modulus used
	
 		//tenth,hundredth for kelvin, since kelvin is 273.15 + celsius, need to mod (lower/16); tenth place only needs 1 cycle of mod, hundredth needs 2 cycle
		if ((((((lower % 16) * 10) % 16) * 10) / 16) + 4'b0101 >= 4'b1010) begin //since you need to add 273.15 to celsius, need to check if the fractional value 
			bcd_hundreth_k <= (((((lower % 16) * 10) % 16) * 10) / 16) - 4'b0101;//hundredth value is going to be greater than 10 AFTER adding the '5' from the .15 of 273.15.
			if ((((lower % 16) * 10) / 16) + 4'b0010 >= 4'b1010) begin	//if it is, then subtract 5, b/c it's hundredth+5-10 = hundredth-5 to get the single digit. then check to see if the kelvin tenth is going to be greater than 
				bcd_tenth_k <= (((lower % 16) * 10) / 16) - 4'b1000;	//10 after adding 2 (plus 1 from the .15 and another plus 1 coming from the hundredth place),
			end								//subtract 8 if it is, b/c its tenth+1+1-10 = tenth-8 to get the single digit.
			else begin							//If kelvin tenth is not greater than 10 after adding 2, then just add 2. 
				bcd_tenth_k <= (((lower % 16) * 10) / 16) + 4'b0010;
			end
		end
		else if ((((((lower % 16) * 10) % 16) * 10) / 16) + 4'b0101 < 4'b1010) begin //if the kelvin hundredth place is NOT greater than 10
			bcd_hundreth_k[3:0] <= (((((lower % 16) * 10) % 16) * 10) / 16) + 4'b0101;//then, just add 5 from the .15
			if((((lower % 16) * 10) / 16) + 4'b0001 >= 4'b1010) begin	//if the kelvin tenth value is greater than 10
				bcd_tenth_k <= (((lower % 16) * 10) / 16) - 4'b1001;	//then subtract 9 to get the single digit
			end
			else begin							//if the kelvin tenth value is less than 10
				bcd_tenth_k <= (((lower % 16) * 10) / 16) + 4'b0001;	//just add 1
			end
		end
		//tenth for fahrenheit, since fahrenheit is (((celsius)(9))/5) + 32, need 1 cycle of mod of value ((((upper*16) + (lower/16))(9))/5)
		if (((((upper * 144) % 5) * 10) / 5) + ((((lower * 9) % 80) * 10) / 80) >= 4'b1010) begin //if the tenth value is greater than 10
			bcd_tenth_f <= ((((upper * 144) % 5) * 10) / 5) + ((((lower * 9) % 80) * 10) / 80) - 4'b1010;//subtract ten to get the single digit
		end
		else if (((((upper * 144) % 5) * 10) / 5) + ((((lower * 9) % 80) * 10) / 80) < 4'b1010) begin
			bcd_tenth_f <= ((((upper * 144) % 5) * 10) / 5) + ((((lower * 9) % 80) * 10) / 80);
		end
		//tenth for fahrenheit, since fahrenheit is (((celsius)(9))/5) + 32, need 2 cycle of mod of value ((((upper*16) + (lower/16))(9))/5)
		if (((((((upper * 144) % 5) * 10) % 5) * 10) / 5) + ((((((lower * 9) % 80) * 10) % 80) * 10) / 80) >= 4'b1010) begin//if the hundredth value is greater than 10
			bcd_hundreth_f <= ((((((upper * 144) % 5) * 10) % 5) * 10) / 5) + ((((((lower * 9) % 80) * 10) % 80) * 10) / 80) - 4'b1010;//subtract ten to get the single digit
		end
		else if (((((((upper * 144) % 5) * 10) % 5) * 10) / 5) + ((((((lower * 9) % 80) * 10) % 80) * 10) / 80) < 4'b1010) begin
			bcd_hundreth_f <= ((((((upper * 144) % 5) * 10) % 5) * 10) / 5) + ((((((lower * 9) % 80) * 10) % 80) * 10) / 80);
		end
		//f_offset is if the fractional fahrenheit value becomes greater than 1, the value needs to be stored and added into, i.e. (celsius*9)+f_offset
		if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h11)
			f_offset <= 0;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h22)
			f_offset <= 1;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h33)
			f_offset <= 2;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h44)
			f_offset <= 3;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h55)
			f_offset <= 4;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h66)
			f_offset <= 5;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h77)
			f_offset <= 6;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h88)
			f_offset <= 7;
		else if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} <= 8'h99)
			f_offset <= 8;
		STATE <= binary_temps;
	end
	binary_temps : begin//calculating the integer temperature values
		temp_bcd_celsius <= 12'h000; //reset value, want to hold the previous value until conversion is completely done
		temp_bcd_fahrenheit <= 12'h000;
		temp_bcd_kelvin <= 12'h000;
	
		if (upper[4] == 1'b0) begin//based on MCP9808, if the upper's bit 4 = 0, then the temperature is greater than or equal to 0.
			celsius <= (upper * 16) + (lower / 16);
			fahrenheit <= ((((((upper * 16) + (lower / 16))) * 9) + f_offset) / 5) + 32;//the f_offset is added after celsius*9 and before it's divided by 5
			if ({bcd_tenth_c[3:0],bcd_hundreth_c[3:0]} >= 8'h85)//if the fractional value of celsius + 15 from the 273.15 to get kelvin is greater than 85, then it's a +1 to the integer kelvin value
				kelvin <= ((upper * 16) + (lower / 16)) + 274;
			else
				kelvin <= ((upper * 16) + (lower / 16)) + 273;
			sign <= 8'hFE;	//'+' symbol in ascii
		end
		else begin//if the upper's bit 4 = 1, then the temperature is less than 0, i.e. negative temperature.
			celsius <= (256 - (((upper * 8'h0F) * 16) + (lower / 16)));
			fahrenheit <= (((((256 - (((upper* 8'h0F) * 16) + (lower / 16)))) * 9) + f_offset) / 5) - 32;//the f_offset is added after celsius*9 and before it's divided by 5
			sign <= 8'h2D;	//'-' symbol in ascii
			if (bcd_tenth_c >= 4'h1 && bcd_hundreth_c > 4'h5)//if the fractional value of celsius + 15 from the 273.15 to get kelvin is greater than 85, then it's a +1 to the integer kelvin value
				kelvin <= 272 - (256 - (((upper* 8'h0F) * 16) + (lower / 16)));
			else
				kelvin <= 273 - (256 - (((upper* 8'h0F) * 16) + (lower / 16)));
		end
		STATE <= shift;
	end
	shift : begin //shifting all binary temperature value, starting from MSB then descend down to the last bit into BCD registers
		if (i <= 7) begin//celsius and fahrenheit will only be 8 bits since the max MCP9808 reads is 100C or 212F, which is less than 255
			temp_bcd_celsius <= temp_bcd_celsius << 1;
			temp_bcd_celsius[0] <= celsius[7-i];
			temp_bcd_fahrenheit <= temp_bcd_fahrenheit << 1;
			temp_bcd_fahrenheit[0] <= fahrenheit[7-i];
		end//Kelvin's max from 100C is 373.15 which exceeds 8 bits binary, so does the shift 8 times
		temp_bcd_kelvin <= temp_bcd_kelvin << 1;
		temp_bcd_kelvin[0] <= kelvin[8-i];
		STATE <= shift_check;
	end
	shift_check : begin//check if shifting is done or not
		if (i <= 8) begin
			STATE <= add3;
			i <= i + 1;
		end
		else begin//if done, then go to set
			STATE <= set;
			i <= 0;
		end
	end
	add3 : begin //part of double dabble: after shifting, check if each BCD digit is greater than 5
		if (i <= 7) begin//if it is, then add 3 to that BCD digit. only do celsius and fahrenheit 8 times
			if (temp_bcd_celsius[3:0] > 4) begin //celsius 100s,10s,1s
				temp_bcd_celsius[3:0] <= temp_bcd_celsius[3:0] + 4'h3;
			end
			if (temp_bcd_celsius[7:4] > 4) begin
				temp_bcd_celsius[7:4] <= temp_bcd_celsius[7:4] + 4'h3; 
			end
			if (temp_bcd_celsius[11:8] > 4) begin
				temp_bcd_celsius[11:8] <= temp_bcd_celsius[11:8] + 4'h3; 
			end
			if (temp_bcd_fahrenheit[3:0] > 4) begin //fahrenheit 100s,10s,1s
				temp_bcd_fahrenheit[3:0] <= temp_bcd_fahrenheit[3:0] + 4'h3;
			end
			if (temp_bcd_fahrenheit[7:4] > 4) begin
				temp_bcd_fahrenheit[7:4] <= temp_bcd_fahrenheit[7:4] + 4'h3;
			end
			if (temp_bcd_fahrenheit[11:8] > 4) begin
				temp_bcd_fahrenheit[11:8] <= temp_bcd_fahrenheit[11:8] + 4'h3;
			end
		end//do the add 3, 9 times 
		if (temp_bcd_kelvin[3:0] > 4) begin //kelvin 100s,10s,1s
			temp_bcd_kelvin[3:0] <= temp_bcd_kelvin[3:0] + 4'h3;
		end
		if (temp_bcd_kelvin[7:4] > 4) begin
			temp_bcd_kelvin[7:4] <= temp_bcd_kelvin[7:4] + 4'h3;
		end
		if (temp_bcd_kelvin[11:8] > 4) begin
			temp_bcd_kelvin[11:8] <= temp_bcd_kelvin[11:8] + 4'h3;
		end
		STATE <= shift;
	end
	set : begin//will wait for i2c_data to obtain the temperature values
		if (toggle == 1'b1) begin//set the new temperature values or skip and keep the old temrpature values
			bcd_tenth_hundreth_c [7:4] <= bcd_tenth_c;
			bcd_tenth_hundreth_c [3:0] <= bcd_hundreth_c;
			bcd_tenth_hundreth_f [7:4] <= bcd_tenth_f;
			bcd_tenth_hundreth_f [3:0] <= bcd_hundreth_f;
			bcd_tenth_hundreth_k [7:4] <= bcd_tenth_k;
			bcd_tenth_hundreth_k [3:0] <= bcd_hundreth_k;
	
			BCD_celsius <= temp_bcd_celsius;
			BCD_fahrenheit <= temp_bcd_fahrenheit;
			BCD_kelvin <= temp_bcd_kelvin;
		end
		STATE <= fractional_bcd;
	end
endcase
//end
end

endmodule 
