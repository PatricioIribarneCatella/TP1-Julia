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
            General Register Save Area (SRA)- Usada - 48 bytes - SP, GP, RA, s0, s1, s2, s3, s4, s5, s6, s7
            Float Regs Area (FRA) - No usada - 0 bytes - No guardamos variables flotantes locales
            Local and Temporary Area (LTA) - Usada - 8 bytes - Resultados de la función itoa
            Arg Building Area (ABA) - No usada - 16 bytes - porque se llama a itoa
    */

                        # debugging info: descripcion del stack frame
    .frame  $fp, 72, ra # $fp: registro usado como frame pointer
                        # 72: tamaño del stack frame
                        # ra: registro que almacena el return address

                        # bloque para codigo PIC
    .set noreorder	# apaga reordenamiento de instrucciones
    .cpload t9		# directiva usada para codigo PIC
    .set reorder	# enciende reordenamiento de instrucciones

                    	# creo stack frame
    subu sp, sp, 72 	# 12 (SRA) + 2 (LTA) + 4 (ABA)

    			# directiva para codigo PIC
    .cprestore 56	# inserta aqui "sw gp, 56(sp)",
			# mas "lw gp, 56(sp)" luego de cada jal.

    # El ra y fp van en las posiciones más altas del stack frame
    sw	$fp, 60(sp)
    sw	ra, 64(sp)
    
    # A partir de ahora se usa directamente el fp como sp
    move $fp,sp
    
    sw s0, 24($fp)  # x_res
    sw s1, 28($fp)  # y_res
    sw s2, 32($fp)  # shades
    sw s3, 36($fp)  # fd
    sw s4, 40($fp)  # x (contador)
    sw s5, 44($fp)  # y (contador)
    sw s6, 48($fp)  # c (contador)
    sw s7, 52($fp)  # Se va a usar para poner el espacio usado en el buffer.
    
    # Se hace un back-up de la estructura recibida por parámetro en la ABA de la funcion llamante
    sw a0, 72($fp)

    # El buffer empieza con 0 bytes ocupados
    move s7, $0
    
    # Usaremos de f4, f5, f6 ... f9 para cargar los datos que son floats de la estructura
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

    move a0, s0    # a0 <- s0
    la t9, itoa
    jal ra, t9 	   # call itoa

    # writeBuffer("x_res", len("x_res"))

    move a0, v0     # a0 <- dirección de memoria del primer caracter
    move a1, v1     # a1 <- cantidad de bytes a escribir
    move a2, s7     # a2 <- s7 (el offset a partir del cual tiene que escribir en el buffer)
    la t9, writeBuffer
    jal ra, t9

    addu s7, s7, a1 # Se suman los bytes que devuelve itoa a s7

    # Se agrega un espacio (" ")

    lb t4, sep($0)
    sb t4, buffer(s7)
    addu s7, s7, 1

    # itoa(y_res)

    move a0, s1     # a0 <- s1
    la t9, itoa
    jal ra, t9      # call itoa

    # writeBuffer("y_res", len("y_res"))

    move a0, v0     # a0 <- dirección de memoria del primer caracter
    move a1, v1     # a1 <- cantidad de bytes a escribir
    move a2, s7     # a2 <- s7 (el offset a partir del cual tiene que escribir en el buffer)
    la t9, writeBuffer
    jal ra, t9

    addu s7, s7, a1 # Se suman los bytes que devuelve itoa a s7

    # Se agrega un espacio (" ")

    lb t4, sep($0)
    sb t4, buffer(s7)
    addu s7, s7, 1

    # itoa(shades)

    move a0, s2     # a0 <- s2
    la t9, itoa
    jal ra, t9      # call itoa

    # writeBuffer("shades", len("shades"))

    move a0, v0     # a0 <- dirección de memoria del primer caracter
    move a1, v1     # a1 <- cantidad de bytes a escribir
    move a2, s7     # a2 <- s7 (el offset a partir del cual tiene que escribir en el buffer)
    la t9, writeBuffer
    jal ra, t9

    addu s7, s7, a1 # Se suman los bytes que devuelve itoa a s7

    # Se agrega un enter ("\n") que es el ascii 10

    li t4, 10
    sb t4, buffer(s7)
    addu s7, s7, 1

    # write(fd, text, len(text))

    move a0, s3     # a0 <- fd
    la a1, buffer   # a1 <- buffer
    move a2, s7     # a2 <- len(text)

    li v0, SYS_write
    syscall

    bne a3, zero, return_error 	# Se verifica si hubo un error de escritura

    move s7, $0     # Tamaño del buffer nuevamente en cero

    # Comienzo de la simulación del conjunto

    li s5, 0                        # y = 0
    mov.s $f1, $f5                  # ci = UL_im

loop_im:
    beq s5, s1, return              # brach on y == y_res
    li s4, 0                        # x = 0
    mov.s $f2, $f4                  # cr = UL_re

loop_re:
    beq s4, s0, end_loop_im         # branch on x == x_res
    li s6, 0                        # c = 0
    mov.s $f10, $f2                 # zr = cr
    mov.s $f11, $f1                 # zi = ci

loop_brightness:
    beq s6, s2, assign_brightness   # c == shades

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

    addu s6, s6, 1                  # ++c
    j loop_brightness

assign_brightness:
    # itoa(c)
    move a0, s6
    la t9, itoa
    jal ra, t9                      # call itoa
    addu t0, s7, v1                 # Suma auxiliar de la cantidad de bytes totales
    sw v0, 16($fp)                  # Se guarda la dirección de memoria del resultado de itoa
    sw v1, 20($fp)

    li t1, BUF_SZ
    bgt t0, t1, empty_buffer        # Si la cantidad de bytes supera el tamaño del buffer

label1:
    lw a0, 16($fp)                  # a0 <- Comienzo del primer caracter en el bufferAux (direccion de memoria)
    lw a1, 20($fp)                  # a1 <- Cantidad de bytes a escribir
    move a2, s7                     # a2 <- Offset a partir del cual tiene que escribir en el buffer
    la t9, writeBuffer
    jal ra, t9                      # call writeBuffer

    addu s7, s7, a1                 # Se actualiza la cantidad de bytes en el buffer

    li t4, 10					    # t4 <- "\n" ascci 10
    sb t4, buffer(s7)               # Se guarda el enter en el buffer
    addu s7, s7, 1                  # Se actualiza la cantidad de bytes ocupados

    j end_loop_re

end_loop_re:
    addu s4, s4, 1          # x++
    add.s $f2, $f2, $f6     # cr += d_re
    j loop_re

end_loop_im:
    addu s5, s5, 1          # y++
    sub.s $f1, $f1, $f7     # ci -= d_im
    j loop_im

empty_buffer:
    move a0, s3             # a0 <- fd
    la a1, buffer           # a1 <- buffer
    move a2, s7             # a2 <- len(text)

    li v0, SYS_write
    syscall

    bne a3, zero, return_error 	# Se verifica si hubo un error de escritura

    move s7, $0             	# La cantidad de bytes ocupados es 0
    j label1

return:
    # Se escribe lo que haya quedado en el buffer
    move a0, s3      # a0 <- fd
    la a1, buffer    # a1 <- buffer
    move a2, s7      # a2 <- len(text)

    li v0, SYS_write
    syscall

    bne a3, zero, return_error 	# Se verifica si hubo un error de escritura

    lw s0, 24($fp)
    lw s1, 28($fp)
    lw s2, 32($fp)
    lw s3, 36($fp)
    lw s4, 40($fp)
    lw s5, 44($fp)
    lw s6, 48($fp)
    lw s7, 52($fp)

    lw a0, 72(sp)

    lw gp, 56(sp)
    lw $fp, 60(sp)
    lw ra, 64(sp)
    addu sp, sp, 72  # Se destruye stack frame
    move v0, $0
    jr ra

return_error:
    # Se escribe el mensaje de error
    li a0, 2      	    # a0 <- 2 (stderr)
    la a1, error_message    # a1 <- error_message
    li a2, 11      	    # a2 <- 11 bytes

    li v0, SYS_write
    syscall

    lw s0, 24($fp)
    lw s1, 28($fp)
    lw s2, 32($fp)
    lw s3, 36($fp)
    lw s4, 40($fp)
    lw s5, 44($fp)
    lw s6, 48($fp)
    lw s7, 52($fp)

    lw a0, 72(sp)

    lw gp, 56(sp)
    lw $fp, 60(sp)
    lw ra, 64(sp)
    addu sp, sp, 72  # Se destruye stack frame
    li v0, -1 	     # Devuelve un número negativo en caso de error
    jr ra

    .end mips32_plot
    .size mips32_plot,.-mips32_plot

/*
    (char* buffer, int cantBytes) itoa(unsigned int val);

    Devuelve la dirección de memoria del primer caracter en el bufferAux -> v0
    Devuelve la cantiddad de bytes ocupados para la representación en caracteres del entero (val) -> v1
*/

    .ent itoa

itoa:

    /*
        Preparacion del stack frame.
        Estado del frame:
            General Register Save Area (SRA)- Usada - 8 bytes - SP y GP. Al ser leaf no se necesita guardar RA
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
    
    # Se hace un back-up del número entero
    sw a0, 8($fp)

    li t4, 48 			# Es el número ascii del 0

    beq a0, zero, return_0	# Si el número es igual a cero

    li t5, 3 			# (bufferAux-1) es el índice del primer caracter del número

for_itoa:
    beq a0, zero, end_for 	# Condición de corte (val == 0)
    remu t6, a0, 10 		# t6 <- val % 10
    addu t6, t6, t4 		# t6 <- t6 + 48 (Se calcula en base al ascii del cero qué número ascii corresponde)
    sb t6, bufferAux(t5)

    subu t5, t5, 1
    divu a0, a0, 10 		# val <- val / 10

    j for_itoa

end_for:
    addu t5, t5, 1 		# Se le suma 1 porque en la última iteración se le restó 1
    la v0, bufferAux(t5)
    li t0, BUF_SZ_AUX
    subu v1, t0, t5
    j return_f

return_0:
    sb t4, bufferAux($0)
    la v0, bufferAux
    li v1, 1

return_f:
    lw a0, 8(sp)
    lw gp, 0(sp)
    lw  $fp, 4(sp)
    addu sp, sp, 8          # Se destruye stack frame
    jr ra

    .end itoa
    .size itoa,.-itoa

/*
    void writeBuffer(char* buffer, int cantBytes, int offset)
*/

    .ent writeBuffer

writeBuffer:

    /*
        Preparacion del stack frame.
        Estado del frame:
            General Register Save Area (SRA)- Usada - 8 bytes - SP y GP. Al ser leaf no se necesita guardar RA
            Float Regs Area (FRA) - No usada - 0 bytes - No guardamos variables flotantes locales
            Local and Temporary Area (LTA) - Usada  - 0 bytes 
            Arg Building Area (ABA) - No usada - 0 bytes - No se llama a ninguna otra funcion
    */

                        # debugging info: descripcion del stack frame
    .frame  $fp, 8, ra  # $fp: registro usado como frame pointer
                        # 8: tamaño del stack frame
                        # ra: registro que almacena el return address

    .set    noreorder   # apaga reordenamiento de instrucciones
    .cpload t9          # directiva usada para codigo PIC
    .set    reorder     # enciende reordenamiento de instrucciones

                        # creo stack frame
    subu sp, sp, 8      # 2 (SRA) + 0 (LTA) + 0 (ABA)

    # El gp y FP van en las posiciones mas altas del stack frame
    sw gp, 0(sp)
    sw $fp, 4(sp)
    
    # A partir de ahora se usa directamente el fp como sp
    move $fp,sp
    
    # Se hace un back-up del char*, de la cantidad de bytes y del offset
    sw a0, 8($fp)
    sw a1, 12($fp)
    sw a2, 16($fp)

    move t0, $0

write:
    beq t0, a1, return_w    # Condición de corte (i == BUF_SZ_AUX)
    addu t1, a0, t0
    lb t6, 0(t1)            # t6 <- bufferAux[t1]
    sb t6, buffer(a2)       # buffer[offset] <- t6

    addu a2, a2, 1          # offset++
    addu t0, t0, 1          # i++

    j write

return_w:
    lw a0, 8(sp)
    lw a1, 12(sp) 
    lw gp, 0(sp)
    lw  $fp, 4(sp)
    addu sp, sp, 8          # Se destruye stack frame
    jr ra

    .end writeBuffer
    .size writeBuffer,.-writeBuffer

    .data
    .align 2 		    # alineacion 2^2
buffer: .space BUF_SZ
    .align 2
bufferAux: .space BUF_SZ_AUX
    .align 2
header: .asciiz "P2  "
    .align 2
sep: .asciiz " "
    .align 2
error_message: .asciiz "i/o error\n"

