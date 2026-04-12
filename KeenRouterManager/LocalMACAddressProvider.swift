import Foundation
import Darwin

/**
 * Loads MAC addresses from local network interfaces of the current Mac.
 */
final class LocalMACAddressProvider {
    /**
     * Reads a set of active local MAC addresses.
     * - Returns: Normalized lowercased MAC addresses (`aa:bb:cc:dd:ee:ff`).
     */
    func loadMACAddresses() -> Set<String> {
        var listPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&listPointer) == 0, let first = listPointer else {
            return []
        }
        defer { freeifaddrs(listPointer) }

        var addresses = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let entry = current.pointee
            guard let addressPointer = entry.ifa_addr else {
                continue
            }

            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  (flags & IFF_POINTOPOINT) == 0,
                  addressPointer.pointee.sa_family == UInt8(AF_LINK)
            else {
                continue
            }

            let interfaceName = String(cString: entry.ifa_name)
            guard !Self.isIgnoredInterface(interfaceName) else { continue }

            guard let normalized = Self.macAddress(from: addressPointer) else { continue }
            addresses.insert(normalized)
        }

        return addresses
    }

    private static func isIgnoredInterface(_ name: String) -> Bool {
        let prefixes = ["lo", "utun", "awdl", "llw", "anpi", "gif", "stf", "ap", "bridge"]
        return prefixes.contains { name.hasPrefix($0) }
    }

    private static func macAddress(from pointer: UnsafePointer<sockaddr>) -> String? {
        let sdlPointer = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_dl.self)
        let sdl = sdlPointer.pointee
        let addressLength = Int(sdl.sdl_alen)
        guard addressLength == 6 else { return nil }

        let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) ?? 0
        let dataPtr = UnsafeRawPointer(sdlPointer)
            .advanced(by: dataOffset)
            .assumingMemoryBound(to: UInt8.self)
        let nameLength = Int(sdl.sdl_nlen)
        let bytes = UnsafeBufferPointer(start: dataPtr.advanced(by: nameLength), count: addressLength)
        let mac = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")

        if mac == "00:00:00:00:00:00" {
            return nil
        }
        return mac
    }
}
