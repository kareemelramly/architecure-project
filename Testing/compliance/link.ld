SECTIONS { . = 0x0; .text : { *(.text*) } . = ALIGN(16); .data : { *(.data*) *(.sdata*) *(.bss*) } }
