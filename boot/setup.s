!
!	setup.s		(C) 1991 Linus Torvalds
!
! setup.s is responsible for getting the system data from the BIOS,
! and putting them into the appropriate places in system memory.
! both setup.s and system has been loaded by the bootblock.
!
! This code asks the bios for memory/disk/other parameters, and
! puts them in a "safe" place: 0x90000-0x901FF, ie where the
! boot-block used to be. It is then up to the protected mode
! system to read them from there before the area is overwritten
! for buffer-blocks.
!

! NOTE! These had better be the same as in bootsect.s!

INITSEG  = 0x9000	! we move boot here - out of the way
SYSSEG   = 0x1000	! system loaded at 0x10000 (65536).
SETUPSEG = 0x9020	! this is the current segment

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

entry start// 后续根据33-41行示例看,90200的代码把bios的东西放到90000位置
start:

! ok, the read went well so we get current cursor position and save it for
! posterity.

	mov	ax,#INITSEG	! this is done in bootsect already, but... bootsect位置,用完了
	mov	ds,ax
	mov	ah,#0x03	! read cursor pos // bios芯片里从int 13 黑屏光标位置 ,读出,装
	xor	bh,bh
	int	0x10		! save it in known place, con_init fetches// int10 的3号子程序,光标位置返回给9000,读机器系统数据;
	mov	[0],dx		! it from 0x90000.

! Get memory size (extended mem, kB)

	mov	ah,#0x88
	int	0x15
	mov	[2],ax

! Get video-card data:

	mov	ah,#0x0f
	int	0x10
	mov	[4],bx		! bh = display page
	mov	[6],ax		! al = video mode, ah = window width

! check for EGA/VGA and some config parameters

	mov	ah,#0x12
	mov	bl,#0x10
	int	0x10
	mov	[8],ax
	mov	[10],bx
	mov	[12],cx

! Get hd0 data

	mov	ax,#0x0000
	mov	ds,ax
	lds	si,[4*0x41]
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0080
	mov	cx,#0x10
	rep
	movsb

! Get hd1 data

	mov	ax,#0x0000
	mov	ds,ax
	lds	si,[4*0x46]
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0090
	mov	cx,#0x10
	rep
	movsb

! Check that there IS a hd1 :-)

	mov	ax,#0x01500
	mov	dl,#0x81
	int	0x13
	jc	no_disk1
	cmp	ah,#3
	je	is_disk1
no_disk1:
	mov	ax,#INITSEG
	mov	es,ax
	mov	di,#0x0090
	mov	cx,#0x10
	mov	ax,#0x00
	rep
	stosb
is_disk1:

! now we want to move to protected mode ...

	cli			! no interrupts allowed !//重要!!!!!!clear interupt关中断,EFLAGS 第9位IF=0, 关中断听不见

! first we move the system to it's rightful place// 

	mov	ax,#0x0000
	cld			! 'direction'=0, movs moves forward // clear derection 
do_move:
//循环, 功能是: 搬代码,sysseg = Ox1000 to Ox00000,setup 做的,
//setup目的保护模式20实模式到32位特权级的保护模式,,这段操作废掉实模式原来的中断逻辑,因为吧原来位置Ox00000位置中断向量覆盖了
// 所以必须提前关中断,不然把后续覆盖的中断向量值当成原来的中断值进行后续的操作
//开中断的位置在sti 在main函数 
	mov	es,ax		! destination segment
	add	ax,#0x1000
	cmp	ax,#0x9000
	jz	end_move
	mov	ds,ax		! source segment
	sub	di,di
	sub	si,si
	mov 	cx,#0x8000
	rep
	movsw
	jmp	do_move

! then we load the segment descriptors

end_move:
	mov	ax,#SETUPSEG	! right, forgot this at first. didn't work :-)
	mov	ds,ax
	lidt	idt_48		! load idt with 0,0 //!IDT (中断描述符表)活的不限制写的位置有保护模式(特权级)替代中断向量表死的在Ox0000位置,!CPU中有idtR寄存器,GDTR,LDTR, 内存有对应的表, 寄存器大概指向各自表的位置
	lgdt	gdt_48		! load gdt with whatever appropriate// !GDT (全局描述符表),GDTR指向gdt_48标记的位置.GDT目的:替代段寄存器, T含义:原来一个寄存器,后来扩充到两个寄存器,为了兼容性,改成 R+长度,因此这个数据结构由一行变成一个数据结构

! that was painless, now we enable A20

	call	empty_8042
	mov	al,#0xD1		! command write
	out	#0x64,al
	call	empty_8042
	mov	al,#0xDF		! A20 // 20位实模式到32保护,北桥南桥CPU寻址能力都变CPU中PE打开,A20打开中间和MEM相关
	out	#0x60,al
	call	empty_8042

! well, that went ok, I hope. Now we have to reprogram the interrupts :-(
! we put them right after the intel-reserved hardware interrupts, at
! int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
! messed this up with the original PC, and they haven't been able to
! rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
! which is used for the internal hardware interrupts as well. We just
! have to reprogram the 8259's, and it isn't fun.
// 这段是硬件保护模式下的规定
	mov	al,#0x11		! initialization sequence
	out	#0x20,al		! send it to 8259A-1 // 8259A有名的电路: 可编程中断控制器; 实模式下有一套,保护模式下又重新编,(图)
	.word	0x00eb,0x00eb		! jmp $+2, jmp $+2
	out	#0xA0,al		! and to 8259A-2
	.word	0x00eb,0x00eb
	mov	al,#0x20		! start of hardware int's (0x20)
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x28		! start of hardware int's 2 (0x28)
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x04		! 8259-1 is master
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x02		! 8259-2 is slave
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x01		! 8086 mode for both
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0xFF		! mask off all interrupts for now
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al

! well, that certainly wasn't fun :-(. Hopefully it works, and we don't
! need no steenking BIOS anyway (except for the initial loading :-).
! The BIOS-routine wants lots of unnecessary data, and it's less
! "interesting" anyway. This is how REAL programmers do it.
!
! Well, now's the time to actually move into protected mode. To make
! things as simple as possible, we do no register set-up or anything,
! we let the gnu-compiled 32-bit programs do that. We just jump to
! absolute address 0x00000, in 32-bit protected mode.
// 打开PE, PE在CPU, EFLAGS与CSDS区别都能存数,DS只存数,EFLAFGS有开关作用(控制寄存器CR,不够用,多加了几个CRO和CR3)寄存器中,PE在CR0寄存器第0位,
//	还有PG位是与分页有关的
	mov	ax,#0x0001	! protected mode (PE) bit
	lmsw	ax		! This is it!
	jmpi	0,8		! jmp offset 0 of segment 8 (cs) 
	// setup最后一条,结束setup,跳转到head.s执行,head.s在前面覆盖实模式中断向量表时候被顶到前面00000位置
	// 8 !!!看成 01000(b)) 低位00:pl 特权级是0; 第3位 0表示GDT/LDT, 第4位:1代表第2项,(第1项是Null,第2项是代码段,第3项)(图—)
	// 保护模式已经打开, 现在是32位, 段要用GDT,
	// GDT表格式:在书上有
	// setup.s 四个扇区 90200,  代码段限长8MB , setup.s head.s 都在这段, 代码位置在0特权位置
	// 这个代码在90200低位

! This routine checks that the keyboard command queue is empty
! No timeout is used - if this hangs there is something wrong with
! the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	al,#0x64	! 8042 status port
	test	al,#2		! is input buffer full?
	jnz	empty_8042	! yes - loop
	ret

gdt:
	.word	0,0,0,0		! dummy

	.word	0x07FF		! 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		! base address=0
	.word	0x9A00		! code read/exec
	.word	0x00C0		! granularity=4096, 386

	.word	0x07FF		! 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		! base address=0
	.word	0x9200		! data read/write
	.word	0x00C0		! granularity=4096, 386

idt_48:
	.word	0			! idt limit=0
	.word	0,0			! idt base=0L

gdt_48:
	.word	0x800		! gdt limit=2048, 256 GDT entries
	.word	512+gdt,0x9	! gdt base = 0X9xxxx
	
.text
endtext:
.data
enddata:
.bss
endbss:
