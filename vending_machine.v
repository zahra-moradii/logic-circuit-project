module vending_machine
(
	clk, rst, charge, coin, dispense, withdraw, done, deliver, payback, mode, select, price, count
);


	input wire clk, rst, charge, coin, dispense, withdraw;
	input wire [1:0] mode;		
	input wire [4:0] select;	// one-hot code select a product
	input wire done; 			//feedback mechanism to payback or delivery command
	output payback;				//singal to coin payback mechanism
	output deliver;				//command to drink delivery mechanism

	output wire [3:0] price, count;	//outputs to 7-Segment -- input to dispenser 

	//reg [3:0] prices[0:4];
	
	wire payb1;			//  coin is paidback to  supervisor
	wire payb2;			//  coin is paidbacked to customer
	wire dec = payb2; 	//  signal to decrement from total balance
	
	wire payback = payb1 | payb2;  // signal to system to payback a coin to customer or withdraw by supervisor
	
	wire discharge; // = !(mode[0] | mode[1]) ; // = deliver;  // selected drink is delivered so its count must be decremented
	MUX2x1b muxx(deliver, 1'b0, mode[0]& mode[1], discharge);
	
	
	unit_money_withdraw umw(clk, rst, withdraw, coin, dec, done, payb1);	
	unit_charge_product ucp(clk, mode, charge, discharge, select, price, count);	
	unit_drink_dispenser udd(clk, rst, coin, dispense, done, price, count, deliver, payb2);
	
endmodule 

//==========================================================================================================
module unit_drink_dispenser
(
	clk, rst, coin, dispense, done, price, count, deliver, payback
);

	input wire clk, rst, coin, dispense, done;
	input wire [3:0] price, count; 
	output wire deliver, payback;

	wire enough, zero, sub;
	wire [1:0] select_value;
	wire [2:0] select_next;
	
	drink_dispenser_cntrl ddc(clk, rst, coin, dispense, done, enough, zero, deliver, payback, select_value, select_next, sub);
	drink_dispenser_data ddd(clk, select_value, select_next, sub, price, enough, zero);

endmodule



module drink_dispenser_cntrl
(
	clk, reset, coin, dispense, done, enough, zero, deliver, payback,  select_value,  select_next, sub
);

	input wire clk, reset, coin, dispense, done, enough, zero;
	output wire deliver, payback;
	output wire [1:0] select_value;
	output wire [2:0] select_next;
	output wire sub;

	reg [2:0] present_state, next_state;
	
	// State Encoding
	parameter DEPOSIT  = 3'b000; 
	parameter DELIVER1 = 3'b001;
	parameter DELIVER2 = 3'b010;
	parameter PAYBACK1 = 3'b011;
	parameter PAYBACK2 = 3'b100;
	
	always @(dispense or enough or done or zero or present_state)
	begin
		casex({dispense, enough, done, zero, present_state})
			{4'b11xx, DEPOSIT}:  next_state = DELIVER1; 		//  dispense & enough
			{4'b0xxx, DEPOSIT}:  next_state = DEPOSIT;			//  ~dispense  	
			{4'bx0xx, DEPOSIT}:  next_state = DEPOSIT;			//  dispense & !enought
			
			{4'bxx1x, DELIVER1}:  next_state = DELIVER2;	 	//  done
			{4'bxx0x, DELIVER1}:  next_state = DELIVER1;		//  ~done
			
			{4'bxx01, DELIVER2}:  next_state = DEPOSIT; 		//  ~done & zero
			{4'bxx00, DELIVER2}:  next_state = PAYBACK1;		//  ~done & ~zero
			{4'bxx1x, DELIVER2}:  next_state = DELIVER2;		//  done
			
			{4'bxx1x, PAYBACK1}:  next_state = PAYBACK2;		//  done
			{4'bxx0x, PAYBACK1}:  next_state = PAYBACK1;		//  ~done & ~zero
			
			{4'bxx00, PAYBACK2}:  next_state = PAYBACK1;		//  ~done & ~zero
			{4'bxx01, PAYBACK2}:  next_state = DEPOSIT;			//  ~done & zero
			{4'bxx1x, PAYBACK2}:  next_state = PAYBACK2;		//  done
		endcase
	end
	
	always @(posedge clk)
	begin
		if(reset)
			present_state = DEPOSIT;
		else
			present_state = next_state;
	end
	
	
	//outputs
	wire first;
	wire deliver1 = (present_state == DELIVER1);
	wire payback1 = (present_state == PAYBACK1);
		
	assign deliver = deliver1 & first;
	assign payback = payback1 & first;
	
	wire deposit = (present_state == DEPOSIT);
	
	assign select_value = {(deposit & dispense), ((deposit & coin)|payback)};
	
	wire selv = (deposit & (coin | (dispense & enough))) | (payback & first);

	assign select_next = {!(selv | reset), selv, reset};
	
	assign sub = (deposit & dispense) | payback ;
	
	// only do actions on first cycle of deliver1 or payback1
	wire nfirst = !(deliver1 | payback1) ;
	D_FF first_reg(clk, nfirst, first) ;	
	
endmodule

module drink_dispenser_data
(
	input wire clk,
	input wire[1:0] select_value,
	input wire [2:0] select_next,
	input wire sub,
	input wire [3:0] price,
	output enough, zero
);
	
	parameter n=6;
	wire [3:0] value;
	
	wire [n-1:0] sum ; // output of add/subtract unit
	wire [n-1:0] amount ; // current amount
	wire [n-1:0] next ; // next amount

	wire ovf ; // overflow - ignore for now

 	 // select the value to add or subtract
	MUX2x1 #(4) vmux(price, 4'b0001, select_value, value) ;	

	AddSub #(n) add(amount, {2'b00,value}, sub, sum, ovf);
	
	// select next state from 0, sum, or hold
	MUX3x1 #(n) nsmux(amount, sum, {n{1'b0}}, select_next, next) ;
	
	// state register holds current amount
	D_FF #(n) amt(clk, next, amount) ;	

	// comparators
	assign enough = (amount >= price) ;
	assign zero = (amount == 0) ;

endmodule
//==========================================================================================================


module unit_money_withdraw
(
	clk, rst, withdraw, inc, dec, done, payback	
);
	input wire clk, rst, done, inc, dec, withdraw;
	output  payback;

	parameter n=6;
	
	wire [n-1:0] curr_value;
	wire [n-1:0] next_value;
	
	wire [2:0] sel;
	reg clr;
	wire ovf;   // no usage now
	
	wire inc_value;   // 0 or +1
	wire [n-1:0] value;   
	
	reg [1:0] present_state, next_state;
	
	// State Encoding 
	parameter WAIT = 2'b00; parameter WITHD1  = 2'b01;  parameter WITHD2 = 2'b10;
		
	wire withd1 = (present_state == WITHD1);
	wire payback = withd1;
	wire  withd2 = (present_state == WITHD2);
	wire sub = withd1 | dec; // subrtact if sub==1 
	wire zero = (curr_value==0);
	wire hold = ((present_state == WAIT) | (present_state == WITHD2)) & !sub & !inc;
		
	D_FF #(n) balance(clk, next_value, curr_value);
		
	MUX2x1b #(n) mux_next_value(value, {n{1'b0}} , clr, next_value);
		
	MUX2x1b mux_inc_value({1'b1}, {1'b0}, hold, inc_value );

	AddSub #(n) adder(curr_value, {{(n-1){1'b0}}, inc_value}, sub, value, ovf);
		

	always @(present_state or withdraw or zero or done)
	begin
		casex({withdraw, zero, done, present_state})
			{4'b0xx, WAIT}:  next_state = WAIT;
			{4'b11x, WAIT}:  next_state = WAIT;
			{4'b10x, WAIT}:  next_state = WITHD1;
			{4'bxx0, WITHD1}:   next_state = WITHD2;
			{4'bx01, WITHD1}:   next_state = WITHD1;
			{4'bx11, WITHD1}:   next_state = WAIT;
			{4'bx01, WITHD2}:   next_state = WITHD1;
			{4'bx11, WITHD2}:   next_state = WAIT;
			{4'bxx0, WITHD2}:   next_state = WITHD2;
		endcase
	end
		
	always @(posedge clk)
	begin
		if(rst)
		begin
			present_state = WAIT;
		end
		begin
			present_state = next_state;
		end
	end
		
	always @(posedge clk)
	begin
		if(rst)
			clr = 1'b1;
		else
		begin
			clr = 1'b0;
		end
	end
	
endmodule






//===================================================================================
module unit_charge_product
(
	clk, mode, charge, discharge, select, p, count
);
	input wire clk;
	input wire charge, discharge;	// is active for one clock only
	input wire [1:0] mode;
	input wire[4:0] select;	// one-hot index of selected drinks
	output wire[3:0] count;	// selected drink count to 7segment output & delivery unit
	output wire[3:0] p;
	
	reg[3:0] stock[0:4];   //  holds count of drinks -- initliazed  from stuff.txt file
	reg[3:0] price[0:4];   //  holds price of drinks -- initliazed  from stuff.txt file
	
	wire[3:0] curr_count;  //  mux output for selected drink count
	wire[3:0] curr_price;  //  mux output for select drind price
	
	wire ovf;  // overflow or underflow produce error signal to LED

	reg  sub;
	reg [3:0] inc_value = 4'b0001;
	wire [3:0] next_value;
	
	reg [2:0] idx;	//  binery index of selected product

	
	
	genvar i;
	generate for(i=0; i< 4; i=i+1) begin: mux_loop
		 	MUX5x1  smux( stock[0][i], stock[1][i],stock[2][i],stock[3][i],stock[4][i], curr_count[i], select);
			MUX5x1  pmux( price[0][i], price[1][i],price[2][i],price[3][i],price[4][i], curr_price[i], select);
			
		end
	endgenerate

	
	always@(mode)
	case(mode)
		2'b00:   sub=1'b1;
		default: sub = 1'b0;
	endcase
	
	AddSub #(4) adder(curr_count, inc_value, sub, next_value, ovf);
	
	assign count = curr_count;
	assign p = curr_price;


	always @(posedge clk)
	begin
		case(select)
			5'b00001: idx = 3'b000;
			5'b00010: idx = 3'b001;
			5'b00100: idx = 3'b010;
			5'b01000: idx = 3'b011;
			5'b10000: idx = 3'b100;
		endcase
		if(charge | discharge)
			stock[idx] = next_value;
		else
			stock[idx] = curr_count;
	end

endmodule



//===================================================================================

// parameterized 2*1 mulitplexer with binary select
module MUX2x1b( i0,i1,sel,out);
	parameter k=1;
	input  [k-1:0] i0,i1;
	input  sel;
	output [k-1:0] out;
    wire [k-1:0] out = ({k{!sel}} & i0) | ({k{sel}} & i1);
endmodule

// Parameterized n bit wide 2 to 1 mux with one-hot select
module MUX2x1(a0,a1,sel,y);
	parameter k = 1;   // default to 1 bit
	input [k-1:0] a0,a1;  //inputs
	input [1:0] sel;  // one-hot select
	output [k-1:0] y;
	reg [k-1:0] y;
	always @(a0 or a1 or sel)
		case (sel)
			2'b01 : y = a0;
			2'b10 : y = a1;
			default : y = 'b0; // will automatically size to fit
		endcase
endmodule

// Parameterized n bit wide 3 to 1 mux with one-hot select
module MUX3x1(a2, a1, a0, sel, y) ;
	parameter k = 1;  // default to 1 bit
	input [k-1:0] a0, a1, a2; // inputs
	input [2:0] sel ;  // one-hot select
	output[k-1:0] y ;
	wire [k-1:0] y = ({k{sel[0]}} & a0) | ({k{sel[1]}} & a1) | ({k{sel[2]}} & a2) ;
endmodule

// Parameterized n bit wide 5 to 1 mux with one-hot select
module MUX5x1
(
	a0, a1, a2, a3, a4, y, sel
);
	parameter n=1;
	input [n-1:0]  a0, a1, a2, a3, a4;
	output [n-1:1] y;
	input [4:0] sel;
	wire [n-1:0] y = ({n{sel[0]}} & a0) | 
						({n{sel[1]}} & a1) |
					    ({n{sel[2]}} & a2) |
					    ({n{sel[3]}} & a3) |
					    ({n{sel[4]}} & a4) ;
endmodule

//Positive edged D-FLIPFLOP
module D_FF
(
	clk, D, Q
);
	parameter n = 1;
	input [n-1:0] D;
	input clk;
	output reg [n-1:0] Q;

	always @ (posedge clk)
	begin
		Q <= D;
	end
endmodule


//===================================================================================

//Parameterized adder/subtractor with overflow 
module AddSub
(
	a,b,sub,s,ovf
);
	parameter n = 6;  //  default to 4 bit
	input [n-1:0] a, b;
	input sub; // subtract if sub=1, otherwise add
	output [n-1:0] s;
	output ovf; // 1 if overflow
	wire c1, c2; // carry out of last two bits
	wire ovf = c1 ^ c2 ; // overflow if signs don?t match
	// add non sign bits
	assign {c1, s[n-2:0]} = a[n-2:0] + (b[n-2:0] ^ {n-1{sub}}) + sub ;
	// add sign bits
	assign {c2, s[n-1]} = a[n-1] + (b[n-1] ^ sub) + c1 ;
endmodule
	
//======================================================================================

//testbench for drin chargin unit
module vending_machine_charge_tb;
	reg clk;
	reg rst;
	
	reg [1:0] mode = 2'b01;	
	reg [4:0] select = 5'b00001;
	reg charge = 1'b0;
	reg withdraw = 1'b0;
	reg dispense = 1'b0; 
	
	reg coin = 1'b0;
	reg done = 1'b0;
	
	wire [3:0] price , count;
	wire deliver, payback ;
	
	integer i, fd, st, j;
	
	
	vending_machine vm( clk, rst, charge, coin, dispense, withdraw, done, deliver, payback, mode, select, price, count );
		
	initial
	begin
		init_vend_machine;
	end
	
	initial
	begin
		rst=1;  #22 rst= 0;
	end
	
	
	initial
	begin
		clk = 1; #5 clk = 0;
		forever
		begin
			#5 clk = 1 ; #5 clk = 0 ;
		end
	end
	
	
	// Testbench for charge product unit
	initial 
	begin
		display_invetory_stock;			
		#40 select = 5'b00001;	//increment first item count	
		#10 charge = 1'b1; #10 charge = 1'b0;
		display_invetory_stock;				
		#10 select = 5'b00010;	//increment next item to charge its count
		#20 charge = 1'b1; #10 charge = 1'b0;
		display_invetory_stock;
		#10 select = 5'b00100;	//test in case of  increment buttion is not pressed
		display_invetory_stock;
		
	end
	
	task display_invetory_stock;
		begin
			for(j=0; j<5; j=j+1)
				$display("type=%h count=%h price=%h", j, vm.ucp.stock[j], vm.ucp.price[j]);
		end
	endtask
	
	task init_vend_machine;
		reg [10:0] line;
		reg [2:0] idx;
		begin
			// initialize register values from stuff file
			i = 5;
			fd = $fopen("c:\\work\\stuff.txt", "r");
			while (!$feof(fd) && i>0)
			begin
				st = $fscanf(fd, "%b", line);
				//$display("line=%p", line);
				idx = {line[10],line[9],line[8]};
				vm.ucp.price[idx] = line[3:0];
				vm.ucp.stock[idx] = line[7:4];
				$display("type=%h amount=%h price=%h", idx, vm.ucp.stock[idx], vm.ucp.price[idx]);
				i = i - 1;
			end
			$fclose(fd);
		end
	endtask

endmodule

//======================================================================================

module vending_machine_withdraw_tb;
	reg clk;
	reg rst;
	
	reg [1:0] mode;	
	reg [4:0] select;
	wire [3:0] price;
	wire [3:0] count;

	reg charge=1'b0;

	reg [10:0] line;
	reg [2:0] idx;
	reg withdraw = 1'b0;
	
	reg nickel, done ;
	wire deliver, payback ;
	
	integer i, fd, st, j;
	reg coin = 1'b0;
	reg dispense = 1'b0;


	
	vending_machine vm( clk, rst, charge, coin, dispense, withdraw, done, deliver, payback, mode, select, price, count );
		
	initial
		init_vend_machine;
	end
	
	// clock with period of 10 units
	initial
	begin
		clk = 1 ; #5 clk = 0 ;
		forever
		begin				
			#5 clk = 1 ; #5 clk = 0 ;
		end
	end
		
	initial
	begin
		rst = 1 ; inc = 0;
		#18 rst = 0 ;
		#20 inc = 1; #20 inc = 0;
		#20 withdraw = 1'b1; #10 withdraw = 1'b0;
		#100 $stop ;
	end
	
	//feedback to system
	always @(posedge clk)
	begin
		done = (payback) ;
	end
	
	task display_statue_signals;
		begin
			$display("coin=%b withdraw=%b done=%b current_money =%h ",vm.umw.charge, vm.umw.withdraw, done, vm.umw.curr_value);	
		end
	endtask	
	
	task init_vend_machine;
		reg [10:0] line;
		reg [2:0] idx;
		begin
			// initialize register values from stuff file
			i = 5;
			fd = $fopen("c:\\work\\stuff.txt", "r");
			while (!$feof(fd) && i>0)
			begin
				st = $fscanf(fd, "%b", line);
				//$display("line=%p", line);
				idx = {line[10],line[9],line[8]};
				vm.ucp.price[idx] = line[3:0];
				vm.ucp.stock[idx] = line[7:4];
				$display("type=%h amount=%h price=%h", idx, vm.ucp.stock[idx], vm.ucp.price[idx]);
				i = i - 1;
			end
			$fclose(fd);
		end
	endtask
endmodule

//======================================================================================
module vending_machine_serv_tb;
	reg clk;
	reg rst;
	
	reg [1:0] mode = ;	
	reg [4:0] select;
	wire [3:0] price;
	wire [3:0] count;

	reg load=1'b0;

	reg [10:0] line;
	reg [2:0] idx;
	reg inc = 1'b0;
	
	reg nickel, dime, quarter, dispense, done, coin ;
	wire deliver, payback ;
	reg withdraw = 1'b0;
	
	integer i, fd, st, j;
	
	
	
	vending_machine vm( clk, rst, load, coin, dispense, withdraw, done, deliver, payback, mode, select, price, count );
		
	initial
	begin
		// initialize register values from stuff file
		mode = 2'b00;
		i = 5;
		fd = $fopen("c:\\work\\stuff.txt", "r");
		while (!$feof(fd) && i>0)
		begin
			st = $fscanf(fd, "%b", line);
			idx = {line[10],line[9],line[8]};
			vm.ucp.price[idx] = line[3:0];
			vm.ucp.stock[idx] = line[7:4];
			$display("type=%h amount=%h price=%h", idx, vm.ucp.stock[idx], vm.ucp.price[idx]);
			i = i - 1;
		end
		$fclose(fd);
	end
	
	// clock with period of 10 units
	initial
	begin
		clk = 1 ; #5 clk = 0 ;
		forever
		begin
			//$display("%b %h %h %b %b",{nickel,dime,quarter,dispense}, vm.vmc.state, vm.vmd.amount, deliver, payback) ;
			$display("%b %h %b %b",{coin,dispense}, vm.udd.ddc.present_state, deliver, payback) ;

			#5 clk = 1 ; #5 clk = 0 ;
		end
	end
	
	// give prompt feedback
	always @(posedge clk)
	begin
		done = (deliver | payback) ;
	end
	initial
	begin
		rst = 1 ; {coin, dispense} = 4'b00 ; select = 5'b00001 ;
		#22 rst = 0 ;
		#8 {coin, dispense} = 2'b10 ; // coin 1
		#10 {coin, dispense} = 2'b10 ; // coin 2
		#10 {coin, dispense} = 2'b00 ; // nothing
		#10 {coin, dispense} = 2'b01 ; // dispense early
		#10 {coin, dispense} = 2'b10 ; // coin 3
		#10 {coin, dispense} = 2'b10 ; // coin 4
		#10 {coin, dispense} = 2'b00 ; // nothing
		#10 {coin, dispense} = 2'b01 ; // dispense
		#10 dispense = 0 ;
		#200 $stop ;
	end
endmodule
//======================================================================================



	