# BPSR-ImageChanger

An interactive PowerShell tool for changing player card and profile images in the Steam edition of Blue Protocol: Star Resonance.

## What it does

The wizard replaces a selected image asset in the game's package and keeps a backup so you can restore the original package later.

## Requirements

- The Steam edition of the game.
- Keep the game closed while installing or restoring a package.
- Download [PKGcontrolV6RC32Lite](https://drive.google.com/file/d/1_bkOGwe-GLrgcwDAHBCt8A1Nw_HX5qPy/view?usp=sharing) and [WindowResizer](https://github.com/imkuang/WindowResizer/releases/latest), then place both tools beside the script.
- Card and Dungeon images must be 1500x2500 pixels. Portrait and Chat images must be 1500x1500 pixels.

## Quick start

1. Download and extract the [latest release](https://github.com/Joseleelsuper/BPSR-ImageChanger/releases/latest).
2. Add the PNG image you want to use. The wizard lets you choose the image and image type.
3. Open PowerShell in the project folder and run:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\BPSR-ImageChanger.ps1"
~~~

4. Follow the wizard. Allow administrator access when Windows asks for it.
5. Keep the game closed until the package change is complete.

If the game is installed in a custom Steam library, pass **-GamePath** with the folder that contains **BPSR_STEAM_Data**.

## Restoring the original package

After reviewing the changed image, close the game and type **RESTORE** when the wizard asks whether to restore the original package. If you leave the response blank, the modified package stays installed; you can run the wizard again to restore it.

## Game updates

The script uses **m98.pkg** by default. If a game update moves the target asset, locate its package with option 1 in PKGcontrol and pass **-PackageName mXX.pkg** to each action.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).

## Support

Join the [DaoPalace Discord server](https://discord.gg/brwaAZktrn) and find Joseleelsuper.