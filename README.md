# BPSR-ImageChanger

Script de PowerShell que te permite cambiar la imagen de cartelera y perfil en BPSR.

## Uso

> [!Note]
> Necesitas tener instalado el juego a través de Steam.

1. [Descarga](https://github.com/Joseleelsuper/BPSR-ImageChanger/releases/latest) el repositorio.

2. Accede a los ficheros [PKGcontrolV6RC32Lite.url](https://drive.google.com/file/d/1_bkOGwe-GLrgcwDAHBCt8A1Nw_HX5qPy/view?usp=sharing) y [WindowsResizer](https://github.com/imkuang/WindowResizer/releases/latest) y descargalos. Ponlos en la misma carpeta.

3. Añade el PNG que deseas usar. Debe medir 1500×2500 para Card/Dungeon o 1500×1500 para Portrait/Chat; puedes elegir cualquier nombre en el asistente.

4. Ejecuta el script de PowerShell con privilegios de administrador y **con el juego cerrado**:

```ps1
powerShell -NoProfile -ExecutionPolicy Bypass -File ".\BPSR-ImageChanger.ps1"
```

5. Sigue las instrucciones hasta que el script haya terminado de ejecutarse.

Si hay varias instalaciones de Steam o la ruta es personalizada, usa `-GamePath` con la carpeta que contiene `BPSR_STEAM_Data`.

> [!Important]
> Tras guardar y confirmar la foto, cierra BPSR y escribe `RESTAURAR` para volver al paquete original. Si pulsas Enter, el paquete modificado permanece instalado y puedes abrir el asistente más tarde para restaurarlo.

## Temporada actual

En el build 25820058, la textura `personalzone_player_bg_2` está en `m98.pkg`. El script usa ese paquete por defecto y comprueba que la clave exista antes de preparar las copias. Si una actualización vuelve a moverla, localiza el paquete con la opción 1 de PKGcontrol y pasa `-PackageName mXX.pkg` a todas las acciones. No reutilices un `*_mod.pkg` de otra versión.
