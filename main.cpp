#include <errno.h>
#include <fcntl.h> 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include <sys/types.h>
#include <dirent.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h> /* superset of previous */
#include <arpa/inet.h>

#include <sys/select.h>
#include <sys/wait.h>

#include <map>
#include <string>

#include "client.h"

#include "rapidjson/document.h"
#include "rapidjson/writer.h"
#include "rapidjson/stringbuffer.h"
#include <iostream>
#include "rapidjson/istreamwrapper.h"
#include <fstream>
#include "rapidjson/error/en.h"
 
using namespace rapidjson;
using namespace std;


// map of client names (IP address) to client objects
typedef std::map<std::string, client_t> client_map_t;
client_map_t client_map;

// the search path for all clients
static Value _empty;
Value& search_path = _empty;

extern speed_t string_to_speed (const string& str);
extern unsigned long int speed_to_baud (const speed_t& speed);
extern speed_t baud_to_speed (const int& baud);

// client receive buffer object
struct client_buf_t {
    client_buf_t() {
        offset  = 0;
        cnt = 1;
    }
    unsigned char buffer[512];
    int offset;
    int cnt;
};

// map of file descriptors to client bufs
typedef std::map<int, client_buf_t> client_buf_map_t;
client_buf_map_t client_bufs;

int set_interface_attribs(int fd, int baud)
{
    struct termios tty;

    if (tcgetattr(fd, &tty) < 0) {
        printf("Error from tcgetattr: %s\n", strerror(errno));
        return -1;
    }

	speed_t speed = baud_to_speed(baud);
	if(speed == -1) 
	{
	    printf("Unrecognized baud rate %d\n", baud);
        return -1;
    }

	cfsetospeed(&tty, (speed_t)speed);
	cfsetispeed(&tty, (speed_t)speed);
	
    tty.c_cflag |= (CLOCAL | CREAD);    // ignore modem controls
    tty.c_cflag &= ~CSIZE;
    tty.c_cflag |= CS8;         // 8-bit characters
    tty.c_cflag &= ~PARENB;     // no parity bit
    tty.c_cflag &= ~CSTOPB;     // only need 1 stop bit
    tty.c_cflag &= ~CRTSCTS;    // no hardware flowcontrol

    // setup for non-canonical mode
    //tty.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    //tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    //tty.c_oflag &= ~OPOST;
    tty.c_iflag = IGNBRK | IGNPAR;
    tty.c_lflag = 0;
    tty.c_oflag = 0;

    // By returning after 0.1 seconds, we can cleanup the client receive buffer if we get out of sync.
	// This is good for serial ports where dropped characters are a definite possibility.
    tty.c_cc[VMIN] = 0;  // set to 1 to block until a byte is available
    tty.c_cc[VTIME] = 1;  // 0.1 second timer

    if (tcsetattr(fd, TCSANOW, &tty) != 0) {
        printf("Error from tcsetattr: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

// void set_mincount(int fd, int mcount)
// {
    // struct termios tty;

    // if (tcgetattr(fd, &tty) < 0) {
        // printf("Error tcgetattr: %s\n", strerror(errno));
        // return;
    // }

    // tty.c_cc[VMIN] = mcount ? 1 : 0;
    // tty.c_cc[VTIME] = 1; // 0.1 second timer

    // if (tcsetattr(fd, TCSANOW, &tty) < 0)
        // printf("Error tcsetattr: %s\n", strerror(errno));
// }


void send_resp(const int fd, const msgbuf_t &resp)
{
    msgbuf_t cmd = resp; // make copy so we can insert LEN and CHK

    //printf("response len=%02x: ", cmd.size());
    if(cmd.size())
    {
        unsigned char chksum = 0;

        // insert length at start of resp
        cmd.insert(cmd.begin(), 2 + cmd.size());
        // compute chksum and push to end of resp
        for(int i=0 ; i<cmd.size() ; ++i)
        {
            //printf("%02x ", cmd[i]);
            chksum += cmd[i];
        }
        cmd.push_back(~chksum + 1);
        //printf("%02x ", cmd[cmd.size()-1]);
        write(fd, cmd.data(), cmd.size());
        tcdrain(fd);    // delay for output
    }
    //printf("\n");
}


void recv_request(client_t & client)
{
    client_buf_t &cbuf = client_bufs[client.fd];

    int fd = client.fd;
    unsigned char * buf = cbuf.buffer;
    int & offset = cbuf.offset;
    int & cnt = cbuf.cnt;

    do {
//printf("recv_request (%d) entered\n", fd);
        int rdlen = read(fd, buf + offset, cnt - offset);
//printf("recv_request (%d) read returned (%d)\n", fd, rdlen);

        if(rdlen < 0)
        {
            // If there's no data to read, just return
            if(EAGAIN == errno)
            {
                offset = 0;
                cnt = 1;
                return;
            }

            // Print error and close the socket
            perror("read error");
            close(fd);
            client.fd = -1;
            client_bufs.erase(fd);
            return;
        }
        else if(rdlen == 0)
        {
            // reset buf for next message (serial)
            printf("read timeout\n");
            offset = 0;
            cnt = 1;
            return;
        }
        else
        {
            //if(0 == offset)
            //    printf("start of message, cnt=%d\n", cnt);
            //else
            //    printf("  got %d bytes of %d\n", rdlen, cnt);

            cnt = buf[0]; // number of bytes to expect
            offset += rdlen;

            if(offset >= cnt)
            {
                unsigned char chksum = 0;

                // validate checksum
                //printf("msg :");
                for(int i=0 ; i < cnt ; ++i)
                {
                    //printf("%02x ", buf[i]);
                    chksum += buf[i];
                }
                //printf(" chksum=%02x\n", chksum);

                if((0 == chksum) && (cnt > 2)) 
                {
                    // process client msg
                    msgbuf_t msg;
                    msg.assign(&buf[1], &buf[cnt - 1]);
                    msgbuf_t resp = client.process_cmd(msg);
                    send_resp(fd, resp);
                }
                else
                {
                    printf("checksum failure\n");
                    for(int i=0 ; i < cnt ; ++i)
                    {
                        printf("%02x ", buf[i]);
                        if(i % 16 == 15) printf("\n");
                    }
                    printf("\n");
                }

                // reset for next message
                offset = 0;
                cnt = 1;
            }
        }
    } while(1);
}


int main()
{
	// Read config file
	ifstream ifs("config.json");
	IStreamWrapper isw(ifs);
	Document config;
	ParseResult ok = config.ParseStream(isw);

	if(ok)
	{
		printf("Parsed the config file\n");
		
		// set search path
		search_path = config["path"];
		// print search path
		for (SizeType i = 0; i < search_path.Size(); i++)
			printf("a[%d] = %s\n", i, search_path[i].GetString());
		
		// process serial ports
		Value& serial_ports = config["serial"];
		for (SizeType i = 0; i < serial_ports.Size(); i++)
		{
			string port = serial_ports[i]["port"].GetString();
			int baud = serial_ports[i]["baud"].GetInt();
			
			printf("port=%s baud=%d\n", port.c_str(), baud);
			
			int fd = open(port.c_str(), O_RDWR | O_NOCTTY | O_SYNC);
			if (fd < 0) {
				printf("Error opening %s: %s\n", port.c_str(), strerror(errno));
				continue;
			}

			// baudrate 'baud', 8 bits, no parity, 1 stop bit
			if(0 != set_interface_attribs(fd, baud))
			{
				printf("Error setting baud rate (%d) on port %s\n", baud, port.c_str());
				close(fd);
				continue;
			}

            // add port to client map
            client_t & client = client_map[port];			
            client.fd = fd;
            client.name = port;
		}
	}
	else
	{
		printf("JSON parse error: %s (%u)\n",
			GetParseError_En(ok.Code()), ok.Offset());
	}
	
    struct sockaddr_in my_addr, peer_addr;
    socklen_t peer_addr_size = sizeof(peer_addr);

    memset(&my_addr, 0, sizeof(my_addr));
    my_addr.sin_family = AF_INET;
    my_addr.sin_port = htons(8234);
    my_addr.sin_addr.s_addr = INADDR_ANY;

    int sock_fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0/*protocol*/);
    //int sock_fd = socket(AF_INET, SOCK_STREAM, 0/*protocol*/);
    if (-1 == sock_fd)
    {
        printf("socket err=%d\n", errno);
	exit(1);
    }

    if(-1 == bind(sock_fd, (struct sockaddr*)&my_addr, sizeof(my_addr)))
    {
        printf("bind err=%d\n", errno);
	exit(1);
    }

    if(-1 == listen(sock_fd, 5/*connections*/))
    {
        printf("listen err=%d\n", errno);
	exit(1);
    }

    fd_set readfds;
    struct timeval timeout;
    int rv;

    do {
        FD_ZERO(&readfds);

        int max_fds = sock_fd;
        FD_SET(sock_fd, &readfds); // add the listen socket descriptor

        // add all client socket descriptors
        for(client_map_t::iterator it = client_map.begin() ;
            it != client_map.end() ;
            ++it)
        {
            // don't add this client if the file descriptor is invalid
            if(it->second.fd != -1)
            {
                FD_SET(it->second.fd, &readfds);
                if(it->second.fd > max_fds)
                    max_fds = it->second.fd;
            }
        }

        timeout.tv_sec = 20;
        timeout.tv_usec = 0;

//printf("select() entered\n");
        rv = select(max_fds + 1, &readfds, NULL, NULL, &timeout);
//printf("select() returned (%d)\n", rv);
        if(rv == -1)
        {
            perror("select");
            exit(1);
        }
        else if(rv == 0)
        {
            //printf("timeout occurred (20 second) \n");
            //return 1;
        }
        else if FD_ISSET(sock_fd, &readfds)
        {
            // accept the connection
            int fd = 
                accept (sock_fd,(struct sockaddr *) &peer_addr, &peer_addr_size);

            // accept4() should be able to set O_NONBLOCK too...
            int flags = fcntl(fd, F_GETFL, NULL);
            fcntl(fd, F_SETFL, flags | O_NONBLOCK);

            // get client IP address
            char *client_name = inet_ntoa(peer_addr.sin_addr);
            printf("Got connection, IP address (%d): %s\n", fd, client_name);

            // lookup peer_addr in map, add it if not found
            client_t & client = client_map[client_name];

            // A stale file descriptor can happen when the serial-to-
            // ethernet translator is unplugged because Linux doesn't
            // generate any signal when the other side of a TCP socket
            // disappears without a proper close socket negotiation.
            // Yep. Tried passing exception fds to select().
            if((client.fd != -1) && (fd != client.fd))
                close(client.fd);

            client.fd = fd;
            client.name = client_name;
        }
        else // determine which client & process received data
        {
            for(client_map_t::iterator it = client_map.begin() ;
                it != client_map.end() ;
                ++it)
            {
                if(FD_ISSET(it->second.fd, &readfds))
                {
                    //printf("Got data, IP address(%d): %s\n",
                    //    it->second.fd, it->second.name.c_str());
                    recv_request(it->second);
                }
            }
        }
    } while(1);

}

