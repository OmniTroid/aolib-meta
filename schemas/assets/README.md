# Asset formats

Schemas here describe **character asset files** (fetched by the client from
`characters/<name>/`), not wire packets. They carry no `$header` or
`x-receiver`. JSON Schema describes the *parsed* shape; the on-disk text
grammar that JSON Schema can't express (char.ini is INI, not JSON) is
specified below.

- `CharIni` — parsed `char.ini`.

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
postanim  = bow.gif       ; exit animation with extension, or omit / `-` for none
camera    = objection_cam.vmd ; 3D: camera-motion VMD framing this emote, or omit / `-`
sound     = objection.opus ; optional; file with extension (.opus/.wav/.ogg)
sounddelayms = 480        ; optional, milliseconds
modifier  = zoom          ; number or EmoteModifier name; 3D ignores it (use the emote's camera VMD)
deskmod   = shown         ; optional; number or DeskModifier name

[emote think]
anim = think_loop.gif
```

The **block name** (`objection`, `think`) is the emote's `key`: the stable
identity the button keys off. It is independent of button order, so reordering
`[emotions]` never shifts anything. `[emotions]` itself is
optional: when it is absent (or lists no blocks) every `[emote <name>]` block is
an emote, in the order it appears in the file; when present it selects and
orders the blocks, and a block it does not list is not shown as a button.

Only `anim` is required in a block (`key` is the block name); every other field
has a default, so the parsed `Emote` is a complete shape either way. Block field
names are the lowercased `Emote` field names: `name` (display label; defaults to
the block name), `anim`, `preanim` (`-`/absent → null), `postanim` (`-`/absent →
null), `camera` (`-`/absent → null), `sound` (absent → null), `sounddelayms`
(milliseconds; absent → 0), `deskmod` (absent → 1, shown), and `modifier`
(absent → 0). The normalized emote list is in button order, so there is no id.
Unlike the legacy stems, a block's file references **must carry the file
extension** — no extension guessing:
`anim`/`preanim`/`postanim` (`.gif`/`.webp`/`.png` for 2D, `.vmd` for 3D),
`camera` (a `.vmd` with a camera track, 3D only), and `sound`
(`.opus`/`.wav`/`.ogg`). `modifier` and `deskmod` each
accept either a number or the matching enum name, case-insensitive:
EmoteModifier for `modifier` (`no_preanim` 0,
`preanim` 1, `preanim_and_objection` 2, `zoom` 5, `objection_zoom` 6) and
DeskModifier for `deskmod` (`hidden` 0, `shown` 1, `hide_during_preanim` 2,
`show_during_preanim` 3, `hide_and_center_during_preanim` 4,
`show_during_preanim_then_center` 5).

`postanim` is an exit animation, the mirror of `preanim`. The preanim phase is
gated: it runs only when preanim is enabled **for that message** — the sender's
"Preanim" toggle, carried on the wire as the MS emote modifier. When it is off,
**neither** the leaving emote's `postanim` **nor** the entering emote's
`preanim` plays: the entering emote goes straight to its loop and the previous
emote is left instantly. When it is on, the client plays the **leaving** emote's
`postanim` first, then the **entering** emote's `preanim`, then the entering
emote's loop (`anim`); either file may be absent and is simply skipped.

The gate follows the effective emote modifier: preanim runs for the
preanim-playing values (`preanim`, `preanim_and_objection`, `objection_zoom`)
and not for `no_preanim` or `zoom`. An emote's own `modifier` field is that
message's default, so an emote authored with a preanim-playing `modifier` turns
the toggle on by default (the box appears pre-checked). `postanim` exists only
in blocks; legacy characters have none.

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

`N = desc#preanim#anim#modifier#deskmod`, zipped with `[soundn]` (sound) and
`[soundt]` (sound delay) by id. `[soundt]` is in **ticks** — one tick is 60 ms,
the message text update interval — and is normalized to milliseconds in
`Emote.sounddelayms` (ticks × 60). When no `[emote <name>]` blocks are present a
parser reads these banks. Normalized `key` is the stringified id. Comment
markers are `;` and `//` only — never `#` (it delimits emote fields).
