# BPSR-ImageChanger

Script de PowerShell que te permite cambiar la imagen de cartelera y perfil en BPSR.

## Uso

> [!Note]
> Necesitas tener instalado el juego a través de Steam.

1. [Descarga](https://github.com/Joseleelsuper/BPSR-ImageChanger/archive/refs/heads/main.zip) el repositorio.

2. Accede a los ficheros [PKGcontrolV6RC32Lite.url](https://drive.google.com/file/d/1_bkOGwe-GLrgcwDAHBCt8A1Nw_HX5qPy/view?usp=sharing) y [WindowsResizer](https://github.com/imkuang/WindowResizer/releases/latest) y descargalos. Ponlos en la misma carpeta.

3. Añade la imagen que deseas usar en la carpeta raíz. Asegúrate de que la imagen tenga el mismo nombre que la imagen original que deseas reemplazar.

4. Ejecuta el script de PowerShell con privilegios de administrador y **con el juego cerrado**:

```ps1
powerShell -NoProfile -ExecutionPolicy Bypass -File ".\BPSR-ImageChanger.ps1"
```

5. Sigue las instrucciones hasta que el script haya terminado de ejecutarse.

> [!Important]
> Guarda y confirma la foto en BPSR, cierra el juego y pulsa Enter en el asistente. La restauración del fichero original es obligatoria: espera a que el asistente confirme que ha terminado.
