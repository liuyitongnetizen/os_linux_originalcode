//人工模仿 硬件中断压栈,此时iret前是boot阶段无进程,内核栈特殊脱离了进程, (真正内核栈4KB,依附于进程)假定之前有过3特权级中断(iret 前是0特权级),现在要切换到3特权级
// iret前那个内核栈是给0特权级用的,现在要切换到3特权级,所以要新建一个内核栈给3特权级用,但是现在还没进程,所以用iret前的栈直接复用,从boot开始用这个栈直到这里的iret前没动过这个user_stack
// user_stack在boot阶段,内核栈需要依附进程,但是boot阶段没进程,所以假定了一个
//user_stack :大部分时间用在3特权进程0 而不是boot阶段
//ss  0x17=0001 0111。11:3 LDT
/*esp, user_stack 内核栈, */
//eflags
//*  0x0f=0000 1111。11:3 LDT。  cs*/
//eip
// 先push到eax 因为后续push操作会改变esp
// 这段实现启动进程0 ,必须是进程0 ,因为sched_init里初始化的init_task就是进程0
#define move_to_user_mode() \
__asm__ ("movl %%esp,%%eax\n\t" \
	"pushl $0x17\n\t" \
	"pushl %%eax\n\t" \ 
	"pushfl\n\t" \		
	"pushl $0x0f\n\t" \ 
	"pushl $1f\n\t" \	
	"iret\n" \  
	"1:\tmovl $0x17,%%eax\n\t" \
	"movw %%ax,%%ds\n\t" \
	"movw %%ax,%%es\n\t" \
	"movw %%ax,%%fs\n\t" \
	"movw %%ax,%%gs" \
	:::"ax")

#define sti() __asm__ ("sti"::)
#define cli() __asm__ ("cli"::)
#define nop() __asm__ ("nop"::)

#define iret() __asm__ ("iret"::)

// 嵌入汇编 d:edx,32位(田字格好记)带来了地址指针(!!!在IDT那个图和田字格类似哦) a:eax
/** 
 * IDT在内存中, 借助寄存器edx和eax来设置IDT表项(田字格)
 * edx低16位(地址低16位) 给eax低16位
 * %1 是IDT表项地址
 * 看笔记图
 * gate_addr: IDT表项地址,IDT是中断描述符表
 * 对于除零错误idt[0], IDT图中 此时段选择符是8(jumpi 0 8), 是“a" 0x00080000
 * "i" 设置 IDT表项(第二行),给edx低16位赋值
 * 总结: 设置IDT表项
 */
#define _set_gate(gate_addr,type,dpl,addr) \
__asm__ ("movw %%dx,%%ax\n\t" \ 
	"movw %0,%%dx\n\t" \
	"movl %%eax,%1\n\t" \
	"movl %%edx,%2" \
	: \
	: "i" ((short) (0x8000+(dpl<<13)+(type<<8))), \
	"o" (*((char *) (gate_addr))), \
	"o" (*(4+(char *) (gate_addr))), \
	"d" ((char *) (addr)),"a" (0x00080000))

#define set_intr_gate(n,addr) \
	_set_gate(&idt[n],14,0,addr)

/**15: f=1111。
 * CPL code privilege level ,指令本身所在段的特权级
 * DPL descriptor privilege level, 
 * RPL requestor privilege level 
 * jmpi 0 8; 8=1000=代码段描述符,低位00是RPL requestor privilege level
 * 看书CPL DPL RPL
 */
#define set_trap_gate(n,addr) \
	_set_gate(&idt[n],15,0,addr)

#define set_system_gate(n,addr) \
	_set_gate(&idt[n],15,3,addr)

#define _set_seg_desc(gate_addr,type,dpl,base,limit) {\
	*(gate_addr) = ((base) & 0xff000000) | \
		(((base) & 0x00ff0000)>>16) | \
		((limit) & 0xf0000) | \
		((dpl)<<13) | \
		(0x00408000) | \
		((type)<<8); \
	*((gate_addr)+1) = (((base) & 0x0000ffff)<<16) | \
		((limit) & 0x0ffff); }

// 看,目的做段描述符表(图)
#define _set_tssldt_desc(n,addr,type) \
__asm__ ("movw $104,%1\n\t" \
	"movw %%ax,%2\n\t" \
	"rorl $16,%%eax\n\t" \
	"movb %%al,%3\n\t" \
	"movb $" type ",%4\n\t" \
	"movb $0x00,%5\n\t" \
	"movb %%ah,%6\n\t" \
	"rorl $16,%%eax" \
	::"a" (addr), "m" (*(n)), "m" (*(n+2)), "m" (*(n+4)), \
	 "m" (*(n+5)), "m" (*(n+6)), "m" (*(n+7)) \
	)

#define set_tss_desc(n,addr) _set_tssldt_desc(((char *) (n)),addr,"0x89")
#define set_ldt_desc(n,addr) _set_tssldt_desc(((char *) (n)),addr,"0x82")
