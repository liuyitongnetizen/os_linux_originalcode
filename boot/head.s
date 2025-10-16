/*
 *  linux/boot/head.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  head.s contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 */
.text
.globl _idt,_gdt,_pg_dir,_tmp_floppy_area
_pg_dir:// 页目录表, head.s现在在内存最前面, 在0x00000位置
startup_32:// 现在是保护模式
	movl $0x10,%eax // 0x10 = 0001 0000(b) = 00:特权级0,0:GDT, 010:第3项,(背: Ox10内核数据段,Ox08内核代码段)
	mov %ax,%ds // ds指向内核数据段,四个段对齐, ax是eax低位 !!!!自己算 _gdt ds 0x10 基址,长度,特权级,代码or数据
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	lss _stack_start,%esp // 汇编中带下划线,去掉跟C语言内容相通,栈指针得到
	call setup_idt	// idt替代中断向量表, 中断描述符表
	call setup_gdt
	movl $0x10,%eax		# reload all the segment registers
	mov %ax,%ds		# after changing gdt. CS was already
	mov %ax,%es		# reloaded in 'setup_gdt'
	mov %ax,%fs
	mov %ax,%gs
	lss _stack_start,%esp
	xorl %eax,%eax
1:	incl %eax		# check that A20 really IS enabled
	movl %eax,0x000000	# loop forever if it isn't
	cmpl %eax,0x100000
	je 1b // 1 是33,b是往前找,是循环,f往后找1;  这段比较0位置和1M位置,相同,类似补码回滚, A20打开则相同,没打开是不相同
/*
 * NOTE! 486 should set bit 16, to check for write-protect in supervisor
 * mode. Then it would be unnecessary with the "verify_area()"-calls.
 * 486 users probably want to set the NE (#5) bit also, so as to use
 * int 16 for math errors.
 */
	movl %cr0,%eax		# check math chip
	andl $0x80000011,%eax	# Save PG,PE,ET
/* "orl $0x10020,%eax" here for 486 might be good */
	orl $2,%eax		# set MP
	movl %eax,%cr0
	call check_x87
	jmp after_page_tables

/*
 * We depend on ET to be correct. This checks for 287/387.
 */
check_x87:
	fninit
	fstsw %ax
	cmpb $0,%al
	je 1f			/* no coprocessor: have to set bits */
	movl %cr0,%eax
	xorl $6,%eax		/* reset MP, set EM */
	movl %eax,%cr0
	ret
.align 2
1:	.byte 0xDB,0xE4		/* fsetpm for 287, ignored by 387 */
	ret

/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It then loads
 *  idt. Everything that wants to install itself
 *  in the idt-table may do so themselves. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok. This routine will be over-
 *  written by the page tables.
 *  irq中断请求->CPU idtR->idt 表项,表项是图1-28, 找到基址,偏移-> 找到中断服务程序(目前放ignore_int)
 */
setup_idt:
	lea ignore_int,%edx   // ignore_int 是未知中断,所有中断具体可能没写完前的默认提示
	movl $0x00080000,%eax //看图1-28, 保留0-32,为了兼容以前中断, 现在是保护模式位数增加, 因此增加图上面两行打补丁;中断描述符表暗含链接GDT
	movw %dx,%ax		/* selector = 0x0008 = cs */
	movw $0x8E00,%dx	/* interrupt gate - dpl=0, present */

	lea _idt,%edi
	mov $256,%ecx
rp_sidt:
	movl %eax,(%edi)
	movl %edx,4(%edi)
	addl $8,%edi
	dec %ecx
	jne rp_sidt
	lidt idt_descr	// idtr指向
	ret

/*
 *  setup_gdt
 *
 *  This routines sets up a new gdt and loads it.
 *  Only two entries are currently built, the same
 *  ones that were built in init.s. The routine
 *  is VERY complicated at two whole lines, so this
 *  rather long comment is certainly needed :-).
 *  This routine will beoverwritten by the page tables.
 */
setup_gdt:
	lgdt gdt_descr // gdt_descr起始位
	ret

/*
 * I put the kernel page tables right after the page directory,
 * using 4 of them to span 16 Mb of physical memory. People with
 * more than 16MB will have to expand this.
 */
.org 0x1000
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

.org 0x5000
/*
 * tmp_floppy_area is used by the floppy-driver when DMA cannot
 * reach to a buffer-block. It needs to be aligned, so that it isn't
 * on a 64kB border.
 */
_tmp_floppy_area:
	.fill 1024,1,0

after_page_tables:
	pushl $0		# These are the parameters to main :-)
	pushl $0
	pushl $0
	pushl $L6		# return address for main, if it decides to.
	pushl $_main    // main函数执行入口地址压栈= 调用main函数,执行jmp 后,返回?
	jmp setup_paging
L6:
	jmp L6			# main should never return here, but
				# just in case, we know what happens.

/* This is the default interrupt "handler" :-) */
// 在整个保护模式建立过程中, 如果遇到中断, 先统一一个值, 不然没有响应
int_msg:
	.asciz "Unknown interrupt\n\r"
.align 2
ignore_int:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	pushl $int_msg // 输出参数
	call _printk //内核状态直接往屏幕输出
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret //interupt return, 上述是中断服务程序


/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 16MB. The pager assumes that no illegal
 * addresses are produced (ie >4Mb on a 4Mb machine).
 *
 * NOTE! Although all physical memory should be identity
 * mapped by this routine, only the kernel page functions
 * use the >1Mb addresses directly. All "normal" functions
 * use just the lower 1Mb, or the local data space, which
 * will be mapped to some other place - mm keeps track of
 * that.
 *
 * For those with more memory than 16 Mb - tough luck. I've
 * not got it, why should you :-) The source is here. Change
 * it. (Seriously - it shouldn't be too difficult. Mostly
 * change some constants etc. I left it at 16Mb, as my machine
 * even cannot be extended past that (ok, but it was cheap :-)
 * I've tried to show which constants to change by having
 * some kind of marker at them (search for "16Mb"), but I
 * won't guarantee that's all :-( )
 *
 * 分页, 分页机制是CPU硬件规定, 4K页, 线性地址: 页目录项-页表项-页内偏移; 页目录项4字节, 共1k项, 占10位; 页表项4字节,占10位; 10+10+12 =32 (2^32=4G)
 * 页目录表项 查到页表项需要20位就够了,还剩12bit位(放一些位,如缺页中断),与下文7相关
 * CR3 指向页目录表地址
 * 一个页目录表对应一个线性地址空间,需要一个CR3指向页目录表,这叫CR3切换
 * 用户程序 线性地址; kenel程序 也是指向线性地址, 跑代码寻址全是线性地址,因为0特权是在线性地址上,所以kenel程序也是指向线性地址的
 * 分页是对于硬件和线性地址都分页, 线性地址算后到物理地址与真实的物理地址一样, 能实现有效内存访问控制
 * 两个线性页可以是同一个物理地址: 代码段复用 (父进程创建子进程,可以共享或不共享,子进程拿到内存中这个过程必须要父进程,需要映射)有意义
 */
.align 2
setup_paging:
	movl $1024*5,%ecx		/* 5 pages - pg_dir+4 page tables */ // 前4行, 5个页清0
	xorl %eax,%eax
	xorl %edi,%edi			/* pg_dir is at 0x000 */
	cld;rep;stosl
	movl $pg0+7,_pg_dir		/* set present bit/user r/w */ // 地址+7 放到页目录表第一个位置(后4个页放到第1个页里,第一个页是页目录表)
	movl $pg1+7,_pg_dir+4		/*  --------- " " --------- */ // 7含义:
	movl $pg2+7,_pg_dir+8		/*  --------- " " --------- */
	movl $pg3+7,_pg_dir+12		/*  --------- " " --------- */
	movl $pg3+4092,%edi
	movl $0xfff007,%eax		/*  16Mb - 4096 + 7 (r/w user,p) */
	std
1:	stosl			/* fill pages backwards - more efficient :-) */
	subl $0x1000,%eax
	jge 1b
	xorl %eax,%eax		/* pg_dir is at 0x0000 */
	movl %eax,%cr3		/* cr3 - page directory start */ //CR3指定页目录表基址0
	movl %cr0,%eax //cr0 原来是PE=1
	orl $0x80000000,%eax //100...001 //不能只打开分页,不打开保护模式
	movl %eax,%cr0		/* set paging (PG) bit */
	ret			/* this also flushes prefetch-queue */

.align 2
.word 0
// 实模式: 中断向量 到 中断服务程序
// 保护模式: CPU中idtR找idt, 找idt找描述符, 指向中断服务程序, 首先统一一个中端服务程序(所有都能跳到这,叫Ignore_int)
idt_descr: //idt表
	.word 256*8-1		# idt contains 256 entries
	.long _idt
.align 2
.word 0
gdt_descr:
	.word 256*8-1		# so does gdt (not that that's any
	.long _gdt		# magic number, but it works for me :^)

	.align 3
_idt:	.fill 256,8,0		# idt is uninitialized

_gdt:	.quad 0x0000000000000000	/* 0项: 空? 书上找 NULL descriptor */
	.quad 0x00c09a0000000fff	/* 0特权代码段 16Mb */
	.quad 0x00c0920000000fff	/* 0特权数据段 16Mb */
	.quad 0x0000000000000000	/* 空 与前后隔开,后续是进程   TEMPORARY - don't use */
	.fill 252,8,0			/* space for LDT's and TSS's etc */
