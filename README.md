# Image Viewer

A macOS image viewer designed for game sprite work. Browse, view, crop, and export sprite sheets from images with grid overlays, selection tools, and sequence/animation management.

## Features

### Multi-Gallery Tabs
- Tabbed sidebar with **Browser** and up to **3 independent gallery tabs**
- Each gallery has its own image set, selection, and persistence (`paths-g1.json`, `paths-g2.json`, `paths-g3.json`)
- Add/remove galleries via `+`/`-` buttons (removing a non-empty gallery shows a confirmation alert)
- Switch tabs with **Tab** key or click (Tab is suppressed when editing a text field)

### File Browser
- Navigate directories, back button, `Choose…` folder picker
- Shows image files only; sorted directories-first then alphabetically
- Multi-selection: plain click (single), **Cmd+click** (toggle), **Shift+click** (range)
- Click a file → preview in ImagePreview without adding to any gallery
- Right-click → **Add To Gallery** submenu → loads image(s) into chosen gallery
- Last browsed folder persisted in UserDefaults

### Image Preview
- Full-resolution image display with scroll/pan
- **Zoom**: `↑`/`↓` arrows, pinch gesture, `Keep Zoom` toggle preserves zoom across images
- **Selection**: drag to create a selection rectangle; resize by dragging edge handles
- **Fixed selection**: enable in toolbar, enter W×H, then click to place centered selection
- **Grid overlay**: toggle grid with configurable cell size, color, stroke width, and offset
- **Snap to grid**: selection snaps to grid lines when enabled
- **Selection actions**: copy to clipboard, add sprite to animation sequence, export as PNG (`Cmd+E`), change selection color, clear
- **Export selection**: `Cmd+E` or click the `square.and.arrow.up.fill` button → save named .png via NSSavePanel
- **Tap to cancel**: single click outside selection clears it
- Bottom info bar: filename, dimensions, file size, zoom percentage

### Sequence & Animation System
- Create named sequences with an ordered list of image frames
- Each frame stores its own per-frame **offset** (X/Y) for tiling alignment
- Set frame dimensions (W×H), background color, or transparent background
- **Preview**: render the current frame with 4-tile wrapping (shows how tiled sprite looks)
- **Playback**: play/pause, loop, ping-pong mode, configurable speed
- Preview window is resizable (drag the handle below the preview)
- Zoom in preview via pinch gesture

### Stripe Image Generation
- **Merge** all frames of a sequence into a single horizontal strip (PNG)
- Respects per-frame offsets and background color/transparency
- View the stripe in a separate window; **Copy** as PNG to clipboard (works in Discord, Slack, browsers)
- **Export** individual sequence via right-click context menu
- **Export All** button exports every sequence's strip to a chosen folder

### Convert Area to Animation (ATA)
- Select an area on an image, choose a grid size, and extract every grid cell as a separate frame
- Creates a new sequence with all extracted frames, auto-named from grid dimensions
- Saves extracted sprites to `~/Library/Application Support/ImageViewer/Sprites/`

### Drag & Drop
- Drop image files or folders onto a gallery sidebar or the main empty state to add them
- Also supported from browser add-to-gallery context menu

### Pave Compositing Board
- Floating panel (`P` key or toolbar button) with up to **5 board tabs**
- Each board has a **layers sidebar**: add/remove layers, toggle visibility with eye icons, rename (long press), reorder
- **Paste image** (`Cmd+V`) from clipboard as a floating pre-pave image with marching-ants border
- **Commit** floating image to the selected layer with `Enter`; cancel with `Escape`
- **Drag** floating image to reposition before committing
- **Marching ants animation** on both selection rect and floating image border
- **Area selection**: drag on canvas to create selection rect; `Cmd+C` copies selected area as PNG; `Cmd+D` clears; single click on empty canvas cancels
- **Grid overlay**: toggle per board with configurable W×H
- **Checkerboard background**: configured in Preferences (light/dark colors, tile size)
- **Undo/Redo**: per-board undo/redo stacks; `Cmd+Z` / `Cmd+Shift+Z`
- **Persistence**: board metadata + per-layer PNGs saved to `~/Library/Application Support/ImageViewer/Pave/board_N/`
- Window frame saved and restored across launches

### Preferences Window
- Open via `ImageViewer → Preferences…` (`Cmd+,`)
- **Checker Color** tab: `NSColorWell` squares for light square and dark square colors; tile width/height steppers (2–128px)
- **Show Pave Panel on startup** checkbox

### Persistence
- Gallery image paths saved per-gallery to `paths-g{n}.json`
- Sequences saved to `sequences.json`
- Window state (frame, visibility) persisted for the Animation panel
- Last browsed file browser folder restored on launch

---

## Keyboard Shortcuts

### Global (App Menu)

| Key | Action |
|---|---|
| `Cmd+O` | Open files/folders |
| `Cmd+V` | Paste image from clipboard |
| `Cmd+W` | Close window |
| `Cmd+A` | Select all (full image) |
| `Cmd+D` | Deselect |
| `Cmd+C` | Copy selection to clipboard (PNG) |
| `Clear Gallery` | Remove all images from active gallery (menu item) |

### Image Preview

| Key | Action |
|---|---|
| `←` `→` | Previous / next image |
| `↑` `↓` | Zoom in / out |
| `F` | Toggle fixed-size selection mode |
| `G` | Toggle grid overlay |
| `S` | Add sprite from selection to active animation sequence |
| `Cmd+E` | Export selection as .png |
| Click outside selection | Cancel selection |
| Drag | Create or resize selection |
| Shift+drag | Constrain selection axis (horizontal/vertical) |
| `Escape` | Defocus text fields |

### File Browser

| Key | Action |
|---|---|
| Click | Select single file / enter directory |
| `Cmd+click` | Toggle multi-selection |
| `Shift+click` | Range selection |
| Right-click | Context menu → Add To Gallery |

### Tab Navigation

| Key | Action |
|---|---|
| `Tab` | Cycle through tabs (Browser → Gallery1 → Gallery2 …) |

### Animation / Sequence Window

| Key | Action |
|---|---|
| `Enter` / `Space` | Toggle play / pause |
| `←` `→` | Previous / next frame in sequence |
| `↑` `↓` | Previous / next sequence |
| `J` | Nudge current frame offset left by 1px |
| `L` | Nudge current frame offset right by 1px |
| `I` | Nudge current frame offset up by 1px |
| `K` | Nudge current frame offset down by 1px |
| `Shift+J` / `Shift+L` / `Shift+I` / `Shift+K` | Nudge by 10px |
| `M` | Merge frames → open Stripe window |
| `A` (in animation window) | Close animation window, focus main window |
| `Escape` | Defocus text fields |

### Stripe Window

| Key | Action |
|---|---|
| `Escape` | Close stripe window |
| `Cmd+C` | Copy stripe image to clipboard as PNG |

### Convert Area to Animation (ATA)

| Key | Action |
|---|---|
| `Q` | Open Convert Area panel |
| `Enter` | Confirm and create sequence |
| `Escape` | Close panel |

### Pave Compositing Board

| Key | Action |
|---|---|
| `P` | Toggle Pave panel |
| `Cmd+V` | Paste image from clipboard as floating pre-pave image |
| `Enter` | Commit floating image to selected layer |
| `Escape` | Cancel floating image |
| `Cmd+C` | Copy selection area to clipboard |
| `Cmd+D` | Clear selection |
| `Cmd+Z` | Undo last layer change |
| `Cmd+Shift+Z` | Redo last undone change |
| `Click` (empty area) | Cancel selection |
| Drag (empty area) | Create selection |
| Drag (floating image) | Reposition before commit |

### Toolbar

| Control | Description |
|---|---|
| Fixed Size checkbox + W/H fields | Enable fixed-size selection; enter width/height |
| Keep Zoom checkbox | Preserve zoom level when switching images |
| Clear Gallery button | Remove all images from active gallery |
| Grid checkbox + W/H + color + stroke | Toggle grid overlay with settings |
| Offset X/Y sliders | Shift grid origin |
| Snap checkbox | Snap selection to grid lines |
| `Q` button (film stack icon) | Open Convert Area panel |
| `P` button (grid 3×3 icon) | Toggle Pave compositing board |
| Animation button (play stack icon) | Toggle Animation window |
