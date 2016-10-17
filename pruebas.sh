#!/bin/bash

# Prueba 1: Imagen imposible (Hay cero píxeles de ancho)
./tp1 -c 0+0i -r 0x1 -o -

# Prueba 2: Archivo de salida imposible (El archivo no es válido)
./tp1 -o /tmp

# Prueba 3: Coordenadas complejas inválidas en el centro
./tp1 -c 1+3 -o -

# Prueba 4: Coordenadas complejas inválidas en el parámetro C
./tp1 -C 2+4 -o -

# Prueba 5: No se especifican las coordenadas del centro
./tp1 -c -o -

# Prueba 6: Ningún argumento ingresado
./tp1

# Prueba 7: Alto de la imagen inválido
./tp1 -H 3.0.0 -o -

# Prueba 8: Ancho de la imagen negativo
./tp1 -w -3.0

# Prueba 9: Imagen default
./tp1 -o imagenDefault.pgm

# Prueba 10: Imagen con parámetros [r: 1000x1000]
./tp1 -r 1000x1000 -o imagen1000x1000.pgm

# Prueba 11: Imagen con parámetros [r: 1000x1000, C: -0.75+0.0i, w(ancho): 3, H(alto): 3]
./tp1 -r 1000x1000 -C -0.75+0.0i -w 3.0 -H 3.0 -o imagen1.pgm

# Prueba 12: Imagen con parámetros [r: 1000x1000, C: -0.29799-0.65705i]
./tp1 -r 1000x1000 -C -0.29799-0.65705i -o imagen2.pgm

# Prueba 13: Imagen con parámetros [r: 1000x1000, C: -0.20722+0.64840i]
./tp1 -r 1000x1000 -C -0.20722+0.64840i -o imagen3.pgm

# Prueba 14: Imagen con parámetros [r: 1000x1000, C: -0.45793+0.52736i]
./tp1 -r 1000x1000 -C -0.45793+0.52736i -o imagen4.pgm

# Prueba 15: Imagen con parámetros [r: 1000x1000, C: -1.75473+0i]
./tp1 -r 1000x1000 -C -1.75473+0i -o imagen5.pgm

