//
//  NetworkMonitor.swift
//  Droopies
//
//  Surveillance temps réel de la connectivité réseau (WiFi, Cellulaire, Filaire)
//  utilisant Network.framework (NWPathMonitor) d'Apple.
//  Permet le basculement transparent entre mode Connecté et mode Hors-Ligne.
//

import Foundation
import Network
import Observation

@Observable
public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()

    /// Indique si l'appareil dispose actuellement d'un accès réseau fonctionnel
    public var isOnline: Bool = true

    /// Permet de forcer le mode Hors-Ligne pour les tests et la validation de l'interface
    public var isForcedOffline: Bool = false {
        didSet {
            Task { @MainActor in
                let newOnline = !self.isForcedOffline && (self.monitor.currentPath.status == .satisfied)
                let previous = self.isOnline
                self.isOnline = newOnline
                if previous != newOnline {
                    print("[NetworkMonitor] Mode forcé modifié : \(newOnline ? "EN LIGNE 🟢" : "HORS-LIGNE 🟠")")
                    self.onStatusChange?(newOnline)
                }
            }
        }
    }

    /// Indique si la connexion est de type cellulaire ou partage de connexion
    public var isExpensive: Bool = false

    /// Indique si le mode « Économie de données » est activé dans iOS
    public var isConstrained: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "fr.education.droopies.networkmonitor", qos: .utility)

    /// Callback appelé lors d'une transition réseau (true: retour en ligne, false: passage hors-ligne)
    public var onStatusChange: (@Sendable (Bool) -> Void)? = nil

    private init() {
        self.monitor = NWPathMonitor()

        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let online = (path.status == .satisfied) && !self.isForcedOffline
            let expensive = path.isExpensive
            let constrained = path.isConstrained

            Task { @MainActor in
                let previous = self.isOnline
                self.isOnline = online
                self.isExpensive = expensive
                self.isConstrained = constrained

                if previous != online {
                    print("[NetworkMonitor] Connectivité changée : \(online ? "EN LIGNE 🟢" : "HORS-LIGNE 🟠")")
                    self.onStatusChange?(online)
                }
            }
        }

        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
