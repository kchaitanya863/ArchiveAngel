import Foundation
import Photos

/// How backed-up files are arranged under the chosen folder.
enum BackupFolderLayout: String, Codable, CaseIterable, Identifiable {
    /// All files directly in the backup root (default, matches earlier app versions).
    case flat
    /// `YYYY/MM/…`
    case byYearMonth
    /// `YYYY/MM/DD/…`
    case byYearMonthDay
    /// `Photos/…` or `Videos/…`
    case byMediaType
    /// `Photos/YYYY/MM/…` or `Videos/YYYY/MM/…`
    case byMediaTypeYearMonth

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .flat: return "Flat (no subfolders)"
        case .byYearMonth: return "By year and month"
        case .byYearMonthDay: return "By year, month, and day"
        case .byMediaType: return "By photos vs videos"
        case .byMediaTypeYearMonth: return "By type, then year and month"
        }
    }
}

/// How each exported file is named on disk.
enum BackupFileNaming: String, Codable, CaseIterable, Identifiable {
    /// `localId_originalFilename` (default; stable and unique).
    case identifierAndOriginal
    /// `yyyy-MM-dd_localId_originalFilename`
    case datePrefixIdentifierOriginal
    /// `localId.ext` only (short; extension from the resource when possible).
    case localIdentifierOnly

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .identifierAndOriginal: return "ID + original filename"
        case .datePrefixIdentifierOriginal: return "Date + ID + original name"
        case .localIdentifierOnly: return "ID + extension only"
        }
    }
}

/// Pure path math (testable without a live `PHAsset`).
enum BackupOutputPathMath {
    /// Gregorian calendar in UTC so folder names match across devices and time zones.
    private static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    static func folderComponents(
        layout: BackupFolderLayout,
        creationDate: Date?,
        mediaType: PHAssetMediaType
    ) -> [String] {
        let cal = utcCalendar
        let date = creationDate ?? Date(timeIntervalSince1970: 0)
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let yStr = String(format: "%04d", y)
        let mStr = String(format: "%02d", m)
        let dStr = String(format: "%02d", d)

        switch layout {
        case .flat:
            return []
        case .byYearMonth:
            return [yStr, mStr]
        case .byYearMonthDay:
            return [yStr, mStr, dStr]
        case .byMediaType:
            return [mediaType == .video ? "Videos" : "Photos"]
        case .byMediaTypeYearMonth:
            return [mediaType == .video ? "Videos" : "Photos", yStr, mStr]
        }
    }

    static func datePrefixString(creationDate: Date?) -> String {
        let cal = utcCalendar
        let date = creationDate ?? Date(timeIntervalSince1970: 0)
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Single path component (no directory separators).
    static func fileBasename(
        naming: BackupFileNaming,
        sanitizedId: String,
        sanitizedOriginalFilename: String,
        creationDate: Date?
    ) -> String {
        switch naming {
        case .identifierAndOriginal:
            return sanitizedId + "_" + sanitizedOriginalFilename
        case .datePrefixIdentifierOriginal:
            let prefix = datePrefixString(creationDate: creationDate)
            return prefix + "_" + sanitizedId + "_" + sanitizedOriginalFilename
        case .localIdentifierOnly:
            let ext = (sanitizedOriginalFilename as NSString).pathExtension
            let safeExt = ext.lowercased().filter { $0.isLetter || $0.isNumber }
            if safeExt.isEmpty {
                return sanitizedId
            }
            return sanitizedId + "." + safeExt
        }
    }
}
