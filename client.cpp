#include "client.h"
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <malloc.h>
#include <unistd.h>
#include <time.h>

#include <termios.h>
#include <unistd.h>

#include <sys/wait.h>
#include <stdlib.h>
#include <pty.h>
#include <stdarg.h>
#include <signal.h>
#include <utmp.h>
#include <pwd.h>

#include <iostream>
#include <sstream>
#include <bitset>
#include <iomanip>

#undef DEBUG

uint32_t getTick() 
{
    struct timespec ts;
    unsigned theTick = 0U;
    clock_gettime( CLOCK_MONOTONIC, &ts );
    theTick  = ts.tv_nsec / 1000000;
    theTick += ts.tv_sec * 1000;
    return theTick;
}

std::string hexStr(unsigned char* data, int len)
{
    std::stringstream ss;
    ss << std::hex;
    for(int i=0;i<len;++i)
        ss << std::setw(2) << std::setfill('0') << (int)data[i];
    return ss.str();
}

const int MAX_FILENAME_LEN = 11;
const time_t FILE_TIMEOUT = 5*60;

const char* BAD_DIRECTORY = "Bad directory";

client_t::client_t()
{
    m_fd = -1;
    m_cwd = "";

    m_child_pid = -1;
    m_fd_pty = -1;

    m_dir = NULL;
    m_de = NULL;
        
    init(-1/*fd*/, ""/*name*/, ""/*home_dir*/, "dumb"/*term*/);
    
    m_lasttime = 0;
}

client_t::~client_t()
{
    close_fds();
}

void client_t::close_fds(void)
{
    if(-1 != m_fd)
    {
       //printf("client_t close '%s' m_fd=%d\n", name().c_str(), m_fd);
       close(m_fd);
       m_fd = -1;
    }
    if(-1 != m_fd_pty)
    {
       //printf("client_t close shell m_fd_pty=%d\n", m_fd_pty);
       close(m_fd_pty);
       m_fd_pty = -1;
    }
    
    // Close all file handles
    m_fcbs.clear();
}

void client_t::init(int fd, string name, string home_dir, string term) 
{
    printf("client_t::init(%p) %d, %s, %s, %s\n", this, fd, name.c_str(), home_dir.c_str(), term.c_str());
    
    m_fd = fd;
    if(name.length()) m_name = name;
    if(!m_cwd.length()) m_cwd = root_path;
    if(home_dir.length()) {
        m_cwd = m_cwd + "/" + home_dir;
        printf("%s home directory is: %s\n", name.c_str(), m_cwd.c_str());
    }
    if(term.length()) m_term = term;
    
    m_offset = 0;
    m_cnt = 1;
}

    
// Set my active file descriptors in readfds.
void client_t::add_fds(fd_set& readfds, int& max_fds)
{
	// This is the primary client file descriptor
	if(-1 != m_fd) 
	{
		FD_SET(m_fd, &readfds);
		if(m_fd > max_fds)
			max_fds = m_fd;
	}

    // This is the shell process stdout which we will queue to the client
	if(-1 != m_fd_pty) 
	{
		FD_SET(m_fd_pty, &readfds);
		if(m_fd_pty > max_fds)
			max_fds = m_fd_pty;
	}
}


// Check if one of my file descriptors raised a signal in readfds. If so,
// process the input data.
bool client_t::check_fds(fd_set& readfds)
{
    bool retval = false;
    
	if(FD_ISSET(m_fd, &readfds))  // input from client
	{
        retval = true;
		recv_request();
        fflush(stdout);
	}
	
    if(FD_ISSET(m_fd_pty, &readfds)) // output from shell command
	{
        retval = true;
		msgbuf_t msg(1024);
		int rdlen = read(m_fd_pty, msg.data(), msg.size());
		if(rdlen > 0) // -1 is returned when the child process dies
        {
            msg.resize(rdlen);
            send_stdout(msg);
        }
        else
        {
            printf("child exited\n");
            close(m_fd_pty);
            m_fd_pty = -1;
        }
        fflush(stdout);
	}
		
	return retval;
}


// This function manages the receive buffer for a client.
// Here a request is assembled and if the checksum is valid,
// then the command is processed and a response is sent.
// The function handles partial requests so it can be 
// called multiple times with chunks of the full request.
void client_t::recv_request()
{
    do {
        // Communications breaks can lead to orphaned data which would leave
        // the buffer out-of-sync forever. Detect and discard orphaned data here.
        // 20 mS is fine for hardwired connections but 100 is better for WiFi
        if(getTick() - m_lasttime > 100)
        {
            m_offset = 0;
            m_cnt = 1;
        }
        m_lasttime = getTick();
        
        int rdlen = read(m_fd, m_buffer + m_offset, m_cnt - m_offset);
#ifdef DEBUG
		printf("recv_request (%d) read returned (%d)\n", m_fd, rdlen);
        string hexbytes = hexStr(&m_buffer[m_offset], rdlen);
        printf("%s\n", hexbytes.c_str());
#endif

        if(rdlen < 0)
        {
            // If there's no data to read, just return
            if(EAGAIN == errno)
            {
                // Don't know why, but Windows triggers this condition alot especially over WiFi.
                //printf("recv_request (%d) read error: %d\n", m_fd, errno);
                return;
            }

            // Print error and close the socket
            printf("recv_request (%d) read error: %s\n", m_fd, strerror(errno));
            close_fds();
            return;
        }
        else if(rdlen == 0)
        {
            // if no characters, the socket was closed by the other side
            printf("recv_request (%d) socket closed: %s\n", m_fd, strerror(errno));
            close_fds();
            return;
        }
        else
        {
#ifdef DEBUG
            if(0 == m_offset)
                printf("start of message, cnt=%d\n", m_cnt);
            else
                printf("  got %d bytes of %d\n", rdlen, m_cnt);
#endif

            m_cnt = m_buffer[0]; // number of bytes to expect
            m_offset += rdlen;

            if(m_offset >= m_cnt)
            {
                unsigned char chksum = 0;

                // validate checksum
                for(int i=0 ; i < m_cnt ; ++i)
                {
                    chksum += m_buffer[i];
                }
#ifdef DEBUG
                string hexbytes = hexStr(&m_buffer[0], m_cnt);
                printf("msg: %s chksum=%02x\n", hexbytes.c_str(), chksum);
#endif

                if((0 == chksum) && (m_cnt > 2)) 
                {
                    // process client msg
                    msgbuf_t msg;
                    msg.assign(&m_buffer[1], &m_buffer[m_cnt - 1]);
                    msgbuf_t resp = process_cmd(msg);
                    send_resp(resp);
                }
                else
                {
                    printf("recv_request (%d) checksum failure\n", m_fd);
                    string hexbytes = hexStr(&m_buffer[0], m_cnt);
                    printf("msg: %s chksum=%02x\n", hexbytes.c_str(), chksum);
                }

                // reset for next message
                m_offset = 0;
                m_cnt = 1;

                return; // let someone else get something done
            }
        }
    } while(1);
}

void client_t::send_resp(const msgbuf_t &resp)
{
    msgbuf_t cmd = resp; // make copy so we can insert LEN and CHK

    if(cmd.size())
    {
        unsigned char chksum = 0;

        // insert length at start of resp
        cmd.insert(cmd.begin(), 2 + cmd.size());
        // compute chksum and push to end of resp
        for(int i=0 ; i<cmd.size() ; ++i)
        {
            chksum += cmd[i];
        }
        cmd.push_back(~chksum + 1);
        write(m_fd, cmd.data(), cmd.size());
        tcdrain(m_fd);    // delay for output
    }
#ifdef DEBUG
    string hexbytes = hexStr(cmd.data(), cmd.size());
    printf("resp len=%02x: %s\n", cmd.size(), hexbytes.c_str());
#endif
}

msgbuf_t client_t::process_cmd(const msgbuf_t& msg)
{
    //printf("process_cmd:\n");

    msgbuf_t resp;
    switch(msg[0])
    {
        case CMD_FINDFIRST:
            resp = find_first(msg);
            break;
        case CMD_FINDNEXT:
            resp = find_next(msg);
            break;
        case CMD_OPENFILE:
            resp = open_file(msg);
            break;
        case CMD_CLOSEFILE:
            resp = close_file(msg);
            break;
        case CMD_DELETEFILE:
            resp = delete_file(msg);
            break;
        case CMD_READFILE:
            resp = read_file(msg);
            break;
        case CMD_WRITEFILE:
            resp = write_file(msg);
            break;
        case CMD_CREATEFILE:
            resp = create_file(msg);
            break;
        case CMD_RENAMEFILE:
            resp = rename_file(msg);
            break;

        case CMD_CHANGEDIR:
            resp = change_dir(msg);
            break;
        case CMD_MAKEDIR:
            resp = make_dir(msg);
            break;
        case CMD_REMOVEDIR:
            resp = remove_dir(msg);
            break;

        case CMD_ECHO:
            resp = echo(msg);
            break;
        case CMD_SHELL:
            resp = shell(msg);
            break;

	default:
	    printf("Unrecognized cmd=%02x\n", msg[0]);
    }

    return resp;
}


void client_t::reset_dir()
{
    m_srch_filter.clear();
    //m_local_filename.clear();

    if(m_dir)
    {
#ifdef DEBUG
        printf("reset_dir: closedir()\n");
#endif
        closedir(m_dir);
        m_dir = NULL;
    }
}


int client_t::get_file_handle(const msgbuf_t& msg)
{
    // v1.2 expects the client to send the server file handle
    // and its 2's complement
	if(0 == ((msg[1] + msg[2]) & 255))
		return msg[1];
#ifdef BACKCOMPAT
else
    {
        // v1.0 and 1.1 used FCB address instead of the file handle
        // Using the FCB address as a synonym for a file handle didn't
        // work in all cases because some programs moved the FCB data
        // for different files into and out of the same FCB address.
        int fcb_addr = msg[1] + 256 * msg[2];
        fcb_to_hdl_t::iterator it = m_fcb_to_hdl.find(fcb_addr);
        if(it != m_fcb_to_hdl.end())
        {
            return it->second; // return file handle
        }        
    }
#endif
	return -1; // bad file handle
}

// TODO handle long filenames by hashing name to a CRC
static string GetShortFilename(char* name)
{
    int i,j;
    string retstr(MAX_FILENAME_LEN, ' ');

    for(i=0, j=0 ; (j<MAX_FILENAME_LEN) && (name[i]) ; ++i,++j)
    {
        if(name[i] == '.')
            j = 7;
        else
            retstr[j] = toupper(name[i]);
    }

    return retstr;
}

static string cpm2linux(const char* str, size_t len)
{
    string filename(str, len);

    filename.insert(8, ".");
//printf("%s\n", filename.c_str());

    for(int i=0 ; i<filename.length() ; ++i) 
    {
        filename[i] &= 0x7F;
        if(filename[i] == ' ') filename.erase(i--, 1);
        else filename[i] = tolower(filename[i]);
//printf("%s\n", filename.c_str());
    }

    if(filename[filename.length()-1] == '.')
        filename.erase(filename.length()-1);

//printf("%s\n", filename.c_str());
    return filename;
}

// Inputs:
//   1-byte command
//   2-byte client FCB address (not used)
//   8-byte filename
//   3-byte extension
//     '?' matches any character in filename/extension
// Outputs:
//   1-byte command+1
//   2-byte copied from request
//   1-byte status (0=success, 0xFF=failure)
//   8-byte filename
//   3-byte extension (R/O=msb t1, SYS=msb t2)
//   1-byte EX
//   1-byte S1
//   1-byte S2
//   1-byte RC
//
//   Or at end of directory
//   1-byte command+1
//   2-byte copied from request
//   1-byte 0xFF
//
// If successful:
//    m_dir points to the opened dircectory
//    m_de points to the directory entry
//    m_srch_filter is the search filter from the client
//    m_local_filename is the matching local filename
//    m_full_path is the full pathname of the local file
//   
msgbuf_t client_t::find_first(const msgbuf_t& msg)
{
    reset_dir();

#ifdef DEBUG
    printf("find_first: open dir '%s'\n", m_cwd.c_str());
#endif
    m_dir = opendir(m_cwd.c_str());

	// TODO Improve on this using the 20-second timeout in main socket loop
	// CP/M isn't good about closing files that were only read.
	// So if a file handle was opened 'a long time ago' and not 
	// recently accessed, we will close it here.
	for(fcb_map_t::iterator it = m_fcbs.begin() ; it != m_fcbs.end() ; )
	{
		if(it->second.timeout(FILE_TIMEOUT))
		{
			printf("Timeout, closing file (%d) '%s'\n", 
				it->second.hdl(), 
				it->second.local_filename().c_str());
		
            //printf("Calling fcb erase\n");
            fcb_map_t::iterator era_it = it++;
			m_fcbs.erase(era_it);
		}
        else
            ++it;
	}
	
    return find_next(msg);
}


// Inputs:
//   1-byte command
//   2-byte client FCB address (not used)
//   8-byte filename
//   3-byte extension
//     '?' matches any character in filename/extension
// Outputs:
//   See find_first()
//
msgbuf_t client_t::find_next(const msgbuf_t& msg)
{
    msgbuf_t resp(4); // end of directory response

    // Extract the filter - this is needed for CRCK44.COM which changes the 
    // ambiguous filename on find_next.
    // Check msg.size() for backwards compatibility with NDOS 1.0 & early 1.1
	if(msg.size() > 3)
	{
		m_srch_filter.clear();
		m_srch_filter.resize(MAX_FILENAME_LEN);
		for(size_t i=0 ; i < MAX_FILENAME_LEN ; ++i)
			m_srch_filter[i] = msg[3+i] & 0x7f;
	}
	   
#ifdef DEBUG
    printf("find_next: filter='%s'\n", m_srch_filter.c_str());
#endif

    // copy 'ignored' field to response
    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];
    resp[3] = 0xFF; // end of directory

    if(m_dir) do
    {
        m_de = readdir(m_dir);

		if(!m_de) break;

        m_local_filename = m_de->d_name;

        // search for a file that matches filter
        string name;
        struct stat details;
		m_full_path = m_cwd + "/" + m_local_filename;
        stat(m_full_path.c_str(), &details);

        if(S_ISDIR(details.st_mode))
        {
            name = m_de->d_name;


            // This format doesn't look nice on STAT.COM
            //if(name.length() < 9)
            //{
            //    for(int i = 9 - name.length() ; i ; --i)
            //        name += " ";
            //}
            //else name.resize(9);
            //name += "DIR";

            // This format allows STAT.COM to sort directories
            // at the beginning of the list
            if(name.length() > 9) name.resize(9);
            name.insert((size_t)0,(size_t)1,'<');
            name.insert(name.length(),(size_t)1,'>');
            if(name.length() < MAX_FILENAME_LEN)
            {
                for(int i = MAX_FILENAME_LEN - name.length() ; i ; --i)
                    name += " ";
            }
        }
        else if(S_ISREG(details.st_mode))
        {
            name = GetShortFilename(m_de->d_name);
        }
        else
        {
            printf("Unknown filetype st_mode=%d?\n", details.st_mode);
            continue; // check next entry
        }

#ifdef DEBUG
		printf("find_next: short filename='%s'\n", name.c_str());
#endif

        bool bMatch = true;
        for(int i=0 ; i<MAX_FILENAME_LEN ; ++i) 
        {
            if((name[i] != m_srch_filter[i]) &&
               (m_srch_filter[i] != '?'))
            {
               bMatch = false;
               break;
            }
        }

        if(bMatch) 
        {
#ifdef DEBUG
			printf("find_next: Match!\n");
#endif
            const size_t file_off = 4;
            const size_t ext_off = 12;
            const size_t ex = 15;
            const size_t s1 = 16;
            const size_t s2 = 17;
            const size_t rc = 18;

            resp.resize(19); // response with filename

            resp[3] = 0; // success

            // copy short filename into response
            for(int i=0 ; i<MAX_FILENAME_LEN ; ++i)
                resp[file_off+i] = name[i];

            // get filesize
            //if((details.st_mode & S_IFMT) == S_IFREG)
            if(S_ISREG(details.st_mode))
            {
                resp[s2] = details.st_size / (32*16384);
                resp[ex] = (details.st_size % (32*16384)) / 16384;
                resp[rc] = 1 + (details.st_size % 16384) / 128;
            }

            // set R/O bit
            if((details.st_mode & S_IWUSR) != S_IWUSR)
            {
                resp[ext_off] |= 0x80;
            }

            // set SYS bit
            //if((details.st_mode & S_IXUSR) == S_IXUSR)
            //{
            //    resp[ext_off+1] |= 0x80;
            //}

            return resp;  // m_local_filename is a matching file
        }

    } while (m_de);

    // Return the search parameter when no files match
    m_full_path = m_local_filename = cpm2linux(m_srch_filter.c_str(), MAX_FILENAME_LEN);

    // Close directory and clear m_srch_filter
    reset_dir();

    return resp;  // no matches
}


// Inputs:
//   1-byte command
//   2-byte client FCB address (not used)
//   8-byte filename
//   3-byte extension
//     '?' matches any character in filename/extension
// Outputs:
//   1-byte command+1
//   2-byte fd and -fd
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::open_file(const msgbuf_t& msg)
{
	int hdl = -1;
    uint16_t fcb_addr = msg[1] + 256 * msg[2];

	// look for the file in the current working directory
    msgbuf_t resp = find_first(msg);
	
	// if the file wasn't found, search the search_path
	if(resp[3] == 0xff)
	{
		//printf("open_file: search for file in search path\n");
		string pushd = m_cwd; // push current working directory
		for (size_t i = 0; i < search_path.size(); i++)
		{
			printf("open_file: search '%s'\n", search_path[i].c_str());
			// set the current working directory
			m_cwd = root_path + search_path[i];
			// search new directory
			resp = find_first(msg);
			if(resp[3] != 0xff) 
			{
				break; // we found the file!
			}
		}
		m_cwd = pushd; // restore current working directory
	}

    resp.resize(4);  // discard short filename and file size

    if(0 == resp[3]) // on success, try to open local filename
	{
        // First check if this file is already open
        for(fcb_map_t::iterator it = m_fcbs.begin() ; it != m_fcbs.end() ; ++it)
        {
            if(it->second.local_filename() == m_full_path)
            {
                // Close the handle to prevent issues with delete and rename
                m_fcbs.erase(it);
                break;
            }
        }
        
        // Open the file
        hdl = open(m_full_path.c_str(), O_RDWR);
	}

    if(-1 == hdl)
    {
        if(0 != resp[3]) errno = ENOENT; // file not found
		resp[1] = 0xFF;
		resp[2] = 0xFF;
        resp[3] = 0xFF; // error
    }
    else
    {
		resp[1] = hdl;
		resp[2] = ~hdl + 1; // 2's complement
        resp[3] = 0; // success
		fcb_t& fcb = m_fcbs[hdl];
        fcb.set(hdl, m_full_path);
#ifdef BACKCOMPAT
        // v1.0 and 1.1 compatibility
        m_fcb_to_hdl[fcb_addr] = hdl;
#endif        
    }

    printf("open_file(%d) '%s' fcb_addr=0x%04X %s\n", hdl, m_full_path.c_str(), fcb_addr,
        0==resp[3] ? "success" : strerror(errno));

    reset_dir();
    
    return resp;
}


// Inputs:
//   1-byte command
//   2-byte file handle
// Outputs:
//   1-byte command+1
//   2-byte file handle
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::close_file(const msgbuf_t& msg)
{
    int file_handle = get_file_handle(msg);
    fcb_t& fcb = m_fcbs[file_handle];

    // close the file handle and remove FCB
	m_fcbs.erase(fcb.hdl());

    msgbuf_t resp = msg;

    resp.resize(4);  // add byte for status

    resp[0] += 1; // set response code
    // file handle is set from msg
    resp[3] = 0; // success, we never return an error

    printf("close_file(%d) '%s' %s\n", fcb.hdl(), fcb.local_filename().c_str(),
        0==resp[3] ? "success" : strerror(errno));
    
    return resp;
}


// Inputs:
//   1-byte command
//   2-byte file handle
//   Optional: 2-byte record number
// Outputs:
//   1-byte command+1
//   2-byte file handle
//   1-byte status (0=success, 1=end of file, 0xFF=failure)
//  128-byte record (optional, not present if status=0xFF)
//
msgbuf_t client_t::read_file(const msgbuf_t& msg)
{
    int file_handle = get_file_handle(msg);
    fcb_t& fcb = m_fcbs[file_handle];
    off_t offset = 0;
    bool off_inc = false;

    // check for random access
    if(msg.size() >= 5)
    {
        off_inc = true;
        offset = 128 * ((msg[4] << 8) | msg[3]);
    }

#ifdef DEBUG
    printf("read_file(%d) off=%d '%s'\n", fcb.hdl(), offset, fcb.local_filename().c_str());
#endif

    msgbuf_t resp(132);

    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];

    fcb.accessed();

    if (off_inc) lseek(fcb.hdl(), offset, SEEK_SET);
    
    ssize_t cnt = read(fcb.hdl(), &resp[4], 128);
    if(0 == cnt)
    {
        //printf("read_file(%d) EOF\n", fcb.hdl());
        resp[3] = 1; // end of file
        resp.resize(4);
    }
    else if(cnt < 0)
    {
        printf("read_file(%d) read error\n", fcb.hdl());
        resp[3] = 0xff; // error
        resp.resize(4);
    }
    else if(cnt < 128)
    {
        //printf("read_file(%d) short block cnt=%d\n", fcb.hdl(), cnt);
        // fill remainder of buffer with CTRL-Z the CP/M EOF marker
        memset(&resp[cnt+4], 0x1a, 128 - cnt);
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte file handle
//   Optional: 2-byte record number
//  128-byte record
// Outputs:
//   1-byte command+1
//   2-byte file handle
//   1-byte status (0=success, 5=disk full, 0xFF=failure)
//
msgbuf_t client_t::write_file(const msgbuf_t& msg)
{
    int file_handle = get_file_handle(msg);
    fcb_t& fcb = m_fcbs[file_handle];
    off_t offset = 0;
    bool off_inc = false;

    if(msg.size() >= 133) 
    {
        off_inc = true;
        offset = 128 * ((msg[4] << 8) | msg[3]);
    }

#ifdef DEBUG
    printf("write_file(%d) off=%d '%s'\n", fcb.hdl(), offset, fcb.local_filename().c_str());
#endif

    msgbuf_t resp(4);

    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];

    fcb.accessed();

    if (off_inc) lseek(fcb.hdl(), offset, SEEK_SET);
    
    // start of record moves two bytes when record # is sent
    ssize_t cnt = write(fcb.hdl(), &msg[off_inc ? 5 : 3], 128);
    if(0 == cnt)
    {
        resp[3] = 5; // disk full
    }
    else if(cnt < 0)
    {
        resp[3] = 0xFF; // error
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte client FCB address (not used)
//   8-byte filename
//   3-byte extension
// Outputs:
//   1-byte command+1
//   2-byte file handle
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::create_file(const msgbuf_t& msg)
{
	int hdl = -1;
    uint16_t fcb_addr = msg[1] + 256 * msg[2];

    msgbuf_t resp(4);
    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];

    string filename = m_cwd + "/" + cpm2linux((const char*)&msg[3], MAX_FILENAME_LEN);
   
    // creat() opens the file with O_WRONLY which breaks Random File Access!
    hdl = open(filename.c_str(), O_CREAT | O_TRUNC | O_RDWR,
        S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH);

    if(-1 == hdl)
    {
		resp[1] = 0xFF;
		resp[2] = 0xFF;
        resp[3] = 0xFF; // error
    }
    else
    {
		resp[1] = hdl;
		resp[2] = ~hdl + 1; // 2's complement
        resp[3] = 0; // success
		fcb_t& fcb = m_fcbs[hdl];
        fcb.set(hdl, filename);
#ifdef BACKCOMPAT        
        // v1.0 and 1.1 compatibility
        m_fcb_to_hdl[fcb_addr] = hdl;
#endif        
    }

    printf("create_file(%d) '%s' fcb_addr=0x%04X %s\n", hdl, filename.c_str(), fcb_addr,
        0==resp[3] ? "success" : strerror(errno));

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte client FCB address (not used)
//   8-byte filename
//   3-byte extension
// Outputs:
//   1-byte command+1
//   2-byte 0
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::delete_file(const msgbuf_t& msg)
{
    int retval = -1;
    msgbuf_t resp = find_first(msg);

    resp.resize(4);  // discard short filename and file size
   
    while(0 == resp[3]) // on success, try to delete local filename
    {
        retval = unlink(m_full_path.c_str());
        
        printf("delete_file '%s' %s\n", m_full_path.c_str(), 
            -1 != retval ? "success" : strerror(errno));
        
        if((-1 == retval) && (EISDIR != errno)) break; // quit on an error
        
        resp = find_next(msg);
    }

    if(-1 == retval)
    {
        resp[3] = 0xFF; // error
    }
    else
    {
        resp[3] = 0; // success
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte client FCB address (not used)
//   8-byte filename, old
//   3-byte extension, old
//   8-byte filename, new
//   3-byte extension, new
// Outputs:
//   1-byte command+1
//   2-byte 0
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::rename_file(const msgbuf_t& msg)
{
    msgbuf_t resp = find_first(msg);

    string oldfn = m_full_path;
    string newfn = m_cwd + "/" + cpm2linux((const char*)&msg[14], MAX_FILENAME_LEN);

    resp.resize(4);  // discard filename and file size

    int retval = rename(oldfn.c_str(), newfn.c_str());

    if(-1 == retval)
    {
        resp[3] = 0xFF; // error
    }
    else
    {
        resp[3] = 0; // success
    }

    printf("rename_file '%s'-> '%s' %s\n", oldfn.c_str(), newfn.c_str(), 
        0==resp[3] ? "success" : strerror(errno));

    return resp;
}


bool client_t::getsafepath(string& new_dir, bool mkdir)
{
    string tmp_dir = new_dir; // don't change unless successful
    string mkdir_name;
    bool retval = false; // prepare for failure
   
    // handle reference to root '/'
    if(tmp_dir[0] == '/') tmp_dir = root_path + tmp_dir;
    else tmp_dir = m_cwd + "/" + tmp_dir;

    if(mkdir)
    {
        mkdir_name = tmp_dir.substr(tmp_dir.find_last_of("/"));
        tmp_dir = tmp_dir.substr(0, tmp_dir.find_last_of("/") + 1);
    }
    
    // try to open the directory
    char* path = realpath(tmp_dir.c_str(), NULL);
    if(path)
    {
        // is this directory under the root_path?
        if((strlen(path) >= root_path.length()) &&
           (0==strncmp(path, root_path.c_str(), root_path.length()))
          )
        {
            tmp_dir = path + (mkdir ? mkdir_name : "");
            printf("getsafepath '%s' -> '%s'\n", new_dir.c_str(), tmp_dir.c_str());
            new_dir = tmp_dir; // yep. select the new path.
            retval = true;  // signal success
        }
        free(path);
    }
    
    return retval;
}

// Inputs:
//   1-byte command
//   n-byte directory
// Outputs:
//   1-byte command+1
//   1-byte status (0=success, 0xFF=failure)
//   n-byte current working dirrectory
//
msgbuf_t client_t::change_dir(const msgbuf_t& msg)
{
    msgbuf_t resp(2+128);

    resp[0] = resp[0] + 1; // response code
    resp[1] = 0; // prepare for success

    string new_dir((char*)&msg[1], msg.size() - 1);
    while(new_dir[0] == ' ')
        new_dir.erase(0, 1); // remove any leading spaces

    // convert to lower-case because CPM converts to upper-case
    for(size_t i=0 ; i<new_dir.length() ; ++i)
        new_dir[i] = tolower(new_dir[i]);

    printf("change_dir '%s'\n", new_dir.c_str());

    // get new path relative to m_cwd and limited by root_path
    if(getsafepath(new_dir))
        m_cwd = new_dir;
    
    // copy new directory into response
    if(m_cwd.length() < 128)
		sprintf((char*)&resp[2], m_cwd.c_str());
    else
		sprintf((char*)&resp[2], "Directory name too long.");

    resp.resize(2 + strlen((char*)&resp[2]));
	
    return resp;
}

// Inputs:
//   1-byte command
//   n-byte directory
// Outputs:
//   1-byte command+1
//   1-byte status (0=success, 0xFF=failure)
//   n-byte error msg
//
msgbuf_t client_t::make_dir(const msgbuf_t& msg)
{
    msgbuf_t resp(2);

    resp[0] = resp[0] + 1; // response code

    string new_dir((char*)&msg[1], msg.size() - 1);
    while(new_dir[0] == ' ')
        new_dir.erase(0, 1); // remove any leading spaces

    // convert to lower-case because CPM converts to upper-case
    for(size_t i=0 ; i<new_dir.length() ; ++i)
	new_dir[i] = tolower(new_dir[i]);

    printf("make_dir '%s'\n", new_dir.c_str());
    
    if(new_dir.length() && getsafepath(new_dir, true/*mkdir*/))
    {
        resp[1] = mkdir(new_dir.c_str(), 0755/*mode*/);
        if(0xff == resp[1])
        {
            char *errs = strerror(errno);
            printf("make_dir err='%s'\n", errs);
            resp.resize(resp.size() + strlen(errs));
            memcpy(&resp[2], errs, strlen(errs));
        }
    }
    else  // bad directory
    {
        resp[1] = 0xff;
        resp.resize(resp.size() + strlen(BAD_DIRECTORY));
        memcpy(&resp[2], BAD_DIRECTORY, strlen(BAD_DIRECTORY));        
    }

    return resp;
}

// Inputs:
//   1-byte command
//   n-byte directory
// Outputs:
//   1-byte command+1
//   1-byte status (0=success, 0xFF=failure)
//   n-byte error msg
//
msgbuf_t client_t::remove_dir(const msgbuf_t& msg)
{
    msgbuf_t resp(2);

    resp[0] = resp[0] + 1; // response code

    string new_dir((char*)&msg[1], msg.size() - 1);
    while(new_dir[0] == ' ')
        new_dir.erase(0, 1); // remove any leading spaces

    // convert to lower-case because CPM converts to upper-case
    for(size_t i=0 ; i<new_dir.length() ; ++i)
	new_dir[i] = tolower(new_dir[i]);

    printf("remove_dir '%s'\n", new_dir.c_str());

    if(getsafepath(new_dir) && new_dir.length())
    {
        resp[1] = rmdir(new_dir.c_str());
        if(0xff == resp[1])
        {
            char *errs = strerror(errno);
            printf("remove_dir err='%s'\n", errs);
            resp.resize(resp.size() + strlen(errs));
            memcpy(&resp[2], errs, strlen(errs));
        }
    }
    else  // bad directory
    {
        resp[1] = 0xff;
        resp.resize(resp.size() + strlen(BAD_DIRECTORY));
        memcpy(&resp[2], BAD_DIRECTORY, strlen(BAD_DIRECTORY));        
    }

    return resp;
}

// Inputs:
//   1-byte command
//   n-byte msg
// Outputs:
//   1-byte command+1
//   n-byte msg
//
msgbuf_t client_t::echo(const msgbuf_t& msg)
{
    msgbuf_t resp = msg;
	resp[0] += 1;
    return resp;
}


// Inputs:
//   1-byte command
//   1-byte buffer type: 0=shell command, 1=stdin bytes
//   n-byte buffer: shell command line / stdin bytes
// Outputs:
//   1-byte command+1
//   1-byte status (0=no stdout bytes, 1=stdout bytes present, 0xFF=exit)
//   n-byte stdout bytes
//
// Execute specified shell command line. If the shell command line
// is empty, launch 'bash'. Redirect shell command line stdin and
// stdout. Stdout from the shell command line is buffered. The client
// will poll to send bytes to stdin and receive a block of up to
// 128 bytes from the stdout buffer. The clients are typically not
// interrupt driven so this process introduces flow control to 
// prevent the overflow of the client serial receive buffer. This
// is especially problematic when the screen scrolls as this is
// time consuming resulting in many dropped characters.
msgbuf_t client_t::shell(const msgbuf_t& msg)
{
    msgbuf_t resp(2);
	resp[0] = msg[0] + 1; // set response command byte
    resp[1] = 0; // no stdout bytes
    
    //printf("shell() msg length=%d\n", msg.size());
    
    // extract command / stdin bytes
    string buffer;
    if(msg.size() > 2)
    {
        buffer.insert(buffer.end(), msg.begin() + 2, msg.end());
        //printf("buffer: '%s'\n", buffer.c_str());
    }
    
    // what's in the buffer?
    switch(msg[1])
    {
        case 0: // buffer is shell command
            for(string::iterator it=buffer.begin();
                it!=buffer.end(); ++it)
            {
                *it = (char) tolower(*it);
            }
            // if there's an abandoned shell, we need to kill it
            if(-1 != m_child_pid)
            {
                kill(m_child_pid, SIGHUP);
                m_child_pid = -1;
            }
            // close any open handle
            if(-1 != m_fd_pty)
            {
                close (m_fd_pty);
                m_fd_pty = -1;
            }
            // now start a new shell
            launch_shell_command(buffer);
            break;
        case 1: // buffer is stdin bytes (can be empty)
            if(buffer.length())
            {
                //printf("write to stdin: '%s'\n", buffer.c_str());
                write(m_fd_pty, buffer.c_str(), buffer.length());
            }
            break;
        default:
            printf("Bad shell poll code: %d\n", msg[1]);        
    }
    
    // Get and return any pending bytes
    string ret_bytes = get_stdout();
    if(ret_bytes.length())
    {
        resp.insert(resp.end(), ret_bytes.begin(), ret_bytes.end());
        resp[1] = 1;    // stdout bytes available
    }
    else
    {
        //printf("check child status\n");
        // Return 0xFF if the shell command exited
        int child_status;
        if((-1 == m_child_pid) ||
           (m_child_pid == waitpid(m_child_pid, &child_status, WNOHANG))
           )
        {
            printf("child died, return exit status\n");
            resp[1] = 0xff; // command exited
            m_child_pid = -1;
            if(-1 != m_fd_pty)
            {
                close (m_fd_pty);
                m_fd_pty = -1;
            }
            remove_utmp();
        }
    }
    
    return resp;
}


bool client_t::launch_shell_command(const string& commandline)
{
    string args = commandline;
    
    m_shell_buf.clear();
      
    // First char of '/' indicates the terminal type
    if((args.length() > 2) && (args.substr(0, 2) == " /"))
    {
        int offset_to_space = args.find(' ', 2);
        if(-1 == offset_to_space)
        {
            m_term = args.substr(2);
            args.clear();
        }
        else
        {
            m_term = args.substr(2, offset_to_space - 2);
            args = args.substr(offset_to_space + 1);
        }
    }
    while(' ' == args[0]) args.erase(0, 1);
    
    // forkpty() calls posix_openpt() to get a pseudo-tty, 
    // forks the process, opens the slave-side of the pty
    // in the child process, and assigns stdin/stdout/stderr
    // to the slave-side of the pty.
    m_ttyname.resize(256, '\0');
    
    seteuid(0); // effective uid=root so forkpty() works
    
    m_child_pid = forkpty(
        &m_fd_pty, 
        (char*)m_ttyname.data(),
        NULL, //&tty,
        NULL); // struct winsize

	if( m_child_pid < 0 ) // Something went wrong...
	{
        printf("launch_shell_command: failed to fork\n");
        send_stdout("\r\nFork() remote shell command failed.\r\n");
		return false;
	}
	else if( m_child_pid == 0 ) // I'm the child
	{
        setuid(nsh_uid); // permanent switch to user uid
        
        // set terminal from config file or "dumb" 
        setenv("TERM", m_term.c_str(), 1/*overwrite*/);

        // switch to user's current directory
        chdir(m_cwd.c_str());
        
        // close all client connections and all files
        client_map.clear();        
        // we basically just did 'delete this' so don't try
        // to access member variables or methods after here
        
        if(args.length())
        {
            // launch shell command
            execlp("bash", "bash", "-c", args.c_str(), NULL);
        }
        else
        {
            // remote client welcome
            printf("\nYou are connected from: %s\n", m_name.c_str());
            printf("Your terminal is: %s (%s)\n", m_ttyname.c_str(), m_term.c_str());
            printf("To change terminal type, use: nsh /terminal args\n\n");
            fflush(stdout);
            
            // launch the shell
            execlp("bash", "-bash", NULL);
        }
	}
	else // I'm the parent
	{
        seteuid(file_uid); // back to user uid for safety
        
		printf("My child process is %d fd=%d\n", m_child_pid, m_fd_pty);
        printf("launch_shell_command: '%s' term='%s'\n", args.c_str(), m_term.c_str());
        add_utmp();
	}
    
	return true;
}


// Queue-up bytes to the remote client
//void client_t::send_stdout(const string& msg)
//{
//	m_shell_buf.insert(m_shell_buf.end(), msg.c_str(), msg.c_str() + msg.length());
//}


// Queue-up bytes to the remote client
void client_t::send_stdout(const msgbuf_t& msg)
{
	m_shell_buf.insert(m_shell_buf.end(), msg.begin(), msg.end());
}

void client_t::send_stdout(const char *fmt, ...)
{
    va_list argptr;
    msgbuf_t msg(256);

    va_start(argptr, fmt);
    int len = vsnprintf((char*)msg.data(), msg.size(), fmt, argptr);
    va_end(argptr);
    
    // If a formatted string is greater than 255 characters, it will
    // be discarded.
    if((len >0) && (len< msg.size()))
    {
        msg.resize(len);
        send_stdout(msg);
    }
}


// Get queued bytes to return to client, <128 bytes
string client_t::get_stdout()
{
    string retval;
    if(m_shell_buf.length() < 128)
    {
        retval = m_shell_buf;
        m_shell_buf.clear();
    }
    else
    {
        retval = m_shell_buf.substr(0, 128);
        m_shell_buf.erase(0, 128);
    }
    return retval;
}


void client_t::add_utmp(void)
{
    uid_t uid = geteuid();
    
    // become root to edit UTMP file
    seteuid(0); // effective uid=root
    
    struct utmp entry;
    memset(&entry, 0, sizeof(entry));
    entry.ut_type = USER_PROCESS;
    entry.ut_pid = m_child_pid;
    strcpy(entry.ut_line, m_ttyname.c_str() + strlen("/dev/"));
    strcpy(entry.ut_id, m_ttyname.c_str() + m_ttyname.size() - 4);
    time(&entry.ut_time);
    strcpy(entry.ut_user, getpwuid(nsh_uid)->pw_name);
    strcpy(entry.ut_host, m_name.c_str());
    entry.ut_addr = 0;
    setutent();
    void * ret = pututline(&entry);
    printf("add_utmp(), retval=%s\n", ret==NULL ? "failed" : "success");
    
    // switch back to file user
    seteuid(uid);
}

void client_t::remove_utmp(void)
{
    uid_t uid = geteuid();
    
    // become root to edit UTMP file
    seteuid(0); // effective uid=root
    
    struct utmp entry;
    memset(&entry, 0, sizeof(entry));
    entry.ut_type = DEAD_PROCESS;
    entry.ut_pid = m_child_pid;
    strcpy(entry.ut_id, m_ttyname.c_str() + m_ttyname.size() - 4);
    setutent();
    void * ret = pututline(&entry);
    endutent();
    printf("remove_utmp(), retval=%s\n", ret==NULL ? "failed" : "success");
    
    // switch back to file user
    seteuid(uid);
}
