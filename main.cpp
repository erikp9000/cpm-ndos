#include <errno.h>
#include <fcntl.h> 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <dirent.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/wait.h>

#include <netinet/in.h>
#include <netinet/ip.h> /* superset of previous */
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/tcp.h>
       
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
client_map_t client_map;

// the search path for all clients
vector<string> search_path;
string root_path;

extern speed_t string_to_speed (const string& str);
extern unsigned long int speed_to_baud (const speed_t& speed);
extern speed_t baud_to_speed (const int& baud);

int listen_fd = -1;

uid_t nsh_uid;
uid_t file_uid;
gid_t file_gid;


void quit(int i)
{
    printf("Quitting...\n");
    
    if(listen_fd != -1)
    {
        close(listen_fd);
        listen_fd = -1;
    }
    
    // iterate clients and close open fds
    for(client_map_t::iterator it = client_map.begin() ;
        it != client_map.end() ;
        ++it)
    {
        it->second.close_fds();
    }
}

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
            string term = serial_ports[i].HasMember("term") ? serial_ports[i]["term"].GetString() : "";
            
			printf("port=%s baud=%d term=%s\n", port.c_str(), baud, term.c_str());
			
            int fd = -1;
            if(baud)
            {
                fd = open(port.c_str(), O_RDWR | O_NOCTTY | O_SYNC);
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
            }
            
            // add port to client map
            client_t & client = client_map[port];			
			client.init(fd, port, root_path, term);
		}

		// process clients
        if(config.HasMember("clients"))
        {
            Value& clients = config["clients"];
            for (SizeType i = 0; i < clients.Size(); i++)
            {
                string name = clients[i]["name"].GetString();
                string term = clients[i]["term"].GetString();
                
                printf("name=%s term=%s\n", name.c_str(), term.c_str());
                
                // add port to client map
                client_t & client = client_map[name];
                client.init(-1/*fd*/, name, root_path, term);
            }
        }
        
        file_uid = nsh_uid = getuid();
        
        if(config.HasMember("fileuser"))
        {
            file_uid = getpwnam(config["fileuser"].GetString())->pw_uid;
        }

        if(config.HasMember("shelluser"))
        {
            nsh_uid = getpwnam(config["shelluser"].GetString())->pw_uid;
        }
        
        file_gid = getgid();
        if(config.HasMember("filegroup"))
        {
            file_gid = getgrnam(config["filegroup"].GetString())->gr_gid;
            printf("filegroup %s = %d\n", config["filegroup"].GetString(), file_gid);
        }
	}
	else
	{
		printf("JSON parse error: %s (%l)\n",
			GetParseError_En(ok.Code()), ok.Offset());
	}
}

// This way of detecting a dead connection seems to work...
// TCP really wants an application-layer keepalive to detect dead connections.
// The USR-TCP232-302 does support a heartbeat packet which is sent at the
// application layer and might work better.
void enable_keepalive(int sock) 
{
    int yes = 1; // enable keepalive probes
    setsockopt(sock, SOL_SOCKET, SO_KEEPALIVE, &yes, sizeof(int));

    int idle = 1; // how long connection remains idle before sending keepalive probes
    setsockopt(sock, IPPROTO_TCP, TCP_KEEPIDLE, &idle, sizeof(int));

    int interval = 5; // seconds between keepalive probes
    setsockopt(sock, IPPROTO_TCP, TCP_KEEPINTVL, &interval, sizeof(int));

    int maxpkt = 3; // max keepalive probes to send before dropping connection
    setsockopt(sock, IPPROTO_TCP, TCP_KEEPCNT, &maxpkt, sizeof(int));

    int usertimeout = idle + interval * maxpkt;
    setsockopt(sock, IPPROTO_TCP,  TCP_USER_TIMEOUT, &usertimeout, sizeof(int));
}


int main()
{
    signal(SIGINT, quit); // close sockets on SIGINT
    
    read_config();
    fflush(stdout); // when running as a service, pipes buffer the output
                    // and the log is updated in bursts with long intervals

    // Get uids for specific tasks
    setgid(file_gid);
    seteuid(file_uid); // switch to file uid for safety
    umask(0);  // no mask on create file permissions
    
	// The socket server supports USR-TCP232-302 Serial to Ethernet converter
	
    struct sockaddr_in my_addr, peer_addr;
    socklen_t peer_addr_size = sizeof(peer_addr);

    memset(&my_addr, 0, sizeof(my_addr));
    my_addr.sin_family = AF_INET;
    my_addr.sin_port = htons(8234);
    my_addr.sin_addr.s_addr = INADDR_ANY;

    listen_fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0/*protocol*/);

    if (-1 == listen_fd)
    {
        printf("socket err=%d\n", errno);
        exit(1);
    }

    if(-1 == bind(listen_fd, (struct sockaddr*)&my_addr, sizeof(my_addr)))
    {
        printf("bind err=%d\n", errno);
        exit(1);
    }

    if(-1 == listen(listen_fd, 5/*connections*/))
    {
        printf("listen err=%d\n", errno);
        exit(1);
    }

    fd_set readfds;
    struct timeval timeout;
    int rv;

    do {
        FD_ZERO(&readfds);

        int max_fds = listen_fd;
        FD_SET(listen_fd, &readfds); // add the listen socket descriptor

        // add all client socket descriptors
        for(client_map_t::iterator it = client_map.begin() ;
            it != client_map.end() ;
            ++it)
        {
			it->second.add_fds(readfds, max_fds);
        }

        // set select() timeout to 20 seconds
        timeout.tv_sec = 20;
        timeout.tv_usec = 0;

        //printf("select() entered\n");
        rv = select(max_fds + 1, &readfds, NULL/*writefds*/, NULL/*exceptfds*/, &timeout);
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
        else if FD_ISSET(listen_fd, &readfds)
        {
            // accept the connection
            int fd = 
                accept (listen_fd,(struct sockaddr *) &peer_addr, &peer_addr_size);

            // accept4() should be able to set O_NONBLOCK too...
            int flags = fcntl(fd, F_GETFL, NULL);
            fcntl(fd, F_SETFL, flags | O_NONBLOCK);

            // enable kernel TCP keepalives on this socket so we can detect client disconnect
            enable_keepalive(fd);
            
            // get client IP address
            char *ip_addr = inet_ntoa(peer_addr.sin_addr);
            
            // get client hostname and service port (if possible)
            char client_name[NI_MAXHOST], client_port[NI_MAXSERV];
            getnameinfo(
                (struct sockaddr *) &peer_addr, peer_addr_size,
                client_name, sizeof(client_name),
                client_port, sizeof(client_port), 0/*flags*/);
                
            printf("Got connection (%d), client: %s (%s:%s)\n", fd, client_name, ip_addr, client_port);
            fflush(stdout);

            // lookup peer_addr in map, add it if not found
            client_t & client = client_map[client_name];

            // Check for a stale client. 
            // Should not happen since we have TCP KeepAlives enabled.
            if((client != -1) && (fd != client))
                close(client);

            client.init(fd, client_name, root_path, ""/*term*/);
        }
        else // determine which client & process received data
        {
            for(client_map_t::iterator it = client_map.begin() ;
                it != client_map.end() ;
                ++it)
            {
                // let client check for received data
                it->second.check_fds(readfds);
            }
        }
    } while(1);    
}

