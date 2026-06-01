# aolib-meta

Schemas for the Attorney Online wire protocol. Used as a git submodule by
each language-specific `aolib-*` library so all bindings stay in sync.

JSON Schema (draft-07) is the single source of truth. Each library has its
own codegen step that consumes these files and emits native types,
validators, and wire encoders/decoders.

## Layout

```
schemas/
  packets/<Name>.schema.json   one per AO packet
  enums/<Name>.schema.json     shared named enums, $ref'd from packets
  types/<Name>.schema.json     shared object types, $ref'd from packets
```

All files use the `.schema.json` suffix. Kind is determined by directory,
not by filename.

Each schema carries an absolute-path `$id` matching its location, e.g.
`/packets/MS.schema.json`, `/enums/Side.schema.json`. Packets reference
shared schemas with relative-path `$ref`s like `../enums/Side.schema.json`.
That form is both IDE-resolvable (filesystem) and validator-resolvable
(RFC 3986 URI resolution against the parent `$id` produces the target's
`$id` exactly).

## Codegen strategy

A codegen consumer (see `aolib-ts/scripts/codegen.ts` for the TS reference
implementation) walks the three directories and emits, per file:

- **packets/** → one typed class/struct per packet. Declared fields carry
  the *decoded* shape (every field present, defaults filled);
  constructor/init carries the *input* shape (default-bearing fields
  optional, `const`-only padding slots omitted).
- **enums/** → one named enum in the target language. Names come from
  `x-enum-names` (see below); values come from `enum`.
- **types/** → one shared struct/interface per file, importable by
  packets that `$ref` it.

Each packet schema declares its direction via `x-receiver` and its wire
header via the `$header` const. The codegen scans `packets/`, reads
those two fields, and builds the direction maps directly — no sidecar
registry. Bidirectional packets (e.g. `MC`, `HP`) live as two schemas
(`MCRequest`/`MCBroadcast`, `HPRequest`/`HPBroadcast`) sharing one
header.

## Validation and wire format

Each library wires its JSON Schema validator (e.g. Ajv in TS) and a
fanta-format walker to the same schemas:

- **JSON envelope** — packet body is the schema as-is, with `$header`
  prepended.
- **Fanta wire** — `HEADER#field1#field2#...#%`, one positional slot per
  top-level property (skipping `$header`). The walker derives per-slot
  encoding from the property's JSON type:
  - `string` — escape `#`/`&`/`%`/`$` as `<num>`/`<and>`/`<percent>`/`<dollar>`
  - `number` / `integer` — `String(n)` / `Number(token)`
  - `boolean` — `"1"` / `"0"`
  - `object` — recurse, joining sub-tokens with `&`
  - `array` — greedy: trailing array consumes all remaining slots
  - `const` — emitted as the const value; on decode the slot is consumed
    and the schema-fixed value is used regardless of the token

Validation (defaults, required-field checks, type coercion errors) is
delegated to the JSON Schema validator on both encode (pre-serialize) and
decode (post-parse), so the typed shape is identical on both ends.

## Custom extensions

These `x-*` keywords are project-specific. JSON Schema validators ignore
unknown keywords by default; the codegen and walker interpret them.

### `x-enum-names: string[]`

On an enum schema. Names parallel to the `enum` values array; codegen
uses them as the enum member names in the target language.

```json
{
  "$id": "/enums/Side.schema.json",
  "type": "string",
  "enum": ["def", "pro", "wit"],
  "x-enum-names": ["DEFENSE", "PROSECUTION", "WITNESS"]
}
```

### `x-fanta-codec: string`

On a packet schema. Bypasses the generic positional walker for that
packet — the library looks up a codec registered under this name and
delegates encode/decode to it. Used for packets whose wire form has
discriminator-driven payload shapes (e.g. `ARUP`).

### `x-receiver: "client" | "server"`

On a packet schema. Names which side receives this packet on the wire
(server-receiver packets flow client→server, client-receiver packets
flow server→client). Combined with the packet's `$header` const, this
fully describes routing — codegen builds the c2s/s2c maps from it
directly. Symmetric bidirectional packets are split into two schemas
sharing a header (e.g. `HPRequest` with `x-receiver: "server"` and
`HPBroadcast` with `x-receiver: "client"`).

### `x-fanta-unescape-amp: true`

On an `object`-typed schema. Encoders never emit the legacy `<and>`
escape (objects join sub-tokens with literal `&`). Setting this flag
makes decoders tolerate `<and>` in incoming tokens — useful for shared
object types whose wire slot historically used the chat-escape form on
the way in but no longer does on the way out. Currently set on
`Offset`.

## Reserved property names

- `$header` — every packet schema declares `$header` as a `const` string
  matching the wire header. The framing layer reads/writes it; validators
  enforce it; the typed shape on the consumer side may or may not expose
  it (TS strips it on decode).

## Formatting

Keep all JSON files formatted using `./format.sh`.
