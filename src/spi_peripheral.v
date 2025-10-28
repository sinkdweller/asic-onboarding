
/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module spi_peripheral (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       SCLK,
    input  wire       COPI,
    input  wire       nCS,
    output reg [7:0]  en_reg_out_7_0,
    output reg [7:0]  en_reg_out_15_8,
    output reg [7:0]  en_reg_pwm_7_0,
    output reg [7:0]  en_reg_pwm_15_8,
    output reg [7:0]  pwm_duty_cycle
);

  //SYNCHRONIZE Sclk, COPI, Cs --> Sclk _ync2, COPI_sync2, nCS_sync2;
  reg Sclk_sync1, Sclk_sync2;
  reg COPI_sync1, COPI_sync2;
  reg nCS_sync1, nCS_sync2, nCS_prev; 

  reg Sclk_sync_prev;
  always@(posedge clk)begin
    Sclk_sync1 <= SCLK;
    Sclk_sync2 <= Sclk_sync1;
    Sclk_sync_prev <= Sclk_sync2; //stores previous Sclk synced

    COPI_sync1 <= COPI;
    COPI_sync2 <= COPI_sync1;

    nCS_sync1 <= nCS;
    nCS_sync2 <= nCS_sync1;
    nCS_prev <= nCS_sync2; //stores previous nCS

  end

  wire Rising_Sclk_sync = (Sclk_sync2==1'b1)&&(Sclk_sync_prev == 1'b0); //rising edge of Sclk
  wire Rising_nCS_sync = (nCS_sync2 == 1'b1)&&(nCS_prev == 1'b0); //rising edge of nCS

  reg [4:0] bit_count;
  reg [15:0] shift_reg;
  reg transaction_ready;
  reg transaction_complete;

  //TRANSACTION CAPTURE LOGIC
  //data transfer start on falling edge of nCS, sampling start on rising edge of sclk. detect negedge
  always@(posedge clk or negedge rst_n) begin
    //reset priority
    if(!rst_n) begin
      en_reg_out_7_0 <= 8'b0;
      en_reg_out_15_8 <= 8'b0;
      en_reg_pwm_7_0 <= 8'b0;
      en_reg_pwm_15_8 <= 8'b0;
      pwm_duty_cycle <= 8'b0;
      transaction_ready <= 0;
      transaction_complete <= 0;
      bit_count <= 0;
      shift_reg <= 0;

    //Does transaction start? (TRANSACTION = LOW)
    end else if (nCS_sync2 == 1'b0) begin 
      if(Rising_Sclk_sync)begin //sample COPI on every rising Sclk
        shift_reg <= {shift_reg[14:0], COPI_sync2}; //COPI shifts reg left.
        bit_count <= bit_count + 1; //count bits
      end 
    
    //CASE TRANSACTION = HIGH (STOP TRANSACTION)
    end else begin
      //TRANSACTION JUST STOPS
      if (Rising_nCS_sync)begin
        //validate the transaction: 1. 8 bit count, first bit = 1 (write), valid addr = 0 --> 0x04
        if(bit_count == 16 && //16 bits
          shift_reg[15] ==1 && //write mode
          shift_reg[14:8] >= 7'h00 && shift_reg[14:8] <= 7'h04) begin //valid address

          transaction_ready <= 1'b1;// transaction ready to be used!

        end else begin
          transaction_ready <= 1'b0; //not a valid transaction.
        end
        //reset counters
        bit_count <= 0;
        shift_reg <= 0;
      end else if (transaction_complete) begin
      //reset flag
        transaction_ready <= 0;
      end
    end
    

  end

  always@(posedge clk or negedge rst_n)begin
    //reset priority
    if(!rst_n) begin
      en_reg_out_7_0 <= 8'b0;
      en_reg_out_15_8 <= 8'b0;
      en_reg_pwm_7_0 <= 8'b0;
      en_reg_pwm_15_8 <= 8'b0;
      pwm_duty_cycle <= 8'b0;
      transaction_complete <= 0;

    //START DOING TRANSACTION LOGIC

    //if transaction is ready and not completed
    end else if(transaction_ready&&!transaction_complete) begin
      //upload to register
      case(shift_reg[14:8])  //address
        7'h00: en_reg_out_7_0 <= shift_reg[7:0]; //enable outputs on uo_out[7:0]
        7'h01: en_reg_out_15_8 <= shift_reg[7:0]; //enable outputs on uio_out[7:0]
        7'h02: en_reg_pwm_7_0 <= shift_reg[7:0]; //enable PWM for uo_out[7:0]
        7'h03: en_reg_pwm_15_8 <= shift_reg[7:0]; //enable PWM for uio_out[7:0]
        7'h04: pwm_duty_cycle <= shift_reg[7:0];
      endcase
      
      transaction_complete <= 1'b1;
    //what if no transaction ready and just finish transaction?
    end else if(!transaction_ready && transaction_complete) begin
      transaction_complete <= 1'b0;
    end
  end

endmodule
