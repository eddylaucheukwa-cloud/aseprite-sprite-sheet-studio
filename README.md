# Sprite Sheet Studio

An Aseprite extension for building custom sprite sheets from PNGs, with drag-and-drop arrangement, animation preview, and selective recoloring.

Use sprites from any image editor, renderer, or drawing workflow. No Blender dependency is required. Import a folder of PNGs, arrange the cells, preview an animation, adjust colors, and export a transparent sheet or editable Aseprite project.

Previously named **Blender Sheet Builder**.

## Features

- Custom sprite width, height, columns, and rows. For example, 64×64 sprites in an 8×10 grid produce a 512×640 sheet with 80 cells.
- Folder imports with natural filename sorting, including skipped frame numbers. Add more folders into available cells.
- Shift-click selection, drag-to-swap, horizontal/vertical flips, copy/paste, delete, and undo/redo.
- Centered grid preview with Fit, 150%, 200%, and 300% zoom and wheel scrolling.
- Animation preview with FPS, looping, frame scrubbing, and custom sequences such as `5-8`, `8-5`, or `5,5,6,7,8`.
- Live hue, saturation, brightness, and contrast adjustments for selected cells or the whole sheet.
- Selective recoloring with an eyedropper, similarity threshold, replacement color, HSV picker, and hex input.
- Original/adjusted frame and full-sheet comparisons. Recoloring commits only when you press Apply.
- Lossless splitting of flattened sheets into editable cell layers, including indexed and grayscale input.
- Transparent PNG export and editable `.aseprite` save. Saved projects remember their grid layout.

## Install

1. Download the `.aseprite-extension` file from [Releases](https://github.com/eddylaucheukwa-cloud/aseprite-sprite-sheet-studio/releases).
2. In Aseprite, open **Edit → Preferences → Extensions → Add Extension** and select the downloaded file.
3. Restart Aseprite.
4. Open **File → Import → Sprite Sheet Studio…**.

Tested with Aseprite **1.3.18.6-dev**. Other Aseprite versions and operating systems have not been tested. Install Aseprite separately; this repository contains the extension only.

### Upgrading from Blender Sheet Builder

Save your editable projects first. Remove or disable the old **Blender Sheet Builder** extension in Preferences, then install Sprite Sheet Studio. Existing Builder `.aseprite` projects retain their layout and remain editable. If you used the old script launcher, remove it from the scripts folder to avoid a duplicate menu entry.

### Optional script launcher

Copy [Sprite Sheet Studio.lua](scripts/Sprite%20Sheet%20Studio.lua) into the folder opened by **File → Scripts → Open Scripts Folder**, then choose **Rescan Scripts Folder**. The extension must be installed first.

### Manual installation

Create `extensions/sprite-sheet-studio` inside Aseprite's user configuration folder and copy these seven files into it: `package.json`, `main.lua`, `core.lua`, `effects.lua`, `panels.lua`, `README.md`, and `LICENSE`. Restart Aseprite.

## Quick start

1. Open Sprite Sheet Studio and choose **Sheet size…**. Enter the sprite width/height and grid columns/rows, then press **Use size**.
2. Choose **Import folder…**, select one PNG from the folder, then press **Import**. All PNGs in that folder are imported in natural filename order.
3. Arrange the cells. Use **Add folder…** for another folder, **Animate** to test playback, or **Recolor** to adjust the palette.
4. Choose **Save project…** for editable layers or **Export PNG…** for the finished sheet.

To edit a flattened PNG, open it in Aseprite, choose the matching sprite size and grid, then select **Edit open sheet**. The original is preserved and a new editable copy is created. Saved Builder projects use their own stored layout.

## Controls

| Action | Control |
| --- | --- |
| Select one cell | Click |
| Add/remove from selection | Shift + click |
| Swap two cells | Drag one onto the other |
| Undo / redo | Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z |
| Copy / paste | Ctrl+C / Ctrl+V |
| Remove selected sprites | Delete |
| Flip horizontally / vertically | H / V |
| Scroll a zoomed grid | Mouse wheel |
| Scroll sideways | Shift + mouse wheel |
| Pick a color in Recolor | I, then click a preview |
| Cancel color picking | Esc |

Keyboard editing shortcuts work while the grid has focus; color-picking shortcuts work while a recolor preview has focus. **Shortcuts** in the Arrange window shows the controls.

Cell numbers run left to right, then top to bottom. In a four-column sheet, `5-8` is the second row; in an eight-column sheet, the second row is `9-16`. These numbers refer to sheet cells, not source filenames.

## Recolor

Choose **Selection** or **Whole sheet**. The **Adjust** tab changes hue, saturation, brightness, and contrast. In **Color match**, choose **Picked color**, sample or choose the source color, and adjust **Similarity %**. Zero matches the exact RGB color; higher values include nearby colors. Enable **Replace** to choose a replacement.

Use the frame slider or **Sheet preview** to compare the result across cells. **Apply** commits one undoable change; **Close** discards pending adjustments. Transparency is preserved.

## Limits

- Up to 1024 cells, 16384 pixels per side, and 16 million sheet pixels in total.
- Imported PNGs must all match the chosen sprite width/height and use RGB/RGBA. Images are not automatically resized or cropped.
- Grid capacity may exceed the number of imported sprites; unused cells stay transparent.
- A sheet is a grid of cells in one Aseprite timeline frame. Multi-frame input documents are rejected.
- Choose layout settings before a new import or flattened-sheet split. Changing startup settings does not resize an existing saved project.
- PNG files do not store the grid settings. Save an `.aseprite` project to retain them.

## Build and tests

On Windows, run `powershell -NoProfile -File ./build.ps1`. The installable extension is written to `dist/`.

The tests generate their own images and run through Aseprite's batch interface. Replace `PATH_TO_THIS_REPOSITORY` with an absolute path:

```sh
aseprite --batch --script-param root="PATH_TO_THIS_REPOSITORY" --script tests/test-effects.lua
aseprite --batch --script-param root="PATH_TO_THIS_REPOSITORY" --script tests/test-layouts.lua
```

They cover color transformations, alpha preservation, layout validation, 80-cell and rectangular sheets, import/edit operations, save/reopen, flattening, and legacy project compatibility. Interactive UI checks are manual.

## License

[MIT](LICENSE).
