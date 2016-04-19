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

/* the period between to calls to the timer process in milliseconds*/
#ifndef TCP_PROCESS_TIME
  #define TCP_PROCESS_TIME 1024
#endif

/* all ports below this one are reserved and will not be used on connect */



/* number of retries before giving up */
#ifndef TCP_N_RETRIES
  #define TCP_N_RETRIES 6
#endif

#ifdef DEBUG_OUT
  #include <printf.h>
  #define DBG(...) printf(__VA_ARGS__); printfflush()
#else
  #define DBG(...) 
#endif

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
      
      // set complete struct to 0
      memset(sock, 0, sizeof(struct tcplib_sock) - sizeof(struct tcplib_sock *));
      sock->mss = 200;
      sock->my_wind = 0;
      sock->cwnd = sock->mss;
      sock->ssthresh = 0xffff;
      return SUCCESS;
      
    }
  }

  /* --------------- Implemented events ------------------ */
  
  /* Starts the timer once bootup is complete */
  event void Boot.booted() {
    call Timer.startPeriodic(TCP_PROCESS_TIME);
  }
  
  /* process time specific parts */
  event void Timer.fired() {
    /* TODO: process time spefic part */
    
    
    
  }
  
  
  event void IPAddress.changed(bool valid) {}
  
  
  /* handles receiving IP packets */
  event void IP.recv(struct ip6_hdr *iph, 
                     void *payload, size_t len,
                     struct ip6_metadata *meta) {
    
    uint8_t i;
    struct tcp_hdr *tcp;
    struct tcplib_sock *sock;
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
      if (i == uniqueCount("TCP_CLIENT")) {
        
        DBG("recv error: no open socket\n");
        // TODO: reset on closed
        
        return;
      }
      
      if (socks[i].l_ep.sin6_port == tcp->srcport) {
        break;
      }
      
    }
    
    sock = &socks[i];
    payload_len = len - sizeof(struct tcp_hdr) - (tcp->offset/4);
    
    // TODO:check if socket is in condition to receive FIXME: needed???
    
    
    
    switch (sock->state) {
      case TCP_CLOSED:
        
        // closed connection dont like your presence
        if (call Ltcp.sendFlagged[i](NULL, 0 , (TCP_RST)) != SUCCESS) {
          
          DBG("error sending RST on CLOSED\n");
          return;
        }
        
        break;
        
      case TCP_LAST_ACK:
        break;
        
      case TCP_FIN_WAIT_1:
        break;
        
      case TCP_FIN_WAIT_2:
        break;
        
      case TCP_SYN_SENT:
        
        if (tcp->flags & (TCP_SYN | TCP_ACK) ) {
          
          if (payload_len != 0) {
            DBG("SYN contained data -> ignoring data\n");
          }
          
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_SYN | TCP_ACK) ) != SUCCESS) {
            
            DBG("error while sending ACK in handshake\n");
            return;
          }
          
          sock->state = TCP_ESTABLISHED;
          sock->internal_state = TCP_NOMINAL;
          
          return;
          
        }
        
        break;
        
      case TCP_SYN_RCVD:
        
        if (tcp->flags & (TCP_ACK) ) {
          
        }
        
        break;
        
      case TCP_LISTEN:
        
        // is it syn packet
        if (tcp->flags & TCP_SYN) {
          
          if (payload_len != 0) {
            DBG("SYN contained data -> ignoring data\n");
          }
          
          // set the ackno manually
          sock->ackno = tcp->seqno;
          
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_SYN | TCP_ACK) ) != SUCCESS) {
            
            DBG("error while sending SYNACK\n");
            return;
          }
          
          sock->state = TCP_SYN_RCVD;
          return;
          
        }
        else {
          
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_RST) ) != SUCCESS) {
            
            DBG("recvd packet on listen -> ignoring\n");
            return;
          }
          
          return;
        }
        
        break;
        
      case TCP_CLOSE_WAIT:
        break;
        
      case TCP_TIME_WAIT:
        break;
      
      case TCP_ESTABLISHED:
        break;
        
      default:
        DBG("something really bad has happened\n");
        break;
    }
    
    
    
  }
  
  
  
  /* Bind an interface to a port */
  command error_t Ltcp.bind[uint8_t client](uint16_t port) {
    struct sockaddr_in6 addr;
    
    // check, that no other socket already uses this port
    int i;
    for (i = 0; i < uniqueCount("TCP_CLIENT"); i++) {
      if (socks[i].l_ep.sin6_port == port) {
        DBG("Port %d was already in use\n", port);
        return FAIL;
      }
    }
    
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
    struct tcplib_sock *sock;
    sock = &socks[client];
    
    sock->tx_buf = tx_buf;
    sock->tx_buf_len = tx_buf_len;
    
    
    switch (sock->state) {
    case TCP_CLOSED:
      // connect socket without bind -- binds random free port TODO: implement it
      return FAIL;
      
    case TCP_LISTEN:
      break;
    
    default:
      return FAIL;
    }
    
    // set all important stuff for that particular socket
    sock->ackno = 0;
    sock->seqno = call Random.rand16();
    
    sock->state = TCP_SYN_SENT;
    sock->seqno++;
    sock->retx = 0;
    
    return SUCCESS;
  }
  
  
  /* send stuff over the socket */
  command error_t Ltcp.send[uint8_t client](void *payload, uint16_t len) {
    return call Ltcp.sendFlagged[client](payload, len, 0x0);
  }
  
  
  
  /* send stuff over the socket and specify the falgs to be set */
  command error_t Ltcp.sendFlagged[uint8_t client](void *payload, uint16_t len, 
                                              tcp_flag_t flags){
    struct ip6_packet pkt;
    struct tcp_hdr *tcp;
    struct tcplib_sock *sock;
    struct ip_iovec v;
    struct ip_iovec w;
    
    void * inbuf_payload;
    
    sock = &socks[client];
    
    // check if socket is in correct state
    if (sock->state != TCP_ESTABLISHED) {
      DBG("send failed: connection was not established\n");
      return FAIL;
    }
    
    // this tcp implementation only allows for one unacknowledged packet
    if ( !(sock->internal_state & TCP_ACKPENDING) ) {
      DBG("send failed: txb contained unprocessed data");
      return FAIL;
    }
    
    // max segment size is set by the length of the provided tx_buf
    if ( len > (sock->tx_buf_len - sizeof(struct tcp_hdr))) {
      DBG("send failed: txb too small");
      return FAIL;
    }
    
    /* since the iovecs only exist in this function, but the packet
     * must be kept until acknowledgement has arrived, the packet is constructed
     * inside the tx_buf. Only ip_header is rebuild on resend */
    inbuf_payload = sock->tx_buf + sizeof(struct tcp_hdr);
    memcpy(inbuf_payload, payload, len);
    
    v.iov_base = inbuf_payload;
    v.iov_len = len;
    v.iov_next = NULL;
    
    // set tcp_hdr pointer accordingly
    tcp = sock->tx_buf;
    
    // fill in packet fields
    memclr((uint8_t *)&pkt.ip6_hdr, sizeof(pkt.ip6_hdr));
    memclr((uint8_t *)&tcp, sizeof(tcp));
    memcpy(&pkt.ip6_hdr.ip6_dst, &(sock->r_ep.sin6_addr.s6_addr), 16);
    
    // fill the source in
    call IPAddress.setSource(&pkt.ip6_hdr);
    
    /* FIXME: htonl for network addresses necessary????              
    */
    
    // set the tcp header values
    tcp->srcport = sock->l_ep.sin6_port;
    tcp->dstport = sock->r_ep.sin6_port;
    tcp->seqno = htonl(sock->seqno);
    tcp->ackno = htonl(sock->ackno);
    tcp->offset = 0x5; // options are not implemented
    tcp->flags = flags;
    tcp->window = 0x0; // consideration of this implementation
    tcp->chksum = 0x0; // for now
    tcp->urgent = 0x0;
    
    
    // set ip fields
    pkt.ip6_hdr.ip6_vfc = IPV6_VERSION;
    pkt.ip6_hdr.ip6_nxt = IANA_TCP;
    pkt.ip6_hdr.ip6_plen = (len + sizeof(struct tcp_hdr));
    
    w.iov_base = (uint8_t *)&tcp;
    w.iov_len = sizeof(struct tcp_hdr);
    w.iov_next = &v;
    
    pkt.ip6_data = &w;
    
    tcp->chksum = htons(msg_cksum(&pkt.ip6_hdr, &w, IANA_TCP));
    
    // set socket into TCP_ACKPENDING
    sock->internal_state |= TCP_ACKPENDING;
    
    // increment seqno
    sock->seqno += len;
    
    return call IP.send(&pkt);
    
  }
  
  
  /* close connection and raise closed */
  command error_t Ltcp.close[uint8_t client]() {
    //if (!tcplib_close(&socks[client]))
    struct tcplib_sock *sock;
    sock = &socks[client];
    
    DBG("closing socket\n");
    
    switch (sock->state) {
      case TCP_CLOSE_WAIT:
        sock->retx = 0;
        sock->state = TCP_LAST_ACK;
        
        if (call Ltcp.sendFlagged[client](NULL, 0 , (TCP_ACK | TCP_FIN)) != SUCCESS) {
          
          DBG("error sending FINACK\n");
          return FAIL;
        }
        
        return SUCCESS;
        break;
        
      case TCP_ESTABLISHED:
        
        sock->retx = 0;
        sock->state = TCP_FIN_WAIT_1;
        
        if (call Ltcp.sendFlagged[client](NULL, 0 , (TCP_ACK | TCP_FIN)) != SUCCESS) {
          
          DBG("error sending FINACK\n");
          return FAIL;
        }
        
        return SUCCESS;
        break;
        
      case TCP_SYN_SENT:
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
      case TCP_LISTEN:
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
                                             void **tx_buf, int *tx_buf_len) {
    return FALSE;
  }
  
  /* risen after handshake is fully done or aborted */
  default event void Ltcp.connectDone[uint8_t cid](error_t e) {}
  
  /* risen, if packet is received and TCP layer preprocessing is done */
  default event void Ltcp.recv[uint8_t cid](void *payload, uint16_t len) {  }
  
  /* risen after Tcp connection is fully closed */
  default event void Ltcp.closed[uint8_t cid](error_t e) { }
  
  /* risen after packet send was acked. cannot send another packet before this happens */
  default event void Ltcp.acked[uint8_t cid]() { }
  
}