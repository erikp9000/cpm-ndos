# cpm-ndos

NDOS (Network Disk Operating System) is a terminate-and-stay-resident (TSR) 
program for CP/M 2.2 which adds a network drive (P:) over a serial port. The 
serial port is connected to a Linux computer which runs a service to convert 
the NDOS requests to Linux calls.

## Architecture

NDOS consists of three major parts: 

  - NDOS.COM – A CP/M 2.2 TSR which 'hooks' the BDOS to process commands 
    for the network drive 
  - CCP.COM – A relocatable version of CP/M 2.2 Command Console Processor
  - ndos-srv – Program that runs on a Linux computer

There are also several CP/M utilities:

  - CD.COM – Change the working directory on the server & print the working 
    directory
  - MKDIR.COM – Make a new directory on the server
  - RMDIR.COM – Remove a directory on the server
  - NSTAT.COM – Print network statistics
  - NECHO.COM – Send the string provided on the command line to the server 
    and print the response

## Known Issues

  - The CCP converts all command-line characters to upper-case and ndos-srv 
    converts them back to lower-case. Therefore, server directories with 
	upper-case characters cannot entered from NDOS though they can be seen in 
	their proper case by the CCP DIR command.

  - Filenames that don't comply with the 8.3 convention are truncated by 
    ndos-srv before returning them to NDOS. This means that long filenames on
	the server cannot be opened from NDOS.

  - Directory names longer than 9 characters are truncated by ndos-srv so the 
    full name is not viewable from NDOS though CD can still move into long-
	named directories.

  - Support for raw serial ports is temporarily not supported.
  

## NDOS.ASM/COM

The NDOS.COM TSR installs itself in the 2K bytes just below the BDOS and hooks 
the BDOS entry vector (addresses 6&7) to preserve itself and also so that all 
BDOS calls are first routed through the NDOS. The NDOS also hooks the Warm 
start vector in the BIOS jump table so that NDOS can reload the relocatable 
CCP.COM from drive A: on a warm start. If CCP.COM is not found, NDOS calls 
the old BIOS Warm start which recovers the CP/M system from the system tracks, 
removing NDOS from memory.

### Porting Considerations

  - The NDOS is not relocatable and must be built for the system memory. Adjust 
    memSz and biosSz in NDOS.ASM as appropriate for the target system.
	
  - The NDOS is configured to use the second serial port (@12h/13h) of the 
    88-2SIO Serial Interface Board for the Altair 8800. To support other systems, 
	the smsg and rmsg functions in NDOS.ASM must be updated.
	
  - The network drive is P:. Change NDOSDSK to select another drive.

### BDOS Function Summary

All BDOS functions not listed here are passed to the BDOS.

**NOTE** NDOS ignores the current user number (code) set by BDOS function 32. 
Thus, all files on the server belong to all user numbers.

| BDOS function code | Function name       | Comments |
| ------------------ | ------------------- | -------- |
| 13                 | RESET DISK SYSTEM   | NDOS sets DMA to default address (80h) and jumps to BDOS. |
| 14                 | SELECT DISK         | NDOS stores new active disk and returns if network disk; else, jumps to BDOS. |
| 15                 | OPEN FILE           | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 16                 | CLOSE FILE          | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 17                 | SEARCH FOR FIRST    | If the network disk is selected in the indicated FCB, NDOS calls server and returns response in the DMA buffer. The response is always returned in the DMA buffer as the first directory entry (directory code=0) and the last extent of the file so that S2, EX, and RC can be used to compute the file size. The block allocation vector of the directory entry is initialized based on the number of 1024-byte blocks used for the final directory extent of the file (all blocks are 3). This supports STAT.COM which uses the  |
| 18                 | SEARCH FOR NEXT     | If the directory of the network disk is currently being accessed, then NDOS calls the server and returns the next matching directory entry, else, jumps to BDOS. If the EX byte in the FCB was set to '?' when srchf (17) was called, then NDOS will return all of the directory extents (up to 32 for a maximum of 512KB file size) for the matching file, in reverse order. Since the first response was the last directory extent, the remaining directory extent allocation vectors are always full (all blocks are 3). |
| 19                 | DELETE FILE         | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 20                 | READ SEQUENTIAL     | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the result in the DMA; else, jumps to BDOS. Upon return, the caller's FCB bytes, S2, EX, and CR are updated to point to the next block. Random access is supported by the caller setting S2,EX,CR in the FCB accordingly prior to the call. |
| 21                 | WRITE SEQUENTIAL    | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. Upon return, the caller's FCB bytes, S2, EX, and CR are updated to point to the next block.Random access is supported by the caller setting S2,EX,CR in the FCB accordingly prior to the call. |
| 22                 | MAKE FILE           | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 23                 | RENAME FILE         | If the selected disk in the FCB is the network disk, NDOS calls the server and returns the status; else, jumps to BDOS. |
| 25                 | RETURN CURRENT DISK | If active disk is network disk, NDOS returns it, else jumps to BDOS |
| 26                 | SET DMA ADDRESS     | NDOS stores the new DMA address and jumps to BDOS. |
| 27                 | GET ADDR (ALLOC)    | If the active disk is the network disk, NDOS returns the network disk directory allocation vector which reports that the directory is full; else, jumps to BDOS. |
| 30                 | SET FILE ATTRIBUTES | Not supported. NDOS panics and warm boots the system. |
| 31                 | GETADDR(DISKPARMS)  | NDOS returns network disk parameter block if active disk is network disk, else jumps to BDOS; the disk parameter block indicates that there are 512 directory entries on the network disk and a data allocation block size of 1024 bytes (BSH=3, BLM=7). |
| 33                 | READ RANDOM         | Not supported. NDOS panics and warm boots the system. |
| 34                 | WRITE RANDOM        | Not supported. NDOS panics and warm boots the system. |
| 35                 | COMPUTE FILE SIZE   | Not supported. NDOS panics and warm boots the system. |
| 36                 | SET RANDOM RECORD   | If the selected disk in the FCB is the network disk, NDOS sets r0,r1,r2 in the FCB to the file offset addresed by S2,EX,CR; else, jumps to BDOS. |
| 40                 | WRITE RANDOM        | Not supported. NDOS panics and warm boots the system. |
| ^                  | WITH ZERO FILL      | ^ |
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
    in the configuration file. *[TODO]*
  - USR-TCP232-302 RS232-to-Ethernet Converter. The Converter can be configured 
    for baud rates from 600~230.4Kbps. The ndos-srv supports the TCP Client mode 
	(on TCP port 8234) in which the Converter connects to the configured server 
	name/IP address and sends/receives serial bytes over the TCP socket. 
	Identity and Keepalive packets are NOT supported.
	
### Configuration File

JSON format.

    { 
      "path": ["/dri", "/bin", "/microsoft"],
      "serial": [
        { "port": "/dev/ttyAMA0", "baud": "9600" },
        { "port": "/dev/ttyUSB0", "baud": "19200" }
      ]
    }

## NDOS Protocol

The NDOS Protocol is a request/response protocol where all requests are 
initiated by the client (CP/M machine). All messages are wrapped in the 
standard Envelope.

Envelope
All requests and responses are wrapped in a standard envelope.
	|LEN|CMD|DATA ...|CHK|
The LEN byte includes itself, the CMD byte, the CHK byte, and the length of the variable-length DATA field. Therefore, length(DATA) = LEN-3.
CHK = 2's complement of sum bytes from LEN to byte preceeding CHK. The recipient loads its checksum accumulator with 0 at the beginning of a message and adds each byte received to the accumulator. Upon receiving the CHK byte from the transmitter, the checksum shall be 0. If the checksum is not 0, there was an error in transmission and the packet shall be dropped.
Data
Find First (02h)
Find the first file matching the NAMEx8 and EXTx3 parameters. The FCBhi,FCBlo values are the actual address of the File Control Block on the client. The server uses this value to correlate the open files/directory on the server with the FCB in the client.
Request:
	CMD: 02h
	DATA: |FCBlo|FCBhi|NAMEx8|EXTx3|
Response:
	CMD: 03h
	DATA: |FCBlo|FCBhi|Status=0|NAMEx8|EXTx3|EX|S1=0|S2|RC|
Response for end of directory:
	CMD: 03h
	DATA: |FCBlo|FCBhi|Status=0FFh|
The file size is returned in S2, EX, and RC as a count of 128-byte blocks, where:
	S2=file size / 524288 [0-15, 4 bits]
	EX=(file size % 524288) / 16384 [0-31, 5 bits]
	RC=(file size % 16384) / 128 [0-127, 7 bits]
The maximum file size is 8MB (8388608 bytes) or 65536 128-byte blocks. NDOS populates the block allocation vector of the directory entry to indicate how many blocks of the last extent are allocated before returning to the caller. 
If a directory is matched, the name is truncated to 11 bytes and returned enclosed in '<' and '>' in Filename and Extension. The "<.>" is the current directory and "<..>" is the previous directory. Directory names are returned in their proper case while filenames are always returned in lower-case.
If the file is read-only on the server, then the most-significant bit of the first EXT byte is set to 1. The system file type (most-significant bit of the second EXT byte) is not supported.
Find Next (04h)
Find the next file matching the search parameters specified in Find First.
Request:
	CMD: 04h
	DATA:  |FCBlo|FCBhi|
Response:
	CMD: 05h
	DATA: Same as Find First
Open File (06h)
Open the named file on the server for reading and writing. If the file does not exist, an error is returned.
Request:
	CMD: 06h
	DATA:  |FCBlo|FCBhi|NAMEx8|EXTx3|
Response:
	CMD: 07h
	DATA: |FCBlo|FCBhi|Status|
Status=0 (success) or 0FFh (not found).
Close File (08h)
Close the file referenced by FBChi,FCBlo. 
Request:
	CMD: 08h
	DATA: |FCBlo|FCBhi|
Response:
	CMD: 09h
	DATA: |FCBlo|FCBhi|Status|
Status=0 (success) or 0FFh (error).
Delete File (0ah)
Delete the named file on the server.
Request:
	CMD: 0ah
	DATA:  |FCBlo|FCBhi|NAMEx8|EXTx3|
Response:
	CMD: 0bh
	DATA: |FCBlo|FCBhi|Status|
Status=0 (success) or 0FFh (not found/access denied/etc.).
Read File (0ch)
Read the 128-byte block of a previously opened file starting at the offset specified by Rechi,Reclo. If Rechi,Reclo is not specified, read the next 128-byte block. The last partial 128-byte block at the end of the file is automatically filled with CTRL-Z characters.
Request:
	CMD: 0ch
	DATA: |FCBlo|FCBhi|[Reclo|Rechi|]
Where Rechi,Reclo is the 128-byte record offset.
Response:
	CMD: 0dh
	DATA: |FCBlo|FCBhi|Status|[Datax128|]
Status=0 (success), 1 (end of file) or 0FFh (failure).
Datax128 is not returned on failure.
Write File (0eh)
Write the 128-byte block, Datax128, to a previously opened file at the location specified by Rechi,Reclo. If Rechi,Reclo is not specified, then write to the file at the current location.
Request:
	CMD: 0eh
	DATA:  |FCBlo|FCBhi|[Reclo|Rechi|]Datax128|
Response:
	CMD: 0fh
	DATA: |FCBlo|FCBhi|Status|
Status=0 (success), 5 (disk full) or 0FFh (failure).
Create File (10h)
Create the named file on the server for writing only. If the file already exists, it is truncated.
Request:
	CMD: 10h
	DATA: |FCBlo|FCBhi|NAMEx8|EXTx3|
Response:
	CMD: 11h
	DATA: |FCBlo|FCBhi|Status|
Status=0 (success) or 0FFh (failure).
Rename File (12h)
Rename the old filename on the server to new filename. Only renames the first file found.
Request:
	CMD: 12h
	DATA: |oldNAMEx8|oldEXTx3|newNAMEx8|newEXTx3|
Response:
	CMD: 13h
	DATA: |FCBlo|FCBhi|Status|
Status=0 (success) or 0FFh (failure).
Change Dir (20h)
Change the client's working directory on the server. Note that only lower-case directory names on the server are supported. 
Request:
	CMD: 20h
	DATA: |Pathv128|
Response:
	CMD: 21h
	DATA: |Status|Pathv128|
Status=0 (success) or 0ffh (failure). The client's current working directory is returned in the variable-length Pathv128 for success and failure.
Make Dir (22h)
Make a directory on the server. The server directory will be in lower case. 
Request:
	CMD: 22h
	DATA: |Pathv128|
Response:
	CMD: 23h
	DATA: |Status|Errorv128|
Status=0 (success) or 0ffh (failure).  The variable-length error message, if any, is returned in Errorv128.
Remove Dir (24h)
Remove a directory on the server.
Request:
	CMD: 24h
	DATA: |Pathv128|
Response:
	CMD: 25h
	DATA: |Status|Errorv128|
Status=0 (success) or 0ffh (failure).  The variable-length error message, if any, is returned in Errorv128.
Echo (30h)
The server returns the variable-length message it receives.
Request:
	CMD: 30h
	DATA: |Msgv128|
Response:
	CMD: 31h
	DATA: |Msgv128|
