import Foundation
import SQLite3

/// Durable SQLite mirror of the last good Mac sessions.status.
/// Sparse/empty publishes must never wipe this; Settings → Clear does.
enum SessionCatalogCache {
    private static let dbName = "sessions-catalog.sqlite"
    private static let legacyJSON = "sessions-catalog-cache.json"

    struct Snapshot {
        var sessions: [SessionInfo]
        var history: [SessionInfo]
        var machine: String
        var tokensRecent: Int
        var tokenWindowHours: Int
        var generatedAt: Double
    }

    private static func folderURL(storageDirectory: URL?) -> URL {
        let folder: URL
        if let storageDirectory {
            folder = storageDirectory
        } else {
            let dir = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            folder = dir.appendingPathComponent("GrantTap", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func dbURL(storageDirectory: URL?) -> URL {
        folderURL(storageDirectory: storageDirectory).appendingPathComponent(dbName)
    }

    private static func legacyURL(storageDirectory: URL?) -> URL {
        folderURL(storageDirectory: storageDirectory).appendingPathComponent(legacyJSON)
    }

    static func load(storageDirectory: URL? = nil) -> Snapshot? {
        migrateLegacyJSONIfNeeded(storageDirectory: storageDirectory)
        guard let db = open(readonly: true, storageDirectory: storageDirectory) else { return nil }
        defer { sqlite3_close(db) }

        var snap = Snapshot(
            sessions: [], history: [], machine: "",
            tokensRecent: 0, tokenWindowHours: 12, generatedAt: 0
        )
        var stmt: OpaquePointer?
        let metaSQL = """
        SELECT machine, tokens_recent, token_window_hours, generated_at
        FROM catalog_meta WHERE id = 1;
        """
        if sqlite3_prepare_v2(db, metaSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                snap.machine = string(stmt, 0) ?? ""
                snap.tokensRecent = Int(sqlite3_column_int64(stmt, 1))
                snap.tokenWindowHours = Int(sqlite3_column_int64(stmt, 2))
                snap.generatedAt = sqlite3_column_double(stmt, 3)
            }
            sqlite3_finalize(stmt)
        }

        snap.sessions = loadRows(db, bucket: "live")
        snap.history = loadRows(db, bucket: "history")
        guard !snap.sessions.isEmpty || !snap.history.isEmpty else { return nil }
        return snap
    }

    static func save(sessions: [SessionInfo], history: [SessionInfo],
                     machine: String, tokensRecent: Int,
                     tokenWindowHours: Int, generatedAt: Double,
                     storageDirectory: URL? = nil) {
        guard !sessions.isEmpty || !history.isEmpty else { return }
        guard let db = open(readonly: false, storageDirectory: storageDirectory) else { return }
        defer { sqlite3_close(db) }

        exec(db, "BEGIN IMMEDIATE;")
        exec(db, "DELETE FROM catalog_sessions;")
        exec(db, """
        INSERT INTO catalog_meta(id, machine, tokens_recent, token_window_hours, generated_at, saved_at)
        VALUES (1, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          machine=excluded.machine,
          tokens_recent=excluded.tokens_recent,
          token_window_hours=excluded.token_window_hours,
          generated_at=excluded.generated_at,
          saved_at=excluded.saved_at;
        """, binds: { stmt in
            bindText(stmt, 1, machine)
            sqlite3_bind_int64(stmt, 2, Int64(tokensRecent))
            sqlite3_bind_int64(stmt, 3, Int64(tokenWindowHours))
            sqlite3_bind_double(stmt, 4, generatedAt)
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970 * 1000)
        })

        for (i, s) in sessions.enumerated() {
            insertSession(db, s, bucket: "live", sort: i)
        }
        for (i, s) in history.prefix(120).enumerated() {
            insertSession(db, s, bucket: "history", sort: i)
        }
        exec(db, "COMMIT;")
    }

    static func clear(storageDirectory: URL? = nil) {
        try? FileManager.default.removeItem(at: dbURL(storageDirectory: storageDirectory))
        try? FileManager.default.removeItem(at: legacyURL(storageDirectory: storageDirectory))
    }

    // MARK: - SQLite helpers

    private static func open(readonly: Bool, storageDirectory: URL?) -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = readonly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX)
        let path = dbURL(storageDirectory: storageDirectory).path
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        if !readonly { ensureSchema(db) }
        return db
    }

    private static func ensureSchema(_ db: OpaquePointer) {
        exec(db, """
        CREATE TABLE IF NOT EXISTS catalog_meta (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          machine TEXT NOT NULL DEFAULT '',
          tokens_recent INTEGER NOT NULL DEFAULT 0,
          token_window_hours INTEGER NOT NULL DEFAULT 12,
          generated_at REAL NOT NULL DEFAULT 0,
          saved_at REAL NOT NULL DEFAULT 0
        );
        """)
        exec(db, """
        CREATE TABLE IF NOT EXISTS catalog_sessions (
          bucket TEXT NOT NULL,
          sort_idx INTEGER NOT NULL,
          session_id TEXT NOT NULL,
          payload BLOB NOT NULL,
          PRIMARY KEY (bucket, session_id)
        );
        """)
        exec(db, """
        CREATE INDEX IF NOT EXISTS idx_catalog_bucket_sort
          ON catalog_sessions(bucket, sort_idx);
        """)
    }

    private static func loadRows(_ db: OpaquePointer, bucket: String) -> [SessionInfo] {
        var stmt: OpaquePointer?
        let sql = """
        SELECT payload FROM catalog_sessions
        WHERE bucket = ? ORDER BY sort_idx ASC;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, bucket, -1, SQLITE_TRANSIENT)
        var out: [SessionInfo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let len = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: bytes, count: len)
            if let s = try? JSONDecoder().decode(SessionInfo.self, from: data) {
                out.append(s)
            }
        }
        return out
    }

    private static func insertSession(_ db: OpaquePointer, _ s: SessionInfo,
                                      bucket: String, sort: Int) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        exec(db, """
        INSERT OR REPLACE INTO catalog_sessions(bucket, sort_idx, session_id, payload)
        VALUES (?, ?, ?, ?);
        """, binds: { stmt in
            bindText(stmt, 1, bucket)
            sqlite3_bind_int(stmt, 2, Int32(sort))
            bindText(stmt, 3, s.sessionId)
            _ = data.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 4, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        })
    }

    private static func migrateLegacyJSONIfNeeded(storageDirectory: URL?) {
        let database = dbURL(storageDirectory: storageDirectory)
        let legacyFile = legacyURL(storageDirectory: storageDirectory)
        guard !FileManager.default.fileExists(atPath: database.path),
              FileManager.default.fileExists(atPath: legacyFile.path),
              let data = try? Data(contentsOf: legacyFile),
              let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data)
        else { return }
        save(
            sessions: legacy.sessions,
            history: legacy.history,
            machine: legacy.machine,
            tokensRecent: legacy.tokensRecent,
            tokenWindowHours: legacy.tokenWindowHours,
            generatedAt: legacy.generatedAt,
            storageDirectory: storageDirectory
        )
        try? FileManager.default.removeItem(at: legacyFile)
    }

    private struct LegacySnapshot: Codable {
        var sessions: [SessionInfo]
        var history: [SessionInfo]
        var machine: String
        var tokensRecent: Int
        var tokenWindowHours: Int
        var generatedAt: Double
    }

    private static func exec(_ db: OpaquePointer, _ sql: String,
                             binds: ((OpaquePointer) -> Void)? = nil) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        binds?(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE || rc == SQLITE_ROW { break }
            if rc != SQLITE_ROW { break }
        }
    }

    private static func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    private static func string(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let stmt, let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
