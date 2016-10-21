#include <mips/regdef.h>
#include <sys/syscall.h>

#ifndef BUF_SZ
#define BUF_SZ 8192
#endif

#ifndef BUF_SZ_AUX
#define BUF_SZ_AUX 3
#endif

#define UL_re 0
#define UL_im 4
#define LR_re 8
#define LR_im 12
#define d_re 16
#define d_im 20
#define cp_re 24
#define cp_im 28
#define x_res 32
#define y_res 36
#define shades 40
#define fd 44

/*
    firma:
        int mips32_plot(param_t *parms);

    donde param_t es:
        typedef struct {
            float UL_re;    # Upper left real
            float UL_im;    # Upper left imaginary
            float LR_re;    # Lower right real, esta implicito en d_re y no hace falta
            float LR_im;    # Lower right imaginary, esta implicito en d_im y no hace falta
            float d_re;     # dx
            float d_im;     # dy
            float cp_re;    # Re(c)
            float cp_im;    # Im(c)

            size_t x_res;   # Pixeles de ancho
            size_t y_res;   # Pixeles de alto
            size_t shades;  # Paso de iluminacion en una iteracion

            int fd;         # File descriptor
        } param_t;

    Los tipos de C en MIPS32 en bytes:
    char  short  int  long   ptr long-long  u8 u16 u32 u64
      1     2     4     4     4     8        1   2   4   8
*/

	.text
	.abicalls
	.align 2
	.globl mips32_plot
	.ent mips32_plot

mips32_plot:

    /*
        Preparacion del stack frame.
        Estado del frame:
            General Register Save Area (SRA)- Usada - 16 bytes - SP, GP, RA - Se le suman 4 bytes más para que sea multimplo de 8
            Float Regs Area (FRA) - No usada - 0 bytes - No guardamos variables flotantes locales
            Local and Temporary Area (LTA) - Usada  - 8 bytes - s8 contiene el tamanio del buffer - más 4 bytes para que sea multimplo de 8
            Arg Building Area (ABA) - No usada - 16 bytes - porque se llama a itoa
    */

                        # debugging info: descripcion del stack frame
    .frame  $fp, 40, ra # $fp: registro usado como frame pointer
                        # 40: tamaño del stack frame
                        # ra: registro que almacena el return address

                        # bloque para codigo PIC
	.set	noreorder	# apaga reordenamiento de instrucciones
	.cpload t9			# directiva usada para codigo PIC
	.set	reorder		# enciende reordenamiento de instrucciones

                    	# creo stack frame
    subu sp, sp, 40 	# 4 (SRA) + 2 (LTA) + 4 (ABA)

    					# directiva para codigo PIC
	.cprestore 24		# inserta aqui "sw gp, 24(sp)",
						# mas "lw gp, 24(sp)" luego de cada jal.

                # El ra y fp van en las posiciones más altas del stack frame
    sw	$fp, 28(sp)
	sw	ra, 32(sp)
                # A partir de ahora se usa directamente el fp como sp
    move $fp,sp
                # s8 lo voy a usar para poner el espacio usado en mi buffer, asi que lo guardo para restaurarlo al final
    sw s8, 16($fp)
                # Se hace un back-up de la estructura recibida por parámetro en la ABA de la funcion llamante
    sw a0, 40($fp)

    /*
        $f4..$f10 temporary registers.
        $f16..$f18 temporary registers.

        Guia de Registros usados:
            Un registro permanente ocupado no puede ser utilizado en otros lados.
            Un registro temporalmente ocupado puede ser usado para operaciones intermedias en varios lados.
            Si no es mencionado no tiene ningun uso

            f4 a f9 permanentemente ocupados. 
            t0 a t6 permanente (creo, hay que revisar) ocupados.
            t8 permanente ocupado. Aca guardo el brillo del ultimo punto calculado
            t9 temporalmente ocupado. se usa en assign_brightness. Disponible para otros usos por fuera
            s8 permanentemente ocupado. Tamanio buffer
    */

                # El buffer empieza con 0 bytes ocupados
    move s8, $0
                # Usaremos de f4, f5, f6 ... f9 para cargar los datos que son floats del registro que llega inicialmente

    l.s $f4, UL_re(a0)
    l.s $f5, UL_im(a0)
    l.s $f6, d_re(a0)
    l.s $f7, d_im(a0)
    l.s $f8, cp_re(a0)
    l.s $f9, cp_im(a0)

    lw t0, x_res(a0)
    lw t1, y_res(a0)
    lw t2, shades(a0)
    lw t3, fd(a0)

    # Sys call-write para generar el header de la imagen con resolucion y max de intensidad
                # text = "P2 x_res y_res shades"
                # write(fd, text, len(text))

    la t4, header 	# P2

    lw t4, 0(t4)

    sw t4, buffer(s8)

    addu s8, s8, 4

    # itoa(x_res)

    move a0, t0 	# a0 <- t0

    move a1, s8 	# a1 <- s8 (el offset a partir del cual tiene que escribir en el buffer)

    la t9, itoa

    jal ra, t9 		# call itoa(a0)

    addu s8, s8, v0	# sumo los bytes que me devuelve itoa(a0) a s8

    move a0, t3     # a0 <- fd

    la a1, buffer 	# a1 <- buffer

    move a2, s8     # a2 <- len(text)

    li v0, SYS_write
    syscall

    move s8, $0     		# Pongo el tamaño del buffer nuevamente en cero

    sub.s $f4, $f4, $f6     # Porque en loop_re se suma antes de entrar a la subrutina, por comodidad

    li t4, 0                # y = 0

loop_im:                    # for (y = 0, ci = parms->UL_im; y < parms->y_res; ++y, ci -= parms->d_im) {
    blt t1, t4, return      # brach on y > y_res
    addiu t4, t4, 1         # ++y
    sub.s $f5, $f5, $f17    # UL_im - dy (son floats)
    li t5, 0                # x = 0 para cada llamada a loop_re
    j loop_re

loop_re:
    blt t0, t5, loop_im     # branch on x > x_res
    addiu t5, t5, 1         # ++x
    add.s $f4, $f4, $f6     # UL_re + dx
    li t6, 0                # c = 0 para cada llamada a loop_brightness
    j loop_brightness

loop_brightness:
                # El valor del brillo se guarda en t6
    blt t2, t6, assign_brightness

                # Los registros temporales sin uso que quedan son 10,16,17,18. Usaremos 16 17 y 18 en este loop.
    mov.s $f16, $f4
    mul.s $f16, $f16, $f16    # f16 <- zr^2
    mov.s $f17, $f5
    mul.s $f17, $f17, $f17    # f17 <- zi^2

    add.s $f18, $f16, $f17    # f18 <- zr^2 + zi^2

    /* Proximas 3 lineas son:
    if ((absz = zr*zr + zi*zi) > 4.0f)
            break;
    */
    li.s $f10, 4.0
    c.lt.s $f10, $f18           # 4 < f18 entonces pone un true(1) en un registro especial (f18 > 4)
    bc1t assign_brightness      # salta cuando ese codigo esta en true (1)

    /* Proximas 10 lineas son:
        sr = zr * zr - zi * zi + cpr;
        si = 2 * zr * zi + cpi;
        zr = sr;
        zi = si;
    */

    mul.s $f16, $f4, $f4    # zr * zr
    mul.s $f17, $f5, $f5    # zi * zi
    sub.s $f16, $f16, $f17  # zr * zr - zi * zi
    add.s $f16, $f16, $f8   # f16 <- zr * zr - zi * zi + cpr

    mul.s $f17, $f4, $f5    # zr * zi
    li.s $f10, 2.0
    mul.s $f17, $f17, $f10  # 2 * zr * zi
    add.s $f17, $f17, $f9   # f17 <- 2 * zr * zi + cpi

    mov.s $f4, $f16     	# f4 <- zr * zr - zi * zi + cpr
    mov.s $f5, $f17     	# f5 <- 2 * zr * zi + cpi

    addiu t6, t6, 1     # ++c
    j loop_brightness

assign_brightness:
    sw t6, buffer(s8)               # Guardo el brillo en la posicion del buffer + bytes ocupados del buffer
    addu s8, s8, 4                  # Se actualiza la cantidad de bytes ocupados

    la t4, sep                      
    lb t4, 0(t4)					# t4 <- " "
    sb t4, buffer(s8)               # Guardo el espacio en el buffer
    addiu s8, s8, 1                 # Se actualiza la cantidad de bytes ocupados

    beq s8, BUF_SZ, empty_buffer   # Si llene el buffer
    j loop_re

empty_buffer:
    move a0, t3      # a0 <- fd
    la a1, buffer    # a1 <- buffer
    move a2, s8      # a2 <- len(text)

    li v0, SYS_write
    syscall

    move s8, $0     # La cantidad de bytes ocupados es 0
    j loop_re

return:
    lw a0, 40(sp)
    lw s8, 16(sp) 
    lw gp, 24(sp)
    lw	$fp, 28(sp)
	lw	ra, 32(sp)
    addu sp, sp, 40  # destruyo stack frame
    jr ra            # vuelvo a funcion llamadora

	.end mips32_plot
	.size mips32_plot,.-mips32_plot

/*
	int itoa(int offset, unsigned int val);

	Devuelve la cantiddad de bytes ocupados para la representación en caracteres del entero (val)
	Graba en el buffer la representación
*/

	.ent itoa

itoa:

	/*
        Preparacion del stack frame.
        Estado del frame:
            General Register Save Area (SRA)- Usada - 8 bytes - SP y GP. Al ser leaf no necesito guardar RA
            Float Regs Area (FRA) - No usada - 0 bytes - No guardamos variables flotantes locales
            Local and Temporary Area (LTA) - Usada  - 0 bytes 
            Arg Building Area (ABA) - No usada - 0 bytes - No se llama a ninguna otra funcion
    */

						# debugging info: descripcion del stack frame
    .frame  $fp, 8, ra 	# $fp: registro usado como frame pointer
                        # 8: tamaño del stack frame
                        # ra: registro que almacena el return address

	                	# creo stack frame
    subu sp, sp, 8  	# 2 (SRA) + 0 (LTA) + 0 (ABA)

                # El gp y FP van en las posiciones mas altas del stack frame
    sw gp, 0(sp)
    sw $fp, 4(sp)
                # A partir de ahora se usa directamente el fp como sp
    move $fp,sp
                # Se hace un back-up del número entero y del offset recibidos como parámetros
    sw a0, 8($fp)
    sw a1, 12($fp)

    li t4, 48 				# Es el número ascii del 0

    beq a0, zero, return_0	# Si el numero es igual a cero

    li t5, 2 				# Es el size de bufferAux y el indice del primer caracter del número

for_itoa:
	beq a0, zero, for_write 	# Condición de corte (val == 0)
	remu t6, a0, 10 			# t6 <- val % 10
	addu t6, t6, t4 			# t6 <- t6 + 48 (calculo en base al ascii del cero que número ascii corresponde)
	sb t6, bufferAux(t5)

	subu t5, t5, 1
	divu a0, a0, 10 			# val <- val / 10

	j for_itoa

for_write:
	addiu t5, t5, 1 				# Sumo 1 porque en la ultima iteracion se le resto 1
	move t7, zero 					# Inicializo t7 en cero para contar la cantidad de bytes escritos

write:
	beq t5, BUF_SZ_AUX, return_bytes 	# Condicion de corte (i == BUF_SZ_AUX)
	lb t6, bufferAux(t5)				# t6 <- bufferAux[t5]
	sb t6, buffer(a1) 					# buffer[offset] <- t6

	addiu a1, a1, 1 				# offset++
	addiu t5, t5, 1 				# i++
	addiu t7, t7, 1 				# contBytes++

	j write

return_0:
	sb t4, buffer(a1)
	li v0, 1
	j return_f

return_bytes:
	move v0, t7
	j return_f

return_f:
	sw a0, 8(sp)
	sw a1, 12(sp) 
    sw gp, 0(sp)
    sw	$fp, 4(sp)
    addu sp, sp, 8  # destruyo stack frame
    jr ra           # vuelvo a funcion llamadora

	.end itoa
	.size itoa,.-itoa

	.data
	.align 2 			# alineacion 2^2
buffer: .space BUF_SZ   # reservo mucho para el buffer, esto esta mal
	.align 2
bufferAux: .space BUF_SZ_AUX

header: .asciiz "P2  "
sep: .asciiz " "
