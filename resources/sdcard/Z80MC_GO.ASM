;Z80 Membership Card - CP/M BIOS
;File Z80MC_GO.asm

;Warning: FCB's must never cross page boundaries.
;Some RAM must map to definitions in ROM

;Revisions
;Dec 10 - Changed routine for Track/Sec to Logical to multipy by actual Sectors per Track, no longer fixed coded for 25 SPT
;Dec 10 - Changed location of BIOS SCRATCH AREA to band-aid fix large disk errors on D:


CR		EQU 13
LF		EQU 10
EOS		EQU 0

CPM_DSK_BUFF	EQU 80H	;Default CPM Buffer of 128 Bytes

RAMROM		equ	0xC1	;RAM /ROM selection


		ORG 0F400H
		CALL	PRINTI		;System Start, Display Welcome Message	
		DB	CR,LF,"Z80MC CP/M LOADER.  Dec 10, 2018",CR,LF,EOS
		
		JP	CPM_BOOTER

FCB_CONFIG	DB	0	;FSTAT		.BLOCK	1	;+0  Status of FCB, 00=File Not Open
		DB	"CPMDISKSTXT"		;+1
FCB_CONFIG_C1	DW	00000H	;AFClus0	;+12 First Cluster of File as given by the Directory Entry.
		DW	0FFFFH	;CRFClus	;+14 Current Relative Cluster location in file, (0 to F for a system with 32 Sectors per Cluster)
		DW	0FFFFH	;CAFClus	;+16 Current Absolute Cluster location in file, set to AFClus0, then updated with FAT
		DW	0FFFFH	;RFSec		;+18 Relative Sector being addressed (0 to 500, based 26 sectors per track and 77 tracks Divide by 4)
		DW	0FFFFH	;SSOC		;+20 Starting Sector of Cluster, this is the first Sector for that Cluster
		DW	0FFFFH			;+22
		DW	0FFFFH	;ABS_SEC	;+24 Absolute Sector of Current Relative Sector
		DW	0FFFFH			;
		DW	0FFFFH			;+28
		DW	0FFFFH			;+30
		
DPBPTR		DW	DPB0

FILESIZESEARCH	DS	4		;32BIT File Size to Search for
X32		DS	4		;32BIT Converted ASCII-HEX input (File Size)


CPM_BOOTER	LD	HL,SDISKA	;Clear RAM for the Drive FCB's
		LD	B,128		;These FCB's are custom to this firmware
		CALL	ROM_SUB		;and are for the FAT-16 files on the SD cards
		DW	VCLEAR_BLOCK	;Nothing to do with CP/M.			

		LD	HL,FCB_CONFIG
		LD	(FCB_PTR),HL
				
		CALL	ROM_SUB
		DW	VSD_OPEN
		JP Z,	GO_HALT
		
;DUMP_FILE	CALL	GET_LINE	;HL = LINE_BUFF
;		CALL	PRINT
;		JR	DUMP_FILE
		
		LD	DE,SDISKA
		LD	B,4	
FETCH_LP	CALL	FETCH_NAME	;Preload all SD_FCB's with file names for 4 disks
		DJNZ	FETCH_LP
									
BOOT_MENU	LD	HL,BOOT_MENU
		PUSH	HL
		
		CALL	PRINTI	
		DB	CR,LF,"Menu",CR,LF
		DB	CR,LF,"C   BOOT CP/M"
		DB	CR,LF,"L   LIST FILES"
		DB	CR,LF,EOS

		XOR	A		;Loop through the 4 SD_FCB's and try to open/init the FCB's
BMD_LP		PUSH	AF
		LD	D,A		;D=A=File (0 to 3) (D for printing)
		CALL	SET_FCB_PTR
		LD	(DPBPTR),HL	;Save the DPB location
		LD	A,D
		INC	A
		CALL	PUT_HEX
		CALL	PRINTI
		DB	" - Disk ",EOS
		LD	A,D
		ADD	A,'A'
		CALL	PUT_CHAR
		CALL	PRINTI
		DB	" = ",EOS

		LD	A,0xC0		;Enable view of File And Size
		LD	(VIEW_FLAGS),A
		CALL	ROM_SUB		;Display Filename and Size
		DW	VSD_OPEN

		
		LD	HL,FILESIZE		;Save the File Size for search
		LD	DE,FILESIZESEARCH
		LD	BC,4			;4 bytes
		LDIR				;COPY 4 BYTES

					;Read Config file to find paramaters for a file of this size
		LD	HL,FCB_CONFIG
		LD	(FCB_PTR),HL
		
		XOR	A		;Disable view of File And Size
		LD	(VIEW_FLAGS),A
		
		CALL	ROM_SUB		;Silent Open
		DW	VSD_OPEN

		JP Z,	GO_HALT

SSF_LP		CALL	ROM_SUB		;GET A LINE FROM THE FILE @FCB_PTR
		DW	VLINE_INPUT
		JR NZ,	SSF_NOTFOUND	;Jump if EOF reached
		
		LD	DE,X32
		CALL	ASC_BIN32	;Convert the 8 ASCII chars @(HL) to 32Bit @(DE)
		JR C,	SSF_LP		;Jump if invalid HEX Chars encountered

		PUSH	HL		;Save Pointer to Line Input
		LD	HL,FILESIZESEARCH
		CALL	COMP32
		POP	HL		;Restore Line Pointer
		JR NZ,	SSF_LP

					;HURRAY, WE HAVE FOUND THE RIGHT DISK SIZE		
					;COPY DPB, PRINT MSG
		INC	HL		;Advance past Space
		LD	DE,(DPBPTR)
		LD	B,15
GTL_COPY_LP	CALL	ROM_SUB		;(DE) = VAL("&H" + LEFT$((HL),2)); HL=HL+2
		DW	VASC2BIN
		JR NC,	GTL_HEX_OK
		CALL	PRINTI
		DB	" BAD HEX",EOS
		JP	GO_HALT		
GTL_HEX_OK	INC	DE
		DJNZ	GTL_COPY_LP
		CALL	ROM_SUB	
		DW	VPRINT		;Print rest of line.
		JR	BMD_NEXT

SSF_NOTFOUND	CALL	PRINTI
		DB	" - DISK SIZE NOT LISTED",EOS

BMD_NEXT	POP	AF
		INC	A
		CP	4
		JP NZ,	BMD_LP

		LD	HL,CPM_DSK_BUFF		;Default CPM DMAADD
		LD	(DMAADD),HL
		LD	HL,SDISKA		;Default FCB_PTR for Disk-A
		LD	(FCB_PTR),HL

MENU_ENTER	CALL	PRINTI		;BOOT Menu
		DB CR,LF,"\>",EOS

		LD	HL,RC_TYPE	;IF NOT AUTO BOOT
		BIT	7,(HL)
		JR  Z,	MENU_GETCHAR	;Skip the dots
		
		LD	B,10
		CALL	DOT_GETCHAR	;C=1 if dots timed out or <TAB>, or C=0 and A=char
		JP  C,	CBOOTV
		RES	7,(HL)		;Cancel AUTO BOOT
		JR  	MENU_DO

MENU_GETCHAR	CALL	GET_CHAR

MENU_DO		CALL	TO_UPPER
		CP 	'C'		;
		JP Z, 	CBOOTV		; C = BOOT CP/M
		CP 	'L'		;
		JP Z, 	DO_PRINT_DIR	; L = List Files
		CP	'1'
		JP C,	BOOT_MENU
		CP	'5'
		JP NC,	BOOT_MENU
		DEC	A
		CALL	SET_FCB_PTR
		CALL	INPUT_FNAME
		LD	HL, (FCB_PTR)
		INC	HL		;FNAME
		EX	DE, HL	
		LD	HL,FILENAME
		LD	BC,11
		LDIR
		JP	BOOT_MENU
		
				
;===============================================
;DOT_GETCHAR
;in:	B=Count of Dots
;out: 	C=1, No Char (Time Out)
;	C=0, A = Char
;-----------------------------------------------
DOT_GETCHAR	LD	A,1
		CALL	ROM_SUB		;
		DW	VTIMED_GETCHAR	;C=0, A=Byte from Buffer; C=1, no byte
		JR  C,	DGC_DOT
		CP	9
		JR   Z,	DGC_RET
		RET			;Return to check charcter
DGC_DOT		LD	A,'.'		;Put out some thinking dots
		CALL	PUT_CHAR
		DJNZ	DOT_GETCHAR
DGC_RET		SCF
		RET
		
	
		
		

DO_PRINT_DIR	CALL	PRINT_DIR
		JP	MENU_ENTER

FETCH_NAME	PUSH	BC
		PUSH	DE
		CALL	GET_LINE	;Returns HL=Pointer to Line Buffer
		POP	DE
		LD	BC,32	;COPY 32 CHARACTERS (ONLY chars 2-12 IS FILE NAME)
		LDIR
		POP	BC
		RET

GET_LINE	CALL	ROM_SUB		;GET A LINE FROM THE FILE @FCB_PTR ;HL = LINE_BUFF
		DW	VLINE_INPUT
		RET Z

GO_HALT		CALL	PRINTI
		DB	" - HALT",EOS
		JR	$

COMP32		LD	BC,4
COMP32_LP	LD	A,(DE)
		CPI
		RET	NZ
		RET	PO
		INC	DE		
		JR	COMP32_LP

;Convert the 8 ASCII chars @(HL) to 32Bit @(DE)
;Input:	HL points to ASCII
;	DE points to 32Bit Variable in Memory
;Output:HL points to next ASCII input string
;	DE unchanged
;	A, B Destroyed
;	C = set if invalid ASCII HEX Char encountered
ASC_BIN32	PUSH	DE
		LD	B,4
AB_LP		CALL	ROM_SUB
		DW	VASC2BIN
		JR C,	AB_RET
		INC	DE
		DJNZ	AB_LP
AB_RET		POP	DE
		RET


;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;PRINT IMMEDIATE
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
PRINTI:		EX	(SP),HL		;HL = Top of Stack
		CALL	ROM_SUB
		DW	VPRINT
		EX	(SP),HL		;Move updated return address back to stack
		RET
		
PUT_HEX		CALL	MAP_ROM
		CALL	VPUT_HEX
		JP	MAP_RAM

RX_COUNT	CALL	MAP_ROM
		CALL	VRX_COUNT
		JP	MAP_RAM

TO_UPPER	CALL	MAP_ROM
		CALL	VTO_UPPER
		JP	MAP_RAM

INPUT_FNAME	CALL	MAP_ROM
		CALL	VINPUT_FNAME
		JP	MAP_RAM

PRINT_FNAME	CALL	MAP_ROM
		CALL	VPRINT_FNAME
		JP	MAP_RAM


PRINT_DIR	CALL	MAP_ROM
		CALL	VPRINT_DIR
		JP	MAP_RAM

PUT_BYTE	CALL	MAP_ROM
		CALL	VPUT_BYTE
		JP	MAP_RAM

PUT_HL		CALL	MAP_ROM
		LD	A,H
		CALL	VPUT_BYTE
		LD	A,L
		CALL	VPUT_BYTE
		JP	MAP_RAM





;----------------------------------------------------------------------------------------------------; CP/M BIOS
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;----------------------------------------------------------------------------------------------------; CP/M BIOS



;***************************************************
;*** THIS BEGINS THE AREA WHICH REQUIRES CHANGES ***
;***      FOR DIFFERENT CONSOLE I/O SYSTEMS      ***
;***************************************************

MSIZE		EQU  61	;MEMORY SIZE IN KBYTES.

;*******************************************************
;*** THIS IS THE END OF THE AREA WHICH NORMALLY NEED ***
;***     BE CHANGED FOR MOST CONSOLE I/O SYSTEMS     ***
;*******************************************************

IOBYTE		EQU  3		;ADDRESS OF I/O BYTE.
CCP		EQU  (MSIZE-7)*1024	;START OF CPM (D800)
BDOS		EQU  CCP+806H		;START OF BDOS (E006)
BIOS		EQU  CCP+1600H		;START OF BIOS (EE00)
CPMLEN		EQU  BIOS-CCP		;LENGTH OF CPM SYSTEM (LESS BIOS)
NSECTS		EQU  CPMLEN/128		;NUMBER OF SECTORS IN IT.

;       Page Zero Definitions.
IOBYTE		EQU	3		;Location of IOBYTE
CDISK		EQU	4		;Location of current disk
BIORAM		EQU	40h		;16 ram cells
OPTS		EQU	BIORAM		;GBC DISK1 board switch options
;			BIORAM+1	;GBC (cell before TICK)
TICK		EQU	BIORAM+2	;GBC Sample period
DBUF		EQU	80h		;Default sector buffer

		ORG	BIOS

; I/O JUMP VECTOR
; THIS IS WHERE CP/M CALLS WHENEVER IT NEEDS
; TO DO ANY INPUT/OUTPUT OPERATION.
; USER PROGRAMS MAY USE THESE ENTRY POINTS
; ALSO, BUT NOTE THAT THE LOCATION OF THIS
; VECTOR CHANGES WITH THE MEMORY SIZE.
;
CBOOTV	JP  	CBOOT	;FROM COLD START LOADER.
WBOOTV	JP  	WBOOT	;FROM WARM BOOT.
	JP  	CONST	;CHECK CONSOLE KB STATUS.
	JP  	CONIN	;READ CONSOLE CHARACTER.
	JP  	CONOT	;WRITE CONSOLE CHARACTER.
	JP  	LIST	;WRITE LISTING CHAR.
	JP  	PUNCH	;WRITE PUNCH CHAR.
	JP  	READER	;READ READER CHAR.
	JP  	HOME	;MOVE DISK TO TRACK ZERO.
SELDSKV	JP  	SELDSK	;SELECT DISK DRIVE.
	JP  	SETTRK	;SEEK TO TRACK IN REG A.
	JP  	SETSEC	;SET SECTOR NUMBER.
SETDMAV	JP  	SETDMA	;SET DISK STARTING ADR.
	JP  	DREAD	;READ SELECTED SECTOR.
	JP  	DWRITE	;WRITE SELECTED SECTOR.
	JP  	LISTST	;List status (output)
	JP  	SECTRN	;Translate sector number

;	Control Blocks for disk drives

DPBASE	DW	0,0,0,0,DIRBUF,DPB0,CSV0,ALV0	;Drive A:
	DW	0,0,0,0,DIRBUF,DPB1,CSV1,ALV1	;Drive B:
	DW	0,0,0,0,DIRBUF,DPB2,CSV2,ALV2	;Drive C:
	DW	0,0,0,0,DIRBUF,DPB3,CSV3,ALV3	;Drive D:

NDSK	EQU	4


;       Disk type definition blocks for each particular mode.
DPB0	DW	26		;SEC PER TRACK
        DB	3		;BLOCK SHIFT
        DB	7		;BLOCK MASK
        DB	0		;EXTNT MASK
        DW	242		;DISK SIZE-1
        DW	63		;DIRECTORY MAX
        DB	11000000b	;ALLOC0
        DB	00000000b	;ALLOC1
        DW	16		;CHECK SIZE
        DW	2		;OFFSET

DPB1	DW	26		;SEC PER TRACK
        DB	3		;BLOCK SHIFT
        DB	7		;BLOCK MASK
        DB	0		;EXTNT MASK
        DW	242		;DISK SIZE-1
        DW	63		;DIRECTORY MAX
        DB	11000000b	;ALLOC0
        DB	00000000b	;ALLOC1
        DW	16		;CHECK SIZE
        DW	2		;OFFSET

;DEBUG swapped 2 <-> 3
DPB3	DW	26		;SEC PER TRACK
        DB	3		;BLOCK SHIFT
        DB	7		;BLOCK MASK
        DB	0		;EXTNT MASK
        DW	242		;DISK SIZE-1
        DW	63		;DIRECTORY MAX
        DB	11000000b	;ALLOC0
        DB	00000000b	;ALLOC1
        DW	16		;CHECK SIZE
        DW	2		;OFFSET

DPB2	DW	26		;SEC PER TRACK
        DB	3		;BLOCK SHIFT
        DB	7		;BLOCK MASK
        DB	0		;EXTNT MASK
        DW	242		;DISK SIZE-1
        DW	63		;DIRECTORY MAX
        DB	11000000b	;ALLOC0
        DB	00000000b	;ALLOC1
        DW	16		;CHECK SIZE
        DW	2		;OFFSET




;       B O O T   C P / M   f r o m   d i s k.
;
;       The CBOOT entry point gets control from the cold start
;       loader and is responsible for the basic system initial-
;       ization.  This includes outputting a sign-on message and
;       initializing the following page zero locations:
;
;          0,1,2: Set to the warmstart jump vector.
;              3: Set to the initial IOBYTE value.
;              4: Default and logged on drive.
;          5,6,7: Set to a jump to BDOS.
;             40: (Set by BOOT) Board switch options.
;
;       If BANG is true (DISK1 bit serial latch is to be supported), then
;       board switch option I means to use the BitBanger for console I/O.
;       Register C must contain the selected drive, which is zero to
;       select the A drive.  The exit address is to the CCP routine.
;
;
;       The WBOOT entry point gets control when a warm start occurs,
;       a ^C from the console, a jump to BDOS (function 0), or a jump to
;       location zero.  The WBOOT routine reads the CCP and BDOS from the
;       appropriate disk sectors.  WBOOT must also re-initialize locations
;       0,1,2 and 5,6,7.  The WBOOT routines exits with the C register set
;       to the appropriate drive selection value.  The exit address is to
;       the CCP routine.
;
CBOOT:	LD  SP,STACKTOP		;SET STACK POINTER.
	CALL PRINTI
	DB CR,LF,"Z80MC "
	DB   (MSIZE / 10) + '0', (MSIZE % 10) + '0'
	DB "K CP/M 2.2",CR,LF,EOS

        XOR     A
        LD     (CDISK), A           ;Force A drive
        LD     (IOBYTE), A          ;Clear I/O byte

; WARM-BOOT:  READ ALL OF CPM BACK IN
; EXCEPT BIOS, THEN JUMP TO CCP.
;
WBOOT:	LD  	SP,STACKTOP		;SET STACK POINTER.
	
	LD	HL,CPM_BOOTER
	PUSH	HL

	CALL	MAP_RAM

	CALL PRINTI
	DB CR,LF,"WBOOT",CR,LF,EOS
	
				;Boot CP/M

	LD	A, (CDISK)	;SAVE DISK NUMBER.
	LD	(TEMP), A      
	LD	C,0	;Set DISK A
	CALL	SELDSKV

	LD	DE,CCP		;Save destination address
	LD	B,NSECTS
	LD	HL,1
WBLP	LD	(DISK_LOG_SEC), HL	;Set first sector to read from disk
	PUSH	BC
	PUSH	DE
	CALL	DISK_READ	;HL = Quarter Buffer, BC=128
	POP	DE
	LDIR			;Copy the SD_RAM_BUFFER to CP/M
	LD	HL, (DISK_LOG_SEC)	;Set first sector to read from disk
	INC	HL
	POP	BC
	DJNZ	WBLP

; SET UP JUMPS IN CP/M PAGE ZERO.

	LD  	BC,DBUF	;SET DEFAULT DMA ADR.
	CALL	SETDMAV
	LD	A,0C3H	;PUT JMP TO WBOOT
	LD	(0), A		;ADR AT ZERO.
	LD	(5), A
	LD	HL,WBOOTV
	LD	(1), HL
	LD	HL,BDOS	;PUT JUMP TO BDOS
	LD	(6), HL		;AT ADR 5,6,7.
	XOR	A
	LD	(3),A
	LD	(4),A
	
	LD  A, (TEMP)
	LD  (CDISK), A
	LD  C,A
		
	JP  CCP             ;Go to CPM
        

;===============================================
;       C O N S O L   S T A T U S
;
;       This routine samples the Console status and
;       returns the following values in the A register.
;
;       EXIT    A = 0 (zero), means no character
;               currently ready to read.
;
;               A = FFh (255), means character
;               currently ready to read.
;-----------------------------------------------
CONST:	LD	(SP_SAVE),SP
	LD	SP,STACK_TEMP
	CALL	RX_COUNT
	OR	A
	JR Z,	CONST_RET
	OR	0FFH
CONST_RET
	LD	SP,(SP_SAVE)
	RET		;10


;===============================================
;       C O N S O L   I N P U T
;
;       Read the next character into the A register, clearing the high
;       order bit.  If no character currently ready to read then wait
;       for a character to arrive before returning.
;
;       EXIT    A = character read from terminal.
;-----------------------------------------------
CONIN:	LD	(SP_SAVE),SP
	LD	SP,STACK_TEMP	
CILP	CALL	IN_CHAR	;Get Char No Echo
	JR C,	CILP
	AND	7FH	;MAKE MOST SIG. BIT = 0.
	CP	7FH	;IS IT A RUBOUT?
	JR NZ,	CONIN_RET	;RETURN IF NOT.
	LD	(CONOTF), A	;SET NO PRINT FLAG.
CONIN_RET
	LD	SP,(SP_SAVE)
	RET		;RETURN FROM CONIN.
	
;===============================================
;       C O N S O L   O U T P U T
;
;       Send a character to the console.  If the console is not ready to
;       receive a character wait until the console is ready.
;
;       ENTRY   C = ASCII character to output to console.
;-----------------------------------------------
CONOT:	LD	(SP_SAVE),SP
	LD	SP,STACK_TEMP		
	LD  	A,C		;GET CHARACTER.
	CP  	7FH		;IS IT A RUBOUT?
	JR Z,	CONOT_RET	;IF SO, DON'T PRINT IT.
	LD  	A, (CONOTF)	;GET NO PRINT FLAG.
	OR  	A		;SET CPU FLAGS.
	JP Z,   CONOTA		;NOT SET, SO PRINT.
	XOR  	A		;RESET THE FLAG
	LD  	(CONOTF), A	;TO ZERO.
	LD  	C,8		;PRINT BACKSPACE.
	CALL 	CONOTA
	LD  	A,' '		;PRINT SPACE.
	CALL 	PUT_CHAR
				;ANOTHER BACKSPACE.
CONOTA:	LD  	A,C		;GET CHARACTER.
	CALL 	PUT_CHAR	;PRINT IT.
CONOT_RET
	LD	SP,(SP_SAVE)
	RET			;RETURN.


	
	

;
; WRITE A CHARACTER ON LISTING DEVICE.
;
LIST:

LTBSY	
	RET		;RETURN FROM LIST.


;
; PUNCH PAPER TAPE.
;
PUNCH:	RET		;RETURN FROM PUNCH.

;
;  NORMALLY USED TO READ PAPER TAPE.
;
READER:	RET		;RETURN FROM READER.

LISTST	RET


;       S E L E C T   D I S K   D R I V E
;
;       Select the disk drive for subsequent disk transfers and
;       return the appropriate DPH address. 
;
;       ENTRY   C = disk delection value.
;
;       EXIT    HL = 0, if drive not selectable.
;               HL = DPH address if drive is selectable.
;
SELDSK:	LD	(SP_SAVE),SP
	LD	SP,STACK_TEMP		
	LD	HL,0
	LD	A,C	;GET NEW DISK NUMBER.
	CP	NDSK
	JR NC,	SELDSK_RET	;If Disk invalid...EXIT

	CALL SET_FCB_PTR ;Set the FCB PTR for the correct SD File & HL = DPBASE[A] + 10 (pointer to DPT)
			 ;Set DPH_PTR for DPBASE[A] (or 0000 if drive not exist)

	CALL	ROM_SUB	
	DW	VLD_HL_HL
	LD	(SEC_PER_TRACK),HL
	LD	HL,(DPH_PTR)

SELDSK_RET


	;CALL PRINTI		;DEBUG
	;DB "SLD:",EOS
	;CALL PUT_HL
	;XOR  A		;SET A = 0.
	
	LD	SP,(SP_SAVE)
	RET		;RETURN FROM SELDSK.


; MOVE DISK TO TRACK ZERO.
;
HOME:	LD  C,0	;SEEK TO TRACK ZERO.
;
; SET TRACK NUMBER TO WHATEVER IS IN REGISTER C.
; ALSO PERFORM MOVE TO THE CORRECT TRACK (SEEK).
;
SETTRK:	LD  A,C		;GET NEW TRACK NUMBER.
	LD  (TRK), A	;UPDATE OLD WITH NEW.
	LD  A,B		;
	LD  (TRK+1), A	;

; MOVE THE HEAD TO THE TRACK IN REGISTER A.
;
	XOR  A		;Clear flags
	RET		;RETURN FROM SEEK.

;
; SET DISK SECTOR NUMBER.
;
SETSEC:	LD  A,C		;GET SECTOR NUMBER.
	LD  (SECT), A	;PUT AT SECT # ADDRESS.
	LD  A,B		;
	LD  (SECT+1), A	;
	XOR  A		;Clear flags
	RET		;RETURN FROM SETSEC.
;
; SET DISK DMA ADDRESS.
;
SETDMA:	LD  H,B		;MOVE B&C TO H&L.
	LD  L,C
	LD (DMAADD), HL	;PUT AT DMA ADR ADDRESS.
	RET		;RETURN FROM SETDMA.


;       Translate sector number from logical to physical.
;
;       ENTRY   DE = 0, no translation required.
;               DE = translation table address.
;               BC = sector number to translate.
;
;       EXIT    HL = translated sector.

SECTRN:	;EX	DE,HL
	;ADD	HL,BC
	;RET
	
	LD     L,C	;No Translation
        LD     H,B
        RET

;
; READ THE SECTOR AT SECT, FROM THE PRESENT DISK/TRACK/SSECT.
; USE STARTING ADDRESS AT DMAADD.
;
DREAD:	LD	(SP_SAVE),SP
	LD	SP,STACK_TEMP
	PUSH	HL
	PUSH	BC
	PUSH	DE
	CALL 	GETLOG	;Fetch Logical FSector of requested read
	JP NZ,	DREADE
	
	CALL	DISK_READ	;HL = Quarter Buffer, BC=128
	LD	DE, (DMAADD)	;Destination, CP/M Data Buffer
	;LD	BC,128
	LDIR		;Copy the SD_RAM_BUFFER to CP/M DMAADD
	XOR  A		;SET FLAGS.
	JR	DREADX

DREADE	CALL	PRINTI
	DB	"READ-ERROR",EOS
	LD	A,1	;ERROR
	OR	A
	
DREADX	POP	DE
	POP	BC
	POP	HL
	LD	SP,(SP_SAVE)
	RET


;
; WRITE THE SECTOR AT SECT, ON THE PRESENT TRACK.
; USE STARTING ADDRESS AT DMAADD.
;
DWRITE:	LD	(SP_SAVE),SP
	LD	SP,STACK_TEMP
	PUSH	HL
	PUSH	AF
	PUSH	BC
	PUSH	DE
	CALL 	GETLOG	;Fetch Logical FSector of requested write
	JP NZ,	DREADE
			;DISK_READ will find the right Cluster/File sector *AND* Flush any previous writes.
			
	CALL	DISK_READ	;HL = Quarter Buffer, BC=128
	EX	DE, HL	
	LD	HL, (DMAADD)		;Source, CP/M Data Buffer
	;LD	BC,128
	LDIR		;Copy the SD_RAM_BUFFER to CP/M DMAADD
	LD	A,0FFH
	LD	(DIRTY_DATA), A
	POP	DE
	POP	BC
	POP	AF
	XOR	A		;SET FLAGS.
	POP	HL
	LD	SP,(SP_SAVE)
	RET
	

; Return Logical Disk Sector based on TRACK and SECTOR
; Fixed to 26 Sectors per track
; Track starts at 0 for first track
; Sector starts at 0 for first sector
;
GETLOG		LD	BC,(SEC_PER_TRACK)
		LD	DE,(TRK)
		LD	HL,0			;DE=TRACK#, BC = SEC_PER_TRACK, HL = 0 = RESULT
		
MULT_LOOP	LD	A,B
		OR	C
		JP  Z,	MULT_DONE
		SRL	B			;Shift BC right
		RR	C
		JP  NC,	MULT_SKIP
		ADD	HL,DE
		JP  C,	MULT_OVRF		;
MULT_SKIP	EX	DE,HL
		ADD	HL,HL			;SHIFT HL UP
		EX	DE,HL
		JP  NC,	MULT_LOOP		;
		LD	DE,0xFFFF
		JP	MULT_LOOP
	
MULT_DONE	LD	DE,(SECT)
		ADD	HL,DE			;HL= TRK * SPT + SECT 
		JP  C,	MULT_OVRF		;
		LD	(DISK_LOG_SEC), HL
		RET				;Z=1 if successful
		
MULT_OVRF	XOR	A
		DEC	A			;Z=0 if overflow
		RET






;----------------------------------------------------------------------------------------------------; FLOPPY DISK BIOS
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;----------------------------------------------------------------------------------------------------; FLOPPY DISK BIOS




;SDFCB:
FSTAT		EQU	0	;BLOCK	1	;+0  Status of FCB, 00=File Not Open
FNAME		EQU	1	;BLOCK	11	;+1  File name
AFClus0		EQU	12	;BLOCK	2	;+12 First Cluster of File as given by the Directory Entry.
CRFClus		EQU	14	;BLOCK	2	;+14 Current Relative Cluster location in file, (0 to F for a system with 32 Sectors per Cluster)
CAFClus		EQU	16	;BLOCK	2	;+16 Current Absolute Cluster location in file, set to AFClus0, then updated with FAT
RFSec		EQU	18	;BLOCK	2	;+18 Relative Sector being addressed (0 to 500, based 26 sectors per track and 77 tracks Divide by 4)
SSOC		EQU	20	;BLOCK	4	;+20 Starting Sector of Cluster, this is the first Sector for that Cluster
ABS_SEC		EQU	24	;BLOCK	4	;+24 Absolute Sector of Current Relative Sector



;=====================================================================================================
;Set FCB Pointer to one of 4 FCB blocks
;=====================================================================================================
SET_FCB_PTR	PUSH	BC
		AND	03H		;Limit & Clear Carry
		RRCA			;Set A x 32 to offset into correct FCB
		RRCA			;(Rotating 3 Right is faster than 5 Left)
		RRCA
		LD	C,A
		LD	B,0
		LD	HL,SDISKA	;HL = Base Address of FCB's
		ADD	HL,BC		;HL = FCB[A]   'Add offset x 32
		LD	(FCB_PTR), HL
		RRCA			;Set A x 16
		LD	C,A
		LD	A,(HL)		;Fetch FCB FSTAT (Is File OPEN / Exist)
		LD	HL,0		;HL = 0000 File (disk) not ready
		LD	(DPH_PTR), HL
		OR	A
		JR Z,	SFPE
		LD	HL,DPBASE	;HL = Base Address of Drive Parameter Header
		ADD	HL,BC		;HL = DPH[A]   'Add offset x 16
		LD	(DPH_PTR), HL
		LD	C,10
		ADD	HL,BC		;HL = Address of DPT Pointer (@DPH[A] + 10)
		CALL	ROM_SUB
		DW	VLD_HL_HL
		POP	BC
		RET

SFPE		CALL	PRINTI
		DB " FILE NOT OPENED",EOS
		POP	BC
		RET

		LD	BC,0x0003
		LD	DE,0xE900	;3E900h = 256,256 = 26 * 77 * 128 (Size of a disk)
;		CALL	CMP_HL_32	;Compare Dword
		JP NZ,	SDO_FSERR
SDO_FSERR	CALL	PRINTI
		DB " -FILE SIZE NOT 256256",EOS
		RET


;----------------------------------------------------------------------------------------------------; ROM BIOS
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;----------------------------------------------------------------------------------------------------; ROM BIOS



DISK_READ	LD	HL,(DISK_LOG_SEC)
		SRL	H		;Rotate HL right 2 times
		RR	L
		SRL	H
		RR	L
		LD	(LOGICAL_SEC),HL
				
		CALL	MAP_ROM
		CALL	VDISK_READ
		CALL	MAP_RAM

;--------- Set HL to the 128 byte Quarter Buffer of SD_RAM_BUFFER
SET_QUARTER	LD	BC,128		;Preset Length of copy = 128 Bytes
		LD	HL,SD_RAM_BUFFER
		LD	A,(DISK_LOG_SEC);Fetch sector to be read (lsb)
		RRA			;Adjust H to correct LSector of 128 Bytes
		RR	L
		RRA
		RET	NC
		INC	H
		RET

PUT_CHAR	CALL	MAP_ROM
		CALL	VPUT_CHAR
		JR	MAP_RAM

GET_CHAR	CALL	MAP_ROM
		CALL	VGET_CHAR
		JR	MAP_RAM

IN_CHAR		CALL	MAP_ROM
		CALL	VIN_CHAR
		JR	MAP_RAM

SD_READ_SEC	CALL	MAP_ROM
		CALL	VSD_READ_SEC
		JR	MAP_RAM


;		CALL	ROM_SUB
;		DW	PUT_CHAR
;
;	Stack must be in upper 32K of RAM (not banked switched)
ROM_SUB		EX	(SP),HL		;Fetch PC
		PUSH	AF
		LD	A,(HL)
		LD	(RSCA_L),A
		INC	HL
		LD	A,(HL)
		LD	(RSCA_H),A
		INC	HL
		XOR	A	;MAP ROM
		LD	(RRSTATE),A
		OUT	(RAMROM),A
		POP	AF
		EX	(SP),HL		;Return PC+2 to stack
		DB	0xCD		;Self modifying code for N-Way CALLS
RSCA_L		DB	0
RSCA_H		DB	0		;CALL RETURN FALLS INTO MAP_RAM
		
MAP_RAM		PUSH	AF		;Port will switch the 32K RAM from the middle card to 0-32K
		LD	A,1
		LD	(RRSTATE),A
		OUT	(RAMROM),A
		POP	AF
		RET

MAP_ROM		PUSH	AF
		XOR	A
		LD	(RRSTATE),A
		OUT	(RAMROM),A
		POP	AF
		RET

		

;----------------------------------------------------------------------------------------------------; RAM SPACE
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;----------------------------------------------------------------------------------------------------; RAM SPACE
		ORG	F900H
STACKNORM	DS	64
STACKTOP	EQU	$	;Stack starts saveing at FCFFh and grows downward

STACK_TEMPRAM	DS	64
STACK_TEMP	EQU	$	;Stack starts saveing at FCFFh and grows downward
		;DEFINE RAM AREAS FOR BDOS OPERATION
DIRBUF	DS	128
ALV0	DS	31
CSV0	DS	16
ALV1	DS	31
CSV1	DS	16
ALV2	DS	31	;DEBUG swapped 2 <-> 3	
CSV2	DS	16
ALV3	DS	31	;DEBUG swapped 2 <-> 3	
CSV3	DS	16

WTF	DS	1


; SPECIAL FLAGS.



		ORG	FAEBH
CONOTF		DS	1	;NO-PRINT FLAG (WHEN FF).

; BIOS SCRATCH AREA.
;
TRK:		DS	2	;CURRENT TRACK NUMBER.
SECT:		DS	2	;CURRENT SECTOR NUMBER.
SEC_PER_TRACK	DS	2	;SECTORS PER TRACK
DMAADD:		DS	2	;DISK TRANSFER ADDRESS.
DISKNO:		DS	1	;DISK NUMBER (TO CP/M).
TEMP:		DS	1	;TEMPORARY STORAGE.
DISK_LOG_SEC	DS	2	;Logical Disk Sector  (Input paramater for the File Read)
DPH_PTR		DS	2	;Pointer to Drive Paramaeter Header

SP_SAVE		DS	2	;

		ORG	0xFA00
;This RAM space overwrites DIRBUF space, but that is ok as it's used in the disk setup prior to booting CP/M
;This RAM space is used by LINE_INPUT and must never be called when CP/M is running.
LINE_BUFF	DS	128	
LINE_BUFFEND	DS	1	
GL_FILESIZE	DS	4	
GL_DBP		DS	2

		ORG	0xFB00
RESV1		DS	128	;Reserved for BASE SYSTEM

		ORG	0xFB80
;SDFCB:
FSTAT		EQU	0	;DS  1	;+0  Status of FCB, 00=File Not Open, 01=File Opened, 80=EOF (Line_Input)
FNAME		EQU	1	;DS 11	;+1  File name
AFClus0		EQU	12	;DS  2	;+12 First Cluster of File as given by the Directory Entry.
CRFClus		EQU	14	;DS  2	;+14 Current Relative Cluster location in file, (0 to F for a system with 32 Sectors per Cluster)
CAFClus		EQU	16	;DS  2	;+16 Current Absolute Cluster location in file, set to AFClus0, then updated with FAT
RFSec		EQU	18	;DS  2	;+18 Relative Sector being addressed (0 to 500, based 26 sectors per track and 77 tracks Divide by 4)
SSOC		EQU	20	;DS  4	;+20 Starting Sector of Cluster, this is the first Sector for that Cluster
ABS_SEC		EQU	24	;DS  4	;+24 Absolute Sector of Current Relative Sector
FSIZE		EQU	28	;DS  4	;+28 File Size of file (not used, just kept for completness)

;Warning: FCB's must never cross page boundaries.
SDISKA		DS	32	;File Control Block	;No FCB must cross a page boundary (simple 8 bit addition used for offseting into struct.)
SDISKB		DS	32	;File Control Block	;No FCB must cross a page boundary (simple 8 bit addition used for offseting into struct.)
SDISKC		DS	32	;File Control Block	;No FCB must cross a page boundary (simple 8 bit addition used for offseting into struct.)
SDISKD		DS	32	;File Control Block	;No FCB must cross a page boundary (simple 8 bit addition used for offseting into struct.)

;
;  ********   **     **  *********  *********  *********  ******** 
;  *********  **     **  *********  *********  *********  *********
;  **     **  **     **  **         **         **         **     **
;  **     **  **     **  **         **         **         **     **
;  ********   **     **  *******    *******    *******    ******** 
;  ********   **     **  *******    *******    *******    ******** 
;  **     **  **     **  **         **         **         **  **   
;  **     **  **     **  **         **         **         **   **  
;  *********  *********  **         **         *********  **    ** 
;  ********    *******   **         **         *********  **     **
;
		ORG	0xFC00
SD_RAM_BUFFER	DS	512	;FC00-FDFF 512 bytes of SD Sector Buffer space

RXBUFFER	DS	256	;FExx      256 bytes of RX Buffer space
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


		ORG	0xFF00
BIT_TABLE	DS	8

;Warning: FCB's must never cross page boundaries.
FCB_PTR		DS	2	;Pointer to Current FCB
				;WARNING FOLLOWING RAM must match BASE ROM RAM Definitions
FAT_CLEAR	EQU	$	;Clear bytes of RAM after this point on FAT_INIT
GH_START	DS	2	;HEX File, start address
VIEW_FLAGS	DS	1	;View File Load;  File Open View
				;BIT .0=View HEX Load, display file while reading HEX file
				;    .1=GH_START Address has been set
				;    .6=View FILE SIZE during File Open
				;    .7=View File Name & Found or Not status durin File Open

LOGICAL_SEC	DS	2	;Logical Sector for next Read Operation (Input paramater for the File Read)

DIRTY_DATA	DS	1	;Indicates when data Read has been altered, ie. Requires flushing back to SD Card
SD_CARD_TYPE	DS	1	;SD CARD TYPE
SDC_STATUS	DS	1	;SD Status Code returned
SD_PARAM	DS	4	;32 bit address parameter for SD Commands
SD_PART_TYPE	DS	1	;SD PARTITION TYPE
SD_PART_BASE	DS	4	;SD PARTITION STARTING RECORD
SD_PART_SIZE	DS	4	;SD PARTITION SIZE (Must follow SD_PART_BASE)
BYTE_P_SEC	DS	2	;0x0B Bytes per Sector (Almost always 512)
SEC_PER_CLUS	DS	1	;0x0D
RESERVED_SEC	DS	2	;0x0E - 0x0F
FAT_COPIES	DS	1	;0x10
ROOTDIR_SIZE	DS	2	;0x11 - 0x12
FILESYS_SEC	DS	4	;0x13 - 0x14 or 0x20 - 0x23
HIDDEN_SEC	DS	4	;0x1C - 0x1F
SEC_PER_FAT	DS	2	;0x16 - 0x17
FAT1START	DS	4	;Calculated Sector to FAT1
DIR_SECTOR	DS	4	;Calculated Sector to Root Directory
DATASTART	DS	4	;Calculated Sector to Data Area
SEC_PTR		DS	4	;Sector Pointer, general use variable that holds the last sector read
ENT_COUNT	DS	2	;Directory Entry Counter, Counts down maximum directory entries in Find File
FAT_CLR_LEN	EQU	$ - FAT_CLEAR 
FILENAME	DS	8	;File Name
FILEEXT		DS	3	;File Extension
FILESIZE	DS	4	;File Size


DIVIDE_FUNC	DS	2	;Pointer to the Divide Function
DF_SHIFTCNT	DS	1	;Count of shifts required for Fast Divide
MUL8		DS	1	;8 bit multiplier
MOD_FUNC	DS	2	;Pointer to the Mod Function
MODMASK		DS	1	;8 bit mask to get Relative Sector within a cluster from a Relative File sector

IK_HEXL		DS	1	;IMON HEX INPUT
IK_HEXH		DS	1	;IMON HEX INPUT
HEX_SOURCE	DS	2	;Pointer to the HEX INPUT Source (FILE or Serial Port)

	IF $ >= 0xFF78
	   ERROR RAM ALLOCATION ERROR
	ENDIF

;*** BEGIN COLD_BOOT_INIT (RAM that is to be initialized upon COLD BOOT) ***
RAMSIGNATURE	equ	0xFF78	;RAM signature
				;Following bytes are cleared on COLD BOOT
RC_TYPE		equ	0xFF80	;(1) Type of Reset (WARNING, Next 7 RC counters must end with lsb bits = 001,010,011,100,101,110,111)
RC_SOFT		equ	0xFF81	;(1) Count of Resets by SOFT F-E SWITCH
RC_STEP		equ	0xFF82	;(1) Count of Resets by SINGLE STEP
RC_CC		equ	0xFF83	;(1) Count of Resets by CTRL-C
RC_HALT		equ	0xFF84	;(1) Count of Resets by HALT INSTRUCTION
RC_F0		equ	0xFF85	;(1) Count of Resets by pressing F & 0 keys
RC_RST0		equ	0xFF86	;(1) Count of Resets by RST 0 INSTRUCTION
RC_HARD		equ	0xFF87	;(1) Count of Resets by UNKNOWN RESET LINE

ABUSS		equ	0xFF88	;(2) 
RegPtr		equ	0xFF8A	;(1) Ptr to Registers
IoPtr		equ	0xFF8B	;(1)  I/O Ptr
RX_ERR_LDRT	equ	0xFF8C	;(1) Counts False Start Bits (Noise Flag)
RX_ERR_STOP	equ	0xFF8D	;(1) Counts Missing Stop Bits (Framing Error)
RX_ERR_OVR	equ	0xFF8E	;(1) Counts Overrun Errors

CS_CLR_LEN	equ	0xFF8F-RC_TYPE

ACE_BAUD	equ	0xFF8F	;(1) Baudrate of ACE, 12=9600

PUTCHAR_EXE	equ	0xFF90	;(2) PutChar Execution (Set for PC_LED, PC_BIT, PC_ACE or PC_BOTH)
INCHAR_EXE	equ	0xFF92	;(2) InChar Execution (Set for IN_KEY, IN_BIT, IN_ACE or IN_BOTH)
;*** END COLD_BOOT_INIT (RAM that is to be initialized upon COLD BOOT) ***

HW_SETIO	equ	0xFF94
HW_LIST		equ	0xFF95	;Hardware List, 00 NO FP, 01=FP Only, 02 SIO only, 03 FP & SIO

				;Saved Registers
RSSP		equ	0xFF96	;Value of SP upon REGISTER SAVE
RSAF		equ	0xFF98	;Value of AF upon REGISTER SAVE
RSBC		equ	0xFF9A	;Value of BC upon REGISTER SAVE
RSDE		equ	0xFF9C	;Value of DE upon REGISTER SAVE
RSHL		equ	0xFF9E	;Value of HL upon REGISTER SAVE
RPC		equ	0xFFA0	;Value of PC upon REGISTER SAVE
RSIX		equ	0xFFA2	;Value of IX upon REGISTER SAVE
RSIY		equ	0xFFA4	;Value of IY upon REGISTER SAVE
RSIR		equ	0xFFA6	;Value of IR upon REGISTER SAVE
RSAF2		equ	0xFFA8	;Value of AF' upon REGISTER SAVE
RSBC2		equ	0xFFAA	;Value of BC' upon REGISTER SAVE
RSDE2		equ	0xFFAC	;Value of DE' upon REGISTER SAVE
RSHL2		equ	0xFFAE	;Value of HL' upon REGISTER SAVE

UiVec		equ	0xFFB0	;(2) User Interrupt Vector


;*** BEGIN WARM_BOOT_INIT (RAM that is to be initialized on every boot) ***
				;WARNING, Following 34 bytes must be consecutive in this order for Block Write
BEEP_TO		equ	0xFFB2	;(1) Count down the beep (beep duration)
ANBAR_DEF	equ	0xFFB3	;(1) Base setting for the Annunciator LED's (after current function times out)
GET_REG		equ	0xFFB4	;(2) Get Reg Routine (in monitor mode, registers fetched from RAM)
PUT_REG		equ	0xFFB6	;(2) Put Reg Routine
CTRL_C_CHK	equ	0xFFB8	;(2) Vector for CTRL-C Checking
LDISPMODE	equ	0xFFBA	;(2) Last Display Mode (Holds DISPMODE while in HEX Entry)
DISPMODE	equ	0xFFBC	;(2) Display Routine
KEY_EVENT	equ	0xFFBE	;(2) Routine to call upon Key Press (changes based on user actions, see KEY_EVENT_DISPATCH)
IK_TIMER	equ	0xFFC0	;(1) IMON TIMEOUT
KEYBFMODE	equ	0xFFC1	;(1) KEY INPUT MODE. 8F=HEX INPUT, 90=Shiftable
DISPLABEL	equ	0xFFC2	;(1) Display Label Refresh
IK_HEXST	equ	0xFFC3	;(1) IMON HEX Input State
HEX_CURSOR	equ	0xFFC4	;(2) HEX Input Cursor location
HEX_READY	equ	0xFFC6	;(2) HEX Input Ready
LED_CURSOR	equ	0xFFC8	;(2) Cursor location for LED Put_Char
RXBHEAD		equ	0xFFCA	;(2) RS-232 RX BUFFER HEAD
RXBTAIL		equ	0xFFCC	;(2) RS-232 RX BUFFER TAIL
INT_VEC		equ	0xFFCE	;(2) Vector to Interrupt ISR
SCAN_PTR	equ	0xFFD0	;(2) SCAN_PTR points to next LED_DISPLAY byte to output (will always be 1 more
				;    than the current hardware column because hardware automatically advances)
HALT_TEST	equ	0xFFD2	;(2) HALT_TEST
;*** END WARM_BOOT_INIT (RAM BLOCK that is to be initialized on every boot) ***


CLEARED_SPACE	equ	0xFFD4	;Bytes here and later are cleared upon init (some initialized seperately)
CLEARED_LEN	equ	0xFFFF - CLEARED_SPACE + 1

SDISPMODE	equ	0xFFD4	;(2)
POS_BIT		equ	0xFFD6	;(1) BIT Bang RS232 Character position
POS_ACE		equ	0xFFD7	;(1) ACE RS232 Character position
ISR_FLAGS	equ	0xFFD8	;(1) Indicates how many levels the ISR has nested
RRSTATE		equ	0xFFD9	;(1) RAM/ROM SELECT STATE (FOR RETURN FROM ISR)	
XTIMER_TIC	equ	0xFFDA	;(1) Counts Down tics until Extended Timer ISR_EXXTIMER
READ_RAMROM	equ	0xFFDB	;(1) Selected RAMROM for Monitor READ Operations

NMI_VEC		equ	0xFFDC	;(2) NMI VEC.  Not used

CTRL_C_TIMER	equ	0xFFDE	;Count down the CTRL-C condition
SOFT_RST_FLAG	equ	0xFFDF	;Flag a Soft Reset (F-E Keys, Single Step)

				;Display/Serial Comms
LED_DISPLAY	equ	0xFFE0	;8 Bytes of LED Output bytes to Scan to hardware
;8 Bytes			;Warning, LED_DISPLAY must be nibble aligned at E0 (XXE0)
LED_ANBAR	equ	0xFFE7	;LED Annunciator Bar (Part of LED_DISPLAY Buffer)
				;.0 = x7 = BEEPER
				;.1 = x6 = Run Mode
				;.2 = x5 = Monitor Mode (Default Mode upon Power up)
				;.3 = x4 = Send Data to Output Port
				;.4 = x3 = Alter Memory/Register
				;.5 = x2 = Enter Memory Location
				;.6 = x1 = Enter Register

KBCOLSAMPLED	equ	0xFFE8	;Columns Sampled
KBPORTSAMPLE	equ	0xFFE9	;Input Port sampled only once on each scan, saved here
KBHEXSAMPLE	equ	0xFFEA	;KEY SAMPLER Input HEX format
KEYBSCANPV	equ	0xFFEB	;KEY Input HEX format
KEYBSCANTIMER	equ	0xFFEC	;KEY Input TIMER
KEY_PRES_EV	equ	0xFFED	;KEY INPUT LAST & Currently Processing
KEY_PRES_RTN	equ	0xFFEE	;KEY LAST, for Return To Normal between strokes
KEY_PRESSED	equ	0xFFEF	;(1) KEY PRESSED

TicCounter	equ	0xFFF0	;Tic Counter
;TicCounter	equ	0xFFF1	;
ECHO_STATE	equ	0xFFF2	;Echo characters
XMSEQ		equ	0xFFF3	;XMODEM SEQUENCE NUMBER
XMTYPE		equ	0xFFF4	;XMODEM BLOCK TYPE (CRC/CS)
SCAN_LED	equ	0xFFF5	;Holds the next LED output
LED_DISPLAY_SB	equ	0xFFF6	;10 Bytes FFF6=Start BIT, 7,8,9,A,B,C,D,E=Data bits, F=Stop BIT
;10 bytes	equ	0xFFFF	;Warning, LED_DISPLAY_TBL must be at this address (XXF6)


;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;	HOOK LOCATIONS
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
		org	0x0042
VMAIN_MENU	DS	3
VPUT_CHAR	DS	3
VGET_POS	DS	3
VGET_CHAR	DS	3
VRX_COUNT	DS	3
VIN_CHAR	DS	3
VTIMED_GETCHAR	DS	3
VPRINT		DS	3
VBEEP		DS	3

VSET_ECHO	DS	3
VDELAY_C	DS	3
VDELAY_A	DS	3

		org	0x006B
VPUT_VERSION	DS	3
VPUT_HEX	DS	3
VPUT_BYTE	DS	3
VPUT_BC		DS	3
VPUT_DE		DS	3
VPUT_HL		DS	3
VPUT_SPACE	DS	3
VPUT_NEW_LINE	DS	3

VGET_BYTE	DS	3
VGET_WORD	DS	3
VGET_HEX_CHAR	DS	3

VCLEAR_BLOCK	DS	3
VLD_HL_HL	DS	3
VADD_HL_A	DS	3
VMOV_32_HL	DS	3
VMOV_HL_32	DS	3
VADD_32_HL	DS	3
VCMP_HL_32	DS	3
VINC_32		DS	3
VDEC_32		DS	3
VTSTZ_32	DS	3

VASC2BIN	DS	3
VASC2HEX	DS	3
VHEX2ASC	DS	3
VTO_UPPER	DS	3

VSET_IO		DS	3
VIC_KEY		DS	3
VLED_UPDATE	DS	3

VLED_GET_POS	DS	3
VLED_SET_POS	DS	3
VLED_HOME	DS	3
VLED_PUT_CHAR	DS	3
VLED_PRINT	DS	3
VLED_PUT_BYTE	DS	3
VLED_PUT_HEX	DS	3
VLED_CLEAR	DS	3
VLED_RIGHT	DS	3
VLED_LEFT	DS	3

VPRINT_FNAME	DS	3
VINPUT_FNAME	DS	3
VSD_OPEN	DS	3
VSD_OPEN_FILENAME DS	3
VPRINT_DIR	DS	3
VDISK_READ	DS	3
VSD_READ_SEC	DS	3
VLINE_INPUT	DS	3


;                       *********   *******    *********
;                       *********  *********   *********
;                       **         **     **   **
;                       **         **     **   **
;---------------------  *******    **     **   *******    ---------------------
;---------------------  *******    **     **   *******    ---------------------
;                       **         **     **   **
;                       **         **     **   **
;                       *********  *********   **
;                       *********   *******    **


		END 000
		



;----------------------------------------------------------------------------------------------------; INSTRUCTION LIST REFERENCE
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>;
;<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
;----------------------------------------------------------------------------------------------------;
