//
//  StudentCopy.swift
//  Dropies
//
//  Modèle représentant une copie individuelle découpée pour un élève,
//  incluant ses pages, sa note, ses annotations Apple Pencil et son statut Cloud.
//

import Foundation

public struct StudentCopy: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var index: Int
    public var pageStart: Int
    public var pageEnd: Int
    public var studentId: Int?
    public var studentName: String
    public var grade: Double?
    public var isAbsent: Bool
    public var annotationsData: Data?
    public var cloudSyncStatus: CloudSyncStatus

    public enum CloudSyncStatus: Hashable, Sendable {
        case idle
        case uploading(progress: Double)
        case synced
        case failed(error: String)

        public var isSuccess: Bool {
            if case .synced = self { return true }
            return false
        }
    }

    public init(
        id: UUID = UUID(),
        index: Int,
        pageStart: Int,
        pageEnd: Int,
        studentId: Int? = nil,
        studentName: String = "",
        grade: Double? = nil,
        isAbsent: Bool = false,
        annotationsData: Data? = nil,
        cloudSyncStatus: CloudSyncStatus = .idle
    ) {
        self.id = id
        self.index = index
        self.pageStart = pageStart
        self.pageEnd = pageEnd
        self.studentId = studentId
        self.studentName = studentName
        self.grade = grade
        self.isAbsent = isAbsent
        self.annotationsData = annotationsData
        self.cloudSyncStatus = cloudSyncStatus
    }

    /// Nombre de pages que compose cette copie
    public var pageCount: Int {
        max(1, pageEnd - pageStart + 1)
    }

    /// Indique si la copie a été attribuée à un élève
    public var isIdentified: Bool {
        studentId != nil && !studentName.isEmpty && !isAbsent
    }

    /// Génère le nom de fichier PDF final normalisé
    public func formattedFileName(dateString: String, className: String, evaluationTitle: String) -> String {
        let cleanDate = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanClass = Student.sanitizeFolderName(className)
        let cleanTitle = Student.sanitizeFolderName(evaluationTitle)
        let cleanStudent = Student.sanitizeFolderName(studentName)

        return "\(cleanDate) - \(cleanClass) - \(cleanTitle) - \(cleanStudent).pdf"
    }
}
