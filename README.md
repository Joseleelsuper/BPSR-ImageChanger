# BPSR-ImageChanger

Script de PowerShell que te permite cambiar la imagen de cartelera y perfil en BPSR.

## Uso

> [!Note]
> Necesitas tener instalado el juego a través de Steam.

1. [Descarga](https://github.com/Joseleelsuper/BPSR-ImageChanger/archive/refs/heads/main.zip) el repositorio.

2. Accede a los ficheros [PKGcontrolV6RC32Lite.url](PKGcontrolV6RC32Lite.url) y [WindowsResizer](WindowsResizer.url) y descargalos. Ponlos en la misma carpeta.

3. Añade la imagen que deseas usar en la carpeta raíz. Asegúrate de que la imagen tenga el mismo nombre que la imagen original que deseas reemplazar.

4. Ejecuta el script de PowerShell con privilegios de administrador y **con el juego cerrado**:

```ps1
powerShell -NoProfile -ExecutionPolicy Bypass -File ".\BPSR-ImageChanger.ps1"
```

5. Sigue las instrucciones hasta que el script haya terminado de ejecutarse.

