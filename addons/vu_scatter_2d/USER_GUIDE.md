# Vu Scatter 2D – User Guide

Vu Scatter 2D lets you paint trees, rocks, grass, crates and any other props onto 2D levels with a brush, right in the Godot editor. You choose what to paint, how dense it is and how much each prop varies, then drag across your level. Every stroke can be undone in one step.

Works with Godot **4.4, 4.5, 4.6 and 4.7**. Pure GDScript, so it works in the standard and .NET builds.

Open this guide any time with the **?** button at the top of the Vu Scatter panel. It's also in the plugin folder as `USER_GUIDE.pdf` and `USER_GUIDE.html`.

---

## Quick start: your first scatter in 1 minute

**What it does:** you pick some images or scenes (trees, rocks, grass…), then drag your mouse over the level and copies of them appear. Each copy gets a slightly different size and angle, so it looks natural.

1. **Turn it on.** Project > Project Settings > Plugins > tick **Vu Scatter 2D**. The **Vu Scatter** panel opens on the right with a short **Getting started** list that ticks itself off as you go.
2. **Click "+ Add scatter layer".** This adds the node your props go into. In an empty project (no scene open) it also makes a 2D scene for you, saved as `level.tscn`.
3. **Click "Use example props"** to try it with a few trees, bushes and rocks that come with the plugin, or drag your own images (`.png`, `.svg`), scenes (`.tscn`) or a whole folder from the **FileSystem** dock into the box. Brush size and Gap adjust to the size of your art. Paint turns on by itself, and the top toolbar shows what you're painting next to **Painting:**.
4. **Drag over your level.** The green circle is your brush.
5. **Fix mistakes.** **Shift** + drag erases. **Ctrl+Z** undoes a whole stroke.

That's it. Everything else is optional fine-tuning.

> **Clicking selects things instead of painting?** Select your scatter layer in the Scene dock and click **Paint** in the top toolbar. The hint at the bottom of the 2D view always says what to do next.

> **Godot 4.7:** Godot has its own Scene Paint tool (shortcut B). Vu Scatter turns it off when you start painting, so the two don't fight.

## Place a straight fence (Pro)

1. Select your scatter layer and put only your fence image in **What to paint** (plus its side piece, if you have one, see below).
2. Press **U** (or click **Shape** in the top toolbar, **Line** in the list next to it).
3. Drag from one end to the other and let go. The line snaps straight across or straight down, and the pieces sit end to end so they join up. Hold **Shift** for a sloped fence.

A fence running top to bottom: in a top-down game, add a **side piece** to the layer, an image of the fence drawn running up the screen (at least 1.5 times taller than wide, like `demo/art/tour/fence_side.svg`). Line and Rectangle then use it for the up-down runs and the normal fence piece for the rest, lined up so the corners meet. Without a side piece, long props (art at least 1.5 times wider than tall) turn with the line by themselves, which suits side-on games. Long props are never placed upside down, and if your fence art has a post at one end only, a row that stops on bare rails gets an end post. To turn every prop, also round ones, turn on **Turn props along the shape** (panel > **Shape options**). For a fenced yard, pick **Rectangle** in the list next to **Shape** (or press **Shift+U**) and drag corner to corner. The `demo/fences/fences.tscn` demo shows all three with guide lines to drag along.

## 1. Install

- **From the zip (itch.io, Fab):**
  1. In Godot, right-click `res://` in the **FileSystem** dock (bottom left) and pick **Open in File Manager**. This opens your project folder.
  2. Unzip the download into that folder (Windows: right-click the zip > **Extract All…**, pick the project folder, **Extract**). The folder now has an `addons` folder and a `demo` folder. If you already have an `addons` folder, the plugin goes in next to what's there.
  3. Go back to Godot and wait a few seconds while it loads the new files. Then turn the plugin on as in step 1 of the Quick start.
- **Lite from the Godot Asset Library:** in Godot, open the **AssetLib** tab at the top, search for **Vu Scatter 2D Lite**, click **Download**, then **Install**. Then turn the plugin on as in step 1 of the Quick start.

## How do I…

| I want to… | Do this |
| --- | --- |
| Paint my own art | Drag images, scenes or a whole folder from the FileSystem dock onto the **What to paint** box. |
| Have more trees than rocks (Pro) | Set the number next to each prop: trees 4, rocks 1. |
| Paint trees and grass separately | **+ New layer** at the top of the panel. See *Use two layers* in section 6. |
| Erase just the grass, keep the trees | Untick the trees, tick **Erase only the props listed above** (Erasing & more), then Shift + drag. |
| Make a straight fence or wall (Pro) | Press **U** and drag. See *Place a straight fence* above. |
| Fill an odd-shaped area (Pro) | Press **L** and draw around it. |
| Only put props on grass tiles (Pro) | Placement > **Pick tile type…**, then click a grass tile. |
| Make a symmetrical garden (Pro) | **Mirror painting** > Mirror: Left ↔ right. |
| Give one prop its own size, tilt or (Pro) color | Click its name, then in the Inspector open **Per-prop overrides** and turn on **Override Settings**. |
| Use the same props in another scene (Pro) | **Presets** > **Save…**, then **Load…** on the other layer. |
| Stop the brush changing a finished area | **Lock props** (Erasing & more). |
| Make props block the player | Use a scene with a StaticBody2D and CollisionShape2D as the prop. See section 6. |
| Get my normal mouse back | Press **Esc**, or click the pressed toolbar button again. |

## 2. Try the demos

**Pro: start with the feature tour.** Open `demo/tour/tour.tscn`. Each row shows one feature: a finished **Example** on the left and an empty **Try it here** area on the right with the props already set up. Select the row's layer under **Try** in the Scene dock and follow the steps written above it.

Open `demo/forest/forest.tscn`. The left side is empty and the right side is already painted. In the Scene dock, select **Empty > Trees**, click **Paint** and drag on the left side. Then select **Empty > GroundCover** and paint grass. Press F6 to run the scene.

## 3. Controls

| Input | What it does |
| --- | --- |
| B | Paint |
| E | Erase (while a Vu Scatter tool is on; otherwise E stays Godot's rotate tool) |
| U (Pro) | Shape tool, with the shape picked next to it |
| Shift+U (Pro) | Next shape (line, rectangle, circle, spiral, grid) |
| L (Pro) | Fill area (draw around an area to fill it) |
| P | Place one |
| Shift+B (Pro) | Shuffle |
| Left drag | Paint, erase or shuffle (depends on the button pressed in the top toolbar), or draw a shape |
| Shift + left drag | Erase while painting |
| Left click | Place exactly one prop (**Place one**) |
| `[` and `]` | Smaller / bigger brush |
| Shift while drawing a shape | Line: any angle. Rectangle / Grid: a square |
| Esc | Cancel the shape you're drawing; press again to stop painting (back to normal selecting) |
| Mouse wheel, middle drag | Zoom and pan as usual |
| Ctrl+Z / Ctrl+Shift+Z | Undo / redo one stroke |

On macOS, use Cmd instead of Ctrl (Cmd+Z undoes).

The B, E, P, U and L keys only work while a scatter layer is selected, so they never get in the way elsewhere. Hover a toolbar button to see its shortcut.

The brush circle is green for Paint, red for Erase and blue for Shuffle. The top toolbar shows the brush size, and the props being painted. The hint at the bottom of the 2D view says what to do next.

## 4. The toolbar buttons

**Paint** places props inside the brush until the area is full (see **Amount**). Dragging over the same spot again tops it up but doesn't pile props on top of each other, so you can scrub back and forth freely.

**Erase** removes painted props under the brush. It never touches nodes you placed by hand, only props the brush made.

**Place one** (P) places exactly one prop where you click. Good for hero props, torches or the odd sign.

**Shape** (Pro) places props neatly in a shape. Pick the shape in the list next to the button:

| Shape | How to draw | Good for |
| --- | --- | --- |
| Line | Drag from one end to the other. Snaps to straight across, straight down or 45° (hold Shift for any angle). | Fences, walls, a row of torches |
| Rectangle | Drag from one corner to the other. | A fenced yard, a garden border |
| Circle | Drag from the middle outward. | A stone circle, a ring of trees |
| Spiral | Drag from the middle outward. | Paths, flower beds, magic circles |
| Grid (rows) | Drag from one corner to the other. | An orchard, a crop field, a graveyard |
| Fill area | Draw around the area and let go. Props fill the inside, randomly, like the brush. | A meadow, a patch of flowers in an odd shape |

While you drag, you see the outline and a dot where every prop will go, plus the count. Red dots won't be placed (see **Only on my TileMap**). Let go to place them; one Ctrl+Z undoes the whole shape. Props in a shape all get the same size and no tilt, so rows look tidy. The **Shape options** section in the panel opens by itself and has a few extra options.

**Shuffle** (Pro, Shift+B) keeps props where they are but gives them a new random size, tilt, mirror and color. Use it when a patch looks too regular.

## 5. The Vu Scatter panel

Only **What to paint**, **Brush** and **Variety** are open by default. The rest is folded away; click a heading to open it. Hover any setting for a short explanation.

### What to paint
- Drag scenes, images or a folder of them from the FileSystem dock onto the panel, or click **Use example props**. The first time, **Gap between props** and **Brush size** grow to fit big art so it doesn't pile up (Ctrl+Z undoes that too).
- The **tick** turns a prop on or off without removing it.
- The **number** (Pro) is how often the prop appears compared with the others. Trees 4 and rocks 1 means about four trees for every rock.
- The **bin** removes the prop.
- **Click a prop's name** to open it in the Inspector (select the scatter layer in the Scene dock to come back). Open **Per-prop overrides** there and turn on **Override Settings** to give that prop its own size and tilt (Pro: also mirror, color and draw order; for example, rocks that never tilt).

Lite holds up to 3 props and picks them evenly.

### Brush
| Setting | Meaning |
| --- | --- |
| Brush size | Brush radius in pixels. Also `[` and `]`. |
| Amount | How many props per 100 × 100 pixels. 1 is sparse, 5 is lush grass. |
| Gap between props | No two props get closer than this. 0 lets them overlap. |

### Variety
| Setting | Meaning |
| --- | --- |
| Smallest / Biggest size | Each prop gets a random size in this range (1 = original size). |
| Tilt (± degrees) | Random rotation either way. Keep it 0 for trees and side-view props; use it for rocks, leaves and debris. |
| Mirror left/right, up/down (Pro) | Chance to mirror a prop. 0.5 left/right is the cheapest way to make a forest look less repetitive. |
| Color (Pro) | Color multiplied onto every prop. |
| Color variation (Pro) | Varies brightness and hue a little per prop. 0.2–0.3 looks natural. |

### Placement (Pro, folded)
| Setting | Meaning |
| --- | --- |
| Images stand on their bottom edge | Each image stands where you click (its base), so rows line up and Y-sort draws the nearer prop in front. Turns on by itself when you add your first images; turn it off if you want props centred on the cursor. |
| Snap to grid | One prop per grid cell, centred. |
| Use my TileMap's grid | Takes the grid size from a TileMapLayer next to the layer, otherwise the first one in the scene. |
| Grid width / height | The grid size when not using the TileMap's. |
| Draw order | Z index of painted props. Higher draws on top. |
| Only on my TileMap | Props only land on tiles of the TileMapLayer next to the layer (otherwise the first one in the scene). Works for the brush, Place one and shapes. |
| Pick tile type… | Then click a tile in the level: props only land on that kind of tile (e.g. grass, not water). **Any tile** undoes the choice. The panel shows a picture of the tile props land on. |

### Shape options (Pro, folded; opens when you use Shape)
| Setting | Meaning |
| --- | --- |
| Number of props | 0 = as many as fit end to end. Any other number spreads exactly that many evenly along the shape. |
| Turn props along the shape | Each prop turns to follow the line or curve, like fence posts around a corner. Long props like fences turn on Line and Rectangle even when this is off, unless the layer has a side piece. |
| Wobble | Moves each prop a little off the line so it looks hand-placed. 0 is perfectly neat. |

### Mirror painting (Pro, folded)
| Setting | Meaning |
| --- | --- |
| Mirror | Off, Left ↔ right, Up ↕ down, or Both. Everything you paint, place or draw also appears mirrored on the other side of the yellow dashed line. Erasing is mirrored too. |
| Put mirror line in the middle of the view | Moves the line to where you're looking. The first time you turn Mirror on, this happens by itself. |
| Mirror line X / Y | Exact position of the line. |

### Erasing & more (folded)
| Setting | Meaning |
| --- | --- |
| Erase strength | 1 removes everything under the brush; 0.3 thins it out. |
| Erase only the props listed above | Removes only props that are ticked in the list (untick the trees to erase just the grass). |
| Random seed | 0 gives new randomness every stroke. Any other number repeats the same result. |
| Clear layer | Removes every painted prop on this layer (Ctrl+Z brings them back). |
| Lock props | Turns the painted props into normal nodes: Erase, Shuffle and Clear layer leave them alone from then on. Use it when a patch is finished. Ctrl+Z undoes it. |

The panel also shows how many props are painted on the selected layer.

### Presets (Pro, folded)
The list of props plus all settings is saved inside your scene. **Save…** stores it as a `.tres` preset to reuse on other layers and scenes, **Load…** applies one, **Start over** clears the list and resets every setting. Shape and mirror settings are saved in presets too.

Layers that use the same preset share it: changing a setting on one of them changes it on all of them (and in the `.tres` file when you save). To change one layer on its own, select it, then in the Inspector click the arrow next to **Palette** and choose **Make Unique**.

## 6. Making it look good in 2D

- **Y-sort:** a new ScatterLayer2D has **Y Sort Enabled** turned on, so props lower on screen draw in front. For images, turn on **Images stand on their bottom edge** (Pro). For scenes, put the scene's origin at the prop's base, as you would for any Y-sorted sprite.
- **Use two layers:** one for big props (trees, bushes) with a bigger gap, and one for ground cover (grass, flowers) with a high amount and small gap. With a layer selected, click **+ New layer** at the top of the panel: the new layer draws behind the selected one, so paint trees first, then grass. Drag layers in the Scene dock to change the order. The Forest demo does this.
- **Background and foreground (Pro):** in a side-scroller, use separate layers with different **Draw order** and **Color**. Use a cooler, lighter color and lower draw order for the background. See the Side-scroller demo.
- **Collisions:** put a StaticBody2D/CollisionShape2D inside the prop's scene. Painted scene props are normal instances, so collisions, scripts and animations all work.

## 7. What gets saved

- Painted props are ordinary child nodes of the ScatterLayer2D. Scene props stay linked instances, so editing `tree.tscn` updates every painted tree.
- Each painted prop carries a small `vu_scatter` metadata entry (the source file path). That's how Erase and Shuffle know which nodes the brush made.
- Nothing from the plugin runs in your game. You can even disable the plugin and the scene still loads and plays.
- You can move, delete or edit painted props by hand like any other node.

## 8. Demo scenes

Open them from `demo/`. Each one shows an **Empty** area on the left (or top) with the same props ready to go, next to a **Painted** version.

| Demo | Shows |
| --- | --- |
| `demo/forest/forest.tscn` | Two layers (trees + ground cover), weighted props, bottom-edge anchor, mirror, color variation, Y-sort, scene props with collisions. |
| `demo/side_scroller/side_scroller.tscn` (Pro) | Painting along a ground line with a small brush, background layer with tint and lower z-index. |
| `demo/town/town.tscn` (Pro) | Grid snap using the TileSet cell size, weighted crates/barrels/pots, torches placed with Place one. |
| `demo/fences/fences.tscn` (Pro) | How to place a fence: across, top to bottom and a fenced yard, with guide lines showing where to drag. |
| `demo/tour/tour.tscn` (Pro) | One row per feature: fences (Line), a yard (Rectangle), a stone circle, a hedge spiral, an orchard (Grid), a meadow (Fill area), plants only on grass tiles, and a mirrored garden. |

To try one: open it, select a layer under **Empty** (e.g. `Empty/Trees`), click **Paint** and drag. Run the scene (F6) to see it in game.

## 9. Lite vs Pro

| | Lite (free) | Pro |
| --- | --- | --- |
| Paint, Erase, Place one, undo | ✓ | ✓ |
| Brush size, amount, gap, erase strength, erase filter, seed | ✓ | ✓ |
| Random size and tilt | ✓ | ✓ |
| Props per layer | 3, picked evenly | Unlimited, weighted |
| Random flip, color, draw order, bottom-edge anchor | – | ✓ |
| Shuffle brush, grid snap, TileMap grid | – | ✓ |
| Save / load presets | – | ✓ |
| Shape tool (line, rectangle, circle, spiral, grid, fill area) | – | ✓ |
| Mirror painting, only on my TileMap | – | ✓ |
| Clear layer, lock props | ✓ | ✓ |
| Getting started list, example props, this guide | ✓ | ✓ |
| Demo scenes | Forest | Forest, Side-scroller, Town, Feature tour, Fences |

Scenes made with Lite open unchanged in Pro. In Lite, the Forest demo looks the same, but painting more there uses the Lite rules: the first 3 props of a layer, picked evenly, with no flip or color.

## 10. Troubleshooting

**Clicking in the viewport selects things instead of painting.** Select the scatter layer in the Scene dock and make sure a toolbar button (Paint, Erase…) is pressed.

**"Pick what to paint in the Vu Scatter panel first" appears next to the cursor.** The layer has no ticked props. Click **Use example props**, drag some in, or tick their checkboxes.

**Nothing new appears when I paint over an area again.** That area has already reached the density you set. Raise **Amount** or lower **Gap between props**.

**My scene prop was skipped with a warning.** The scene's root node must be a Node2D (or something that extends it, like Sprite2D).

**Props appear behind the ground.** The ground probably has a higher z-index than the props. Give the ground a lower z-index (e.g. -10), or (Pro) raise the props' **Draw order**.

**Some dots of a shape are red.** **Only on my TileMap** is on, and those spots aren't on the right tiles. Pick a different tile type or click **Any tile**.

**Pressing B, U or L does nothing.** Select a ScatterLayer2D first, and click into the 2D view once so it has keyboard focus. U and L are Pro.

**I closed the Vu Scatter panel.** Click **Project > Tools > Show Vu Scatter panel**. Selecting a scatter layer in the Scene dock also brings it back.

## 11. Support

Questions, bugs and feature requests: contact Vu Studio through the store page you bought from. Please include your Godot version and, if you can, a small scene that shows the problem.
