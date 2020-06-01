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
#include <vector>

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
vector<string> search_path;
string root_path;

extern speed_t string_to_speed (const string& str);
extern unsigned long int speed_to_baud (const speed_t& speed);
extern speed_t baud_to_speed (const int& baud);

// client receive buffer object
// struct client_buf_t {
    // client_buf_t() {
        // offset  = 0;
        // cnt = 1;
    // }
    // unsigned char buffer[512];
    // int offset;
    // int cnt;
// };

// map of file descriptors to client bufs
//typedef std::map<int, client_buf_t> client_buf_map_t;
//client_buf_map_t client_bufs;

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

    // Pure timed read. If VMIN >0, we can get out of sync and get stuck.
    tty.c_cc[VMIN] = 0;  // set to 1 to block until a byte is available
    tty.c_cc[VTIME] = 1;  // *0.1 second timer

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








void read_config()
{
	// Read config file
	ifstream ifs("config.json");
	IStreamWrapper isw(ifs);
	Document config;
	ParseResult ok = config.ParseStream(isw);

	if(ok)
	{
		printf("Parsed the config file\n");
		
		// set root directory
		string root = config["root"].GetString();
		chdir(root.c_str());
		char *d = get_current_dir_name();
		root_path = d;
		free(d);
		printf("root dir is '%s'\n", root_path.c_str());

		// set search path
		Value& path = config["path"];
		// print search path
		printf("search path is:\n");

		for (SizeType i = 0; i < path.Size(); i++)
		{
			printf("    %s\n", path[i].GetString());
			search_path.push_back(path[i].GetString());
		}
		
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
	    client.init(fd, port, root_path);
            //client.fd = fd;
            //client.name = port;
		}
	}
	else
	{
		printf("JSON parse error: %s (%l)\n",
			GetParseError_En(ok.Code()), ok.Offset());
	}
}

int main()
{
    read_config();

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
            if(it->second != -1)
            {
                FD_SET(it->second, &readfds);
                if(it->second > max_fds)
                    max_fds = it->second;
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
            if((client != -1) && (fd != client))
                close(client);

	    client.init(fd, client_name, root_path);
            //client.fd = fd;
            //client.name = client_name;
        }
        else // determine which client & process received data
        {
            for(client_map_t::iterator it = client_map.begin() ;
                it != client_map.end() ;
                ++it)
            {
                if(FD_ISSET(it->second, &readfds))
                {
                    //printf("Got data, IP address(%d): %s\n",
                    //    it->second.fd, it->second.name.c_str());
                    it->second.recv_request();
                }
            }
        }
    } while(1);

}

