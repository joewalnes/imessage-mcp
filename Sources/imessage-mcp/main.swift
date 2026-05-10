import IMMessageMCPLib

while let line = readLine() {
    if line.isEmpty { continue }
    handleRequest(line)
}
