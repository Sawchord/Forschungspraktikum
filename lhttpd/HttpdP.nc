/* debug output */
#ifdef DEBUG_OUT
#include <printf.h>
#define DBG(...) printf(__VA_ARGS__); printfflush()
#else
#define DBG(...) 
#endif


#ifndef RBUF_SIZE
  #define RBUF_SIZE 256
#endif

#ifndef TBUF_SIZE
  #define TBUF_SIZE 1024
#endif


module HttpdP {
  uses {
    interface Leds;
    interface Boot;
    interface Ltcp as Tcp;
  }
} implementation {

  //static char *http_okay = "HTTP/1.0 200 OK\r\n\r\n";
  //static int http_okay_len = 19;

  enum {
    S_IDLE,
    S_CONNECTED,
    S_REQUEST_PRE,
    S_REQUEST,
    S_HEADER,
    S_BODY,
  };

  enum {
    HTTP_GET,
    HTTP_POST,
  };

  /*void process_request(int verb, char *request, int len) {
    
    char reply[43];
    uint8_t bitmap;
    memcpy(reply, "HTTP/1.1 200 OK\r\n\r\n", 19);
    memcpy(reply+19, "led0: 0 led1: 0 led2: 0\n", 24);

    
    bitmap = call Leds.get();
        //call Tcp.send(http_okay, http_okay_len);
    if (bitmap & 1) reply[6+19] = '1';
    if (bitmap & 2) reply[14+19] = '1';
    if (bitmap & 4) reply[22+19] = '1';
    call Tcp.send(reply, 24+19);
    
    call Tcp.close();
  }*/

  int http_state;
  int req_verb;
  char request_buf[RBUF_SIZE], *request;
  char tcp_buf[TBUF_SIZE];

  event void Boot.booted() {
    http_state = S_IDLE;
    call Tcp.bind(80);
  }

  event bool Tcp.accept(struct sockaddr_in6 *from, 
                            void **tx_buf, uint16_t *tx_buf_len) {
    if (http_state == S_IDLE) {
      call Leds.led2On();
      http_state = S_CONNECTED;
      *tx_buf = tcp_buf;
      *tx_buf_len = TBUF_SIZE;
      return TRUE;
    }
    //printfUART("rejecting connection\n");
    return FALSE;
  }
  event void Tcp.connectDone(error_t e) {
    
  }
  
  event void Tcp.recv(void *payload, uint16_t len) {
    
    
    char reply[43];
    uint8_t bitmap;
    memcpy(reply, "HTTP/1.1 200 OK\r\n\r\n", 19);
    memcpy(reply+19, "led0: 0 led1: 0 led2: 0\n", 24);

    
    bitmap = call Leds.get();
        //call Tcp.send(http_okay, http_okay_len);
    if (bitmap & 1) reply[6+19] = '1';
    if (bitmap & 2) reply[14+19] = '1';
    if (bitmap & 4) reply[22+19] = '1';
    call Tcp.send(reply, 24+19);
    
    call Tcp.close();
    
    /*static int crlf_pos;
    char *msg = payload;
    switch (http_state) {
    case S_CONNECTED:
      crlf_pos = 0;
      request = request_buf;
      if (len < 3) {
        call Tcp.close();
        return;
      }
      if (msg[0] == 'G') {
        req_verb = HTTP_GET;
        msg += 3;
        len -= 3;
      }
      http_state = S_REQUEST_PRE;
    case S_REQUEST_PRE:
      while (len > 0 && *msg == ' ') {
        len--; msg++;
      }
      if (len == 0) break;
      http_state = S_REQUEST;
    case S_REQUEST:
      while (len > 0 && *msg != ' ') {
        *request++ = *msg++;
        len--;
      }
      if (len == 0) break;
      *request++ = '\0';
      http_state = S_HEADER;
    case S_HEADER:
      while (len > 0) {
        switch (crlf_pos) {
        case 0:
        case 2:
          if (*msg == '\r') crlf_pos ++;
          else if (*msg == '\n') crlf_pos += 2;
          else crlf_pos = 0;
          break;
        case 1:
        case 3:
          if (*msg == '\n') crlf_pos ++;
          else crlf_pos = 0;
          break;
        }
        len--; msg++;
        // if crlf == 2, we just finished a header line.  you know.  fyi.
        if (crlf_pos == 4) {
          http_state = S_BODY;
          process_request(req_verb, request_buf, request - request_buf - 1);
          break;
        } 
      }
    if (crlf_pos < 4) break;

    case S_BODY:
      // len might be zero here... just a note.
    default:
      call Tcp.close();
    }*/
  }

  event void Tcp.closed(error_t e) {
    call Leds.led2Off();

    call Tcp.bind(80);
    http_state = S_IDLE;
  }

  event void Tcp.acked() {

  }
  
  event void Tcp.sendDone(error_t e) {
  }
}
