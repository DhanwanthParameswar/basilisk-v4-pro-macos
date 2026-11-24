# Basilisk V4 Pro artwork (extracted from Razer Synapse)

Source: Synapse's per-device web bundle for PID 226, pulled from the Synapse Service Worker cache.
Both files are **pure vector SVG** (no embedded bitmaps), top-down view, `viewBox="0 0 200 320"`.

| File | Synapse URL | What it is |
|---|---|---|
| `basilisk_v4_pro_product.svg` | `products/226/ui/static/media/prd.29d71892.svg` | Clean product drawing (used on the Customize/buttons page). 36 paths + 80 polygons + 14 rects, single `#Product` group. |
| `basilisk_v4_pro_lighting.svg` | `products/226/mw/lighting-svgs/226_0_0.svg` | Same drawing **with addressable lighting layers** (used on the Lighting page). Name = `<PID>_<edition>_<variant>`; `0` = black edition (White Edition would be `226_128_0`, not cached). |

## Layer structure of the lighting SVG (drive this from the app)
Root attr: `data-selection-group-order="scrollWheel,logo,underglow"`

| Group id | Contents | Maps to Chroma region |
|---|---|---|
| `Product` | mouse body: fill `#111111`, outlines `#474747`, details `#5D5D5D` | — |
| `Top_LED` | scroll-wheel LED + Razer logo LED (fill `#FF00FF` = placeholder) | `0x01` wheel, `0x04` logo |
| `Bottom_LED` | underglow, **5 sub-shapes `_x31_`…`_x35_`** = LEDs 1–5 | `0x0a` side strip / underglow (5 LEDs) |
| `Top_Selection`, `Bottom_Selection` | Razer-green `#44D62C` outlines for hover/selection hit areas | — |
| `Buttons` *(added by Basilisk)* | One invisible closed outline per button face, `data-button` = firmware button id. Razer's asset has no button shapes, and its seam lines are split into segments with hairline gaps, so these were extracted by flood-filling each face in a high-res render and vectorising it. The Hypershift trigger (57) isn't visible from above. | — |

Placeholder colours to replace at runtime: `#FF00FF` (LED fill, `.st5`; `.st2` is a 40%-opacity glow),
`#00EDFF` (`.st4`, 40% cyan thick stroke — hover glow), `#44D62C` (selection stroke).
To show the mouse's real colours, recolour each LED shape with the RGB the firmware reports (`0f:82` per region)
or the frame being sent (`0f:03`).

## Licensing note
This is Razer's artwork. Fine for a personal tool for your own mouse; don't ship it in something you distribute publicly.
