#pragma once

#include <stdio.h>
#include <stdint.h>
#include <sys/types.h>
#include <dirent.h>
#include <time.h>
#include <unistd.h>

#include <vector>
#include <string>
#include <map>

// Only needed this to get a v1.0 system upgraded to v1.2
#undef BACKCOMPAT

using namespace std;

typedef vector<uint8_t> msgbuf_t;

extern vector<string> search_path;
extern string root_path;
extern uid_t nsh_uid;
extern uid_t file_uid;


#define CMD_FINDFIRST  0x02
#define CMD_FINDNEXT   0x04
#define CMD_OPENFILE   0x06
#define CMD_CLOSEFILE  0x08
#define CMD_DELETEFILE 0x0a
#define CMD_READFILE   0x0c
#define CMD_WRITEFILE  0x0e
#define CMD_CREATEFILE 0x10
#define CMD_RENAMEFILE 0x12

#define CMD_CHANGEDIR  0x20
#define CMD_MAKEDIR    0x22
#define CMD_REMOVEDIR  0x24

#define CMD_ECHO       0x30
#define CMD_SHELL      0x32


class fcb_t 
{
public:
    fcb_t() {
        //printf("fcb_t default constructor %p\n", this);
        m_hdl = -1;
        m_last_access = 0;
    }
    fcb_t (const fcb_t &obj)
    {
        //printf("fcb_t copy constructor %p\n", this);
        m_hdl = obj.m_hdl;
        m_local_filename = obj.m_local_filename;
        m_last_access = obj.m_last_access;
    }
    virtual ~fcb_t() {
        //printf("fcb_t destructor %p hdl=%d name='%s'\n", this, m_hdl, m_local_filename.c_str());
        if(-1 != m_hdl)
        {
            //printf("fcb_t close hdl=%d\n", m_hdl);
            close(m_hdl);
            m_hdl = -1;
        }
    };
    
    void set(const int hdl, const string &filename)
    {
        m_hdl = hdl;
        m_local_filename = filename;
        m_last_access = time(NULL);
    }
    void accessed()
    {
        m_last_access = time(NULL);
    }
    bool timeout(const time_t &timer)
    {
        return (m_hdl > 0) && (time(NULL) - m_last_access > timer);
    }

    const int hdl() { return m_hdl; }
    const string& local_filename() { return m_local_filename; }
    
protected:
    std::string m_local_filename;
    int m_hdl;
	time_t m_last_access;
};

// Map server file handles (from client) to the local file control block
typedef std::map<uint16_t/*file handle*/,fcb_t/*local file control block*/> fcb_map_t;

#ifdef BACKCOMPAT
// For v1.0 and v1.1 compatibility, keep FCB address from open_file() and create_file()
typedef std::map<uint16_t/*remote FCB address*/,uint16_t/*file handle*/> fcb_to_hdl_t;
#endif

class client_t 
{
public:
    client_t();
    //client_t (const client_t &obj);
    virtual ~client_t();

	void recv_request();

    void init(int fd, string name, string home_dir, string term);

    string name() { return m_name; }
	
    operator int() const { return m_fd; }

    void add_fds(fd_set& readfds, int& max_fds);
	bool check_fds(fd_set& readfds);
    
    void close_fds();

protected:
	void send_resp(const msgbuf_t &resp);

    msgbuf_t process_cmd(const msgbuf_t& msg);

    msgbuf_t open_file(const msgbuf_t& msg);
    msgbuf_t close_file(const msgbuf_t& msg);
    msgbuf_t find_first(const msgbuf_t& msg);
    msgbuf_t find_next(const msgbuf_t& msg);
    msgbuf_t delete_file(const msgbuf_t& msg);
    msgbuf_t read_file(const msgbuf_t& msg);
    msgbuf_t write_file(const msgbuf_t& msg);
    msgbuf_t create_file(const msgbuf_t& msg);
    msgbuf_t rename_file(const msgbuf_t& msg);

    msgbuf_t change_dir(const msgbuf_t& msg);
    msgbuf_t make_dir(const msgbuf_t& msg);
    msgbuf_t remove_dir(const msgbuf_t& msg);

    msgbuf_t echo(const msgbuf_t& msg);
    msgbuf_t shell(const msgbuf_t& msg);

    bool launch_shell_command(const string& commandline);
	//void send_stdout(const string& msg);
	void send_stdout(const msgbuf_t& msg);
    void send_stdout(const char *fmt, ...);
    string get_stdout();

private:
    void reset_dir();
    int get_file_handle(const msgbuf_t& msg);
    void add_utmp(void);
    void remove_utmp(void);
    
private:
    string m_cwd;                   // current working directory
    fcb_map_t m_fcbs;               // file control block map, hdl -> fcb_map_t
#ifdef BACKCOMPAT
    fcb_to_hdl_t m_fcb_to_hdl;      // compatibility map, fcb_addr -> hdl
#endif

    int m_fd;                       // I/O file descriptor for receiving & sending messages
    string m_name;                  // Hostname/IP address of the client OR serial port device name
    string m_ttyname;               // ttyname for shell()
	
	// receive buffer
	unsigned char m_buffer[512];
    int m_offset;
    int m_cnt;

	pid_t m_child_pid;		        // process ID of shell command
    int m_fd_pty;                   // pseudo terminal for remote client
	string m_shell_buf;             // the shell command stdout buffer
    string m_term;                  // remote client terminal type
    
    DIR* m_dir;                     // pointer to directory
    struct dirent *m_de;            // pointer to directory entry
    std::string m_srch_filter;      // search filter from client
    std::string m_local_filename;   // local filename matching search filter
};

typedef std::map<std::string, client_t> client_map_t;
extern client_map_t client_map;
