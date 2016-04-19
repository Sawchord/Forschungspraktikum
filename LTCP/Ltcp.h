/* "Copyright (c) 2016 
 * Leon Tan 
 * University of Goettingen
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

/* states a socket can be in */
typedef enum {
  TCP_CLOSED = 0x0,
  TCP_LISTEN,
  TCP_SYN_RCVD,
  TCP_SYN_SENT,
  TCP_ESTABLISHED,
  TCP_CLOSE_WAIT,
  TCP_LAST_ACK,
  TCP_FIN_WAIT_1,
  TCP_FIN_WAIT_2,
  TCP_CLOSING,
  TCP_TIME_WAIT,
} tcplib_sock_state_t;

/* internal processing state during established state */
typedef enum {
  TCP_NOMINAL = 0x0,
  TCP_ACKPENDING = 0x1,
  TCP_RXB_FULL = 0x2,
  TCP_TXB_FULL = 0x4,
} tcp_internal_state_t;

/* le flaques */
typedef enum {
  TCP_FIN = 0x0,
  TCP_SYN = 0x1,
  TCP_RST = 0x2,
  TCP_PSH = 0x4,
  TCP_ACK = 0x8,
  TCP_URG = 0x10,
  TCP_ECE = 0x20,
  TCP_CWR = 0x40,
  TCP_NS  = 0x80,
} tcp_flag_t;



struct tcplib_sock {
  /* internal processing state */
  tcp_internal_state_t internal_state;
  
  //uint8_t flags;
  tcp_flag_t flags;
  
  /* local and remote endpoints */
  struct sockaddr_in6 l_ep;
  struct sockaddr_in6 r_ep;
  
  /* current connection state */
  tcplib_sock_state_t state;
  
  void    *tx_buf;
  int tx_buf_len;
  
  /* max segment size, or default if
   *   we didn't bother to pull it out
   *   of the options field */
  uint16_t mss;
  
  uint16_t my_wind;
  /* the window the other end is
   *   reporting */
  uint16_t r_wind;
  uint16_t cwnd;
  uint16_t ssthresh;
  
  // the current next sequence number for ourgoing data.
  uint32_t seqno;
  // and the index of the last byte we've ACKed
  uint32_t ackno;
  
  //struct {
  //  int8_t retx;
  //} timer;
  
  int8_t retx;
  
  /* retransmission counter */
  uint16_t retxcnt;
  
  /* this needs to be at the end so
   *   we can call init() on a socket
   *   without blowing away the linked
   *   list */
  struct tcplib_sock *next;
};


#endif /* LTCP_H */