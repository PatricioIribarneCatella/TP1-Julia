#include <mips/regdef.h>
#include <sys/syscall.h>

#ifndef BUF_SZ
#define BUF_SZ 8192
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
        int mips32_plot(param_t *parms)

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
.align 2
.globl mips32_plot
.ent mips32_plot

mips32_plot:
    /*
        Preparacion del stack frame.
        Estado del frame:
            General Register Save Area (SRA)- Usada - 8 bytes - SP y GP. Al ser leaf no necesito guardar RA
            Float Regs Area - No usada - 0 bytes - No guardamos variables flotantes locales
            Local Area - No usada  - 4 bytes - s8 contiene el tamanio del buffer
            Arg Building Area - No usada - 0 bytes - No  se llama a ninguna otra funcion
    */

                        # debugging info: descripcion del stack frame
    .frame  $fp, 12, ra # $fp: registro usado como frame pointer
                        # 12: tamaño del stack frame
                        # ra: registro que almacena el return address

                     # creo stack frame
    subu sp, sp, 12  # 2 (SRA) + 1 (LTA) + 0 (ABA)

                # El gp y FP van en las posiciones mas altas del stack frame
    sw gp, 4(sp)
    sw $fp, 8(sp)
                # A partir de ahora se usa directamente el fp como sp
    move $fp,sp

                # s8 lo voy a usar para poner el espacio usado en mi buffer, asi que lo guardo para restaurarlo al final
    sw s8, 0($fp)
                # Se hace un back-up de la estructura recibida por parámetro en la ABA de la funcion llamante
    sw a0, 12($fp)

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

    mov.s $f4, $f16     # f4 <- zr * zr - zi * zi + cpr
    mov.s $f5, $f17     # f5 <- 2 * zr * zi + cpi

    addiu t6, t6, 1     # ++c
    j loop_brightness

assign_brightness:
    # Hago de cuenta que tengo el valor de brigthness en el resgistro t8
    sw t8, buffer(s8)        # Guardo r0 en la posicion del buffer + bytes ocupados del buffer. Luego sera algo que contenga el brillo
    addu s8, s8, 4      # Actualizo la cantidad de bytes ocupados 

    j loop_re

return:
    lw s8, 0(sp) 
    lw gp, 4(sp)
    lw  $fp, 8(sp)
    addu sp, sp, 12  # destruyo stack frame
    jr ra            # vuelvo a funcion llamante

.end mips32_plot

.data
.align 2
buffer: .space 4194304 #reservo mucho para el buffer, esto esta mal