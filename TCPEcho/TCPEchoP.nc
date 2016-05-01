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

#include "TCPEcho.h"

#ifdef PRINTFUART_ENABLED
  #include <printf.h>
#endif


module TCPEchoP {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    
    interface Ltcp as Echo;
    interface Ltcp as RevEcho;
    
    interface Leds;
    
    interface Timer<TMilli> as StatusTimer;

    
    interface Random;
  }
} implementation {
  
  bool timerStarted;
  bool connected = FALSE;
  uint8_t msgs_send = 0;
  struct sockaddr_in6 dest;
  
  char tstr[] = "hello from revecho\n";
  
  uint8_t tbf[1024];
  uint8_t tbf2[128];
  
  event void Boot.booted() {
      
    #ifdef PRINTFUART_ENABLED
        printf("Boooooted\n");
    #endif
    
    call RadioControl.start();
    timerStarted = FALSE;
    
      
  }
    
  event void RadioControl.startDone(error_t e) {
    if (call Echo.bind(7) != SUCCESS) {
      call Leds.led1Toggle();
    }
    else {
      call Leds.led2Toggle();
    }
  }
    
  event void RadioControl.stopDone(error_t e) {
  }
  
  event void Echo.connectDone(error_t e) {
  }
  
  event void RevEcho.connectDone(error_t e) {
    if (e == SUCCESS) {
      msgs_send = 0;
      connected = TRUE;
      call StatusTimer.startPeriodic(2000);
    }
  }
    
  
  event void Echo.closed(error_t e) {
    //call Leds.led0Toggle();
    call Echo.bind(7);
  }
  
  event void RevEcho.closed(error_t e) {
    printf("connection closed on the other side\n");
    connected = FALSE;
  }
  
  event void Echo.acked() {
  }
  
  event void RevEcho.acked() {
  }
  
  // decline all connection attempts to this 
  event bool RevEcho.accept(struct sockaddr_in6 *from, 
    void **tx_buf, uint16_t *tx_buf_len) {
    return FAIL;
  }
  
  event bool Echo.accept(struct sockaddr_in6 *from, 
    void **tx_buf, uint16_t *tx_buf_len) {
    
    *tx_buf = tbf;
    *tx_buf_len = 1024;
    
    call Leds.led2Toggle();
    return TRUE;
  }
    
  event void Echo.sendDone(error_t e) {
  }
  
  event void RevEcho.sendDone(error_t e) {
    
    if (msgs_send == 3) {
        if (call RevEcho.close() == SUCCESS) {
          connected = FALSE;
          printf("connection terminated on this side\n");
        }
        else {
          call Leds.led2Toggle();
        }
      }
  }
  
  event void RevEcho.recv(void *data, uint16_t len) {
    printf("revecho has data: %s\n", data);
    
    
    if (call Echo.send(data, len) != SUCCESS) {
        call Leds.led1Toggle();
    }
  }
  
  event void Echo.recv(void *data, uint16_t len) {
    
    call Leds.led0Toggle();
    printf("RCVD data: %s \n", data);
    
    if (connected == FALSE) {
      msgs_send = 0;
      printf("starting reverse echo\n");
      dest.sin6_port = htons(7);
      inet_pton6("fec0::100", &(dest.sin6_addr));
      if (call RevEcho.connect(&dest, &tbf2, 128) != SUCCESS){
        printf("revecho connection failed\n");
      }
    }
    
    
    if (call Echo.send(data, len) != SUCCESS) {
        call Leds.led1Toggle();
    }
  }
    
  event void StatusTimer.fired() {
    if (connected == TRUE) {
      printf("sending data on revecho\n");
      call RevEcho.send(&tstr, 20);
    
      call Leds.led1Toggle();
      
      msgs_send ++;
      
    }
  }
}



