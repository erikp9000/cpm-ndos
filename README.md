# cpm-ndos

NDOS (Network Disk Operating System) is a terminate-and-stay-resident (TSR) 
program for CP/M 2.2 (Intel 8080) which adds a network drive (P:) over a serial port. The 
serial port is connected to a Linux computer which runs a service to convert 
the NDOS requests to Linux calls.

v1.2a Add TRS 80 NIOS for Model 4/4P/4D Montezuma CP/M. Add shell command (NSH) to 
enable remote client to login to a shell on the server or execute server commands.

v1.2 Dispenses with the FCB address as a file reference. On file open and file create, 
the server returns its file handle to the client who stores it in the FCB disk allocation 
vector array and includes it with subsequent calls to read file, write file, and close
file. This was a necessary change to support the BD Software C Compiler (BDSC) which re-uses
the same FCB (005Ch) to access multiple files.

v1.1a Extended Find Next to support the client changing the ambiguous file name after the
call to Find First. The program, CRCK44.COM, relied on this side-effect behavior of CP/M 2.2
to CRC multiple files specified by an ambiguous filename on the command line.

v1.1 Now fully relocatable without rebuilding and supports the CP/M random access read and 
write functions. Tested with Wordstar.

v1.0 First version.

## Required Build tools

  - RMAC.COM, LINK.COM, MAC.COM and LOAD.COM (on CP/M client)
  - G++ (on server)

## Architecture

NDOS consists of five major parts: 

  - LDNDOS.COM - Loads and relocates NIOS and NDOS into upper TPA
  - NIOS.SPR - The network initialization, send, and receive functions
  - NDOS.SPR - The network OS which hooks the CP/M 2.2 BDOS system calls
    and processes all calls on the network drive (P:)  
  - CCP.COM - A relocatable version of CP/M 2.2 Command Console Processor
  - ndos-srv - C/C++ Program that runs on a Linux computer

There are also several CP/M utilities:

  - CD.COM - Change the working directory on the server & print the working 
    directory
  - MKDIR.COM - Make a new directory on the server
  - RMDIR.COM - Remove a directory on the server
  - NSTAT.COM - Print network statistics
  - NECHO.COM - Send the string provided on the command line to the server 
    and print the response
  - NSH.COM - Execute shell commands on server or log-into shell
    - `nsh /trs4` - starts a Bash shell on the server with TERM=trs4
    - `nsh /kaypro2x telnet` - starts a Bash shell on the server with TERM=kaypro2x 
       and launches telnet
    - It is not necessary to specify the terminal after the first invokation

## Known Issues

  - The CCP converts all command-line characters to upper-case and ndos-srv 
    converts them back to lower-case. Therefore, server directories with 
    upper-case characters cannot be entered from NDOS though they can be seen 
    in their proper case by the CCP DIR command.

  - Filenames that don't comply with the 8.3 convention are truncated by 
    ndos-srv before returning them to NDOS. This means that long filenames on
    the server cannot be opened from NDOS.

  - Directory names longer than 9 characters are truncated by ndos-srv so the 
    full name is not viewable from NDOS though CD can still move into long-
    named directories.
	
  - The built-in SAVE command is broken when NDOS is loaded because breaking-out
    of DDT requires a Warm boot (^C) and this loads CCP.COM into the TPA 
	overwriting anything that was being patched in DDT. The work-around is to
	unload NDOS and patch files on a physical drive.

  

## LDNDOS.COM

LDNDOS.COM loads the page-relocatable files, NDOS.SPR and NIOS.SPR, into the
upper TPA just below the BDOS and jumps into the NDOS cold entry point. The
NDOS hooks the BDOS entry vector (addresses 6&7) to preserve itself and also 
so that all BDOS calls are first routed through the NDOS. The NDOS also hooks 
the Warm start vector in the BIOS jump table so that NDOS can reload the relocatable 
CCP.COM from drive A: on a warm start. If CCP.COM is not found, NDOS jumps to 
the old BIOS Warm start which recovers the CP/M system from the system tracks, 
removing NDOS from memory.

LDNDOS.COM supports three invocation patterns:

  - LDNDOS  *[Loads NDOS.SPR and NIOS.SPR]*
  
  - LDNDOS file.spr *[Loads NDOS.SPR and FILE.SPR]*
  
  - LDNDOS /k *[Unloads NDOS and NIOS and warm starts the system]*

## NIOS.SPR

NIOS.ASM is an example of the NIOS used by the NDOS. This file must be customized 
for the specific hardware on which it's meant to run. See below for a list of
supported hardware.

  - NIOSALTR.ASM is configured to use the second serial port (@12h/13h) of the 
    88-2SIO Serial Interface Board for the Altair 8800. 
	
  - NIOS-KP2.ASM is configured to use the 'J4 SERIAL DATA I/O' port on a Kaypro 2X
    at 19.2Kbps. It should also work on the Kaypro II/2/IV/4/10.

  - NIOS-T80.ASM is configured to use the serial port on a TRS 80 Model 4
    at 19.2Kbps. It should also work on the TRS 80 4/4P/4D.

### Porting Considerations

  - Tools required are:
    - MAC.COM, Digitial Research Macro assembler
	- RMAC.COM, Digitial Research Relocating Macro assembler
	- LOAD.COM, HEX to COM converter
	- LINK.COM, Digitial Research linker
	
  - Copy NIOS.ASM and implement init, smsg and rmsg for specific hardware
	
  - The network drive is P:. Change NDOSDSK in NDOS.ASM to select another drive.
  
## NDOS.SPR

This is the relocatable core of NDOS. It should not require any changes to
run on CP/M 2.2 systems.

### BDOS Function Summary

Below is a table of the BDOS functions which NDOS hooks into in order to process
commands for the network disk. All BDOS functions not listed here are passed to 
the BDOS.

**NOTE** NDOS ignores the current user number (code) set by BDOS function 32. 
Thus, all files on the server belong to all user numbers.

| BDOS function code | Function name       | Comments |
| ------------------ | ------------------- | -------- |
| 13                 | RESET DISK SYSTEM   | NDOS resets internal DMA address to default (80h) and jumps to BDOS. |
| 14                 | SELECT DISK         | NDOS stores new active disk and returns if network disk; else, jumps to BDOS. |
| 15                 | OPEN FILE           | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 16                 | CLOSE FILE          | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 17                 | SEARCH FOR FIRST    | If the selected disk in the FCB is the network disk, NDOS calls server and returns response in the DMA buffer. The response is always returned in the DMA buffer as the first directory entry (directory code=0) and the last extent of the file so that S2, EX, and RC can be used to compute the file size. The block allocation vector of the directory entry is initialized based on the number of 1024-byte blocks used for the final directory extent of the file (all blocks are 3). This supports STAT.COM which uses the directory allocation vector to compute the filesize. |
| 18                 | SEARCH FOR NEXT     | If the directory of the network disk is currently being accessed, then NDOS calls the server and returns the next matching directory entry, else, jumps to BDOS. If the EX byte in the FCB was set to '?' when srchf (17) was called, then NDOS will return all of the directory extents (up to 32 for a maximum of 512KB file size) for the matching file, in reverse order (supports STAT.COM which counts directory extents to compute file size). Since the first response was the last directory extent, the remaining directory extent allocation vectors are always full (all blocks are 3). |
| 19                 | DELETE FILE         | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 20                 | READ SEQUENTIAL     | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the result in the DMA; else, jumps to BDOS. Upon return, the caller's FCB byte, CR, is updated to point to the *next* block. Random access is supported by the caller setting S2,EX,CR in the FCB accordingly prior to the call. |
| 21                 | WRITE SEQUENTIAL    | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. Upon return, the caller's FCB byte, CR, is updated to point to the *next* block. Random access is supported by the caller setting S2,EX,CR in the FCB accordingly prior to the call. |
| 22                 | MAKE FILE           | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 23                 | RENAME FILE         | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 25                 | RETURN CURRENT DISK | If active disk is network disk, NDOS returns it, else jumps to BDOS |
| 26                 | SET DMA ADDRESS     | NDOS stores internally the new DMA address and jumps to BDOS. |
| 27                 | GET ADDR (ALLOC)    | If the active disk is the network disk, NDOS returns the network disk directory allocation vector which reports that the directory is full; else, jumps to BDOS. |
| 30                 | SET FILE ATTRIBUTES | **Not supported** NDOS panics and warm boots the system. |
| 31                 | GETADDR(DISKPARMS)  | NDOS returns network disk parameter block if active disk is network disk, else jumps to BDOS; the disk parameter block indicates that there are 512 directory entries on the network disk and a data allocation block size of 1024 bytes (BSH=3, BLM=7). |
| 33                 | READ RANDOM         | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the result in the DMA; else, jumps to BDOS. Upon return, the caller's FCB bytes, S2, EX, and CR are updated to point to the *current* block. |
| 34                 | WRITE RANDOM        | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. Upon return, the caller's FCB bytes, S2, EX, and CR are updated to point to the *current* block. |
| 35                 | COMPUTE FILE SIZE   | **Not supported** NDOS panics and warm boots the system. |
| 36                 | SET RANDOM RECORD   | If the selected disk in the FCB is the network disk, NDOS sets r0,r1,r2 in the FCB to the file offset addresed by S2,EX,CR; else, jumps to BDOS. |
| 40                 | WRITE RANDOM WITH ZERO FILL | **Not supported** NDOS panics and warm boots the system. |
| 64                 | NDOS GET VERSION    | Returns NDOS version as major.minor, packed BCD in A. If NDOS is not present, BDOS returns A=0. |
| 65                 | NDOS SEND MESSAGE   | Sends packet referenced by DE. See NDOS Protocol Envelope. The Len byte includes itself and the Checksum byte as well as the Command and Data size. The Checksum byte shall be set to 0. sendmsg computes the Checksum during transmission. |
| 66                 | NDOS RECEIVE MESSAGE| Returns received packet in DE, A=0(success)/FF(timeout). See NDOS Protocol Envelope. |
| 67                 | NDOS STATISTICS     | Returns HL pointing to NDOS packet counters: sentcnt, 2 bytes, count of messages sent recvcnt, 2 bytes, count of messages received tocnt, 2 bytes, count of timed-out messages chkcnt, 2 bytes, count of messages with bad checksum |
	
## CCP.COM

The standard CCP was extracted from CP/M 2.2 and prefixed with some relocation 
code (CCPR.ASM) and a table of address fix-ups. When executed, CCP.COM finds 
the top of the TPA by referencing the BDOS entry vector (addresses 6&7) and 
relocates itself to a page 2K bytes below the NDOS.

## ndos-srv

The ndos-srv runs on Linux (Raspberry Pi and Ubuntu) and implements the 
server-side of the NDOS Protocol. It supports multiple clients (CP/M machines).

### Hardware

  - Hardwired serial ports. The serial ports used by the ndos-srv are configured 
    in the configuration file.
  - USR-TCP232-302 RS232-to-Ethernet Converter. The Converter can be configured 
    for baud rates from 600~230.4Kbps. The ndos-srv supports the TCP Client mode 
	(on TCP port 8234) in which the Converter connects to the configured server 
	name/IP address and sends/receives serial bytes over the TCP socket. 
	Identity and Keepalive packets are NOT supported.
	
### Configuration File

JSON format.

    { 
      "root": "cpm",
      "path": ["/dri", "/bin", "/microsoft"],
      "serial": [
        { "port": "/dev/ttyAMA0", "baud": 9600 },
        { "port": "/dev/ttyUSB0", "baud": 19200 },
      ]
    }

 - root - Sets the root path for all clients
 - path - Sets the search path for open file so that clients can access programs
   on the file server which are not present in the current working directory
 - serial - Sets the list of serial ports that ndos-srv will monitor for client
   activity
 - ndos-srv also monitors for connections on TCP port 8234
 
## NDOS Protocol

The NDOS Protocol is a request/response protocol where all requests are 
initiated by the client (CP/M machine). All messages are wrapped in the 
standard Envelope.

### Envelope

All requests and responses are wrapped in a standard envelope.

| LEN | CMD | DATA ... | CHK |
| --- | --- | -------- | --- |

Where:
  - LEN is 1-byte length of message including itself, the CMD byte, the 
    CHK byte, and the length of the variable-length DATA field. Therefore, 
	length(DATA) = LEN-3.
  - CMD is 1-byte command code.
  - DATA is variable-length command data.
  - CHK is 1-byte 2's complement of sum bytes from LEN to byte preceeding 
    CHK. The recipient loads its checksum accumulator with 0 at the beginning 
	of a message and adds each byte received to the accumulator. Upon 
	receiving the CHK byte from the transmitter, the checksum shall be 0. If 
	the checksum is not 0, there was an error in transmission and the packet
	shall be dropped.

The intrachar timeout is 0.1 seconds. If no byte is received within this 
period, the receiver shall discard any partially received message and reset
its receive buffer. 


### NDOS Commands


#### Find First

Find the first file matching the NAMEx8 and EXTx3 parameters.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 02h | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | NAMEx8| File name, supports wildcard character '?' |
|     | EXTx3 | File extension, supports wildcard character '?' | 

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 03h | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | STAT  | 0=success, 0xFF=end of directory |
|     | NAMEx8| File name - not present if STAT=0xFF |
|     | EXTx3 | File extension - not present if STAT=0xFF | 
|     | EX    | Directory extent count (0-31) |
|     | S1    | =0
|     | S2    | Overflow of EX (0-15) |
|     | RC    | # 128-byte records in last extent |

	
The file size is returned in S2, EX, and RC as a count of 128-byte blocks, where:

	- S2=file size / 524288 *[0-15, 4 bits]*
	- EX=(file size % 524288) / 16384 *[0-31, 5 bits]*
	- RC=1 + (file size % 16384) / 128 *[1-128, 7 bits]*
	
The maximum file size is 8MB (8388608 bytes) or 65536 128-byte blocks. NDOS 
populates the block allocation vector of the directory entry to indicate how 
many blocks of the last extent are allocated before returning to the caller. 

If a directory is matched, the name is truncated to 9 bytes and returned 
in Filename and Extension and enclosed in '<' and '>'. The "<.>" is the current 
directory and "<..>" is the previous directory. Directory names are returned 
in their proper case while filenames are always returned in lower-case.

If the file is read-only on the server, then the most-significant bit of the 
first EXT byte is set to 1. The system/hidden file type (most-significant bit of the 
second EXT byte) is not supported.


#### Find Next

Find the next file matching the search parameters specified in NAMEx8 and EXTx3.
The search parameters must be specified again because some programs use a quirk
of CP/M in which they call Find First to prime CP/M to point to a specific
directory entry and then update the FCB so that the Find Next call to CP/M
will return the next file matching the newly changed Find Next search parameters.

If NAMEx8 and EXTx3 are not provided, Find Next will use the filter previously
set by Find First.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 04h | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | NAMEx8| Optional File name, supports wildcard character '?' |
|     | EXTx3 | Optional File extension, supports wildcard character '?' | 

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 05h | ...   | Same as Find First |


#### Open File

Open the named file on the server for reading and writing. If the file does not exist, an error is returned.
The server will look for the file in the current working directory first. If not found, then the server
will search the directories configured in the path configuration.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 06h | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | NAMEx8| File name with optional wildcard character '?' |
|     | EXTx3 | File extension with optional wildcard character '?' | 

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 07h | fd    | File handle |
|     | -fd   | Two's complement file handle |
|     | STAT  | 0=success, 0xFF=not found |


#### Close File

Close the file referenced by fd. 

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 08h | fd    | File handle |
|     | -fd   | Two's complement file handle |

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 09h | fd    | File handle |
|     | -fd   | Two's complement file handle |
|     | STAT  | 0=success, 0xFF=not found |


#### Delete File

Delete the named file on the server.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 0ah | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | NAMEx8| File name |
|     | EXTx3 | File extension | 

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 0bh | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | STAT  | 0=success, 0xFF=not found/access denied/etc. |


#### Read File

Read the 128-byte block of a previously opened file starting at the offset specified by 
Rechi,Reclo. If Rechi,Reclo is not specified, read the next 128-byte block. The last 
partial 128-byte block at the end of the file is automatically filled with CTRL-Z 
characters.

**NOTE** If Reclo is provided, then Rechi MUST be provided.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 0ch | fd    | File handle |
|     | -fd   | Two's complement file handle |
|     | Reclo | Optional record number to seek to before reading, low-byte |
|     | Rechi | Optional record number to seek to before reading, high-byte | 

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 0dh | fd    | File handle |
|     | -fd   | Two's complement file handle |
|     | STAT  | 0=success, 1=end of file, 0xFF=failure |
|     | Datax128 | Optional read data - only returned on success |


#### Write File

Write the 128-byte block, Datax128, to a previously opened file at the location specified by Rechi,Reclo. If Rechi,Reclo is not specified, then write to the file at the current location.

**NOTE** If Reclo is provided, then Rechi MUST be provided.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 0eh | fd    | File handle |
|     | -fd   | Two's complement file handle |
|     | Reclo | Optional record number to seek to before writing, low-byte |
|     | Rechi | Optional record number to seek to before writing, high-byte | 
|     | Datax128 | Write data |

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 0fh | fd    | File handle |
|     | -fd   | Two's complement file handle |
|     | STAT  | 0=success, 5=disk full (access denied), 0xFF=failure |


#### Create File

Create the named file on the server for writing only. If the file already exists, it is truncated.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 10h | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | NAMEx8| File name |
|     | EXTx3 | File extension | 

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 11h | fd    | File handle |
|     | -fd   | Two's complement file handle |
|     | STAT  | 0=success, 0xFF=failure |


#### Rename File

Rename the old filename on the server to new filename. Only renames the first file found.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 12h | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | oldNAMEx8| Old File name |
|     | oldEXTx3 | Old File extension | 
|     | newNAMEx8| New File name |
|     | newEXTx3 | New File extension | 

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 13h | Byte  | FCBlo - not used  |
|     | Byte  | FCBhi - not used  |
|     | STAT  | 0=success, 0xFF=failure |


#### Change Dir

Change the client's working directory on the server. Note that only lower-case directory names on the server are supported. 

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 20h | Pathv128 | Optional new directory to change into. |

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 21h | STAT  | 0=success, 0xFF=failure |
|     | Pathv128 | Variable-length client current working directory. |



#### Make Dir

Make a directory on the server. The new server directory will be in lower-case. 

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 22h | Pathv128 | Variable-length name of new directory. |

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 23h | STAT  | 0=success, 0xFF=failure |
|     | Errorv128 | Optional variable-length error message. |


#### Remove Dir

Remove a directory on the server.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 24h | Pathv128 | Variable-length name of directory to remove. |

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 25h | STAT  | 0=success, 0xFF=failure |
|     | Errorv128 | Optional variable-length error message. |


#### Echo

The server returns the variable-length message it received.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 30h | Msgv128 | Variable-length message. |

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 31h | Msgv128 | Variable-length message returned. |


#### Shell

The client sets Type=0 to execute the shell command in Msgv128. If
the client does not specify a shell command, the server starts bash.
The client polls for stdout bytes by setting Type=1. The client may
optionally include stdin bytes to send to the server.

Request:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 32h | Type  | 0=shell command in Msgv128 |
|     |       | 1=stdin bytes in Msgv128 (empty for a poll) |
|     |Msgv128| shell command / stdin bytes |

Response:

| CMD | DATA  | Comments |
| ----| ----- | -------- |
| 33h | Type  | 0=no stdout bytes, 1=stdout bytes, 0xFF=exit |
|     |Msgv128| stdout bytes |

