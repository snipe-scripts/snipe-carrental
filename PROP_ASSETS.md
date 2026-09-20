# Streamed capsule props

The active vehicle capsule now consists of three independent v2 props. The original combined `snipe_capsule_platform_v1` asset is retained as a compatibility/reference asset; the client no longer spawns it.

| Active role | Model | Local bounds (min → max) | Collision |
| --- | --- | --- | --- |
| Fixed deck | `snipe_capsule_deck_v2` | (-2.38,-3.68,0) → (2.38,3.68,0.152) | Embedded Composite→GeometryBVH |
| Moving roof + four posts | `snipe_capsule_canopy_v2` | (-2.3825,-3.6825,0.13) → (2.3825,3.6825,3.411) | None; physicsDictionary=0 |
| Moving opaque wall shell | `snipe_capsule_shell_v2` | (-2.317,-3.487,0.12) → (2.317,3.487,3.27) | None; physicsDictionary=0 |

All three use the same platform ground origin and heading. The stationary deck stays at Z offset 0. Fully raised canopy/shell offsets are both 0. Fully retracted offsets are both -3.50 m; their highest vertices are then below ground (-0.089 m canopy, -0.230 m shell). The opaque four-sided shell overlaps the deck and canopy to hide the car while closed. It has no roof, allowing the canopy to remain raised when walls retract. Moving parts are deliberately collisionless so scripted movement cannot push, trap, or launch vehicles and players; stand-clear validation belongs to the rental controller.

Suggested animation poses (offsets relative to saved platform ground Z):

| Phase | Deck Z | Canopy Z | Shell Z | Vehicle |
| --- | ---: | ---: | ---: | --- |
| Idle / return ready | 0 | -3.50 | -3.50 | Absent |
| Prepare delivery | 0 | -3.50 | -3.50 | Create hidden/frozen on deck before motion |
| Rise (0–3.0 s) | 0 | -3.50 → 0 | -3.50 → 0 | Hidden/frozen |
| Open (3.2–4.4 s) | 0 | 0 | 0 → -3.50 | Reveal inside enclosure |
| Release (6.6 s) | 0 | 0 | -3.50 | Visible/unfrozen |
| Close (9.6–10.8 s) | 0 | 0 | -3.50 → 0 | Vehicle has departed, or return car is hidden |
| Retract (11–14 s) | 0 | 0 → -3.50 | 0 → -3.50 | Absent |

`RentalWorld.getAssembly(stationId)` exposes `roles.platform`, `roles.canopy`, and `roles.shell`. `RentalWorld.setCapsulePose(idOrAssembly, { canopyZ=..., shellZ=..., canopyVisible=..., shellVisible=... })` applies a pose without moving the deck or kiosk. `RentalWorld.getCapsuleModels()` exposes the model names and raised/retracted offsets. Placement previews show the coherent closed capsule with both moving offsets at zero. Rental lifecycle code must restore the authoritative pose after streaming or station refresh.

These are original static GTA V Gen8 props authored for this resource. They replace all stock rental props and runtime polygon geometry. Geometry is authored in metres, Z-up, with a ground-centered origin and the tablet screen facing local **-Y**. Runtime stations now use only the freestanding tablet; the older booth source remains documented solely for rebuild history.

| Model | Width × depth × height | Render triangles | Role |
| --- | --- | ---: | --- |
| `snipe_capsule_platform_v1` | 4.765 × 7.365 × 3.411 m | 2,248 | Deck, ramps, four posts/bollards, flat canopy and accent strips |
| `snipe_capsule_tablet_v1` | 0.680 × 0.460 × 1.890 m | 398 | Upright tablet, bezel, pedestal, weighted base |
| `snipe_capsule_booth_v1` | 1.850 × 0.700 × 2.145 m | 2,882 | Capsule shelves, glass enclosure, screen and service hatch |

The platform deck is 0.13 m above its origin, with a 0.16 m ramped perimeter and shallow surface details up to 0.147 m. Canopy clearance is approximately 3.06 m above the deck. The post centers are ±2.11 m X and ±3.04 m Y. Place `station.platform.z` at the ground surface; spawning at ground +0.25 m and applying `SetVehicleOnGroundProperly` settles the car onto the collision deck.

The fixed deck, legacy combined platform, and tablet `.ydr` files contain root-bone-owned `Composite > GeometryBVH` collision. The moving canopy and wall shell have no collision bound and a zero physics dictionary. All active `.ytyp` files link the shared `snipe_capsule_txd_v1.ytd`. No YMAP, MLO rooms, portals, external YBN, or YMF is needed for these script-spawned standalone props.

## Embedded DUI screen

Both screens use **`snipe_capsule_txd_v1` / `snipe_capsule_screen_d`**, an un-tinted `emissive.sps` material with full 0..1 UVs and exactly 2:3 aspect. The resource replaces that texture with an interactive 640×960 DUI and projects the game cursor against the model-space screen plane; no floating visual overlay is used.

| Model | Local screen center X,Y,Z | Width × height | Normal |
| --- | --- | --- | --- |
| Tablet | 0, -0.081, 1.390 | 0.56 × 0.84 m | 0, -1, 0 |
| Booth | 0.645, -0.326, 1.350 | 0.42 × 0.63 m | 0, -1, 0 |

Texture replacement is dictionary-wide, so one replacement displays the same DUI on every instance using that texture. The resource's DUI controller must choose the active station's content accordingly.

## Texture variations

Accent geometry uses `emissive_tnt.sps`, with the same `256×16`, one-level uncompressed `TINTPALETTE` pattern as `[alphabets]/glowglyphs`. The palette retains `X64 | UNK24` usage flags. Body, metal, screen and glass materials remain unchanged when calling `SetObjectTextureVariation(object, index)`.

| Index | Color | RGB |
| ---: | --- | --- |
| 0 | White | 255,255,255 |
| 1 | Red | 255,32,32 |
| 2 | Orange | 255,112,24 |
| 3 | Yellow | 255,224,32 |
| 4 | Lime | 128,255,32 |
| 5 | Green | 32,255,72 |
| 6 | Teal | 24,255,176 |
| 7 | Cyan | 24,240,255 |
| 8 | Light blue | 64,176,255 |
| 9 | Blue | 48,72,255 |
| 10 | Purple | 144,48,255 |
| 11 | Magenta | 240,32,255 |
| 12 | Pink | 255,48,144 |
| 13 | Warm white | 255,214,170 |
| 14 | Cool white | 190,220,255 |
| 15 | Dim | 8,8,12 |

`RentalWorld.colorIndex(hex)` chooses the nearest palette color from the saved strip color. Actual ambient light and DUI styling can retain the exact saved RGB. The index 15 material is dim, not a guaranteed fully-off emissive material.

## Rebuild and validation

Run `powershell -ExecutionPolicy Bypass -File tools/Build-Props.ps1` from this resource. The resource-local C# tool links the existing, unchanged PropBuilder `DrawableBuilder.cs`, `YtdBuilder.cs`, and `YtypBuilder.cs`; it references already-installed CodeWalker/Magick assemblies and requires no Lua/npm package checks. It reads the known-good tint palette from `[alphabets]/glowglyphs/stream/glowglyphs_txd_v4.ytd`.

Generated source meshes (`.obj`), source-geometry preview PNGs, texture sources, CodeWalker XML, and the full JSON validation report are in `artifacts/props-candidate`. Preview images are source-geometry renders, not FiveM screenshots.

The build refuses copying into `stream` if CodeWalker parsing/round-trip validation fails. It verifies nonempty geometry, vertex limits, shader indices, resolved sampler textures, tint metadata, root skeleton, embedded BVH collision, archetype hashes and asset/physics/texture dictionary links, screen UV corners, and YTD serialization. Copied binary hashes must match the validated candidate files.

Independent `ydr-inspect.exe` also parsed all three drawables and reported matching visual/collision bounds. `XmlCompile.exe dump-ytyp` parsed all three archetypes. The MLO-specific `verify-ytyp` command reports one base archetype and zero MLOs for each file; its MLO-count exit condition is not an applicable standalone-prop gate.

**FiveM runtime smoke testing and CodeWalker GUI visual inspection have not been run.** Before live use, verify cold streaming, drive/park on all deck edges, walk against posts and kiosk, switch all 16 tint indices, check DUI front/UV orientation, restart the resource, and inspect a fresh CitizenFX log. Structural binary validation does not establish in-game fidelity or collision behavior.
