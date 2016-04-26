/* "Copyright (c) 2016 
 * Leon Tan 
 * Georg-August University of Goettingen
 * All rights reserved"
 * 
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 *
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR 
 * HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 * 
 */
 
 
#include <IPDispatch.h>
#include <lib6lowpan/lib6lowpan.h>
#include <lib6lowpan/ip.h>
#include <lib6lowpan/ip.h>

#include "SerialTCP.h"

#ifdef PRINTFUART_ENABLED
  #include <printf.h>
#endif


module SerialTCPP {
  uses {
    
    interface Boot;
    interface SplitControl as RadioControl;
    
    interface Ltcp as Connection;
    
    interface Leds;
    
    interface Timer<TMilli> as Timer0;
    
  }
    
} implementation {
  
  struct sockaddr_in6 dest;
  uint8_t tx[1024];
  
  char* teststr = "Thesty stringy thingy";
  
  event void Boot.booted() {
    
    printf("Booted\n");
    printf("Hello from Node; %d\n", TOS_NODE_ID);
    
    if ( call RadioControl.start() != SUCCESS){
      printf("could not start radio\n");
      call Leds.led1Toggle();
    }
    
  }
  
  event void RadioControl.startDone(error_t e) {
    // connect one to two
    
    if (TOS_NODE_ID == 1) {
      dest.sin6_port = htons(1337);
      inet_pton6("fec0::2", &(dest.sin6_addr));
      
      if(call Connection.connect(&dest, tx, 512) == SUCCESS){
        call Leds.led0Toggle();
      }
      
    }
    else if (TOS_NODE_ID == 2) {
      if (call Connection.bind(1337) == SUCCESS){
        call Leds.led0Toggle();
      }
      
    }
    
  }
  
  event void RadioControl.stopDone(error_t e) {
  }
  
  event void Timer0.fired() {
    
    if (call Connection.send(&teststr, 100) != SUCCESS) {
      printf("send error\n");
      call Leds.led1Toggle();
    }
    
    call Leds.led2Toggle();
    
  }
  
  event bool Connection.accept(struct sockaddr_in6 *from, 
                    void **tx_buf, uint16_t *tx_buf_len) {
          
          if (TOS_NODE_ID == 2){
            *tx_buf = (void*) &tx;
            *tx_buf_len = 512;
            return TRUE;
          }
          else {
            return FALSE;
          }
          
  }
  
  event void Connection.sendDone(error_t e) {}
  
  event void Connection.connectDone(error_t e) {
    
    printf("Connection done, starting Timer\n");
    call Timer0.startPeriodic(2000);
  }
  
  event void Connection.closing() {}
  
  event void Connection.acked() {}
  
  event void Connection.recv(void *payload, uint16_t len) {
    printf("Got data: \n");
    printf("%s\n", payload);
    
    }
  
  event void Connection.closed(error_t e) {}
  
  
}
  
  
  
  