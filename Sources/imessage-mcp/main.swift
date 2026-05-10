import Foundation
import IMMessageMCPLib

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
