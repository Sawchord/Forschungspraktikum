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
 
#include <lib6lowpan/ip.h>
#include <lib6lowpan/in_cksum.h>



#include "Ltcp.h"

module LtcpP {
  provides interface Ltcp[uint8_t client];
  provides interface Init;
  uses {
    interface Boot;
    
    interface IP;
    interface Timer<TMilli>;
    interface IPAddress;
    
    interface Random;
  }
} implementation {
  
  enum {
    N_CLIENTS = uniqueCount("TCP_CLIENT"),
  };
  
  /* all socket info is basically just stored in one big array
     know at compile time */
  struct tcplib_sock socks[N_CLIENTS];
  
  /* Initializes the sockets, will be executed automatically on startup*/
  command error_t Init.init() {
    
    int i;
    for (i = 0; i < uniqueCount("TCP_CLIENT"); i++) {
      
      struct tcplib_sock *sock;
      sock = &socks[i];
      
      DBG("LTCP init complete\n");
      
      // set complete struct to 0
      memset(sock, 0, sizeof(struct tcplib_sock) - sizeof(struct tcplib_sock *));
      //sock->mss = 200;
      //sock->my_wind = 0;
      //sock->cwnd = sock->mss;
      //sock->ssthresh = 0xffff;
      return SUCCESS;
      
    }
    
    return FAIL;
  }

  /* --------------- Implemented events ------------------ */
  
  /* Starts the timer once bootup is complete */
  event void Boot.booted() {
    call Timer.startPeriodic(TCP_PROCESS_TIME);
  }
  
  /* process time specific parts */
  event void Timer.fired() {
    
    struct tcplib_sock *sock;
    int i;
    
    
    // check all sockets for need to update
    for (i = 0; i < uniqueCount("TCP_CLIENT"); i++) {
      
      DBG("sock %d state:%d\n",i , socks[i].state);
      sock = &socks[i];
      
      // update time
      if ( ((int32_t) sock->rettim - TCP_PROCESS_TIME) < 0) {
        sock->rettim = 0;
      }
      else {
        sock->rettim -= TCP_PROCESS_TIME;
      }
      
      switch (sock->state) {
        case TCP_TIME_WAIT:
          
          if (sock->rettim == 0) {
            sock->retx = 0;
            sock->state = TCP_CLOSED;
          }
          
          break;
        
        case TCP_ESTABLISHED_ACKPENDING:
          
          if (sock->rettim == 0) {
            if (sock->retx < TCP_N_RETRIES) {
              
              // resend packets
              sock->retx++;
              sock->rettim = (sock->retx+1) * TCP_RETRY_FREQ;
              
              call Ltcp.send[i](sock->last_payload, sock->last_payload_len);
              
            }
            else {
              
              // send fails permanent -> signal user the fail
              //sock->retx = 0;
              sock->state = TCP_ESTABLISHED_NOMINAL;
              signal Ltcp.sendDone[i](FAIL);
            }
            
          }
          
          break;
        
        case TCP_CLOSING:
          
          if (sock->rettim == 0) {
            
            if (call Ltcp.sendFlagged[i](NULL, 0, TCP_FIN) != SUCCESS) {
              DBG("error sending FIN in  CLOSE_WAIT\n");
            }
            sock->state = TCP_LAST_ACK;
            
          }
          
          break;
        
        case TCP_FIN_WAIT_1:
          
          if (sock->rettim == 0) {
            
            if (sock->retx < TCP_N_RETRIES) {
              
              sock->retx++;
              sock->rettim = (sock->retx+1) * TCP_RETRY_FREQ;
              
              call Ltcp.send[i](sock->last_payload, sock->last_payload_len);
              
            }
            else {
              
              call Ltcp.sendFlagged[i](NULL, 0, TCP_RST);
              sock->state = TCP_CLOSED;
            }
          }
          
          break;
        
        case TCP_LAST_ACK:
          if (sock->rettim == 0) {
            sock->state = TCP_CLOSED;
          }
          
          break;
        
        default:
          break;
                
        
      }
    }
  }
  
  
  event void IPAddress.changed(bool valid) {}
  
  /* got a packet from an unknown source, send reset*/
  error_t answer_reset (struct ip6_hdr* iph, struct tcp_hdr* tcp) {
    struct ip_iovec v1;
    uint16_t t;
    struct ip6_packet pkt1;
    
    // build a RST tcp packet
    t = tcp->srcport;
    tcp->srcport = tcp->dstport;
    tcp->dstport = t;
    
    // set the ackno and set seqno to zero
    tcp->ackno = htonl(ntohl(tcp->seqno) + 1);
    tcp->seqno = 0x0;
    tcp->offset = 0x5 << 4; // options are not implemented
    tcp->flags = TCP_RST | TCP_ACK;
    tcp->window = 0x0;
    tcp->chksum = 0x0;
    tcp->urgent = 0x0;
    
    // set ip fields
    pkt1.ip6_hdr.ip6_vfc = IPV6_VERSION;
    pkt1.ip6_hdr.ip6_nxt = IANA_TCP;
    pkt1.ip6_hdr.ip6_plen = htons(sizeof(struct tcp_hdr));
    
    call IPAddress.setSource(&pkt1.ip6_hdr);
    
    v1.iov_base = (void* )tcp;
    v1.iov_len = sizeof(struct tcp_hdr);
    v1.iov_next = NULL;
    
    pkt1.ip6_data = &v1;
    
    // copy address to destination
    memcpy(&pkt1.ip6_hdr.ip6_dst, &(iph->ip6_src), 16);
    
    tcp->chksum = htons(msg_cksum(&pkt1.ip6_hdr, &v1, IANA_TCP));
    DBG("recv error: no open socket\n");
    
    if (call IP.send(&pkt1) != SUCCESS) {
      DBG("error RSTING\n");
    }
    return SUCCESS;
  }
  
  /* handles receiving IP packets */
  event void IP.recv(struct ip6_hdr *iph, 
                     void *payload, size_t len,
                     struct ip6_metadata *meta) {
    
    uint8_t option_bytes;
    
    uint8_t i;
    struct tcp_hdr *tcp;
    struct tcplib_sock *sock;
    void* payload_ptr;
    uint16_t payload_len;
    
    DBG("tcp packet received\n");
    
    // check if packet is TCP, ignore if not
    if (iph->ip6_nxt != IANA_TCP) {
      DBG("was not TCP, ignored\n");
      return;
    }
    
    tcp = (struct tcp_hdr*) payload;
    
    // check, if addressed port is on a registered socket
    for (i = 0; i <= uniqueCount("TCP_CLIENT"); i++) {
      
      // found no port, send RST on the fly
      if (i == uniqueCount("TCP_CLIENT")) {
        answer_reset(iph, tcp);
        return;
      }
      
      // legit sock found
      if (socks[i].l_ep.sin6_port == tcp->dstport) {
        if (socks[i].state != TCP_CLOSED) {
          break;
        }
        else {
          answer_reset(iph, tcp);
          return;
        }
      }
      
    }
    
    DBG("is known port\n");
    
    if (tcp->offset != (5 << 4)) {
      DBG("options not implemented, got offset of %d\n", (tcp->offset >> 4));
    //  return FAIL;
    }
    
    // calulate the width of the option field
    option_bytes = ((tcp->offset >> 4) - 5) * 4;
    
    sock = &socks[i];
    payload_ptr = payload + sizeof(struct tcp_hdr) + option_bytes;
    payload_len = len - (sizeof(struct tcp_hdr) + option_bytes);
    
    if (tcp->flags & TCP_SYN || tcp->flags & TCP_FIN) {
      /* if a SYN or a FIN was received, one need to set
       * the acknowledgement number accordingly */
      sock->ackno += 1;
    }
    
    DBG("calculated length of payload %d \n", payload_len);
    sock->ackno += payload_len;
    
    /* some special cases are valid in all or most of the states,
     * these must be caught beforehand
     */
    // no other connection possible, while ESTABLISHED, send reset
    if ( (tcp->flags & TCP_SYN) && !(sock->state == TCP_LISTEN || sock->state == TCP_SYN_SENT) ) {
      answer_reset(iph, tcp);
      return;
    }
    
    switch (sock->state) {
      case TCP_CLOSED:
        
        DBG("in TCP_CLOSED, should not be reachable\n");
        // ignore
        break;
        
      case TCP_LAST_ACK:
        
        if (tcp->flags & TCP_ACK) {
          
          DBG("connection fully closed\n");
          sock->state = TCP_CLOSED;
          signal Ltcp.closed[i](SUCCESS);
          
        }
        
        break;
        
      case TCP_FIN_WAIT_1:
        
        if (tcp->flags & (TCP_FIN | TCP_ACK)) {
          
          
          // sending ack
          if (call Ltcp.sendFlagged[i](NULL, 0 , (TCP_ACK)) != SUCCESS) {
          DBG("error sending ACK on TCP_FIN_WAIT_1\n");
          }
          
          DBG("going to TCP_CLOSING\n");
          sock->state = TCP_CLOSING;
          
        }
        else if (tcp->flags & TCP_FIN) {
          
          
          // sending ack
          if (call Ltcp.sendFlagged[i](NULL, 0 , (TCP_ACK)) != SUCCESS) {
          DBG("error sending ACK on TCP_FIN_WAIT_1\n");
          }
          
          DBG("going to TCP_TIME_WAIT\n");
          sock->state =TCP_TIME_WAIT;
          
        }
        else if (tcp->flags & TCP_ACK) {
          
          DBG("going to TCP_FIN_WAIT_2\n");
          sock->state = TCP_FIN_WAIT_2;
        }
        
        break;
        
      case TCP_FIN_WAIT_2:
        
        if (tcp->flags & TCP_FIN) {
          
          // sending ack
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_ACK)) != SUCCESS) {
          DBG("error sending ACK on TCP_FIN_WAIT_2\n");
          }
          
          DBG("going to TCP_TIME_WAIT\n");
          sock->state = TCP_TIME_WAIT;
          
        }
        
        break;
        
      case TCP_SYN_SENT:
      
        if (tcp->flags & TCP_RST) {
          
          DBG("received RST in SYN_SEND -> closing\n");
          sock->state = TCP_CLOSED;
          signal Ltcp.connectDone[i](FAIL);
          break;
        }
        else if ( (tcp->flags & TCP_SYN)  && (tcp->flags & TCP_ACK) ) {
          
          sock->ackno = ntohl(tcp->seqno) + 1;
          
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_ACK) ) != SUCCESS) {
            DBG("error while sending ACK in handshake\n");
            break;
          }
          
          signal Ltcp.connectDone[i](SUCCESS);
          sock->state = TCP_ESTABLISHED_NOMINAL;          
          break;
        }
        else if (tcp->flags & TCP_SYN) {
          
          DBG("synchronous handshake event\n");
          
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_SYN | TCP_ACK) ) != SUCCESS) {
            DBG("error while sending SINACK in handshake\n");
            break;
          }
          
          sock->state = TCP_SYN_RCVD;
          break;
          
        }
        
        
        
        break;
        
      case TCP_SYN_RCVD:
        
        if (tcp->flags & (TCP_ACK) ) {
          
          DBG("connection complete\n");
          sock->state = TCP_ESTABLISHED_NOMINAL;
          signal Ltcp.connectDone[i](SUCCESS);
          
          break;
          
        }
        
        break;
        
      case TCP_LISTEN:
        
        if (tcp->flags & TCP_SYN) {
          
          memcpy(&sock->r_ep.sin6_addr.s6_addr, &(iph->ip6_src), 16);
          sock->r_ep.sin6_port = tcp->srcport;
          
          DBG("accepting connection on sock %d\n", i);
          
          // ask user, if connection should be accepted
          if (signal Ltcp.accept[i](&(sock->r_ep), &(sock->tx_buf), &(sock->tx_buf_len))) {
          
            // set the ackno manually (+1 since SYN was received)
            sock->ackno = ntohl(tcp->seqno) + 1;
            
            sock->seqno = call Random.rand32();
            
            if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_SYN | TCP_ACK) ) != SUCCESS) {
              DBG("error while sending SYNACK\n");
              break;
            }
            
            sock->state = TCP_SYN_RCVD;
            break;
          }
          // reset connection
          else {
            if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_RST | TCP_ACK) ) != SUCCESS) {
              DBG("error while sending RST\n");
              break;
            }
            // state stays TCP_LISTEN
          }
          
        }
        else {
          
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_RST) ) != SUCCESS) {
            
            DBG("recvd packet on listen -> send rst and ignore\n");
            break;
          }
          
          break;
        }
        
        break;
      
      case TCP_CLOSING:
        
        if (tcp->flags & TCP_ACK) {
          
          DBG("going to TCP_TIME_WAIT\n");
          sock->state = TCP_TIME_WAIT;
          break;
          
        }
        
        break;
      
      case TCP_CLOSE_WAIT:
        // ignore everything
        break;
        
      case TCP_TIME_WAIT:
        // ignore everything
        break;
      
      
      // normal usage
      case TCP_ESTABLISHED_NOMINAL:
        
        // FIN and flagged packets should fall trough
        if (!(tcp->flags & TCP_FIN) && !(tcp->flags & TCP_SYN)) {
          
          // go into processing state
          sock->state = TCP_ESTABLISHED_PROCESSING;
          
          if (payload_len > 0) {
            // signal user of the data
            signal Ltcp.recv[i](payload_ptr, payload_len);
            
          }
          
          /* If the user uses send withing the recv event, the received packet gets
           * acknowledged on the answer, if not, the packet need to be acked now
           */
          if (sock->state == TCP_ESTABLISHED_PROCESSING) {
            DBG("recv did not use send, ACKing now \n");
            call Ltcp.sendFlagged[i](NULL, 0, TCP_ACK);
          }
          
          DBG("Data received\n");
          
          break;
          
        }
        
        
      case TCP_ESTABLISHED_ACKPENDING:
        
        // FIN flagged packets should fall trough
        if ( (tcp->flags & TCP_ACK) && !(tcp->flags & TCP_FIN) && !(tcp->flags & TCP_SYN) ) {
          
          // sucessfull ack
          if ( ntohl(tcp->ackno) == sock->seqno) {
            
            DBG("Packet acked\n");
            signal Ltcp.sendDone[i](SUCCESS);
            sock->state = TCP_ESTABLISHED_NOMINAL;
            
          }
          else {
            DBG("ackno did not fit seqno  ack: %d  seq:%d \n", ntohl(tcp->ackno), sock->seqno);
            return;
          }
          
          // acked packet has also data
          if (payload_len != 0) {
            signal Ltcp.recv[i](payload_ptr, payload_len);
            
            sock->ackno = tcp->seqno;
            call Ltcp.sendFlagged[i](NULL, 0, TCP_ACK);
          }
          
          break;
        }
      
      case TCP_ESTABLISHED_PROCESSING:
      default:
        
        /* if a packet was FIN flagged in any ESTABLISHED state,
         * it reaches this part of the code */
        
        DBG("Connection is to be terminated\n");
        
        // most tcp implementations seem to use this as ending
        if ( (tcp->flags & TCP_FIN) && (tcp->flags & TCP_ACK) ) {
          
          call Ltcp.sendFlagged[i](NULL, 0, (TCP_FIN | TCP_ACK));
          
          sock->retx = 0;
          sock->rettim = TCP_TIMEWAIT_TIME;
          
          sock->state = TCP_LAST_ACK;
          signal Ltcp.closed[i](SUCCESS);
          
        }
        else if (tcp->flags & TCP_FIN) {
          
          sock->retx = 0;
          sock->rettim = TCP_TIMEWAIT_TIME;
          
          sock->state = TCP_CLOSE_WAIT;
          call Ltcp.sendFlagged[i](NULL, 0, TCP_ACK);
        }
        
        break;
    }
  }
  
  
  
  /* Bind an interface to a port */
  command error_t Ltcp.bind[uint8_t client](uint16_t port) {
    struct sockaddr_in6 addr;
    
    // check, that no other socket already uses this port
    int i;
    for (i = 0; i < uniqueCount("TCP_CLIENT"); i++) {
      if (socks[i].l_ep.sin6_port == htons(port)) {
        if(socks[i].state != TCP_CLOSED) {
          DBG("Port %d was already in use\n", port);
          return FAIL;
        }
      }
    }
    
    DBG("Bound port %d \n", port);
    
    // set empty address and bounded port number into local address
    // FIXME: since IP address is not in use, just have port or make ip address usable
    memclr(addr.sin6_addr.s6_addr, 16);
    addr.sin6_port = htons(port);
    
    memcpy(&(socks[client].l_ep), &addr, sizeof(struct sockaddr_in6));
    
    // socket is ready to to listen
    socks[client].state = TCP_LISTEN;
    
    return SUCCESS;
  }
  
  
  
  /* connect the socket to a remote address */
  command error_t Ltcp.connect[uint8_t client](struct sockaddr_in6 *dest,
                                              void *tx_buf, int tx_buf_len) {
    
    
    uint16_t i;
    
    uint8_t port_found = 0;
    
    struct tcplib_sock *sock;
    sock = &socks[client];
    
    sock->tx_buf = tx_buf;
    sock->tx_buf_len = tx_buf_len;
    
    // set socket remote endpoint options
    memcpy(&(sock->r_ep), dest, sizeof(struct sockaddr_in6));
    
    switch (sock->state) {
      case TCP_CLOSED:
      
        // find a free port number greater than TCP_RESERVED_PORTS
        for (i = TCP_RESERVED_PORTS; i < 65335U; i++) {
          
          if (call Ltcp.bind[client](i) == SUCCESS) {
            port_found = 1;
            break;
          }
          
        }
        
        if (!port_found) {
          
          DBG("connect error: could not find free port\n");
          return FAIL;
        }
        
        break;
        
      case TCP_LISTEN:
        break;
      
      default:
        DBG("connect fail: wrong socket state\n");
        return FAIL;
    }
    
    // set all important stuff for that particular socket
    sock->ackno = 0;
    sock->seqno = call Random.rand32();
    
    sock->state = TCP_SYN_SENT;
    
    //FIXME: important??
    //sock->retx = 0;
    
    // send syn
    if (call Ltcp.sendFlagged[client](NULL, 0, (TCP_SYN)) != SUCCESS) {
      DBG("fail to send SYN during CONNECT\n");
      return FAIL;
    }
    
    return SUCCESS;
  }
  
  
  /* send stuff over the socket */
  command error_t Ltcp.send[uint8_t client](void *payload, uint16_t len) {
    
    error_t e;
    struct tcplib_sock *sock;
    
    sock = &socks[client];
    
    sock->last_payload = payload;
    sock->last_payload_len = len;
    
    // check if socket is in correct state
    if (sock->state != TCP_ESTABLISHED_NOMINAL && sock->state != TCP_ESTABLISHED_PROCESSING){
      DBG("send failed: sock %d not in condition to send\n", ntohs(sock->l_ep.sin6_port));
      return FAIL;
    }    
    
    // max segment size is set by the length of the provided tx_buf
    if ( len > (sock->tx_buf_len - sizeof(struct tcp_hdr))) {
      DBG("send failed: txb too small  %x : %x\n", len, (sock->tx_buf_len - sizeof(struct tcp_hdr)) );
      return FAIL;
    }
    
    if (sock->state == TCP_ESTABLISHED_NOMINAL) {
    
      e = call Ltcp.sendFlagged[client](payload, len, TCP_ACK);
      
      // set socket into ACKPENDING
      sock->state = TCP_ESTABLISHED_ACKPENDING;
      
      // set the conditions for resending
      sock->retx = 0;
      sock->rettim = TCP_RETRY_FREQ;
      
      return e;
    }
    /* if the send command is called withing a recv command
     * the other side has a pending ack
     * this gets added to this message right away */
    else if (sock->state == TCP_ESTABLISHED_PROCESSING) {
      
      e = call Ltcp.sendFlagged[client](payload, len, TCP_ACK);
      
      sock->state = TCP_ESTABLISHED_ACKPENDING;
      
      sock->retx = 0;
      sock->rettim = TCP_RETRY_FREQ;
      
    }
    else {
      return FAIL;
    }
    
    return FAIL;
  }
  
  
  
  /* send stuff over the socket and specify the flags to be set */
  command error_t Ltcp.sendFlagged[uint8_t client](void *payload, uint16_t len, 
                                              tcp_flag_t flags){
    struct ip6_packet pkt;
    struct tcp_hdr *tcp;
    struct ip_iovec v;
    struct ip_iovec w;
    
    void * inbuf_payload;
    
    struct tcplib_sock *sock;
    sock = &socks[client];
    
    
    // FIXME: check ix tx_buffer is long enough
    // TODO: options field
    
    // set tcp_hdr pointer accordingly
    tcp = sock->tx_buf;
    memclr(tcp, len + sizeof(struct tcp_hdr));
    
    /* since the iovecs only exist in this function, but the packet
     * must be kept until acknowledgement has arrived, the packet is constructed
     * inside the tx_buf. Only ip_header is rebuild on resend */
    inbuf_payload = sock->tx_buf + sizeof(struct tcp_hdr);
    memcpy(inbuf_payload, payload, len);
    
    v.iov_base = inbuf_payload;
    v.iov_len = len;
    v.iov_next = NULL;
    
    
    // fill in packet fields
    memclr(&pkt.ip6_hdr, sizeof(pkt.ip6_hdr));
    memclr(tcp, sizeof(struct tcp_hdr));
    memcpy(&pkt.ip6_hdr.ip6_dst, &(sock->r_ep.sin6_addr.s6_addr), 16);
    
    // fill the source in
    call IPAddress.setSource(&pkt.ip6_hdr);
    
    
    // set the tcp header values
    tcp->srcport = sock->l_ep.sin6_port;
    tcp->dstport = sock->r_ep.sin6_port;
    tcp->seqno = htonl(sock->seqno);
    
    // only set ackno if it is an ack packet
    if (flags & TCP_ACK) {
      tcp->ackno = htonl(sock->ackno);
    }
    else {
      tcp->ackno = 0x0;
    }
    
    tcp->offset = 0x5 << 4; // options are not implemented
    tcp->flags = flags;
    tcp->window = htons(sock->tx_buf_len); // consideration of this implementation
    tcp->chksum = 0x0; // for now
    tcp->urgent = 0x0;
    
    
    // set ip fields
    pkt.ip6_hdr.ip6_vfc = IPV6_VERSION;
    pkt.ip6_hdr.ip6_nxt = IANA_TCP;
    
    pkt.ip6_hdr.ip6_plen = htons(len + sizeof(struct tcp_hdr));
    
    w.iov_base = (void*) tcp;
    w.iov_len = sizeof(struct tcp_hdr);
    
    if (len != 0) {
      w.iov_next = &v;
    }
    else {
      w.iov_next = NULL;
    }
    
    pkt.ip6_data = &w;
    
    tcp->chksum = htons(msg_cksum(&pkt.ip6_hdr, &w, IANA_TCP));
    
    if (flags & TCP_SYN || flags & TCP_FIN) {
      sock->seqno += 1;
    }
    
    // increment seqno 
    sock->seqno += len;
    
    return call IP.send(&pkt);
    
  }
  
  
  /* the TCP active close event*/
  command error_t Ltcp.close[uint8_t client]() {
    
    struct tcplib_sock *sock;
    sock = &socks[client];
    
    DBG("closing socket\n");
    
    switch (sock->state) {
      case TCP_CLOSE_WAIT:
        
        if (call Ltcp.sendFlagged[client](NULL, 0 , (TCP_FIN)) != SUCCESS) {
          
          DBG("error sending FIN\n");
          return FAIL;
        }
        
        sock->retx = 0;
        sock->rettim = TCP_N_RETRIES;
        sock->state = TCP_LAST_ACK;
        
        return SUCCESS;
        break;
        
      case TCP_ESTABLISHED_NOMINAL:
      case TCP_ESTABLISHED_ACKPENDING:
      case TCP_ESTABLISHED_PROCESSING:
        
        if (call Ltcp.sendFlagged[client](NULL, 0 , (TCP_FIN | TCP_ACK)) != SUCCESS) {
          
          DBG("error sending FIN\n");
          return FAIL;
        }
        
        sock->retx = 0;
        sock->rettim = TCP_TIMEWAIT_TIME;
        
        sock->state = TCP_FIN_WAIT_1;
        
        return SUCCESS;
        break;
        
      case TCP_SYN_SENT:
      case TCP_LISTEN:
        sock->state = TCP_CLOSED;
        return SUCCESS;
        break;
        
      default:
        return FAIL;
    }
    
    
  }
  
  
  /* return to CLOSED state by fastest means possible */
  command error_t Ltcp.abort[uint8_t client]() {
    switch (socks[client].state) {
      case TCP_CLOSED:
        break;
      default:
        memset(&(socks[client].l_ep), 0, sizeof(struct sockaddr_in6));
        memset(&(socks[client].r_ep), 0, sizeof(struct sockaddr_in6));
        socks[client].state = TCP_CLOSED;
        
        if (call Ltcp.sendFlagged[client](NULL, 0 , (TCP_RST)) != SUCCESS) {
          
          DBG("error sending RST on abort\n");
          return FAIL;
        }
        
        DBG("socket reseted\n");
        
    }
    
    return SUCCESS;
  }

  
  
  /* ---------------- EVENTS ------------- */
  default event bool Ltcp.accept[uint8_t cid](struct sockaddr_in6 *from, 
                                             void **tx_buf, uint16_t *tx_buf_len) {
    return FALSE;
  }
  
  /* risen after handshake is fully done or aborted */
  default event void Ltcp.connectDone[uint8_t cid](error_t e) {}
  
  default event void Ltcp.sendDone[uint8_t cid](error_t e) {}
  
  /* risen, if packet is received and TCP layer preprocessing is done */
  default event void Ltcp.recv[uint8_t cid](void *payload, uint16_t len) {  }
  
  /* risen after Tcp connection is fully closed */
  default event void Ltcp.closed[uint8_t cid](error_t e) { }
  
  /* risen after packet send was acked. cannot send another packet before this happens */
  default event void Ltcp.acked[uint8_t cid]() { }
  
}