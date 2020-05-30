#pragma once

#include <stdint.h>
#include <sys/types.h>
#include <dirent.h>

#include <vector>
#include <string>
#include <map>

typedef std::vector<uint8_t> msgbuf_t;

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

typedef struct fcb {
    fcb() {
        d = NULL;
        de = NULL;
        hdl = -1;
    }
    DIR* d;
    struct dirent *de;
    std::string filter;
    std::string local_filename;
    int hdl;
} fcb_t;

typedef std::map<uint16_t,fcb_t> fcb_map_t;

class client_t {
public:
    client_t() {
        cwd = ".";
        fd = -1;
    }
    virtual ~client_t() {}

    msgbuf_t process_cmd(const msgbuf_t& msg);

    int fd;           // I/O file descriptor for receiving & sending messages
    std::string name; // IP address of the client or serial port device name

protected:
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

private:
    void reset_fcb(fcb_t & fcb);
    int get_fcb_addr(const msgbuf_t& msg);

private:
    std::string cwd;  // current working directory
    fcb_map_t fcbs;  // file control block map
};



