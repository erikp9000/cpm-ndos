#include "client.h"
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <malloc.h>

#include <termios.h>
#include <unistd.h>

#undef DEBUG

// This function manages the receive buffer for a client.
// Here a request is assembled and if the checksum is valid,
// then the command is processed and a response is sent.
// The function handles partial requests so it can be 
// called multiple times with chunks of the full request.
void client_t::recv_request()
{
    do {
#ifdef DEBUG		
		printf("recv_request (%d) entered\n", m_fd);
#endif
        int rdlen = read(m_fd, m_buffer + m_offset, m_cnt - m_offset);
#ifdef DEBUG
		printf("recv_request (%d) read returned (%d)\n", m_fd, rdlen);
#endif

        if(rdlen < 0)
        {
            // If there's no data to read, just return
            if(EAGAIN == errno)
            {
                m_offset = 0;
                m_cnt = 1;
                return;
            }

            // Print error and close the socket
            perror("read error");
            close(m_fd);
            m_fd = -1;
            return;
        }
        else if(rdlen == 0)
        {
            // reset buf for next message (serial)
	    // if no characters, this isn't a timeout
            if(m_offset) printf("read timeout\n");
            m_offset = 0;
            m_cnt = 1;
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
#ifdef DEBUG				
                printf("msg :");
#endif
                for(int i=0 ; i < m_cnt ; ++i)
                {
#ifdef DEBUG				
                    printf("%02x ", m_buffer[i]);
#endif
                    chksum += m_buffer[i];
                }
#ifdef DEBUG				
                printf(" chksum=%02x\n", chksum);
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
                    printf("checksum failure\n");
                    for(int i=0 ; i < m_cnt ; ++i)
                    {
                        printf("%02x ", m_buffer[i]);
                        if(i % 16 == 15) printf("\n");
                    }
                    printf("\n");
                }

                // reset for next message
                m_offset = 0;
                m_cnt = 1;
            }
        }
    } while(1);
}

void client_t::send_resp(const msgbuf_t &resp)
{
    msgbuf_t cmd = resp; // make copy so we can insert LEN and CHK

#ifdef DEBUG				
    printf("response len=%02x: ", cmd.size());
#endif
    if(cmd.size())
    {
        unsigned char chksum = 0;

        // insert length at start of resp
        cmd.insert(cmd.begin(), 2 + cmd.size());
        // compute chksum and push to end of resp
        for(int i=0 ; i<cmd.size() ; ++i)
        {
#ifdef DEBUG				
            printf("%02x ", cmd[i]);
#endif
            chksum += cmd[i];
        }
        cmd.push_back(~chksum + 1);
#ifdef DEBUG				
        printf("%02x ", cmd[cmd.size()-1]);
#endif
        write(m_fd, cmd.data(), cmd.size());
        tcdrain(m_fd);    // delay for output
    }
#ifdef DEBUG				
    printf("\n");
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

	default:
	    printf("Unrecognized cmd=%02x\n", msg[0]);
    }

    return resp;
}


void client_t::reset_fcb(fcb_t& fcb)
{
    fcb.filter.clear();
    fcb.local_filename.clear();

    if(fcb.d)
    {
        printf("closedir\n");
        closedir(fcb.d);
        fcb.d = NULL;
    }

    if(-1 != fcb.hdl)
    {
        printf("close hdl=%d\n", fcb.hdl);
        close(fcb.hdl);
        fcb.hdl = -1;
    }
}


int client_t::get_fcb_addr(const msgbuf_t& msg)
{
    int fcb_addr = (msg[2] << 8) | msg[1];
    return fcb_addr;
}

// TODO handle long filenames by hashing name to a CRC
static char out[12];
static char* GetShortFilename(char* name)
{
    int i,j;

    memset(out, ' ', 11);
    out[11] = 0;

    for(i=0, j=0 ; (j<11) && (name[i]) ; ++i,++j)
    {
        if(name[i] == '.')
            j = 7;
        else
            out[j] = toupper(name[i]);
    }

    return out;
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
//   2-byte FCB address
//   8-byte filename
//   3-byte extension
//     '?' matches any character in filename/extension
// Outputs:
//   1-byte command+1
//   2-byte FCB address
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
//   2-byte FCB address
//   1-byte 0xFF
//
msgbuf_t client_t::find_first(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];

    //printf("find_first(%04x)\n", fcb_addr);

    reset_fcb(fcb);

    printf("find_first(%04x): open dir '%s'\n", fcb_addr, m_cwd.c_str());
    fcb.d = opendir(m_cwd.c_str());

    // extract the filter
    fcb.filter.clear();
    fcb.filter.resize(11);
    for(size_t i=0 ; i < 11 ; ++i)
        fcb.filter[i] = msg[3+i] & 0x7f;
    printf("filter: '%s'\n", fcb.filter.c_str());

    return find_next(msg);
}


// Inputs:
//   1-byte command
//   2-byte FCB address
// Outputs:
//   See find_first()
//
msgbuf_t client_t::find_next(const msgbuf_t& msg)
{
    msgbuf_t resp(4); // end of directory response

    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];

    //printf("find_next(%04x)\n", fcb_addr);

    // copy FCB to response
    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];
    resp[3] = 0xFF; // end of directory

    if(fcb.d) do
    {
        fcb.de = readdir(fcb.d);

	if(!fcb.de) break;

        fcb.local_filename = fcb.de->d_name;

        // search for a file that matches filter
        string name;
        struct stat details;
		string pathname = m_cwd + "/" + fcb.local_filename;
        stat(pathname.c_str(), &details);

        if(S_ISDIR(details.st_mode))
        {
            name = fcb.de->d_name;


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
            if(name.length() < 11)
            {
                for(int i = 11 - name.length() ; i ; --i)
                    name += " ";
            }
        }
        else if(S_ISREG(details.st_mode))
        {
            name = GetShortFilename(fcb.de->d_name);
        }
        else
        {
            printf("Huh filetype?\n");
            continue; // check next entry
        }

		//printf("find_next: short filename='%s'\n", name.c_str());

        bool bMatch = true;
        for(int i=0 ; i<11 ; ++i) 
        {
            if((name[i] != fcb.filter[i]) &&
               (fcb.filter[i] != '?'))
            {
               bMatch = false;
               break;
            }
        }

        if(bMatch) 
        {
			//printf("find_next: Match!\n");
            const size_t file_off = 4;
            const size_t ext_off = 12;
            const size_t ex = 15;
            const size_t s1 = 16;
            const size_t s2 = 17;
            const size_t rc = 18;

            resp.resize(19); // response with filename

            resp[3] = 0; // success

            // copy short filename into response
            for(int i=0 ; i<11 ; ++i)
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

            return resp;
        }

    } while (fcb.de);

    reset_fcb(fcb);

    return resp;  // no matches
}


// Inputs:
//   1-byte command
//   2-byte FCB address
//   8-byte filename
//   3-byte extension
//     '?' matches any character in filename/extension
// Outputs:
//   1-byte command+1
//   2-byte FCB address
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::open_file(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];

	// look for the file in the current working directory
    msgbuf_t resp = find_first(msg);
	
	// if the file wasn't found, search the search_path
	if(resp[3] == 0xff)
	{
printf("open_file: search for file in search path\n");
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
				fcb.local_filename = m_cwd + "/" + fcb.local_filename;
				break; // we found the file!
			}
		}
		m_cwd = pushd; // restore current working directory
	}

    resp.resize(4);  // discard short filename and file size

    if(0 == resp[3]) // on success, try to open local filename
        fcb.hdl = open(fcb.local_filename.c_str(), O_RDWR);

    printf("open_file(%04x, %d) '%s' ", fcb_addr, fcb.hdl, fcb.local_filename.c_str());

    if(-1 == fcb.hdl)
    {
        printf("not found\n");
        resp[3] = 0xFF; // error
    }
    else
    {
        printf("success\n");
        resp[3] = 0; // success
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte FCB address
// Outputs:
//   1-byte command+1
//   2-byte FCB address
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::close_file(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];

    printf("close_file(%04x, %d) '%s'\n", fcb_addr, fcb.hdl, fcb.local_filename.c_str());

    reset_fcb(fcb); // close file and reset everything

    msgbuf_t resp = msg;

    resp.resize(4);  // add byte for status

    resp[0] += 1; // set response code
    // FCB address is set from msg
    resp[3] = 0; // success, we never return an error
    
    return resp;
}


// Inputs:
//   1-byte command
//   2-byte FCB address
//   Optional: 2-byte record number
// Outputs:
//   1-byte command+1
//   2-byte FCB address
//   1-byte status (0=success, 1=end of file, 0xFF=failure)
//  128-byte record (optional, not present if status=0xFF)
//
msgbuf_t client_t::read_file(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];
    off_t offset = 0;
    bool off_inc = false;

    if(msg.size() >= 5)
    {
        off_inc = true;
        offset = 128 * ((msg[4] << 8) | msg[3]);
    }

    //printf("read_file(%04x, %d) off=%d '%s'\n", fcb_addr, fcb.hdl, offset, fcb.local_filename.c_str());

    msgbuf_t resp(132);

    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];

    if(-1 != fcb.hdl)
    {
        if (off_inc) lseek(fcb.hdl, offset, SEEK_SET);
        
        size_t cnt = read(fcb.hdl, &resp[4], 128);
        if(!cnt)
        {
            resp[3] = 1; // end of file
            resp.resize(4);
        }
        else if(cnt < 128)
        {
            // fill remainder of buffer with CTRL-Z the CP/M EOF marker
            memset(&resp[cnt+4], 0x1a, 128 - cnt);
        }
    }
    else
    {
        resp[3] = 0xFF; // error
        resp.resize(4);
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte FCB address
//   Optional: 2-byte record number
//  128-byte record
// Outputs:
//   1-byte command+1
//   2-byte FCB address
//   1-byte status (0=success, 5=disk full, 0xFF=failure)
//
msgbuf_t client_t::write_file(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];
    off_t offset = 0;
    bool off_inc = false;

    if(msg.size() >= 133) 
    {
        off_inc = true;
        offset = 128 * ((msg[4] << 8) | msg[3]);
    }

    //printf("write_file(%04x, %d) off=%d '%s'\n", fcb_addr, fcb.hdl, offset, fcb.local_filename.c_str());

    msgbuf_t resp(4);

    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];

    if(-1 != fcb.hdl)
    {
        if (off_inc) lseek(fcb.hdl, offset, SEEK_SET);
        
        // start of record moves two bytes when record # is sent
        size_t cnt = write(fcb.hdl, &msg[off_inc ? 5 : 3], 128);
        if(!cnt)
        {
            resp[3] = 5; // disk full
        }
    }
    else
    {
        resp[3] = 0xFF; // error
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte FCB address
//   8-byte filename
//   3-byte extension
// Outputs:
//   1-byte command+1
//   2-byte FCB address
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::create_file(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];

    reset_fcb(fcb);

    string filename = cpm2linux((const char*)&msg[3], 11);
    
    msgbuf_t resp(4);
    resp[0] = msg[0] + 1;
    resp[1] = msg[1];
    resp[2] = msg[2];

    //creat() opens the file with 0_WRONLY which breaks Random File Access!
    //fcb.hdl = creat(filename.c_str(), S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    fcb.hdl = open(filename.c_str(), O_CREAT | O_TRUNC | O_RDWR,
        S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);

    printf("create_file(%04x, %d) '%s' ", fcb_addr, fcb.hdl, filename.c_str());

    if(-1 == fcb.hdl)
    {
        printf("failed\n");
        resp[3] = 0xFF; // error
    }
    else
    {
        printf("success\n");
        resp[3] = 0; // success
        fcb.local_filename = filename;
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte FCB address
//   8-byte filename
//   3-byte extension
// Outputs:
//   1-byte command+1
//   2-byte FCB address
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::delete_file(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];

    msgbuf_t resp = find_first(msg);

    printf("delete_file(%04x) '%s' ", fcb_addr, fcb.local_filename.c_str());

    resp.resize(4);  // discard short filename and file size

    int retval = -1;
    if(0 == resp[3]) // on success, try to delete local filename
        retval = unlink(fcb.local_filename.c_str());

    if(-1 == retval)
    {
        printf("not found\n");
        resp[3] = 0xFF; // error
    }
    else
    {
        printf("success\n");
        resp[3] = 0; // success
    }

    return resp;
}


// Inputs:
//   1-byte command
//   2-byte FCB address
//   8-byte filename, old
//   3-byte extension, old
//   8-byte filename, new
//   3-byte extension, new
// Outputs:
//   1-byte command+1
//   2-byte FCB address
//   1-byte status (0=success, 0xFF=failure)
//
msgbuf_t client_t::rename_file(const msgbuf_t& msg)
{
    int fcb_addr = get_fcb_addr(msg);
    fcb_t& fcb = m_fcbs[fcb_addr];

    msgbuf_t resp = find_first(msg);

    string oldfn = fcb.local_filename;
    string newfn = cpm2linux((const char*)&msg[14], 11);

    printf("rename_file(%04x) '%s'-> '%s' ", fcb_addr,
        oldfn.c_str(), newfn.c_str());

    resp.resize(4);  // discard filename and file size

    int retval = rename(oldfn.c_str(), newfn.c_str());

    if(-1 == retval)
    {
        printf("not found\n");
        resp[3] = 0xFF; // error
    }
    else
    {
        printf("success\n");
        resp[3] = 0; // success
    }

    return resp;
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
    string old_path = m_cwd; // remember current working directory

//    for(size_t i=0 ; i<msg.size() ; ++i)
//        printf("%02x ", msg[i]);
//    printf("\n");

    resp[0] = resp[0] + 1; // response code

    string new_dir((char*)&msg[1], msg.size() - 1);
    while(new_dir[0] == ' ')
        new_dir.erase(0, 1); // remove any leading spaces

    // convert to lower-case because CPM converts to upper-case
    for(size_t i=0 ; i<new_dir.length() ; ++i)
	new_dir[i] = tolower(new_dir[i]);

    // detect change to root and add root_path
    if(new_dir[0] == '/')
	new_dir = root_path + new_dir;

    printf("change_dir new_dir='%s'\n", new_dir.c_str());

    if(new_dir.length())
        resp[1] = chdir(new_dir.c_str());

    // remember client's new current working directory
    char *d = get_current_dir_name();
    m_cwd = d;
    free(d);

    // is this directory under the root_path?
    if(strncmp(root_path.c_str(), m_cwd.c_str(), root_path.length()))
    {
        // nope. go back to original current working directory
	m_cwd = old_path;
        chdir(m_cwd.c_str());
    }

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

//    for(size_t i=0 ; i<msg.size() ; ++i)
//        printf("%02x ", msg[i]);
//    printf("\n");

    resp[0] = resp[0] + 1; // response code

    string new_dir((char*)&msg[1], msg.size() - 1);
    while(new_dir[0] == ' ')
        new_dir.erase(0, 1); // remove any leading spaces

    // convert to lower-case because CPM converts to upper-case
    for(size_t i=0 ; i<new_dir.length() ; ++i)
	new_dir[i] = tolower(new_dir[i]);

    printf("make_dir new_dir='%s'\n", new_dir.c_str());

    if(new_dir.length())
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

//    for(size_t i=0 ; i<msg.size() ; ++i)
//        printf("%02x ", msg[i]);
//    printf("\n");

    resp[0] = resp[0] + 1; // response code

    string new_dir((char*)&msg[1], msg.size() - 1);
    while(new_dir[0] == ' ')
        new_dir.erase(0, 1); // remove any leading spaces

    // convert to lower-case because CPM converts to upper-case
    for(size_t i=0 ; i<new_dir.length() ; ++i)
	new_dir[i] = tolower(new_dir[i]);

    printf("remove_dir new_dir='%s'\n", new_dir.c_str());

    if(new_dir.length())
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
    //printf("echo cnt=%d\n  ", msg.size()-1);
    //for(size_t i=1 ; i<msg.size() ; ++i)
    //{
    //    printf("%02x ", msg[i]);
    //    if((i - 1) % 16 == 15) printf("\n  ");
    //}
    //printf("\n");
    return resp;
}

