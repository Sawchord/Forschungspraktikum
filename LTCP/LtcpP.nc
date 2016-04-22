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
      sock->mss = 200;
      sock->my_wind = 0;
      sock->cwnd = sock->mss;
      sock->ssthresh = 0xffff;
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
      
      sock = &socks[i];
      
      // if socket in time dependent state, update time
      if (sock->state == TCP_TIME_WAIT || sock->state == TCP_ESTABLISHED_ACKPENDING) {
        if ( ((int32_t) sock->rettim - TCP_PROCESS_TIME) > 0) {
          sock->rettim = 0;
        }
        else {
          sock->rettim -= TCP_PROCESS_TIME;
        }
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
              
              sock->retx++;
              call Ltcp.send[i](sock->last_payload, sock->last_payload_len);
              
            }
            else {
              
              // send fails permanen -> signal user the fail
              sock->state = TCP_ESTABLISHED_NOMINAL;
              signal Ltcp.sendDone[i](FAIL);
              
            }
            
          }
          
          break;
          
        default:
          break;
                
        
      }
    }
  }
  
  
  event void IPAddress.changed(bool valid) {}
  
  
  /* handles receiving IP packets */
  event void IP.recv(struct ip6_hdr *iph, 
                     void *payload, size_t len,
                     struct ip6_metadata *meta) {
    
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
      if (i == uniqueCount("TCP_CLIENT")) {
        
        DBG("recv error: no open socket\n");
        // TODO: send rst without sock  on closed
        
        return;
      }
      
      if (socks[i].l_ep.sin6_port == htons(tcp->srcport) ) {
        break;
      }
      
    }
    
    sock = &socks[i];
    payload_ptr = tcp + sizeof(struct tcp_hdr) + (tcp->offset);
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
        
        if (tcp->flags & (TCP_SYN | TCP_ACK) ) {
          
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
        else if (tcp->flags & TCP_RST) {
          
          DBG("received RST in SYN_SEND -> closing\n");
          sock->state = TCP_CLOSED;
          signal Ltcp.connectDone[i](FAIL);
          break;
        }
        
        
        break;
        
      case TCP_SYN_RCVD:
        
        if (tcp->flags & (TCP_ACK) ) {
          
          if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_ACK) ) != SUCCESS) {
              DBG("error while sending ACK in TCP_SYN_RCVD\n");
              break;
            }
          DBG("connection complete\n");
          sock->state = TCP_ESTABLISHED_NOMINAL;
          
          signal Ltcp.connectDone[i](SUCCESS);
          
          break;
          
        }
        
        break;
        
      case TCP_LISTEN:
        
        if (tcp->flags & TCP_SYN) {
          
          // ask user, if connection should be accepted
          if (signal Ltcp.accept[i](&(sock->r_ep), (sock->tx_buf), &(sock->tx_buf_len))) {
          
            // set the ackno manually
            sock->ackno = tcp->seqno;
            sock->seqno = tcp->ackno;
            
            if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_SYN | TCP_ACK) ) != SUCCESS) {
              DBG("error while sending SYNACK\n");
              break;
            }
            
            sock->state = TCP_SYN_RCVD;
            break;
          }
          // else reset connection
          else {
            if (call Ltcp.sendFlagged[i](NULL, 0, (TCP_SYN | TCP_ACK) ) != SUCCESS) {
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
      //TODO
        break;
      
      case TCP_ESTABLISHED_ACKPENDING:
      //TODO
        break;
        
      case TCP_ESTABLISHED_PROCESSING:
      //TODO
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
      if (socks[i].l_ep.sin6_port == htons(port)) {
        DBG("Port %d was already in use\n", port);
        return FAIL;
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
    uint8_t j;
    
    uint8_t port_found = 0;
    
    struct tcplib_sock *sock;
    sock = &socks[client];
    
    sock->tx_buf = tx_buf;
    sock->tx_buf_len = tx_buf_len;
    
    // set socket remote endpoint options
    memcpy(&(sock->l_ep), dest, sizeof(struct sockaddr_in6));
    
    switch (sock->state) {
    case TCP_CLOSED:
    
      // find a free port number greater than TCP_RESERVED_PORTS
      for (i = TCP_RESERVED_PORTS; i < 65335U; i++) {
        
        if (call Ltcp.bind[client](i) == SUCCESS) {
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
    sock->seqno = call Random.rand16();
    
    sock->state = TCP_SYN_SENT;
    sock->retx = 0;
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
    if (sock->state != TCP_ESTABLISHED_NOMINAL) {
      DBG("send failed: connection was not established\n");
      return FAIL;
    }    
    
    // max segment size is set by the length of the provided tx_buf
    if ( len > (sock->tx_buf_len - sizeof(struct tcp_hdr))) {
      DBG("send failed: txb too small\n");
      return FAIL;
    }
    
    if (sock->state == TCP_ESTABLISHED_NOMINAL) {
    
      e = call Ltcp.sendFlagged[client](payload, len, 0x0);
      
      // set socket into ACKPENDING
      sock->state = TCP_ESTABLISHED_ACKPENDING;
      
      return e;
    }
    else {
      return FAIL;
    }
  }
  
  
  
  /* send stuff over the socket and specify the falgs to be set */
  // TODO: make it an internal call
  command error_t Ltcp.sendFlagged[uint8_t client](void *payload, uint16_t len, 
                                              tcp_flag_t flags){
    struct ip6_packet pkt;
    struct tcp_hdr *tcp;
    struct tcplib_sock *sock;
    struct ip_iovec v;
    struct ip_iovec w;
    
    void * inbuf_payload;
    
    sock = &socks[client];
    
    
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
    
    
    // increment seqno
    sock->seqno += len;
    
    return call IP.send(&pkt);
    
  }
  
  
  /* the TCP active close event*/
  command error_t Ltcp.close[uint8_t client]() {
    //if (!tcplib_close(&socks[client]))
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
        sock->state = TCP_LAST_ACK;
        
        return SUCCESS;
        break;
        
      case TCP_ESTABLISHED_NOMINAL:
      case TCP_ESTABLISHED_ACKPENDING:
      case TCP_ESTABLISHED_PROCESSING:
        
        if (call Ltcp.sendFlagged[client](NULL, 0 , (TCP_FIN)) != SUCCESS) {
          
          DBG("error sending FIN\n");
          return FAIL;
        }
        
        sock->retx = 0;
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