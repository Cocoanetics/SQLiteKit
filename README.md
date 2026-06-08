# SQLiteKit

A small, pure-Swift wrapper over a vendored SQLite amalgamation — prepared
statements, typed values, and sqlite3-compatible result formatting, with
**FTS5 full-text search** and **sqlite-vec semantic search** available behind
opt-in traits. Runs everywhere Swift does: macOS, iOS, tvOS, watchOS, visionOS,
Linux, Android, and Windows.

[![Swift](https://github.com/Cocoanetics/SQLiteKit/actions/workflows/swift.yml/badge.svg)](https://github.com/Cocoanetics/SQLiteKit/actions/workflows/swift.yml)
[![SwiftLint](https://github.com/Cocoanetics/SQLiteKit/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/Cocoanetics/SQLiteKit/actions/workflows/swiftlint.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20·%20iOS%20·%20tvOS%20·%20watchOS%20·%20visionOS%20·%20Linux%20·%20Android%20·%20Windows-blue.svg)](#platforms)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)

## Why

- **Self-contained.** The SQLite engine is vendored — via
  [`stephencelis/CSQLite`](https://github.com/stephencelis/CSQLite), pinned to an
  exact version — and statically linked. No system `libsqlite3`, so the engine
  version is identical on every platform and every feature is available even
  where the system build strips it out.
- **Typed and safe.** Values are a `SQLiteValue` enum
  (`.null` / `.integer` / `.real` / `.text` / `.blob`); parameters bind
  out-of-band (`?` and `:name`), so there is no string-interpolation injection
  surface.
- **On-device search.** Opt into FTS5 (bm25) and/or sqlite-vec (`vec0`
  cosine / L2 KNN) at build time — the same engine that fits on an iPhone or an
  Android handset.
- **Faithful formatting.** `ResultFormatter` reproduces the sqlite3 shell's
  output modes (list, csv, json, column, box, markdown, …).

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Cocoanetics/SQLiteKit", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "SQLiteKit", package: "SQLiteKit"),
        ]
    ),
]
```

To turn on the search engines, enable the traits — both are **off by default**:

```swift
.package(url: "https://github.com/Cocoanetics/SQLiteKit",
         from: "0.1.0",
         traits: ["FTS5", "SQLiteVec"]),
```

## Quick start

```swift
import SQLiteKit

let db = try SQLiteDatabase(.file("library.sqlite"))
// or: let db = try SQLiteDatabase.inMemory()

try db.evaluate("""
    CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT NOT NULL, year INTEGER);
    """)

// Parameters bind out-of-band — no escaping, no injection.
try db.execute(
    "INSERT INTO book(title, year) VALUES (?, ?);",
    [.text("The Swift Programming Language"), .integer(2014)]
)
print(db.lastInsertRowID)   // 1

let results = try db.evaluate("SELECT title, year FROM book ORDER BY year;")
for row in results[0].rows {
    print(row[0], row[1])   // .text("…")  .integer(2014)
}
```

### Named parameters

```swift
let rows = try db.evaluate(
    "SELECT id FROM book WHERE year >= :from AND year < :to;",
    [":from": .integer(2000), ":to": .integer(2020)]
)[0].rows
```

### Prepared statements (bind once, step many)

```swift
let insert = try SQLiteStatement(db, "INSERT INTO book(title, year) VALUES (?, ?);")
for (title, year) in catalog {
    try insert.bind([.text(title), .integer(Int64(year))])
    _ = try insert.step()
    insert.reset()
}
```

### Streaming rows

```swift
try db.execute("SELECT title FROM book;") { row in
    print(row["title"] ?? .null)   // SQLiteRow subscripts by index or column name
}
```

### Formatting results like the sqlite3 shell

```swift
let set = try db.evaluate("SELECT id, title FROM book;")[0]
print(ResultFormatter(mode: .box, showHeader: true).render(set))
// ┌────┬───────────────────────────────┐
// │ id │ title                         │
// ├────┼───────────────────────────────┤
// │ 1  │ The Swift Programming Language │
// └────┴───────────────────────────────┘
```

Modes: `.list`, `.csv`, `.json`, `.column`, `.table`, `.box`, `.markdown`,
`.html`, `.tabs`, `.quote`, `.insert`, `.line`, `.ascii`.

## Full-text search (`FTS5` trait)

```swift
try db.evaluate("CREATE VIRTUAL TABLE docs USING fts5(title, body);")
try db.execute("INSERT INTO docs(title, body) VALUES (?, ?);",
               [.text("SQLite FTS"), .text("Full text search. Full ranking.")])

// bm25 relevance ranking via the special `rank` column.
let hits = try db.evaluate("""
    SELECT title FROM docs WHERE docs MATCH 'full' ORDER BY rank;
    """)
```

Column filters (`body:term`), boolean operators (`a AND b`), and phrase queries
all work as in upstream FTS5.

## Semantic search (`SQLiteVec` trait)

[`sqlite-vec`](https://github.com/asg017/sqlite-vec) is compiled statically into
the engine, giving you a `vec0` virtual table for cosine / L2 nearest-neighbor
search — entirely on-device.

```swift
try db.evaluate("""
    CREATE VIRTUAL TABLE docs USING vec0(
        doc_id INTEGER PRIMARY KEY,
        embedding float[768] distance_metric=cosine
    );
    """)

// Bind embeddings as packed little-endian float32 — ~6 KB for a 1536-d vector
// vs. ~20 KB as a JSON literal.
func packed(_ floats: [Float]) -> Data {
    var data = Data(capacity: floats.count * 4)
    for f in floats {
        var le = f.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
    return data
}

let insert = try SQLiteStatement(db, "INSERT INTO docs(doc_id, embedding) VALUES (?, ?);")
try insert.bind([.integer(1), .blob(packed(embedding))])
_ = try insert.step()

// KNN: the query vector bound as a blob; results ordered by distance.
let knn = try db.evaluate("""
    SELECT doc_id, distance FROM docs
    WHERE embedding MATCH ? AND k = 10
    ORDER BY distance;
    """, [.blob(packed(queryVector))])
```

Pair it with FTS5 for hybrid keyword + semantic retrieval.

## Traits

| Trait | Effect | Default |
|-------|--------|---------|
| `FTS5` | Compiles SQLite with `-DSQLITE_ENABLE_FTS5` (full-text search + bm25). | off |
| `SQLiteVec` | Compiles in the `sqlite-vec` amalgamation (`vec0` vector search). | off |

Enable when depending on the package via `traits: ["FTS5", "SQLiteVec"]`, or when
building directly with `swift build --traits FTS5,SQLiteVec`. Each trait
recompiles the engine, so they are opt-in.

## API at a glance

- **`SQLiteDatabase`** — `init(_:readonly:)` / `.inMemory()`; `evaluate(_:)` and
  `evaluate(_:_:)` returning `[ResultSet]`; streaming `execute(_:_:row:)`;
  `lastInsertRowID`, `changes`; `tableNames()`, `schemaSQL(of:)`,
  `nonGeneratedColumns(of:)`; `enableSafeMode()` + `attachTargets(in:)` for
  sandboxing hosts; `backup(to:)`; static `quoteIdentifier(_:)` and `libVersion`.
- **`SQLiteStatement`** — `init(_:_:)`; `bind([SQLiteValue])` / `bind(_:_:)` /
  `bind([String: SQLiteValue])`; `step() -> SQLiteRow?`; `reset()`.
- **`SQLiteValue`** — `.null | .integer(Int64) | .real(Double) | .text(String) | .blob(Data)`, `Equatable & Sendable`.
- **`SQLiteRow` / `ResultSet`** — typed rows, subscriptable by index and column name.
- **`ResultFormatter`** — sqlite3-compatible rendering.

## Platforms

macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, visionOS 1+, Linux, Android, Windows.
Swift 6.2+.

## Acknowledgements

- **SQLite** — public domain, by D. Richard Hipp and the SQLite team. Vendored
  via [`stephencelis/CSQLite`](https://github.com/stephencelis/CSQLite).
- **sqlite-vec** — © Alex Garcia, dual-licensed
  [MIT](Sources/CSQLiteVec/LICENSE-MIT) /
  [Apache-2.0](Sources/CSQLiteVec/LICENSE-APACHE). Vendored under
  `Sources/CSQLiteVec`.

SQLiteKit was extracted from
[Cocoanetics/SwiftPorts](https://github.com/Cocoanetics/SwiftPorts), where it
backs the `sqlite3` command-line port.

## License

MIT © Cocoanetics / Oliver Drobnik. See [LICENSE](LICENSE).
