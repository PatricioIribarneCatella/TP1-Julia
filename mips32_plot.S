#include <mips/regdef.h>
#include <sys/syscall.h>

#ifndef BUF_SZ 8192
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
        Preparar el stack frame aca
    */

    lw f0, UL_re(a0)
    lw f1, UL_im(a0)
    lw f2, d_re(a0)
    lw f3, d_im(a0)
    lw f4, cp_re(a0)
    lw f5, cp_im(a0)

    lw t0, x_res(a0)
    lw t1, y_res(a0)
    lw t2, shades(a0)
    lw t3, fd(a0)

    sub.s f0, f0, f2    # Porque en loop_re se suma antes de entrar a la subrutina, por comodidad

    li t4, 0    # y = 0

loop_im: # for (y = 0, ci = parms->UL_im; y < parms->y_res; ++y, ci -= parms->d_im) {
    blt t1, t4, exit    # brach on y > y_res
    addiu t4, t4, 1     # ++y
    sub.s f1, f1, f3    # UL_im - dy (son floats)
    li t5, 0            # x = 0 para cada llamada a loop_re
    j loop_re

loop_re:
    blt t0, t5, loop_im # branch on x > x_res
    addiu t5, t5, 1     # ++x
    add.s f0, f0, f2    # UL_re + dx
    li t6, 0            # c = 0 para cada llamada a loop_brightness
    j loop_brightness

loop_brightness:
    blt t2, t6, assign_brightness

    mv.s f6, f0
    mul.s f6, f6, f6    # zr^2
    mv.s f7, f1
    mul.s f7, f7, f7    # zi^2
    add.s f8, f6, f7    # zr^2 + zi^2

    /* a traducir
        if ((absz = zr*zr + zi*zi) > 4.0f)
            break;
        sr = zr * zr - zi * zi + cpr;
        si = 2 * zr * zi + cpi;
        zr = sr;
        zi = si;
    */

    addiu t6, t6, 1     # ++c
    j loop_brightness

assign_brightness:
    /*
        Aca hay que poner el valor de c alcanzado en el buffer
    */
    j loop_re

.end mips32_plot