# Changelog

All notable changes to this package are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial public release, extracted from
  [SwiftPorts](https://github.com/Cocoanetics/SwiftPorts) where it backs the
  `sqlite3` CLI port.
- `SQLiteDatabase` — open in-memory or file-backed databases; `evaluate` /
  `execute` SQL with multi-statement result sets, streaming row callbacks,
  schema introspection, a `-safe`-mode authorizer (`enableSafeMode` /
  `attachTargets`), and online `backup`.
- `SQLiteStatement` — prepared statements with positional (`?`) and named
  (`:name`) parameter binding, strict arity checks, and reusable
  bind / step / reset.
- `SQLiteValue` / `SQLiteRow` / `ResultSet` — typed storage-class values,
  subscriptable by index and column name.
- `ResultFormatter` — sqlite3-compatible output modes (list, csv, json, column,
  table, box, markdown, html, insert, line, …).
- `FTS5` trait — full-text search with bm25 ranking.
- `SQLiteVec` trait — on-device vector / semantic search via sqlite-vec
  (`vec0` cosine / L2 KNN), with packed little-endian float32 blob binding.
- Cross-platform support: macOS, iOS, tvOS, watchOS, visionOS, Linux, Android,
  and Windows.
