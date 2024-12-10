		.title	condrv(em).sys manager XCONT

PROGRAM:	.reg	'xcont'
VERSION:	.reg	'1.0.0-beta.1'
DATE:		.reg	'2024'
AUTHOR:		.reg	'TcbnErik'


# symbols
#	__CRLF__	CRLF 改行を出力する(標準では LF 改行).
#	__OLD_FUNC__	-x のバッファリング停止は movem を rts に
#			書き換える(標準ではシステムコール $24 を使う).
#	SLASH_CNV	実行ファイル検索時に '/' -> '\'


* Include File -------------------------------- *

		.include	macro.mac
		.include	dosdef.mac
		.include	fefunc.mac
		.include	console.mac
		.include	doscall.mac
		.include	filesys.mac
		.include	iocscall.mac


* スレッド管理情報の構造 ---------------------- *

		.offset	0
BG_NextThread:	.ds.l	1
BG_WaitFlag:	.ds.b	1
BG_Count:	.ds.b	1
BG_CountMax:	.ds.b	1
BG_DosCmd:	.ds.b	1
BG_PSP:		.ds.l	1
BG_USP:		.ds.l	1
BG_RegSave:	.ds.l	15
BG_SR:		.ds	1
BG_PC:		.ds.l	1
BG_SSP:		.ds.l	1
BG_InDosFlag:	.ds.w	1
BG_InDosPtr:	.ds.l	1
BG_Buffer:	.ds.l	1
BG_Name:	.ds.b	16
BG_WaitTime:	.ds.l	1
*BG_MemoryTop:	.ds.l	1
*BG_MemoryEnd:	.ds.l	1
BG_SIZE:
		.fail	$.ne.(124-8)


* Fixed Number -------------------------------- *

STACK_SIZE:	.equ	8*1024
EXEC_NAME_SIZE:	.equ	256

BG_USP_SIZE:	.equ	64+466
BG_SSP_SIZE:	.equ	5*1024
		.fail	STACK_SIZE<(BG_USP_SIZE+BG_SSP_SIZE)

		.offset	0
syscall_adr:	.ds.l	1
arg_buf_adr:	.ds.l	1
arg_buf_size:
exec_name:	.ds.b	EXEC_NAME_SIZE
thread_buf:	.ds.b	BG_SIZE
		.even
priority:	.ds	1
		.ds.b	STACK_SIZE
stack_end:
work_size:

STDIN_ATR:	.equ	$80c1
STDOUT_ATR:	.equ	$80c2
RTS_CODE:	.equ	$4e75
MOVEM_CODE:	.equ	$48e7

*EXIT_SUCCESS:	.equ	0
EXIT_NOCONDRV:	.equ	1
EXIT_NOMEM:	.equ	2
EXIT_ARGERR:	.equ	3
EXIT_IOERR:	.equ	4
EXIT_NOTSUPP:	.equ	5
EXIT_STACKERR:	.equ	6
EXIT_EXECERR:	.equ	7
EXIT_KEEPERR:	.equ	8
EXIT_BGERR:	.equ	9


* CONDRV.SYS 内部構造の定義 ------------------- *

CONDRV_MARK:	.equ	'hmk*'
bufstruct_size:	.equ	32

		.offset	-28
option_flag:	.ds.b	1
		.even				;未使用
wait_count:	.ds	1			;廃止
wait_init:	.ds	1			;〃
syscall_adr_:	.ds.l	1
nul_string:	.ds.b	1			;追加
winkey_flag:	.ds.b	1
bufinp_addr:	.ds.l	1
keybuf_len:	.ds.l	1
keybuf_addr:	.ds.l	1
condrv_mark:	.ds.l	1
		.fail	*.ne.0
key_init_entry:

option_f_bit:	.equ	0
option_bg_bit:	.equ	1
option_j_bit:	.equ	7

* システムコール
COND_ONOFF:	.equ	$0000
COND_STACK:	.equ	$0023
COND_LEVEL:	.equ	$0024
COND_GETVER:	.equ	-1			;$ffff


* Macro --------------------------------------- *

STRSKIP:	.macro	an
@loop:		tst.b	(an)+
		bne	@loop
		.endm


* Text Section -------------------------------- *

		.cpu	68000

		.text
		.even

**** ↓ ここから常駐部 ↓ ****

start_:
		bra.s	@f
hupair_mark:
		.dc.b	'#HUPAIR',0
@@:
		bra	start_2

bg_start_0:
		DOS	_CHANGE_PR
bg_start:
		move.b	(start_-$100+4,pc),d0
		not.b	d0
		bne	bg_start_0		;常駐終了するまで待機

		lea	(bg_spsave,pc),a0
		move.l	sp,(a0)

		pea	(bg_start_2,pc)
		move	#_ERRJVC,-(sp)
		DOS	_INTVCS
		addq.l	#6,sp
bg_start_2:
		movea.l	(bg_spsave,pc),sp

		lea	(bg_com_id,pc),a0
		moveq	#-1,d1
		moveq	#0,d2
		move	(bg_sleep_cnt,pc),d2
bg_loop:
		cmp	(a0),d1
		beq	bg_keysns		;通信データなし
		move	(bg_com_cmd,pc),d0
		move	d1,(a0)			;通信許可

		cmpi	#THREAD_KILL,d0
		bne	@f
		DOS	_KILL_PR		;自己破棄
*		bra	bg_keysns
@@:
		cmpi	#THREAD_SLEEP,d0
		bne	bg_keysns
		clr.l	-(sp)			;永久スリープ
		DOS	_SLEEP_PR
		addq.l	#4,sp
		bra	bg_keysns

bg_keysns_input:
		IOCS	_B_KEYINP		;SHIFT/CTRL/OPT.1/2 は読み捨てる
bg_keysns:
		IOCS	_B_KEYSNS
		cmpi	#$7000,d0
		bcc	bg_keysns_input

		move.l	d2,-(sp)		;暫くスリープする
		DOS	_SLEEP_PR
		addq.l	#4,sp
		bra	bg_loop

bg_combuf:
		.dc.l	0			;length
		.dc.l	0			;buffer address
bg_com_cmd:	.dc	0			;command no.
bg_com_id:	.dc	-1			;sender ID

bg_sleep_cnt:	.dc	50			;0.05秒

bg_spsave:	.ds.l	1

**** ↑ ここまで常駐部(実行コード) ↑ ****


* スレッドを起動してから常駐終了するまでの間、bg_usp_bottom以降は起動
* したスレッドのスタックとして使用されてしまい実行中のコードを破壊して
* しまう恐れがあるので、常駐に必要なルーチンは常駐部の一部として記述する.


* 常駐時に使用するサブルーチン

* condrv(em).sysのBGフラグをセット/クリアする.
* in	d0.l	0:クリア 1:セット
*	a0.l	get_condrv_workの返値

bitchg_bg_flag:
		PUSH	a0-a1
		move.l	d0,-(sp)
		lea	(option_flag,a0),a1
		IOCS	_B_BPEEK

		move.b	d0,d1
		moveq	#option_bg_bit,d0
		bclr	d0,d1
		tst.l	(sp)+
		beq	@f			;in.d0=0ならクリア
		bset	d0,d1			;     =1ならセット
@@:
		subq.l	#1,a1
		IOCS	_B_BPOKE
		POP	a0-a1
		rts

* 常駐ルーチン

openpr_and_keep:
		bsr	print_title

		clr.l	-(sp)			;メモリを全て解放する
		DOS	_MFREE

		pea	(100)			;初期スリープ時間0.1秒
		pea	(bg_combuf,pc)		;通信バッファ
		pea	(bg_start,pc)		;初期pc
		.if	0
		clr	-(sp)			;初期sr
		.else
		move	#$2000,-(sp)		;supervisor mode
		.endif
		pea	(bg_ssp_bottom,pc)	;初期ssp
		pea	(bg_usp_bottom,pc)	;初期usp
		move	(priority,a6),-(sp)	;実行優先レベル
		pea	(thread_name,pc)	;スレッド名
		DOS	_OPEN_PR
		lea	(28,sp),sp
		tst.l	d0
		bmi	keep_error

		moveq	#1,d0
		bsr	bitchg_bg_flag

		pea	(keep_mes,pc)
		DOS	_PRINT

		clr	-(sp)
		pea	(bg_ssp_bottom-start_).w
		DOS	_KEEPPR

bg_end:

bg_usp_bottom:	.equ	bg_end+BG_USP_SIZE
bg_ssp_bottom:	.equ	bg_end+BG_USP_SIZE+BG_SSP_SIZE

**** ↑ ここまで常駐部 ↑ ****

start_2:
		pea	(end_-start_+work_size+$f0).w
		pea	(16,a0)
		DOS	_SETBLOCK
		tst.l	d0
		bmi	memory_error
		lea	(end_,pc),a6
		lea	(stack_end,a6),sp

		clr.l	(syscall_adr,a6)
		bsr	get_condrv_work
		bne	@f

		lea	(syscall_adr_,a1),a1
		IOCS	_B_LPEEK
		move.l	d0,(syscall_adr,a6)
@@:
		addq.l	#1,a2
		lea	(a2),a0
		STRSKIP	a2
		suba.l	a0,a2			;a2 = strlen(arg) + 1
		move.l	a2,(arg_buf_size,a6)

		move.l	a2,-(sp)		;引数復元用バッファを確保する
		move	#2,-(sp)		;上位から検索
		DOS	_MALLOC2
		addq.l	#6,sp
		move.l	d0,(arg_buf_adr,a6)
		bmi	memory_error
		movea.l	d0,a1

		bsr	DecodeHUPAIR
		move.l	d0,d7			引数の数
		beq	check_stdin_redirect

		lea	(a1),a0
		moveq	#0,d6			(空でない)引数が一度でもあったか
arg_loop:
		lea	(a0),a1			;引数先頭アドレス
		move.b	(a0)+,d0
		beq	next_arg_skip
		cmpi.b	#'-',d0
		beq	check_option

		lea	(command_list,pc),a0
		moveq	#0,d1
command_check_loop:
		bsr	strcmp
		beq	command_found
		addq	#2,d1
		STRSKIP	a0			;次のコマンド名へ
		tst.b	(a0)
		bne	command_check_loop
		bra	argument_err		;どれでもなかった
command_found:
		move.l	a1,-(sp)
		move	(@f,pc,d1.w),d1
		jsr	(@f,pc,d1.w)
		move.l	(sp)+,a0
		STRSKIP	a0			;次の引数へ
		bra	next_arg
@@:
		.dc	command_on-@b
		.dc	command_off-@b
		.dc	command_x-@b
		.dc	command_xon-@b
		.dc	command_xoff-@b
		.dc	command_k-@b
		.dc	command_kon-@b
		.dc	command_koff-@b
		.dc	command_push-@b
		.dc	command_pop-@b
		.dc	command_check-@b
		.dc	command_ver-@b
		.dc	command_sleep-@b
		.dc	command_wakeup-@b

check_option:
		move.b	(a0)+,d0
		cmpi.b	#'-',d0
		beq	check_long_option
next_opt:	cmpi.b	#'?',d0
		beq	print_usage
		ori.b	#$20,d0
		lea	(option_table,pc),a2
@@:
		move.l	(a2)+,d1
		beq	argument_err
		cmp.b	d0,d1
		bne	@b
		swap	d1
		adda	d1,a2
		jsr	(a2)
		move.b	(a0)+,d0		オプションは続けてもよい
		bne	next_opt
next_arg:
		moveq	#-1,d6
next_arg_skip:
		subq.l	#1,d7
		bhi	arg_loop
		tst	d6
		bne	exit
		bra	check_stdin_redirect

check_long_option:
		move.b	(a0),d0
		lea	(str_help,pc),a2
		cmp.b	(a2),d0
		seq	d0			;$ff = --help
		beq	@f
		addq.l	#str_version-str_help,a2
@@:
		cmpm.b	(a2)+,(a0)+
		bne	argument_err
		tst.b	(-1,a0)
		bne	@b
		tst.b	d0
		bne	option_h
		bra	option_v


* 引数省略時 --------------------------------- *

check_stdin_redirect:
		clr.l	-(sp)
		DOS	_IOCTRL
		addq.l	#4,sp
		cmpi	#STDIN_ATR,d0
		beq	print_onoff		STDIN切り換えなし

		lea	(hyphen,pc),a0		;"-"
		bsr	option_l		切り換えられていた場合は XCONT -L- と見なす
exit:		DOS	_EXIT

print_onoff:
		tst.l	(syscall_adr,a6)	*
		beq	print_off		* 未常駐時はoffを表示

		bsr	get_bufinp_addr
		IOCS	_B_WPEEK
		subi	#MOVEM_CODE,d0
print_on_off:
		lea	(on_mes,pc),a0
		beq	print_a0_exit
print_off:
		lea	(off_mes,pc),a0
print_a0_exit:
		move.l	a0,-(sp)
print_exit:	DOS	_PRINT
		DOS	_EXIT

* コマンド 系 --------------------------------- *

command_x:
		moveq	#0,d1			;停止レベルの取得
		bsr	call_stop_level
@@:
		lea	(buffer,pc),a0
		pea	(a0)
		FPACK	__LTOS			;文字列に変換
		bra	print_line

command_xoff:
		moveq	#+1,d1			;stop_level++
		bra	call_stop_level

command_xon:
		moveq	#-1,d1			;stop_level--
		bra	call_stop_level

call_stop_level:
		move.l	(syscall_adr,a6),d0
		beq	@f			;未常駐時は 0 を返す

		moveq	#COND_LEVEL,d0
		bra	call_sys_call
@@:
		rts


command_k:
		tst.l	(syscall_adr,a6)	*
		beq	print_off		* 未常駐時はoffを表示

		bsr	get_condrv_work
		moveq	#winkey_flag,d1
		bsr	bpeek
		tst.b	d0
		bra	print_on_off

command_on:
		move	#1,d1			;取り込み開始
		bra	@f
command_off:
		move	#0,d1			;取り込み停止
@@:		tst.l	(syscall_adr,a6)
		beq	command_on_off_return	;未常駐時は何もしない

		moveq	#COND_ONOFF,d0
		bsr	call_sys_call
		bra	conctrl_fncmod

command_kon:
		moveq	#0,d2
		bra	@f
command_koff:
		moveq	#-1,d2
@@:
		tst.l	(syscall_adr,a6)	*
		beq	command_on_off_return	* 未常駐時は何もしない

		bsr	get_condrv_work
		lea	(winkey_flag,a0),a1
		move	d2,d1
		IOCS	_B_BPOKE
command_on_off_return:
		rts

command_check:
		clr	-(sp)
		bsr	get_condrv_work
		beq	@f
		addq	#1,(sp)
@@:
		DOS	_EXIT2

command_ver:
		tst.l	(syscall_adr,a6)	*
		beq	condrv_err		* 組み込まれていなければエラー

		bsr	get_cond_ver
		lea	(ver_print_buf,pc),a0
		move.l	d0,(a0)
		bmi	condrv_err2
		bra	print_a0_exit

command_push:
		moveq	#1,d1
		lea	(push_err_mes,pc),a0	;エラー発生時に表示する文字列
		bra	@f
command_pop:
		pea	(conctrl_fncmod,pc)	POP時はシステムステータスを書き直す
		moveq	#0,d1
		lea	(pop_err_mes,pc),a0	;エラー発生時に表示する文字列
@@:
		tst.l	(syscall_adr,a6)	*
		beq	@f			* 未常駐時は何もしない

		moveq	#COND_STACK,d0
		bsr	call_sys_call
		tst.l	d0
		bmi	stack_error
@@:
		rts

* オプション --------------------------------- *

option_table:
		.irpc	%a,hvfjlxzr
		.dc	(option_%a-$-4),'&%a'
		.endm
		.dc.l	0

str_help:	.dc.b	'help',0
str_version:	.dc.b	'version',0
		.even

option_h:
print_usage:
		bsr	print_title
		pea	(usage_mes,pc)
		bra	print_exit

option_v:
		pea	(version_mes,pc)
		lea	(version_mes_end,pc),a0
		bra	print_line

* 末尾に CRLF を付加して表示.
* in	(sp).l	文字列の先頭アドレス
*	a0.l	末尾

print_line:
	.ifdef	__CRLF__
		move.b	#CR,(a0)+
	.endif
		move.b	#LF,(a0)+
		clr.b	(a0)
		bra	print_exit

option_f:
		pea	(conctrl_fncmod,pc)
		moveq	#1.shl.option_f_bit,d2
		bra	@f
option_j:
		moveq	#1.shl.option_j_bit,d2
@@:
		moveq	#1,d1
		bsr	is_number
		bmi	@f			;数値省略時は1
		bsr	get_value
@@:		subq.l	#1,d1
		bhi	over_val_err
		seq	d3			d3=-1:$.or.d2 d3=0:($.or.d2).eor.d2

		tst.l	(syscall_adr,a6)	*
		beq	option_fj_return	* 未常駐時は何もしない

		move.l	a0,-(sp)
		bsr	get_condrv_work
		lea	(option_flag,a0),a1
		IOCS	_B_BPEEK
		movea.l	(sp)+,a0

		or.b	d2,d0
		tst.b	d3
		bmi	@f
		eor.b	d2,d0
@@:
		move.b	d0,d1
		subq.l	#1,a1
		IOCS	_B_BPOKE
option_fj_return:
		rts

option_l:
		bsr	check_filearg

		moveq	#STDIN,d5		;"-" なら標準入力から読む
		lea	(stdin_mes,pc),a1	;エラーメッセージは <stdin>
		cmpi.b	#'-',(a0)
		bne	@f
		tst.b	(1,a0)
		beq	read_from_stdin
@@:
		lea	(a0),a1			;エラーメッセージはファイル名
		clr	-(sp)
		move.l	a0,-(sp)
		DOS	_OPEN
		addq.l	#6,sp
		move.l	d0,d5
		bmi	fopen_error
read_from_stdin:
		moveq	#0,d2			d2=-1:標準入力デバイス

		move	d5,-(sp)
		clr	-(sp)
		DOS	_IOCTRL
		tst.l	d0
		bmi	ioctrl_error
		tst.b	d0
		bpl	@f			ブロックデバイス上のファイルは 0 が返る

		ori.b	#%0111_1110,d0
		addq.b	#1,d0
		seq	d2			CharDev&&STDINでCONからの入力とみなす

		addq	#6,(sp)
		DOS	_IOCTRL
		tst.l	d0			-1.l で入力可
		beq	cannot_input_error	入力不可のキャラクタデバイス
@@:
		addq.l	#4,sp

		tst.l	(syscall_adr,a6)	*
		beq	end_of_file		* 未常駐時は入力ファイルのチェックだけする

		moveq	#-1,d4
		lsr.l	#8,d4
		move.l	d4,-(sp)
		DOS	_MALLOC
		and.l	d0,d4
		lsr.l	#1,d4			全フリーメモリの半分を確保
		move.l	d4,(sp)
		DOS	_MALLOC
		addq.l	#4,sp
		tst.l	d0
		bmi	memory_error
		movea.l	d0,a5

*XCON をオープンする
		move	#OPENMODE_WRITE,-(sp)
		pea	(xcon,pc)
		DOS	_OPEN
		addq.l	#6,sp
		tst.l	d0
		bmi	xcon_open_error
		swap	d5
		move	d0,d5			d5:file|XCON

		move	d5,-(sp)
		clr	-(sp)
		DOS	_IOCTRL
		tst.l	d0
		bmi	xcon_ioctrl_error
		tst.b	d0
		bpl	xcon_char_open_error	普通のファイルをオープンしてしまった

		addq	#7,(sp)
		DOS	_IOCTRL
		addq.l	#4,sp
		tst.l	d0			-1.l で出力可
		beq	cannot_output_error

* 標準出力が切り換えられているか調べる
		moveq	#0,d3			d3.hw=0:切り換えなし
		pea	(STDOUT)		$0000_0001
		DOS	_IOCTRL
		addq.l	#4,sp
		cmpi	#STDOUT_ATR,d0
		beq	@f
		moveq	#-1,d3			d3.hw=-1:あり(両方に書き込む)
@@:
read_write_loop:
		swap	d5			XCON|file
		move.l	d4,-(sp)
		move.l	a5,-(sp)
		move	d5,-(sp)
		DOS	_READ
		lea	(10,sp),sp
		tst.l	d0
		bmi	fread_error
		beq	end_of_file

* 標準入力からの場合はeofを調べる
		tst.b	d2
		beq	write_stdout
		lea	(a5),a2
		subq.l	#1,d0
@@:
		move.b	(a2)+,d1
		cmpi.b	#$04,d1			^D
		beq	eof_found
		cmpi.b	#EOF,d1
		beq	eof_found
		dbra	d0,@b
		clr	d0
		subq.l	#1,d0
		bcc	@b
		bra	@f
eof_found:
		moveq	#-1,d2
@@:
		move.l	a2,d0
		subq.l	#1,d0
		sub.l	a5,d0
		beq	end_of_file		行頭にeofがあった場合

write_stdout:
		move.l	d0,-(sp)
		move.l	a5,-(sp)
		move	#STDOUT,-(sp)
		tst.l	d3
		bpl	@f
		DOS	_WRITE
@@:
* XCON に書き込む
		swap	d5			file|XCON
		move	d5,(sp)
		DOS	_WRITE
		addq.l	#10-2,sp

		move	d2,(sp)+		;eofを検出したか
		bpl	read_write_loop
* 後片付
end_of_file:
		DOS	_ALLCLOSE
		STREND	a0			;ファイル名の末尾に移動
		rts

option_x:
		bsr	check_filearg

		STRLEN	a0,d6			;strlen (argv0)
		addq.l	#8,d6			;"HUPAIR\0"
		addq.l	#8,d6			;余分
		add.l	(arg_buf_size,a6),d6	;sizeof (ARG_BUF)

		move.l	d6,-(sp)
		DOS	_MALLOC
		move.l	d0,(sp)+
		bmi	memory_error
		movea.l	d0,a3
		lea	(8,a3),a4		#HUPAIR\0の分
		subq.l	#8,d6			〃

		lea	(exec_name,a6),a5
		lea	(a5),a2
		move	#EXEC_NAME_SIZE-1,d0
@@:
		move.b	(a0)+,(a2)+
		dbeq	d0,@b
		bne	too_long_filename_error

		clr.l	-(sp)			環境
		move.l	a4,-(sp)		ダミーのコマンドラインバッファ
		move.l	a5,-(sp)		ファイル名
		move	#EXECMODE_PATHCHK,-(sp)
		DOS	_EXEC
		.ifndef	SLASH_CNV
		tst.l	d0
		lea	(14,sp),sp
		bmi	load_error
		.else
		move.l	d0,d1
		bpl	exec_load_ok

* '/' を '\' に変えて試してみる
		lea	(a5),a0
*		moveq	#-1,d1
@@:
		move.b	(a0)+,d0
		beq	@f
		cmpi.b	#'/',d0
		bne	@b
		moveq	#'\',d1
		move.b	d1,(-1,a0)
		bra	@b
@@:
		tst	d1
		bmi	@f			;'/'は未使用だった

		DOS	_EXEC
		tst.l	d0
		bpl	exec_load_ok
@@:
		lea	(14,sp),sp
		move.l	d1,d0			今度もエラーなら前回の返値を使う
		bra	load_error
exec_load_ok:
		lea	(14,sp),sp
		.endif	/* SLASH_CNV */

		move.l	d6,d0			バッファ容量
		move.l	d7,d1
		subq.l	#1,d1			;引数の数
		lea	(a4),a0			;バッファ先頭
		move.l	a1,-(sp)
		STRSKIP	a1			;引数列
		bsr	EncodeHUPAIR
		move.l	(sp)+,a2
		bmi	memory_error		*

		move.l	d6,d1			バッファ容量
		lea	(a4),a1			バッファ先頭
		bsr	SetHUPAIR
		bmi	memory_error		*

		suba.l	a3,a0			引数エンコードバッファを
		move.l	a0,-(sp)		必要な分だけの大きさにする
		move.l	a3,-(sp)
		DOS	_SETBLOCK

		move.l	(arg_buf_adr,a6),(sp)	不要になった引数復元バッファを解放する
		DOS	_MFREE
		addq.l	#8,sp

		clr.l	-(sp)			環境
		move.l	a4,-(sp)		コマンドライン
		move.l	a5,-(sp)		ファイル名
		move	#EXECMODE_LOAD,-(sp)
		DOS	_EXEC
		lea	(14,sp),sp
		move.l	d0,d6
		bmi	load_error

		tst.l	(syscall_adr,a6)
		beq	@f

	.ifdef	__OLD_FUNC__
		bsr	get_bufinp_addr		*
		IOCS	_B_WPEEK		* 現在のモードを得る
		move	d0,d7

		bsr	command_off		* 取り込みを停止する
	.else
		bsr	command_xoff		;stop_level++
		move.l	d0,d7
	.endif
@@:
		move.l	d7,-(sp)
		move.l	a6,-(sp)

		move.l	d6,-(sp)		* exec address
		move	#4,-(sp)
		DOS	_EXEC
		addq.l	#6,sp

		move.l	(sp)+,a6
		move.l	(sp)+,d7
		move	d0,-(sp)		;exit2の引数

		tst.l	(syscall_adr,a6)
		beq	@f

	.ifdef	__OLD_FUNC__
		bsr	get_bufinp_addr		*
		move	d7,d1			* 以前のモードに戻す
		IOCS	_B_WPOKE		*
		bsr	conctrl_fncmod
	.else
		tst.l	d7
		bmi	@f
		bsr	command_xon		;stop_level--
	.endif
@@:
		DOS	_EXIT2


* BG 対応処理 -------------------------------- *

option_z:
		moveq	#2,d1
		bsr	is_number
		bmi	@f
		bsr	get_value		;優先度の収得
*		cmpi	#2,d1
*		bcs	small_val_err
		cmpi	#255,d1
		bhi	over_val_err
@@:		move	d1,(priority,a6)

		cmpi.b	#',',(a0)
		bne	@f
		addq.l	#1,a0
*		bsr	is_number
*		bmi	@f
		bsr	get_value		;スリープ時間の収得
		tst	d1
		beq	small_val_err
		lea	(bg_sleep_cnt,pc),a1
		move	d1,(a1)
@@:
		bsr	check_condrv
		bsr	get_condrv_work
		bra	openpr_and_keep

* condrv(em).sysが組み込まれているか調べる.
* 組み込まれていなければ、エラー終了する.

check_condrv:
		tst.l	(syscall_adr,a6)
		beq	condrv_err
		bsr	get_cond_ver
		tst.l	d0
		bmi	condrv_err2
		rts

get_cond_ver:
		moveq	#COND_GETVER,d0
		bra	call_sys_call

call_sys_call:
		move.l	(syscall_adr,a6),-(sp)
		DOS	_SUPER_JSR
		addq.l	#4,sp
		rts


command_sleep:
		move.l	#-1<<16+THREAD_SLEEP,d5
		bra	@f
command_wakeup:
		move.l	#-1<<16+THREAD_WAKEUP,d5
		bra	@f
option_r:
		move.l	#0<<16+THREAD_WAKEUP,d5
@@:
		bsr	check_condrv

		lea	(thread_name,pc),a0
		lea	(thread_buf+BG_Name,a6),a1
		STRCPY	a0,a1

		pea	(thread_buf,a6)		;指定スレッド名のスレッド番号を収得する
		move	#-1,-(sp)
		DOS	_GET_PR
		move.l	d0,d1
		bmi	release_error

		subq	#1,(sp)			;自分のスレッド番号を収得する
		DOS	_GET_PR
		addq.l	#6,sp

		clr.l	-(sp)			;取り敢えず起こす
		clr.l	-(sp)
		move	d5,-(sp)
		move	d1,-(sp)
		move	d0,-(sp)
		DOS	_SEND_PR

		tst.l	d5
		bpl	@f
		lea	(14,sp),sp		;sleep/wakeup なら戻る
		rts
@@:
		move	#THREAD_KILL,(4,sp)
		moveq	#DOSE_CANTSEND,d2
		bra	send_pr
send_pr_loop:
		DOS	_CHANGE_PR
send_pr:
		DOS	_SEND_PR		;受け付けられるまで
		cmp.l	d2,d0			;破棄要求を繰り返す
		beq	send_pr_loop
		tst.l	d0
		lea	(14,sp),sp
		bmi	release_error2

		pea	(thread_buf,a6)
		move	d1,-(sp)
get_pr_loop:
		DOS	_CHANGE_PR		;破棄されるのを確認する
		DOS	_GET_PR
		tst.l	d0
		bpl	get_pr_loop
		addq.l	#6,sp

		bsr	get_condrv_work
		moveq	#0,d0
		bsr	bitchg_bg_flag

		bsr	print_title
		pea	(release_mes,pc)
		DOS	_PRINT
		DOS	_EXIT


* Sub ---------------------------------------- *

conctrl_fncmod:
		move.l	#$000e_ffff,-(sp)
		DOS	_CONCTRL
		addq.l	#4,sp
		rts

print_title:
		pea	(title_mes,pc)
		DOS	_PRINT
		addq.l	#4,sp
		rts

check_filearg_next:
		subq.l	#1,d7
		bls	no_filename_error
check_filearg:
		tst.b	(a0)+
		beq	check_filearg_next
		subq.l	#1,a0
		movea.l	a0,a1
		rts

get_condrv_work:
		move	#$100+_KEY_INIT,-(sp)
		DOS	_INTVCG
		addq.l	#2,sp
		movea.l	d0,a0
		moveq	#condrv_mark,d1
		bsr	lpeek
		cmpi.l	#CONDRV_MARK,d0
		rts

get_bufinp_addr:
		bsr	get_condrv_work
		moveq	#bufinp_addr,d1
		bsr	lpeek
		movea.l	d0,a1
		rts

lpeek:
		moveq	#_B_LPEEK,d0
		bra	@f
bpeek:
		moveq	#_B_BPEEK,d0
@@:		lea	(a0,d1.l),a1
		trap	#15
		rts

get_value:
		moveq	#0,d1
		bra	get_value_start
get_value_loop:
		moveq	#$f,d0
		and.b	(a0)+,d0
		mulu	#10,d1
		add.l	d0,d1
get_value_start:
		bsr	is_number
		bpl	get_value_loop
		rts

is_number:
		cmpi.b	#'0',(a0)
		bcs	@f
		cmpi.b	#'9',(a0)
		bhi	@f
		moveq	#0,d0
		rts
@@:		moveq	#-1,d0
		rts


* 大文字小文字同一視の文字列比較
* in	a0.l	文字列(必ず英小文字であること)
*	a1.l	文字列
* out	ccr	Z=1:一致 Z=0:不一致

strcmp:
		PUSH	d0/a0-a1
strcmp_loop:
		move.b	(a1)+,d0
		beq	strcmp_nul
		ori.b	#$20,d0			;小文字化
		sub.b	(a0)+,d0
		beq	strcmp_loop
		bra	@f
strcmp_nul:
		tst.b	(a0)+
@@:		POP	d0/a0-a1
		rts


* エラー処理 --------------------------------- *
; exit(1):condrv(em).sys が組み込まれていない
; exit(2):内部エラー
; exit(3):引数が異常
; exit(4):ファイルアクセスに失敗した(含むXCON)
; exit(5):condrv.sys は純正品である
; exit(6):スタック操作のエラー
; exit(7):ファイルの実行に失敗した
; exit(8):xcontは既に常駐している/まだ常駐していない
; exit(9):BGプロセスが登録出来ない

condrv_err:
		lea	(condrv_err_mes,pc),a0
		moveq	#EXIT_NOCONDRV,d1
		bra	1f
condrv_err2:
		lea	(condrv_err_mes2,pc),a0
		moveq	#EXIT_NOTSUPP,d1
		bra	1f

memory_error:
		lea	(mem_err_mes,pc),a0
		moveq	#EXIT_NOMEM,d1
		bra	1f

stack_error:
		addq.l	#1,d0
		beq	condrv_err2		d0.l=-1
		moveq	#EXIT_STACKERR,d1
1:
		suba.l	a1,a1
		bra	error_exit

argument_err:
		lea	(arg_err_mes,pc),a0
		bra	@f
over_val_err:
		lea	(val_err_mes,pc),a0
		bra	@f
small_val_err:
		lea	(val_err_mes,pc),a0
		move.l	#'小さ',(6,a0)
		bra	@f
no_filename_error:
		lea	(nofilename_err_mes,pc),a0
		bra	@f
too_long_filename_error:
		lea	(too_long_filename_mes,pc),a0
		bra	@f
@@:
		moveq	#EXIT_ARGERR,d1
		bra	error_exit

xcon_char_open_error:
		lea	(xcon_open_err_mes,pc),a0
		bra	@f
cannot_output_error:
		lea	(cant_out_err_mes,pc),a0
		move	#'出',(a0)
		bra	@f
@@:
		lea	(xcon,pc),a1
		bra	1f

xcon_open_error:
		bsr	get_condrv_work		;condrv(em).sys が組み込まれていない場合は
		lea	(xcon,pc),a1		;エラーメッセージも変える
fopen_error:
		lea	(fopen_mes_tbl,pc),a0
		move.b	d0,(fopen_err_mes-fopen_mes_tbl,a0)
check_open_err:
		cmp.b	(a0)+,d0
		beq	1f
		STRSKIP	a0
		bra	check_open_err
xcon_ioctrl_error:
		lea	(xcon,pc),a1
ioctrl_error:
		lea	(ioctrl_err_mes,pc),a0
		bra	1f
cannot_input_error:
		lea	(cant_inp_err_mes,pc),a0
		bra	1f
fread_error:
		lea	(fread_err_mes,pc),a0
		bra	1f
1:
		moveq	#EXIT_IOERR,d1
		bra	error_exit

load_error:
		lea	(load_err_mes,pc),a0
		lea	(a5),a1

		moveq	#EXIT_EXECERR,d1
		bra	error_exit

keep_error:
		moveq	#EXIT_KEEPERR,d1
		moveq	#DOSE_DUPTHNAM,d2	;既に常駐している
		lea	(already_keep_mes,pc),a0
		cmp.l	d2,d0
		beq	@f

		moveq	#EXIT_BGERR,d1
		moveq	#DOSE_THFULL,d2		;スレッドが一杯
		lea	(thread_full_mes,pc),a0
		cmp.l	d2,d0
		beq	@f

*		moveq	#EXIT_BGERR,d1		;process未設定
		lea	(proccess_err_mes,pc),a0
		bra	@f
release_error:
		lea	(not_keep_mes,pc),a0
		moveq	#EXIT_KEEPERR,d1
		bra	@f
release_error2:
		lea	(release_err_mes,pc),a0
		moveq	#EXIT_BGERR,d1
@@:
		suba.l	a1,a1
		bra	error_exit

error_exit:
		move	#STDERR,-(sp)
		pea	(xcont_mes,pc)
		DOS	_FPUTS			XCONT:
		move.l	a0,(sp)
		DOS	_FPUTS			エラーメッセージ
		move.l	a1,(sp)
		beq	@f
		DOS	_FPUTS			引数
@@:		addq.l	#4,sp
		pea	(crlf,pc)
		DOS	_FPUTS			改行
		move	d1,(sp)
		DOS	_EXIT2


* HUPAIR Encoder/Decoder ---------------------- *

DecodeHUPAIR:
		PUSH	d1-d2/a1
		moveq	#0,d0
		moveq	#0,d2
1:
		move.b	(a0)+,d1
		beq	8f
		cmpi.b	#SPACE,d1
		beq	1b

		addq.l	#1,d0
2:
		tst.b	d2
		beq	4f

		cmp.b	d2,d1
		bne	5f
3:
		eor.b	d1,d2
		bra	6f
4:
		cmpi.b	#'"',d1
		beq	3b
		cmpi.b	#"'",d1
		beq	3b

		cmpi.b	#SPACE,d1
		beq	7f
5:
		move.b	d1,(a1)+
		beq	8f
6:
		move.b	(a0)+,d1
		bra	2b
7:
		clr.b	(a1)+
		bra	1b
8:
		POP	d1-d2/a1
		tst.l	d0
		rts

EncodeHUPAIR:
		PUSH	d1-d3/a1-a2
		move.l	d0,d2
		bmi	2f
1:
		subq.l	#1,d1
		bcc	3f
2:
		move.l	d2,d0
		POP	d1-d3/a1-a2
		rts
3:
		subq.l	#1,d2
		bmi	2b

		move.b	#SPACE,(a0)+
		move.b	(a1),d0
		beq	5f
3:
		movea.l	a1,a2
		sf	d3
4:
		move.b	(a2)+,d0
		beq	4f

		cmpi.b	#'"',d0
		beq	5f
		cmpi.b	#"'",d0
		beq	5f

		cmpi.b	#SPACE,d0
		bne	4b
		st	d3
		bra	4b
4:
		tst.b	d3
		bne	5f
4:
		move.b	(a1)+,d0
		beq	1b
		subq.l	#1,d2
		bmi	2b
		move.b	d0,(a0)+
		bra	4b
5:
		moveq	#'"',d3
		cmp.b	d0,d3
		bne	7f
		moveq	#"'",d3
7:
		move.b	d3,d0
		bra	6f
5:
		move.b	(a1),d0
		beq	5f
		cmp.b	d3,d0
		beq	5f

		addq.l	#1,a1
6:
		subq.l	#1,d2
		bmi	2b

		move.b	d0,(a0)+
		bra	5b
5:
		subq.l	#1,d2
		bmi	2b

		move.b	d3,(a0)+
		bra	3b

SetHUPAIR:
		PUSH	d2/a2
		tst.l	d0
		bmi	4f

		sub.l	d0,d1
		beq	1f

		move.l	d1,d2
		subq.l	#1,d2
		moveq	#0,d1
		subq.b	#1,d1
		bhi	3f
		bra	2f
1:
		subq.l	#1,d0
		bmi	4f

		lea	(1,a1),a0
		moveq	#0,d2
2:
		move.l	d2,d1
3:
		move.b	d1,(a1)

		subq.l	#1,d0
		bmi	4f

		clr.b	(a0)+
3:
		subq.l	#1,d0
		bmi	4f

		move.b	(a2)+,(a0)+
		bne	3b

		subq.l	#8,a1
		lea	(hupair_mark,pc),a2
3:		move.b	(a2)+,(a1)+
		bne	3b

		move.l	d2,d0
4:
		POP	d2/a2
		rts


* Data Section -------------------------------- *

		.data
		.even

title_mes:
		.dc.b	'condrv(em).sys manager '
version_mes:
		.dc.b	'XCONT version ',VERSION
version_mes_end:
		.dc.b	'  Copyright ',DATE,' ',AUTHOR,'.'
crlf:		.dc.b	CRLF,0

**usage_mes:
**		.dc.b	'option: on/off k/kon/koff push/pop check/ver sleep/wakeup'
**		.dc.b	' -f/j<n> -l<file> -x<command> -z<p,s>/r',CRLF
usage_mes:
		.dc.b	'usage: ',PROGRAM,' [option] ...',CRLF
		.dc.b	'option:',CRLF
		.dc.b	'  省略         取り込み状態表示',CRLF
		.dc.b	'  on / off     取り込み開始 / 停止',CRLF
		.dc.b	'  x            停止レベル表示',CRLF
		.dc.b	'  xon / xoff   停止レベル-1 / 停止レベル+1',CRLF
		.dc.b	'  k            キー状態表示',CRLF
		.dc.b	'  kon / koff   キー操作許可 / 禁止',CRLF
		.dc.b	'  push / pop   状態退避 / 復帰',CRLF
		.dc.b	'  check / ver  常駐検査 / バージョン表示',CRLF
		.dc.b	'  sleep / wakeup  スリープ / 再起動',CRLF
		.dc.b	'  -f[num]      システムライン表示(0:表示 [1]:抑制)',CRLF
		.dc.b	'  -j[num]      コード入力時のペースト文字(0:全て [1]:16 進数のみ)',CRLF
		.dc.b	'  -l<file>     ファイル取り込み',CRLF
		.dc.b	'  -x<cmd> ...  取り込みを停止してファイル実行',CRLF
		.dc.b	'  -z[p][,s]    常駐(p:優先順位 s:スリープ時間)',CRLF
		.dc.b	'  -r           常駐解除',CRLF
		.dc.b	0

command_list:
		.dc.b	'on',0
		.dc.b	'off',0
		.dc.b	'x',0
		.dc.b	'xon',0
		.dc.b	'xoff',0
		.dc.b	'k',0
		.dc.b	'kon',0
		.dc.b	'koff',0
		.dc.b	'push',0
		.dc.b	'pop',0
		.dc.b	'check',0
		.dc.b	'ver',0
		.dc.b	'sleep',0
		.dc.b	'wakeup',0
		.dc.b	0

		.even
ver_print_buf:	.dc.b	0,0
*		.dc.b	'e08b',CRLF
on_mes:		.dc.b	'on',CRLF,0
off_mes:	.dc.b	'off',CRLF,0

xcont_mes:	.dc.b	PROGRAM,':',0
xcon:		.dc.b	'xcon',0

thread_name:	.dc.b	'condrvd',0

stdin_mes:	.dc.b	'<stdin>',0
hyphen:		.dc.b	'-',0

condrv_err_mes:
		.dc.b	'condrv(em).sys は組み込まれていません。',0
condrv_err_mes2:
		.dc.b	'condrv.sys は純正品です。',0

mem_err_mes:
		.dc.b	'メモリが足りません。',0

arg_err_mes:
		.dc.b	'引数が無効です:',0
nofilename_err_mes:
		.dc.b	'ファイル名を指定して下さい:',0
too_long_filename_mes:
		.dc.b	'ファイル名が長すぎます:',0
load_err_mes:
		.dc.b	'ファイルがロード出来ません:',0

xcon_open_err_mes:
		.dc.b	'キャラクタデバイスがオープンできません:',0

fopen_mes_tbl:	.dc.b	$fe,'ファイルがありません:',0
		.dc.b	$fd,'ディレクトリがありません:',0
		.dc.b	$fc,'FCB が足りません:',0
		.dc.b	$fb,'ディレクトリ/ボリュームラベルはオープンできません:',0
		.dc.b	$f3,'ファイル名の指定に誤りがあります:',0
		.dc.b	$f1,'ドライブ指定に誤りがあります:',0
		.dc.b	$df,'指定のファイルはロックされています:',0
fopen_err_mes:	.dc.b	$00,'ファイルがオープンできません(その他のエラー):',0
ioctrl_err_mes:
		.dc.b	'IOCTRL に失敗しました:',0
		.even
val_err_mes:		       ****
		.dc.b	'数値が大きすぎます:',0
		.even
cant_inp_err_mes:
cant_out_err_mes:	 **
		.dc.b	'入力不可能なファイルです:',0
fread_err_mes:
		.dc.b	'ファイルが読めません:',0

push_err_mes:
		.dc.b	'これ以上スタックに積めません。',0
pop_err_mes:
		.dc.b	'スタックは空です。',0

keep_mes:
		.dc.b	'常駐しました。',CRLF,0
already_keep_mes:
		.dc.b	'既に常駐しています。',0
thread_full_mes:
		.dc.b	'これ以上バックグラウンドプロセスを起動できません。',0
proccess_err_mes:
		.dc.b	'CONFIG.SYS で PROCESS が設定されていません。',0

release_mes:
		.dc.b	'常駐解除しました。',CRLF,0
not_keep_mes:
		.dc.b	'常駐していません。',0
release_err_mes:
		.dc.b	'常駐解除できませんでした。',0


* Block Storage Section ----------------------- *

		.bss
		.even
buffer:
end_:


		.end

* End of File --------------------------------- *
