/*Description: FPGA as the I2C master interfacing 
with slave MCP9808. The resolution will first be 
set to +0.0625°C and the 12 bit ambient temperature
will be read. 

Parameters: MPC9808 slave address: 00110010 (write), 00110011(read)
            System Clock: 50 MHZ (20ns)
            SCL: 400KHz (1.3us low, 1.2us high)
*/
module i2c_data(
input clk,	//System clock
input reset,	//reset
output scl,	//SCL, the serial clock for the I2C
inout sda,	//Serial data line, it is inout b/c it will be tri-stated. It will be high impedance when FPGA master is receiving data
output [7:0] UPPER, //UPPER ambient byte, only lower 4 bits are used towards the ambient temperature
output [7:0] LOWER, //LOWER ambient byte
output reg toggle); //Will let the temp_converter module when to convert or not. low: no conversion, wait mode, high: covert mode

reg r_scl = 1'b1;
reg r_sda = 1'b1;
reg [11:0] scl_delay = 12'h000;		//counter to generate the SCL
reg [11:0] delay_counter = 12'h000;	//counter that will let FPGA know when to go next state
reg [7:0] slave_ADDR_W = 8'b00110010;	
reg [7:0] slave_ADDR_R = 8'b00110011;
reg [7:0] TA_pointer = 8'b00000101;	//temperature ambient pointer address
reg [7:0] res_pointer = 8'b00001000;	//resolution pointer address
reg [7:0] res_data = 8'b00000011;	//byte to set resolution to +0.0625°C
reg [2:0] i = 3'b111;			//i is used for bit position of a byte
reg [3:0] state_ctr = 4'b0000;		//ambient temperature counter when in the ambient temperature portion
reg [3:0] res_ctr = 4'b0000;		//resolution counter when in the resolution portion
reg [4:0] STATE = 5'b00000;		//register to use to go from state to state 
reg [7:0] r_upper = 8'h00;
reg [7:0] r_lower = 8'h00;
reg [23:0] delay65ms_counter = 24'h000000; //a separate counter to use for the 65ms 

parameter START = 0;			//Waits 1.2us, then depending on previous state, will go into SLAVE_ADDRESS_TRANSFER or DATA_TRANSFER_2
parameter SLAVEADDRESS_TRANSFER = 1;	//Transfer the MCP9808 slave address 00110010 (WRITE)
parameter RESOLUTION_delay700ns = 2;	//700ns delay portion to be used in the resolution portion of the process
parameter RESOLUTION_slave_ack0 = 3;	//1st part of FPGA master ACK'ing MCP9808 slave in the resolution portion
parameter RESOLUTION_slave_ack1 = 4;	//2nd part of FPGA master ACK'ing MCP9808 slave in the resolution portion
parameter RESOLUTION_DATA_TRANSFER1 = 5;//Transfers resolution pointer to MCP9808 slave
parameter RESOLUTION_DATA_TRANSFER2 = 6;//Transfers the resolution data to MCP9808 so that ambient temperature can be 0.0625C
parameter DATA_TRANSFER0 = 7;		//Unused State
parameter delay700ns = 8;		//Ambient temperature's 700ns delay
parameter slave_ack0 = 9;		//1st part of FPGA master ACK'ing MCP9808 slave in the ambient temp portion
parameter slave_ack1 = 19;		//2nd part of FPGA master ACK'ing MCP9808 slave in the ambient temp portion
parameter DATA_TRANSFER1 = 11;		//Transfers ambient temperature pointer to the MCP9808
parameter DATA_TRANSFER2 = 12;		//Transfers the MCP9808 slave address 00110011 (READ) 
parameter UPPER_TRANSFER = 13;		//FPGA Master receives the UPPER byte of the ambient temperature
parameter LOWER_TRANSFER = 14;		//FPGA Master receives the LOWER byte of the ambient temperature
parameter STOP1 = 15;			//1st part of STOP I2C communications
parameter STOP2 = 16;			//2nd parto f STOP I2C communications
parameter temp = 18;			//Unused State
parameter master_ack0 = 17;		//1st part of FPGA Master sending ACK to MCP9808 slave
parameter master_ack1 = 21;		//2nd part of FPGA Master sending ACK to MCP9808 slave
parameter delay65ms = 22;		//delay 65ms before starting a new transmission so that the MCP9808 will have enough time to convert


//This process sets up the SCL 400KHz (2.5us) using the system clock.
//1.3us of the SCL will be low, 1.2us of the SCL will be high. 
always @(posedge clk) begin 
if (STATE === START | STATE === STOP2 | STATE === delay65ms) begin 
	scl_delay <= 12'h000; //reset SCL counter (scl_delay) and set SCL high		
	r_scl <= 1'b1;	      //the needs SCL to be high at least 1.2us because the setup start
end			      //time needs SCL to be high for 600ns and the hold start time needs SCL to be high for 600ns. 
else begin
if (scl_delay === 59) begin  
	r_scl <= 1'b0; //set SCL to be low after 1.2us
	scl_delay <= scl_delay + 1'b1;
end
else if (scl_delay === 124) begin 
	r_scl <= 1'b1; //set SCL to be high after 1.3us
	scl_delay <= 12'h000;
end
else
	scl_delay <= scl_delay + 1'b1; //keep incrementing if the specified time has not been reached
end
end

//This process will first set up the resolution of the temperature that will be received.
//Then it will receive the ambient temperature.  
//Order of events: 
//( 1 )Resolution: Wait 1.2us (START) -> Send the addr of the MCP9808 slave -> ACK -> Send resolution pointer 
//     -> ACK -> Send 0.25C resolution data -> ACK -> STOP
//( 2 )Ambient Temperature: Wait 1.2us (START) -> Send the addr of MCP9808 slave -> ACK -> Send ambient temp pointer 
//     -> ACK -> START -> Ambient temp pointer -> ACK -> Receive UPPER temp byte -> ACK -> Receive LOWER temp byte 
//     -> NACK -> STOP -> repeat Ambient temperature
always @(posedge clk) begin
case (STATE)
	START : begin 					//START state
		toggle <= 1'b0;				//set toggle low so that conversion doesn't happen
		if (r_scl === 1'b1) begin 		//if SCL been high for 1.2us (setup 600ns, hold 600ns)
			if (delay_counter === 59) begin	//then set SDA line low and reset delay counter
				r_sda <= 1'b0;
				delay_counter <= 12'h000;				
				if (state_ctr === 4'b0011) begin //If state_ctr is coming out of 0011
					STATE <= DATA_TRANSFER2; //then, go into DATA_TRANSFER2, all 
					state_ctr <= 4'b0100;	 //other cases go into slave addr
				end
				else
					STATE <= SLAVEADDRESS_TRANSFER; 
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
	end
	SLAVEADDRESS_TRANSFER : begin			//Transfer the MCP9808 slave addr on SDA line
		if (r_scl === 1'b0) begin		//Data-in setup time at least 100ns, Data-out hold time at least 200ns but less than 900ns
			if (delay_counter === 34) begin //700ns delay was used
				if (i === 3'b000) begin 				//if transfer is on the last bit of the byte
					delay_counter <= delay_counter + 12'h001;	//increment delay counter
					i <= 3'b111;					//reset i
					r_sda <= slave_ADDR_W[i];			//transfer LSB bit of the byte
					state_ctr <= 4'b0000;				//reset state_ctr
					if (res_ctr === 4'b0000)			//if in resolution portion, needs to resolution delay 700ns state
						STATE <= RESOLUTION_delay700ns;
					else						//if in ambient temp portion, needs to go to ambient temp delay 700ns state
						STATE <= delay700ns;
				end
				else begin
					delay_counter <= delay_counter + 12'h001;	
					i <= i - 3'b001;				//transfer bits 7-1, but stay within this SLAVE_ADDRESS_TRANSFER state
					r_sda <= slave_ADDR_W[i];
				end
			end
			else							
				delay_counter <= delay_counter + 12'h001;	//keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000;	//keep incrementing if the specified time has not been reached
	end
	RESOLUTION_delay700ns : begin			//This state will delay 700ns, but will only be used for the resolution portion.
		if (r_scl === 1'b0) begin		//There is a separate delay 700ns that's used for the ambient temperature. This was done to keep the 2 portions separate but kept in the same process. 
			if (delay_counter === 34) begin		//If, SCL has been low for 700ns
				if (res_ctr === 4'b0010) begin	//then make STATE go into RESOLUTION_slave_ack0
					STATE <= RESOLUTION_slave_ack0;
				end
				else
					STATE <= RESOLUTION_slave_ack0;
			end
			else
				delay_counter <= delay_counter + 12'h001;//keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000; //reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
	RESOLUTION_slave_ack0 : begin		//1st part is just to wait for when SCL becomes high
		if (r_scl === 1'b1) begin
			delay_counter <= 12'h000;//reset delay counter
			STATE <= RESOLUTION_slave_ack1;//go to 2nd part of FPGA Master ACK'ing from the slave the resolution pointer and data
		end
	end
	RESOLUTION_slave_ack1 : begin		//2nd part of FPGA master ACK'ing
		if (r_scl === 1'b0) begin	//wait until SCL is low, then, if 100ns (data_in setup) has passed
			if (delay_counter === 5) begin	// go into respective STATES depending on res_ctr
				delay_counter <= 12'h000;
				if (res_ctr === 4'b0000) begin	
					STATE <= RESOLUTION_DATA_TRANSFER1;
				end
				else if(res_ctr === 4'b0001) begin
					STATE <= RESOLUTION_DATA_TRANSFER2;
				end
				else if (res_ctr === 4'b0010) begin
					STATE <= STOP1;
				end
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
	end
	RESOLUTION_DATA_TRANSFER1 : begin //Transfer resolution pointer 00001000
		if (r_scl === 1'b0) begin		
			if (delay_counter === 34) begin //Wait 700ns when SCL is low
				if (i === 3'b000) begin //If on the last bit of byte, transfer last bit of byte, reset i and go back to RESOLUTION_delay700ns
					delay_counter <= delay_counter + 12'h001;
					i <= 3'b111;
					r_sda <= res_pointer[i];
					res_ctr <= 4'b0001;
					STATE <= RESOLUTION_delay700ns;
				end
				else begin
					delay_counter <= delay_counter + 12'h001;
					i <= i - 3'b001;
					r_sda <= res_pointer[i];
				end
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000;//reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
	RESOLUTION_DATA_TRANSFER2 : begin	//Transfer 00000011 to MCP9808 so that the ambient temperature's resolution can be 0.0625C
		if (r_scl === 1'b0) begin
			if (delay_counter === 34) begin //Wait 700ns delay when SCL is low, then transfer 00000011
				if (i === 3'b000) begin //If on the last bit of byte, reset i, and then go into RESOLUTION_delay700ns state
					delay_counter <= delay_counter + 12'h001;
					i <= 3'b111;
					r_sda <= res_data[i];
					res_ctr <= 4'b0010;
					STATE <= RESOLUTION_delay700ns;
				end
				else begin		//transfer bits 7-1, but stay within this SLAVE_ADDRESS_TRANSFER state
					delay_counter <= delay_counter + 12'h001;
					i <= i - 3'b001;
					r_sda <= res_data[i];
				end
			end
			else
				delay_counter <= delay_counter + 12'h001;//keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000; //reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low.
	end
	delay700ns : begin				//This state will delay 700ns, but will only be used for the ambient temp portion.
		if (r_scl === 1'b0) begin		//There is a separate delay 700ns that's used for the resolution portion. This was done to keep the 2 portions separate but kept in the same process.
			if (delay_counter === 34) begin //If SCL is low for 700ns, then go into the respective states depending on state_ctr
				if (state_ctr === 4'b0010) begin
					STATE <= STOP1; 
					delay_counter <= 12'h000;
					state_ctr <= 4'b0011;
				end
				else if (state_ctr === 4'b0111) begin
					delay_counter <= 12'h000;
					r_sda <= 1'b1;	//set high to send NACK from master to slave
					STATE <= master_ack0;
				end
				else if (state_ctr === 4'b0110) begin
					delay_counter <= 12'h000;
					STATE <= master_ack0;
					r_sda <= 1'b0;	//set low to send ACK from master to slave
				end
				else
					STATE <= slave_ack0;
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000; //reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
	slave_ack0 : begin			//First portion of FPGA Master ACK'ing from MCP9808 in the ambient temp portion
		if (r_scl === 1'b1) begin	//Wait until SCL is high
			delay_counter <= 12'h000;//then reset delay counter and go into the 2nd part
			STATE <= slave_ack1;
		end
	end
	slave_ack1 : begin			//Second portion of FPGA Master ACK'ing from MCP9808 in the ambient temp portion
		if (r_scl === 1'b0) begin	//Wait until SCL is low for 100 ns (data-in set up time)
			if (delay_counter === 5) begin	//then go into respective states depending on state_ctr
					delay_counter <= 12'h000;
					if (state_ctr === 4'b0000)
						STATE <= DATA_TRANSFER1;
					else if(state_ctr === 4'b0001) begin
						STATE <= STOP1;
						state_ctr <= 4'b0010;
						r_sda <= 1'b0;
					end
					else if (state_ctr === 4'b0101) begin
						toggle <= 1'b0;		//Before receiving the first BYTE of the ambient temperature
						STATE <= UPPER_TRANSFER; //turn of conversion by setting toggle low. 
					end
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
	end
	master_ack0 : begin			//First portion of FPGA Master sending ACK to MCP9808 slave.
		if (r_scl === 1'b1) begin	//Wait for SCL to go high
			delay_counter <= 12'h000;//then reset delay counter and then go to 2nd part of master ACK
			STATE <= master_ack1;
		end
	end
	master_ack1 : begin
		if (r_scl === 1'b0) begin	//Second portion of FPGA Master sending ACK to MCP9808 slave.
			if (delay_counter === 5) begin //Wait SCL to be low for 100ns (data_in setup), then proceed into respective states
				if (state_ctr === 4'b0110) begin //depending on state_ctr
					delay_counter <= 12'h000;
					r_sda <= 1'b1;	//set SDA high, so that it will be high impedance, so that it can receive the LOWER byte
					STATE <= LOWER_TRANSFER;
					state_ctr <= 4'b0111;
				end
				else if (state_ctr === 4'b0111) begin
					delay_counter <= 12'h000;
					r_sda <= 1'b0; //set SDA low to initiate the STOP
					STATE <= STOP1;
					state_ctr <= 4'b1000;
					toggle <= 1'b1;		//Since both temperature bytes have been received, toggle is set high so that conversion can happen
				end
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000;//reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
	STOP1 : begin				//First part of STOP of I2C transmission
		if (r_scl === 1'b1) begin	//Wait for SCL to be high, then go into respective state depending on state_ctr
			delay_counter <= 12'h000; //reset delay counter
			if (state_ctr === 4'b0010) begin //This portion is if the state machine sent out ambient temperature pointer.
				state_ctr <= 4'b0011;
				r_sda <= 1'b1;		
				STATE <= STOP2;
			end
			else begin		//This portion is if the state machine is at the end of resolution portion or at the end of ambient temp.
				r_sda <= 1'b0;
				STATE <= STOP2;
			end
		end
	end
	STOP2 : begin				//Second part of STOP of I2C transmission
		if (r_scl === 1'b1) begin	//Wait 680ns (setup stop) for SCL to be high
			if (delay_counter === 33) begin
				r_sda <= 1'b1;	//set SDA high
				delay_counter <= delay_counter + 12'h001;
				if (state_ctr === 4'b1000) begin //This is if STATE is at the end of the ambient temp portion.
					STATE <= delay65ms;	 //And needs to delay the 65ms so that there'll be enough time
					delay_counter <= 12'h000;//for conversion to happen
				end
			end
			else if (delay_counter === 98) begin //Wait 1.3us (bus free) for SCL to be high
				if (state_ctr === 4'b1000) begin //then go into respective STATE depending on state_ctr
					STATE <= START;
					delay_counter <= 12'h000;
					state_ctr <= 4'b0011;
				end
				else if (state_ctr === 4'b0011) begin
					STATE <= START;
					delay_counter <= 12'h000;
				end
				else if (state_ctr === 4'b0000) begin
					STATE <= START;
					delay_counter <= 12'h000;
				end
				else begin
					STATE <= START;
					delay_counter <= 12'h000;
					state_ctr <= 4'b0011;
				end
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
	end
	delay65ms : begin					//Delays 65ms using the sepaarate counter, delay65ms_counter
		if (delay65ms_counter === 3250000/*59*/) begin	//Once done, return back to STOP2
			STATE <= STOP2;
			delay_counter <= 34;
			delay65ms_counter <= 24'h000000;
		end
		else
			delay65ms_counter <= delay65ms_counter + 24'h000001;//keep incrementing if the specified time has not been reached

	end
	DATA_TRANSFER1 : begin				//Transfer Ambient temperature pointer to MCP9808 slave
		if (r_scl === 1'b0) begin		//Wait 700ns for SCL to be low, then transfer 00000101 from MSB to LSB
			if (delay_counter === 34) begin 
				if (i === 3'b000) begin //if on last bit, transfer last bit, reset delay counter and go to delay_700ns state
					delay_counter <= delay_counter + 12'h001;
					i <= 3'b111;
					r_sda <= TA_pointer[i];
					state_ctr <= 4'b0001;
					STATE <= delay700ns;
				end
				else begin 	//transfer bits 7-1, but stay within this DATA_TRANSFER1 state
					delay_counter <= delay_counter + 12'h001;
					i <= i - 3'b001;
					r_sda <= TA_pointer[i];
				end
			end
			else
				delay_counter <= delay_counter + 12'h001; //keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000; //reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
	DATA_TRANSFER2 : begin			//Transfer slave address with READ bit, 00110011 to MCP9808 slave
		if (r_scl === 1'b0) begin	//Wait 700ns for SCL to be low, then transfer 00000101 from MSB to LS
			if (delay_counter === 34) begin //if on last bit, transfer last bit, reset delay counter and go to delay_700ns state
				if (i === 3'b000) begin
					delay_counter <= delay_counter + 12'h001;
					i <= 3'b111;
					r_sda <= slave_ADDR_R[i];
					state_ctr <= 4'b0101;
					STATE <= delay700ns;
				end
				else begin	//transfer bits 7-1, but stay within this DATA_TRANSFER2 state
					delay_counter <= delay_counter + 12'h001;
					i <= i - 3'b001;
					r_sda <= slave_ADDR_R[i];
				end
			end
			else
				delay_counter <= delay_counter + 12'h001;//keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000; //reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
	UPPER_TRANSFER: begin			//Receive UPPER temperatuer byte from MCP9808 slave
		if (r_scl === 1'b0) begin	//Wait 700ns for SCL to be low, then read UPPER byte from MSB to LSB
			if (delay_counter === 34) begin //The 4 MSBs are set to 0 as they are indicators for other features of the sensor, and the 4 LSBs are read
				if (i === 3'b000) begin	//if on last bit, read last bit, reset delay counter and go to delay_700ns state
					delay_counter <= delay_counter + 12'h001;
					i <= 3'b111;
					r_upper[i] <= sda;
					STATE <= delay700ns;
					r_upper[7] <= 1'b0;
					r_upper[6] <= 1'b0;
					r_upper[5] <= 1'b0;
					r_upper[4] <= 1'b0;
				end
				else begin		//read bits 7-1, but stay within this UPPER_TRANSFER state
					delay_counter <= delay_counter + 12'h001;
					i <= i - 3'b001;
					r_upper[i] <= sda;
					state_ctr <= 4'b0110;
				end
			end
			else
				delay_counter <= delay_counter + 12'h001;//keep incrementing if the specified time has not been reached
		end
		else				
			delay_counter <= 12'h000;//reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
	LOWER_TRANSFER: begin			//Receive LOWER temperatuer byte from MCP9808 slave
		if (r_scl === 1'b0) begin	//Wait 700ns for SCL to be low, then read LOWER byte from MSB to LSB
			if (delay_counter === 34) begin 
				if (i === 3'b000) begin	//if on last bit, read last bit, reset delay counter and go to delay_700ns state
					delay_counter <= delay_counter + 12'h001;
					i <= 3'b111;
					r_lower[i] <= sda;
					STATE <= delay700ns;
				end
				else begin
					delay_counter <= delay_counter + 12'h001;
					i <= i - 3'b001;
					r_lower[i] <= sda;
					state_ctr <= 4'b0111;
				end
			end
			else
				delay_counter <= delay_counter + 12'h001;//keep incrementing if the specified time has not been reached
		end
		else
			delay_counter <= 12'h000;//reset the delay counter if SCL becomes high. This is done to ensure that 700ns will be counted when SCL is low. 
	end
endcase
//end
end

assign scl = (r_scl) ? 1'bZ : r_scl;
assign sda =(r_sda | STATE === slave_ack0 | STATE === slave_ack1 | STATE === RESOLUTION_slave_ack0 | STATE === RESOLUTION_slave_ack1) ? 1'bZ : r_sda; //tri-state buffer, if r_sda is high OR in any STATE where the slave is sending an ACK, FPGA to set SDA to be high impedance.
assign UPPER = r_upper;
assign LOWER = r_lower;
//assign sda=(sda_int)?1'bZ:sda_int;
endmodule

