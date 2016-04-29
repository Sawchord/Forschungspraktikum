/* Coypright 2016 Leon Tan
 * Licensed unser GPLv2
 */

#include <IPDispatch.h>
#include <lib6lowpan/lib6lowpan.h>
#include <lib6lowpan/ip.h>
#include <lib6lowpan/ip.h>

#include "TCPEcho.h"

#ifdef PRINTFUART_ENABLED
  #include <printf.h>
#endif
  
#define REPORT_PERIOD 10L


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
  }
  
  event void RevEcho.recv(void *data, uint16_t len) {
    printf("revecho has data: %s\n", data);
    
    
    if (call Echo.send(data, len) != SUCCESS) {
        call Leds.led1Toggle();
    }
  }
  
  event void Echo.recv(void *data, uint16_t len) {
    
    call Leds.led0Toggle();
    printf("RCVD data %s: \n", data);
    
    if (connected == FALSE) {
      printf("starting reverse echo\n");
      dest.sin6_port = htons(7);
      inet_pton6("fec0::100", &(dest.sin6_addr));
      if (call RevEcho.connect(&dest, &tbf2, 128) == SUCCESS){
        connected = TRUE;
        call StatusTimer.startPeriodic(2000);
      }
    }
    
    
    if (call Echo.send(data, len) != SUCCESS) {
        call Leds.led1Toggle();
    }
  }
    
  event void StatusTimer.fired() {
    if (connected == TRUE) {
      call RevEcho.send(&tstr, 20);
    
      call Leds.led1Toggle();
      
      msgs_send ++;
      
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
  }
}



