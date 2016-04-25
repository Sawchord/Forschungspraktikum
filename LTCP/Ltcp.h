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
#ifndef LTCP_H
#define LTCP_H

#include <lib6lowpan/ip.h>

/* the period between two calls to the timer process in milliseconds*/
#ifndef TCP_PROCESS_TIME
#define TCP_PROCESS_TIME 512
#endif

/* all ports below this one are reserved and will not be used on connect */
#ifndef TCP_RESERVED_PORTS
#define TCP_RESERVED_PORTS 1024
#endif

/* start retry frequency (gets doubled on every retry) */
#ifndef TCP_RETRY_FREQ
#define TCP_RETRY_FREQ 1000;
#endif

/* the standard time for TCP_TIME_WAIT in ms */
#ifndef TCP_TIMEWAIT_TIME
#define TCP_TIMEWAIT_TIME 2000
#endif

/* number of retries before giving up */
#ifndef TCP_N_RETRIES
#define TCP_N_RETRIES 6
#endif

/* debug output */
#ifdef DEBUG_OUT
#include <printf.h>
#define DBG(...) printf(__VA_ARGS__); printfflush()
#else
#define DBG(...) 
#endif


/* states a socket can be in */
typedef enum {
  TCP_CLOSED = 0x0,
  TCP_LISTEN,
  TCP_SYN_RCVD,
  TCP_SYN_SENT,
  TCP_ESTABLISHED_NOMINAL,
  TCP_ESTABLISHED_ACKPENDING,
  TCP_CLOSE_WAIT,
  TCP_LAST_ACK,
  TCP_FIN_WAIT_1,
  TCP_FIN_WAIT_2,
  TCP_CLOSING,
  TCP_TIME_WAIT,
} tcplib_sock_state_t;


/* le flaques */
typedef enum {
  TCP_FIN = 0x1,
  TCP_SYN = 0x2,
  TCP_RST = 0x4,
  TCP_PSH = 0x8,
  TCP_ACK = 0x10,
  TCP_URG = 0x20,
  TCP_ECE = 0x40,
  TCP_CWR = 0x80,
  TCP_NS  = 0x100,
} tcp_flag_t;



struct tcplib_sock {
  
  //tcp_flag_t flags;
  /* current connection state */
  tcplib_sock_state_t state;
  
  void* last_payload;
  uint16_t last_payload_len;
  
  void    *tx_buf;
  uint16_t tx_buf_len;
  
  /* max segment size, or default if
   *   we didn't bother to pull it out
   *   of the options field */
  //uint16_t mss;
  
  //uint16_t my_wind;
  /* the window the other end is
   *   reporting */
  //uint16_t r_wind;
  //uint16_t cwnd;
  //uint16_t ssthresh;
  
  // the current next sequence number for ourgoing data.
  uint32_t seqno;
  // and the index of the last byte we've ACKed
  uint32_t ackno;
  
  // number of resends to an unacknowledged packet
  int8_t retx;
  
  /* retransmission timer */
  uint16_t rettim;
  
  /* this needs to be at the end so
   *   we can call init() on a socket
   *   without blowing away the linked
   *   list */
  //struct tcplib_sock *next;
  
  /* local and remote endpoints */
  struct sockaddr_in6 l_ep;
  struct sockaddr_in6 r_ep;
  
};


#endif /* LTCP_H */