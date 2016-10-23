#include <mips/regdef.h>
#include <sys/syscall.h>

#ifndef BUF_SZ
#define BUF_SZ 8192
#endif

#ifndef BUF_SZ_AUX
#define BUF_SZ_AUX 4
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
            General Register Save Area (SRA)- Usada - 32 bytes - SP, GP, RA, s0, s1, s2, s3, s7
            Float Regs Area (FRA) - No usada - 0 bytes - No guardamos variables flotantes locales
            Local and Temporary Area (LTA) - No usada
            Arg Building Area (ABA) - No usada - 16 bytes - porque se llama a itoa
    */

                        # debugging info: descripcion del stack frame
    .frame  $fp, 48, ra # $fp: registro usado como frame pointer
                        # 48: tamaño del stack frame
                        # ra: registro que almacena el return address

                        # bloque para codigo PIC
	.set	noreorder	# apaga reordenamiento de instrucciones
	.cpload t9			# directiva usada para codigo PIC
	.set	reorder		# enciende reordenamiento de instrucciones

                    	# creo stack frame
    subu sp, sp, 48 	# 8 (SRA) + 0 (LTA) + 4 (ABA)

    					# directiva para codigo PIC
	.cprestore 36		# inserta aqui "sw gp, 36(sp)",
						# mas "lw gp, 36(sp)" luego de cada jal.

    # El ra y fp van en las posiciones más altas del stack frame
    sw	$fp, 40(sp)
	sw	ra, 44(sp)
    
    # A partir de ahora se usa directamente el fp como sp
    move $fp,sp
    
    # s0 -> x_res
    # s1 -> y_res
    # s2 -> shades
    # s3 -> fd
    # s7 se va a usar para poner el espacio usado en el buffer.
    sw s0, 16($fp)
    sw s1, 20($fp)
    sw s2, 24($fp)
    sw s3, 28($fp)
    sw s7, 32($fp)
    
    # Se hace un back-up de la estructura recibida por parámetro en la ABA de la funcion llamante
    sw a0, 48($fp)

    /*
        $f4..$f10 temporary registers.
        $f16..$f18 temporary registers.

        Guia de Registros usados:
            Un registro permanente ocupado no puede ser utilizado en otros lados.
            Un registro temporalmente ocupado puede ser usado para operaciones intermedias en varios lados.
            Si no es mencionado no tiene ningun uso

            f4 a f9 permanentemente ocupados. 
            t0 a t6 permanente (creo, hay que revisar) ocupados.
            t8 permanente ocupado. Aca guardo el brillo del ultimo punto calculado.
            t9 temporalmente ocupado. se usa en assign_brightness. Disponible para otros usos por fuera.
            s0 permanentemente ocupado. File descriptor.
            s7 permanentemente ocupado. Tamanio buffer.
    */

    # El buffer empieza con 0 bytes ocupados
    move s7, $0
    
    # Usaremos de f4, f5, f6 ... f9 para cargar los datos que son floats del registro que llega inicialmente
    l.s $f4, UL_re(a0)
    l.s $f5, UL_im(a0)
    l.s $f6, d_re(a0)
    l.s $f7, d_im(a0)
    l.s $f8, cp_re(a0)
    l.s $f9, cp_im(a0)

    lw s0, x_res(a0)
    lw s1, y_res(a0)
    lw s2, shades(a0)
    lw s3, fd(a0)

    # Sys call-write para generar el header de la imagen con resolucion y max de intensidad
    # text = "P2 x_res y_res shades"

    # ("P2  ")

    lw t4, header($0)    
    sw t4, buffer(s7)
    addu s7, s7, 4

    # itoa(x_res)

    move a0, s0 	# a0 <- s0
    move a1, s7 	# a1 <- s7 (el offset a partir del cual tiene que escribir en el buffer)
    la t9, itoa
    jal ra, t9 		# call itoa
	addu s7, s7, v0	# Se suman los bytes que devuelve itoa a s7

    # Se agrega un espacio (" ")

    lb t4, sep($0)
    sb t4, buffer(s7)
    addu s7, s7, 1

    # itoa(y_res)

    move a0, s1     # a0 <- s1
    move a1, s7     # a1 <- s7 (el offset a partir del cual tiene que escribir en el buffer)
    la t9, itoa
    jal ra, t9      # call itoa
    addu s7, s7, v0 # Se suman los bytes que devuelve itoa a s7

    # Se agrega un espacio (" ")

    lb t4, sep($0)
    sb t4, buffer(s7)
    addu s7, s7, 1

    # itoa(shades)

    move a0, s2     # a0 <- s2
    move a1, s7     # a1 <- s7 (el offset a partir del cual tiene que escribir en el buffer)
    la t9, itoa
    jal ra, t9      # call itoa
    addu s7, s7, v0 # Se suman los bytes que devuelve itoa a s7

    # Se agrega un enter ("\n") que es el ascii 10

    li t4, 10
    sb t4, buffer(s7)
    addu s7, s7, 1

    # write(fd, text, len(text))

    move a0, s3     # a0 <- fd
    la a1, buffer 	# a1 <- buffer
    move a2, s7     # a2 <- len(text)

    li v0, SYS_write
    syscall

    move s7, $0     # Tamaño del buffer nuevamente en cero

    # Comienzo de la simulación del conjunto

    li t0, 0                        # y = 0
    mov.s $f1, $f5                  # ci = UL_im

loop_im:
    beq t0, s1, return              # brach on y == y_res
    li t1, 0                        # x = 0
    mov.s $f2, $f4                  # cr = UL_re

loop_re:
    beq t1, s0, end_loop_im         # branch on x == x_res
    li t2, 0                        # c = 0
    mov.s $f10, $f2                 # zr = cr
    mov.s $f11, $f1                 # zi = ci

loop_brightness:
    beq t2, s2, assign_brightness   # c == shades

    mul.s $f16, $f10, $f10          # f16 <- zr * zr
    mul.s $f17, $f11, $f11          # f17 <- zi * zi

    add.s $f18, $f16, $f17          # f18 <- zr * zr + zi * zi

    /* Proximas 3 lineas son:
        if ((absz = zr*zr + zi*zi) > 4.0f)
            break;
    */

    li.s $f3, 4.0
    c.lt.s $f3, $f18                # 4 < f18 entonces pone un true(1) en un registro especial (f18 > 4)
    bc1t assign_brightness          # salta cuando ese codigo esta en true (1)

    sub.s $f16, $f16, $f17          # zr * zr - zi * zi
    add.s $f16, $f16, $f8           # f16 <- zr * zr - zi * zi + cpr

    mul.s $f17, $f10, $f11          # zr * zi
    li.s $f3, 2.0
    mul.s $f17, $f17, $f3           # 2 * zr * zi
    add.s $f17, $f17, $f9           # f17 <- 2 * zr * zi + cpi

    mov.s $f10, $f16                # f4 <- zr * zr - zi * zi + cpr
    mov.s $f11, $f17                # f5 <- 2 * zr * zi + cpi

    addu t2, t2, 1                  # ++c
    j loop_brightness

assign_brightness:
    # itoa(c)
    move a0, t2                     # a0 <- s0
    move a1, s7                     # a1 <- s7 (el offset a partir del cual tiene que escribir en el buffer)
    la t9, itoa
    jal ra, t9                      # call itoa
    addu s7, s7, v0                 # Se suman los bytes que devuelve itoa a s7

    li t4, 10					    # t4 <- "\n" ascci 10
    sb t4, buffer(s7)               # Se guarda el enter en el buffer
    addu s7, s7, 1                  # Se actualiza la cantidad de bytes ocupados

    beq s7, BUF_SZ, empty_buffer    # Si se llenó el buffer
    j end_loop_re

end_loop_re:
    addu t1, t1, 1          # x++
    add.s $f2, $f2, $f6     # cr += d_re
    j loop_re

end_loop_im:
    addu t0, t0, 1          # y++
    sub.s $f1, $f1, $f7     # ci -= d_im
    j loop_im

empty_buffer:
    move a0, s3             # a0 <- fd
    la a1, buffer           # a1 <- buffer
    move a2, s7             # a2 <- len(text)

    li v0, SYS_write
    syscall

    move s7, $0             # La cantidad de bytes ocupados es 0
    j end_loop_re

return:
    # Se escribe lo que haya quedado en el buffer
    move a0, s3      # a0 <- fd
    la a1, buffer    # a1 <- buffer
    move a2, s7      # a2 <- len(text)

    li v0, SYS_write
    syscall

    lw s0, 16(sp)
    lw s1, 20(sp)
    lw s2, 24(sp)
    lw s3, 28(sp)
    lw s7, 32(sp)

    lw a0, 48(sp)

    lw gp, 36(sp)
    lw $fp, 40(sp)
	lw ra, 44(sp)
    addu sp, sp, 48  # destruyo stack frame
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

    .set    noreorder   # apaga reordenamiento de instrucciones
    .cpload t9          # directiva usada para codigo PIC
    .set    reorder     # enciende reordenamiento de instrucciones

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

    li t5, 3 				# (bufferAux-1) es el indice del primer caracter del número

for_itoa:
	beq a0, zero, for_write 	# Condición de corte (val == 0)
	remu t6, a0, 10 			# t6 <- val % 10
	addu t6, t6, t4 			# t6 <- t6 + 48 (calculo en base al ascii del cero que número ascii corresponde)
	sb t6, bufferAux(t5)

	subu t5, t5, 1
	divu a0, a0, 10 			# val <- val / 10

	j for_itoa

for_write:
	addu t5, t5, 1 				# Sumo 1 porque en la ultima iteracion se le resto 1
	move t7, $0 				# Inicializo t7 en cero para contar la cantidad de bytes escritos

write:
	beq t5, BUF_SZ_AUX, return_bytes 	# Condicion de corte (i == BUF_SZ_AUX)
	lb t6, bufferAux(t5)				# t6 <- bufferAux[t5]
	sb t6, buffer(a1) 					# buffer[offset] <- t6

	addu a1, a1, 1 				# offset++
	addu t5, t5, 1 				# i++
	addu t7, t7, 1 				# contBytes++

	j write

return_0:
	sb t4, buffer(a1)
	li v0, 1
	j return_f

return_bytes:
	move v0, t7
	j return_f

return_f:
	lw a0, 8(sp)
	lw a1, 12(sp) 
    lw gp, 0(sp)
    lw  $fp, 4(sp)
    addu sp, sp, 8      # destruyo stack frame
    jr ra               # vuelvo a funcion llamadora

	.end itoa
	.size itoa,.-itoa

	.data
	.align 2 			# alineacion 2^2
buffer: .space BUF_SZ   # reservo mucho para el buffer, esto esta mal
	.align 2
bufferAux: .space BUF_SZ_AUX
	.align 2
header: .asciiz "P2  "
    .align 2
sep: .asciiz " "
