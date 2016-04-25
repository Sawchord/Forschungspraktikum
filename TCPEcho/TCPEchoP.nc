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
        
        interface Leds;
        
        interface Timer<TMilli> as StatusTimer;
   
        //interface BlipStatistics<ip_statistics_t> as IPStats;
        
        interface Random;
    }
} implementation {
    
    bool timerStarted;
    struct sockaddr_in6 route_dest;
    
    uint8_t tbf[256];
    
    event void Boot.booted() {
        
        #ifdef PRINTFUART_ENABLED
            printf("Boooooted\n");
        #endif
        
        call RadioControl.start();
        timerStarted = FALSE;
        
        //call IPStats.clear();
        
#ifdef REPORT_DEST
        route_dest.sin6_port = htons(7000);
        inet_pton6(REPORT_DEST, &route_dest.sin6_addr);
        call StatusTimer.startOneShot(call Random.rand16() % (1024 * REPORT_PERIOD));
#endif
        
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
    
    event void Echo.closing() {}
    
    event void Echo.closed(error_t e) {\
        call Leds.led0Toggle();
        call Echo.bind(7);
    }
    
    event void Echo.acked() {
    }
    
    event bool Echo.accept(struct sockaddr_in6 *from, 
        void **tx_buf, uint16_t *tx_buf_len) {
        
        *tx_buf = &tbf;
        *tx_buf_len = 256;
        
        call Leds.led2Toggle();
        return TRUE;
    }
    
    event void Echo.sendDone(error_t e) {
    }
    
    event void Echo.recv(void *data, uint16_t len) {
        
#ifdef PRINTFUART_ENABLED
        int i;
        uint8_t *cur = data;
        call Leds.led0Toggle();
        printf("Echo revc [%i]: ", len);
        for (i = 0; i < len; i++) {
            printf("%02x ", cur[i]);
        }
        printf(" \r\n");
#endif
        if (call Echo.send(data, len) != SUCCESS) {
            call Leds.led1Toggle();
        }
    }
    
    event void StatusTimer.fired() {
        if (!timerStarted) {
            call StatusTimer.startPeriodic(1024 * REPORT_PERIOD);
            timerStarted = TRUE;
        }
        
        call Leds.led1Toggle();
    }
}