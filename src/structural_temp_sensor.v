/*Description: Structural top level of
the temperature sensor. Combines modules
'i2c_data', 'temp_converter', and 'lcd_output'
to have a display temperatures onto the 20x4 
LCD in different modes (Celsius, Fahrenheit, Kelvins) 
by interfacing a MCP9808 temperature sensor 
with a FPGA (Altera Cyclone IV rz easyfpga a2.2 
dev board).
*/

module structural_temp_sensor(
input clk,
input reset,
input cmode,
input fmode,
input kmode,
input allmode,
inout sda,
output scl,
output RS,
output RW,
output E,
output [7:0] D);


wire [7:0] upper;
wire [7:0] lower;
wire [11:0] BCD_celsius;
wire [11:0] BCD_fahrenheit;
wire [11:0] BCD_kelvin;
wire [7:0] bcd_tenth_hundreth_c;
wire [7:0] bcd_tenth_hundreth_k;
wire [7:0] bcd_tenth_hundreth_f;
wire [7:0] sign;
wire toggle;

i2c_data i2c_data(
.clk(clk),
.reset(reset),
.scl(scl),
.sda(sda),
.toggle(toggle),
.UPPER(upper),
.LOWER(lower));

temp_converter temp_converter(
.clk(clk),
.reset(reset),
.upper(upper),
.lower(lower),
.toggle(toggle),
.BCD_celsius(BCD_celsius),
.BCD_fahrenheit(BCD_fahrenheit),
.BCD_kelvin(BCD_kelvin),
.bcd_tenth_hundreth_c(bcd_tenth_hundreth_c),
.bcd_tenth_hundreth_f(bcd_tenth_hundreth_f),
.bcd_tenth_hundreth_k(bcd_tenth_hundreth_k),
.sign(sign));

lcd_output lcd_output(
.clk(clk),
.reset(reset),
.cmode(cmode),
.fmode(fmode),
.kmode(kmode),
.allmode(allmode),
.BCD_celsius(BCD_celsius),
.BCD_fahrenheit(BCD_fahrenheit),
.BCD_kelvin(BCD_kelvin),
.bcd_tenth_hundreth_c(bcd_tenth_hundreth_c),
.bcd_tenth_hundreth_f(bcd_tenth_hundreth_f),
.bcd_tenth_hundreth_k(bcd_tenth_hundreth_k),
.sign(sign),
.RS(RS),
.RW(RW),
.E(E),
.D(D));

endmodule 
