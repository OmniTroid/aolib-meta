# Asset formats

Schemas here describe **character asset files** (fetched by the client from
`characters/<name>/`), not wire packets. They carry no `$header` or
`x-receiver`. JSON Schema describes the *parsed* shape; the on-disk text
grammar that JSON Schema can't express (char.ini is INI, not JSON) is
specified below.

- `CharIni` — parsed `char.ini`.
- `CameraRig` — parsed `camera.json` (3D characters only).

A character is **3D** when `[options] model` names a `.pmx`, otherwise **2D**.
The emote table normalizes to one shape either way; `anim` is a sprite stem
for 2D and a base VMD stem for 3D.

## char.ini emote conventions

Historically `(a)`/`(b)` idle/talk sprites were never stored in char.ini — the
client derives `(a)<anim>` / `(b)<anim>` from the emote's `anim` at runtime. 3D
has no `(a)`/`(b)` split (idle and talking share one mouth-free base VMD; the
mouth is morph-driven), so the file format is unchanged by mode; only the
client's interpretation of `anim` differs.

Two emote encodings are supported. A parser MUST prefer blocks and fall back to
the legacy banks, emitting the same normalized `Emote[]` for both.

### `[emote <name>]` blocks (preferred)

Each `[emote <name>]` section is an emote. `[emotions]` optionally lists them in
button order, one `N = <name>` per block:

```ini
[options]
model = model.pmx        ; present => 3D character

[emotions]
number = 2
1 = objection
2 = think

[emote objection]
anim      = objection.gif ; animation file, extension REQUIRED (.gif/.webp/.png 2D, .vmd 3D)
preanim   = point.gif     ; animation file with extension, or omit / `-` for none
sound     = objection.opus ; optional; file with extension (.opus/.wav/.ogg)
sounddelayms = 480        ; optional, milliseconds
modifier  = zoom          ; number or EmoteModifier name; 3D ignores it (see camera.json)
deskmod   = shown         ; optional; number or DeskModifier name

[emote think]
anim = think_loop.gif
```

The **block name** (`objection`, `think`) is the emote's `key`: the stable
identity shared by the button and `camera.json`. It is independent of button
order, so reordering `[emotions]` never shifts anything. `[emotions]` itself is
optional: when it is absent (or lists no blocks) every `[emote <name>]` block is
an emote, in the order it appears in the file; when present it selects and
orders the blocks, and a block it does not list is not shown as a button. Block
field names are
the lowercased `Emote` field names: `name` (display label; defaults to the
block name), `anim`, `preanim` (`-`/absent → null), `sound`, `sounddelayms`
(milliseconds), `deskmod`, and `modifier`. Unlike the legacy stems, a block's
file references **must carry the file extension** — no extension guessing:
`anim`/`preanim` (`.gif`/`.webp`/`.png` for 2D, `.vmd` for 3D) and `sound`
(`.opus`/`.wav`/`.ogg`). `modifier` and `deskmod` each
accept either a number or the matching enum name, case-insensitive:
EmoteModifier for `modifier` (`no_preanim` 0,
`preanim` 1, `preanim_and_objection` 2, `zoom` 5, `objection_zoom` 6) and
DeskModifier for `deskmod` (`hidden` 0, `shown` 1, `hide_during_preanim` 2,
`show_during_preanim` 3, `hide_and_center_during_preanim` 4,
`show_during_preanim_then_center` 5).

This encoding is valid for 2D and 3D. New characters (and tools) should emit it.

### Legacy banks (fallback)

Existing characters encode emotes as `#`-delimited records across parallel
sections indexed by the same id:

```ini
[emotions]
number = 2
1 = normal#-#normal#1
2 = point#point#point#5

[soundn]
1 = 0
2 = shocked

[soundt]
2 = 8
```

`N = desc#preanim#anim#modifier#deskMod`, zipped with `[soundn]` (sound) and
`[soundt]` (sound delay) by id. `[soundt]` is in **ticks** — one tick is 60 ms,
the message text update interval — and is normalized to milliseconds in
`Emote.soundDelayMs` (ticks × 60). When no `[emote <name>]` blocks are present a
parser reads these banks. Normalized `key` is the stringified id. Comment
markers are `;` and `//` only — never `#` (it delimits emote fields).

## camera.json (3D only)

The 3D viewport is a real camera, so framing that a 2D artist would bake into a
sprite must be rigged per emote. `camera.json` sits beside `char.ini` and is
keyed by emote `key`.

### Poses are height-normalized

A `Pose` frames the character relative to its own height (`targetY` as a
fraction of height, `distance` in character-heights, `yaw`/`pitch`/`fov` in
degrees), not in world units — so a shot is stable across models of different
scale and a sane `default` works before any tuning. Every field is optional and
overrides the resolved default, so a pose can tweak just `distance`.

### Phases: static loop, dynamic preanim

Each emote's camera has two optional slots mirroring the animation phases:

- `loop` — the idle/talking shot. Idle and talking share it (like the body's
  base motion), so entering/leaving talking never moves the camera. Usually a
  static `Pose`; may be a looping `KeyedClip` for a subtle drift. Absent → the
  rig `default`.
- `preanim` — a one-shot `KeyedClip` played during the preanim phase, after
  which the camera eases back to `loop`. Absent → the preanim keeps the loop
  shot.

Most emotes need only a static `loop` (or nothing). Dynamic cameras are
normally reserved for preanims.

### Clip timing and looping

A `KeyedClip`'s keyframe `t` is normalized 0..1 across the phase's driving
motion: the preanim VMD's duration for a `preanim` clip, the base loop's
duration for a `loop` clip. Keys retime automatically if a motion's length
changes. A looping clip's first and last keys should be equal (`t` 0 and 1) so
the cycle has no seam; authoring tools should auto-close the loop.

### Resolution and stacking

For emote `E` in phase `P`, the active shot is `emotes[E].P ?? (P === "loop" ?
default : none)`. Message-driven effects (screenshake, realization) apply as a
transient layer on top of the resolved shot, independent of the loop/preanim
split.
