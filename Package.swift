// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SQLiteKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        // The SDK: a thin, pure-Swift wrapper over the vendored SQLite
        // amalgamation. FTS5 and sqlite-vec ride along behind opt-in traits.
        .library(name: "SQLiteKit", targets: ["SQLiteKit"]),
        // The `sqlite3` shell driver — the argv parser plus the dot-command /
        // REPL engine that reproduces the sqlite3 CLI. ArgumentParser-free and
        // IO-agnostic (it reads / writes / authorizes paths through
        // `ShellKit.Shell`), so a host can drive it in-process on any platform,
        // Android included. The SwiftPorts `sqlite3` executable wraps it in an
        // ArgumentParser command; SwiftBash registers it as a native builtin.
        // Pulls in ShellKit — SDK-only consumers that depend on the `SQLiteKit`
        // product never build this target (or ShellKit) into their link.
        .library(name: "Sqlite3Shell", targets: ["Sqlite3Shell"]),
    ],
    // Opt-in, build-time engine toggles. Both off by default.
    //   • depending on this package:   .package(url: …, traits: ["FTS5", "SQLiteVec"])
    //   • building this package direct: swift build --traits FTS5,SQLiteVec
    // See `fullTextSearchFTS5` / `semanticSearchSQLiteVec` / `vec0BlobBind`
    // in SQLiteKitTests for the on/off contract each trait pins.
    traits: [
        .trait(name: "FTS5",
               description: "Compile SQLite with FTS5 full-text search."),
        .trait(name: "SQLiteVec",
               description: "Compile in sqlite-vec for on-device vector / semantic search."),
    ],
    dependencies: [
        // Vendored SQLite amalgamation — a single public-domain `sqlite3.c`
        // packaged as a SwiftPM C target. Pinned exact so the engine version
        // is identical on every platform. Our `FTS5` trait forwards to
        // CSQLite's `FTS5` trait, which compiles the amalgamation with
        // `-DSQLITE_ENABLE_FTS5`.
        .package(url: "https://github.com/stephencelis/CSQLite",
                 exact: "3.50.4",
                 traits: [.trait(name: "FTS5", condition: .when(traits: ["FTS5"]))]),
        // Host runtime context for the `Sqlite3Shell` driver: the IO sinks it
        // reads / writes through and the sandbox gate (`Shell.resolve` /
        // `Shell.authorize`) every file-touching dot-command passes. Only the
        // ArgumentParser-free `ShellKit` core product is used, so no
        // ArgumentParser enters this package's graph. Pinned to `main` until
        // ShellKit ships a tagged release.
        .package(url: "https://github.com/Cocoanetics/ShellKit",
                 branch: "main"),
    ],
    targets: [
        // Typed C wrappers for SQLite's variadic printf (`sqlite3_mprintf`),
        // which Swift can't call directly — gives `SQLiteKit` byte-exact access
        // to the engine's float formatting for round-trip output.
        .target(
            name: "CSQLiteShim",
            dependencies: [
                .product(name: "SQLiteSwiftCSQLite", package: "CSQLite"),
            ],
            publicHeadersPath: "include"
        ),
        // sqlite-vec, compiled statically into the engine for on-device vector
        // search. Linked only when the `SQLiteVec` trait is on (see SQLiteKit's
        // dependency below); no product exposes it, so consumers don't build it
        // unless they opt in. The vendored amalgamation (sqlite-vec.c) is
        // compiled via sqlite-vec-shim.c — which adds the one missing system
        // include — so it stays byte-for-byte upstream and is excluded from
        // direct compilation. See Sources/CSQLiteVec/README.md.
        .target(
            name: "CSQLiteVec",
            dependencies: [
                .product(name: "SQLiteSwiftCSQLite", package: "CSQLite"),
            ],
            exclude: ["sqlite-vec.c", "README.md", "LICENSE-MIT", "LICENSE-APACHE"],
            publicHeadersPath: "include",
            cSettings: [
                // Static link against the core engine (no sqlite3ext.h
                // api-routine indirection); empty the API export macro so the
                // symbol isn't dllexport'd on Windows for a static build; drop
                // the filesystem helpers to keep vectors in-database.
                .define("SQLITE_CORE"),
                .define("SQLITE_VEC_STATIC"),
                .define("SQLITE_VEC_OMIT_FS"),
            ]
        ),
        // The SDK — `SQLiteDatabase`, `SQLiteStatement`, `SQLiteValue`,
        // `SQLiteRow`, `ResultSet`, `ResultFormatter`. Pure Swift over the
        // amalgamation; no system libsqlite3.
        .target(
            name: "SQLiteKit",
            dependencies: [
                .product(name: "SQLiteSwiftCSQLite", package: "CSQLite"),
                "CSQLiteShim",
                // Linked (and the amalgamation compiled) only when the
                // SQLiteVec trait is enabled.
                .target(name: "CSQLiteVec", condition: .when(traits: ["SQLiteVec"])),
            ],
            linkerSettings: [
                // Apple SDKs provide these via libSystem; gate to non-Apple.
                .linkedLibrary("m", .when(platforms: [.linux, .android])),
                .linkedLibrary("dl", .when(platforms: [.linux, .android])),
                // Linux only: Android's Bionic folds pthread into libc (there
                // is no separate libpthread.so), so `-lpthread` would fail
                // there. The pthread symbols come from libc on Android.
                .linkedLibrary("pthread", .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "SQLiteKitTests",
            dependencies: ["SQLiteKit"]
        ),
        // The `sqlite3` shell driver: `Parser` (SQLite's single-dash long
        // options, which ArgumentParser can't express) plus `Sqlite3Executable`
        // / `Session` (the dot-command and REPL engine). Depends on the SDK and
        // on ShellKit's core for IO + the sandbox gate; carries no
        // ArgumentParser, so it builds on every platform (Android included).
        .target(
            name: "Sqlite3Shell",
            dependencies: [
                "SQLiteKit",
                .product(name: "ShellKit", package: "ShellKit"),
            ]
        ),
        // Drives `Sqlite3Executable` directly (no ArgumentParser), so it builds
        // and runs on every platform in the matrix — Android included —
        // exercising the shell port on the emulator in CI.
        .testTarget(
            name: "Sqlite3ShellTests",
            dependencies: [
                "Sqlite3Shell",
                "SQLiteKit",
                .product(name: "ShellKit", package: "ShellKit"),
            ]
        ),
    ]
)
