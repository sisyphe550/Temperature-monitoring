import Darwin
import Foundation

public enum SessionLockError: Error, Sendable, Equatable {
    case alreadyHeld
    case openFailed(String)
}

public final class SessionLock: @unchecked Sendable {
    public let lockURL: URL
    private var fileDescriptor: Int32 = -1

    public var isHeld: Bool {
        fileDescriptor >= 0
    }

    public static func acquire(at lockURL: URL) throws -> SessionLock {
        let lock = SessionLock(lockURL: lockURL)
        try lock.openAndLock()
        return lock
    }

    private init(lockURL: URL) {
        self.lockURL = lockURL
    }

    deinit {
        release()
    }

    public func release() {
        guard fileDescriptor >= 0 else {
            return
        }
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    private func openAndLock() throws {
        let parent = lockURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let path = lockURL.path
        let fd = path.withCString { cPath in
            open(cPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard fd >= 0 else {
            throw SessionLockError.openFailed(String(cString: strerror(errno)))
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            if errno == EWOULDBLOCK {
                throw SessionLockError.alreadyHeld
            }
            throw SessionLockError.openFailed(String(cString: strerror(errno)))
        }

        fileDescriptor = fd
    }
}
