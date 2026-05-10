import Foundation
import Darwin
import IMMessageMCPLib

// MARK: - TCC responsibility self-disclaim
//
// macOS TCC evaluates permissions (e.g. Full Disk Access) against a process's
// "responsible" process, which by default is inherited from whoever spawned us.
// When this binary is launched from a non-LaunchServices parent (Hermes'
// Python, a shell pipe, etc.), the parent becomes our responsible — and the
// FDA grant the user attached to *our bundle* is ignored.
//
// `responsibility_spawnattrs_setdisclaim` is a libsystem SPI that, when set on
// a posix_spawnattr, makes the spawned child its own responsible process.
// We re-exec ourselves with it set; the child runs with bundle identity
// io.github.joewalnes.imessage-mcp, which is what the user granted FDA to.

@_silgen_name("responsibility_spawnattrs_setdisclaim")
func responsibility_spawnattrs_setdisclaim(
    _ attrs: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ disclaim: Int32
) -> Int32

private let kReexecMarker = "__IMESSAGE_MCP_DISCLAIMED__"

private func reexecAsSelfResponsible() -> Never {
    // Resolve our own executable path.
    var size: UInt32 = 4096
    var pathBuf = [CChar](repeating: 0, count: Int(size))
    if _NSGetExecutablePath(&pathBuf, &size) != 0 {
        FileHandle.standardError.write(Data("re-exec: _NSGetExecutablePath failed\n".utf8))
        exit(127)
    }

    // The re-exec'd child must skip this branch.
    setenv(kReexecMarker, "1", 1)

    var attrs: posix_spawnattr_t?
    if posix_spawnattr_init(&attrs) != 0 {
        FileHandle.standardError.write(Data("re-exec: posix_spawnattr_init failed\n".utf8))
        exit(127)
    }
    defer { posix_spawnattr_destroy(&attrs) }

    let drc = responsibility_spawnattrs_setdisclaim(&attrs, 1)
    if drc != 0 {
        FileHandle.standardError.write(Data("re-exec: setdisclaim failed: \(drc)\n".utf8))
        exit(127)
    }

    // Forward argv.
    let cArgs = CommandLine.arguments.map { strdup($0) }
    var argv: [UnsafeMutablePointer<CChar>?] = cArgs + [nil]

    // Forward environment.
    var envp: [UnsafeMutablePointer<CChar>?] = []
    var p = environ
    while let s = p.pointee {
        envp.append(s)
        p = p.advanced(by: 1)
    }
    envp.append(nil)

    // Spawn child with disclaim attr; inherits our stdio fds by default.
    var pid: pid_t = 0
    let rc = pathBuf.withUnsafeBufferPointer { buf -> Int32 in
        posix_spawn(&pid, buf.baseAddress, nil, &attrs, &argv, &envp)
    }
    if rc != 0 {
        FileHandle.standardError.write(Data("re-exec: posix_spawn failed: \(rc)\n".utf8))
        exit(127)
    }

    // Wait for child, propagate exit status.
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 {
        if errno == EINTR { continue }
        FileHandle.standardError.write(Data("re-exec: waitpid failed: \(errno)\n".utf8))
        exit(127)
    }
    for s in cArgs { free(s) }
    if (status & 0x7f) == 0 {
        exit((status >> 8) & 0xff)
    }
    exit(128 + (status & 0x7f))
}

if ProcessInfo.processInfo.environment[kReexecMarker] == nil {
    reexecAsSelfResponsible()
}

// MARK: - MCP server (running as the disclaimed, self-responsible child)

let server = MCPServer(
    reader: SQLiteMessageReader(),
    sender: AppleScriptMessageSender()
)

while let line = readLine() {
    if line.isEmpty { continue }
    if let response = server.handleLine(line) {
        FileHandle.standardOutput.write(response)
    }
}
