//
//  AppSettingsView.swift
//  Droopies
//
//  Réglages complets de l'application :
//  - Langue & Région (tout en haut)
//  - Bloc de configuration des 4 Services Cloud (style Splashscreen avec radio buttons et logos officiels)
//  - Synchronisation & Diagnostic local
//  - À Propos & RGPD
//

import SwiftUI
import AuthenticationServices

public struct AppSettingsView: View {
    @Bindable public var appState: AppState

    @State private var selectedLanguage: AppSettings.AppLanguage = .automatic
    @State private var selectedCloudTab: AppSettings.StorageProviderType = .dropbox

    // Feuilles modales
    @State private var isFolderPickerPresented: Bool = false

    // État de synchronisation
    @State private var isSyncing: Bool = false
    @State private var syncSuccessMessage: String? = nil

    // États Nextcloud
    @AppStorage("droopies_nextcloud_url") private var nextcloudUrl: String = ""
    @AppStorage("droopies_nextcloud_user") private var nextcloudUser: String = ""
    @AppStorage("droopies_nextcloud_pass") private var nextcloudPass: String = ""
    @AppStorage("droopies_nextcloud_folder") private var nextcloudFolder: String = "/Droopies/2026-2027"

    public init(appState: AppState) {
        self.appState = appState
        let savedLang = UserDefaults.standard.string(forKey: "droopies_app_language") ?? "auto"
        _selectedLanguage = State(initialValue: AppSettings.AppLanguage(rawValue: savedLang) ?? .automatic)
        _selectedCloudTab = State(initialValue: appState.storageManager.activeProvider.providerType)
    }

    private var activeRootPath: String {
        let clean = appState.currentRootFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean.isEmpty ? "/" : "/\(clean)"
    }

    private var isDropboxConnected: Bool {
        if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
            return dropbox.isConnected
        }
        return false
    }

    private var dropboxDisplayName: String {
        if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
            return dropbox.accountDisplayName ?? dropbox.accountEmail ?? "Compte personnel"
        }
        return "Compte personnel"
    }

    private var dropboxEmail: String? {
        if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
            return dropbox.accountEmail
        }
        return nil
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 1. Général & Langue
                generalLangCard

                // 2. Stockage & Services Cloud
                cloudStorageCard

                // 3. Synchronisation & Diagnostic Local
                syncDiagnosticCard

                // 4. À Propos & Confidentialité
                aboutPrivacyCard
            }
            .padding(.horizontal, 24)
            #if os(iOS)
            .padding(.top, 8)
            #else
            .padding(.top, 12)
            #endif
            .padding(.bottom, 36)
        }
        .background(Color.clear)
        .sheet(isPresented: $isFolderPickerPresented) {
            CloudFolderPickerSheet(
                provider: appState.storageManager.activeProvider,
                initialPath: appState.currentRootFolderPath
            ) { chosenPath in
                Task {
                    await appState.switchSourceFolder(to: chosenPath)
                }
            }
        }
    }

    // MARK: - 0. En-tête de page Liquid Glass

    private var settingsPageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.t(.settingsTitle))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Paramètres généraux, stockage Cloud et diagnostic")
                .font(.system(size: 13.5))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 2)
    }

    // MARK: - 1. Carte Langue & Région

    private var generalLangCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appState.t(.settingsGeneralLang), systemImage: "globe")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)

            HStack {
                Text(appState.t(.settingsInterfaceLang))
                    .font(.system(size: 13.5))
                    .foregroundColor(.primary)
                Spacer()
                Picker(appState.t(.settingsInterfaceLang), selection: $selectedLanguage) {
                    ForEach(AppSettings.AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLanguage) { _, newLang in
                    UserDefaults.standard.set(newLang.rawValue, forKey: "droopies_app_language")
                    appState.settings.language = newLang
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(white: 0.5, opacity: 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(appState.t(.settingsLangFooter))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .background(Color(white: 0.5, opacity: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 2. Carte Stockage & Services Cloud

    private var cloudStorageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appState.t(.settingsCloudStorage), systemImage: "icloud.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)

            // 4 Gros boutons agissant comme des radiobuttons
            HStack(spacing: 8) {
                cloudRadioButton(
                    type: .dropbox,
                    label: "Dropbox",
                    color: Color(red: 0.0, green: 0.38, blue: 1.0)
                )
                cloudRadioButton(
                    type: .nextcloud,
                    label: "Nextcloud",
                    color: Color(red: 0.0, green: 0.51, blue: 0.79)
                )
                cloudRadioButton(
                    type: .oneDrive,
                    label: "OneDrive",
                    color: Color(red: 0.0, green: 0.47, blue: 0.83)
                )
                cloudRadioButton(
                    type: .googleDrive,
                    label: "Google Drive",
                    color: Color(red: 0.0, green: 0.67, blue: 0.28)
                )
            }

            // Carte de configuration contextuelle sous les 4 boutons
            cloudConfigurationCard

            Text(appState.t(.settingsCloudFooter))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .background(Color(white: 0.5, opacity: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 3. Carte Synchronisation & Diagnostic Local

    private var syncDiagnosticCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appState.t(.settingsSyncCache), systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)

            VStack(spacing: 10) {
                HStack {
                    Label("Connectivité Réseau", systemImage: appState.isOnline ? "wifi" : "bolt.slash.fill")
                        .font(.system(size: 13.5))
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isOnline ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(appState.isOnline ? "Connecté au Cloud" : "Hors-ligne (Cache local)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.isOnline ? .green : .orange)
                    }
                }
                Divider().opacity(0.4)

                HStack {
                    Label(appState.t(.settingsStudentsCount), systemImage: "person.2")
                        .font(.system(size: 13.5))
                    Spacer()
                    Text("\(appState.students.count)")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.secondary)
                }
                Divider().opacity(0.4)

                HStack {
                    Label(appState.t(.settingsClassesCount), systemImage: "rectangle.3.group")
                        .font(.system(size: 13.5))
                    Spacer()
                    Text("\(appState.classes.count)")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.secondary)
                }
                Divider().opacity(0.4)

                HStack {
                    Label(appState.t(.settingsLastSync), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 13.5))
                    Spacer()
                    Text(appState.settings.studentsLastSyncedAt ?? appState.t(.settingsJustNow))
                        .font(.system(size: 13.5))
                        .foregroundColor(.secondary)
                }
                Divider().opacity(0.4)

                Toggle(isOn: Binding(
                    get: { NetworkMonitor.shared.isForcedOffline },
                    set: { NetworkMonitor.shared.isForcedOffline = $0 }
                )) {
                    Label("Simuler le Mode Hors-Ligne (Test)", systemImage: "bolt.slash")
                        .font(.system(size: 13.5))
                }
                .tint(.orange)
            }
            .padding(14)
            .background(Color(white: 0.5, opacity: 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                isSyncing = true
                Task {
                    await appState.loadInitialData()
                    isSyncing = false
                    syncSuccessMessage = appState.t(.settingsReloadSuccess)
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    syncSuccessMessage = nil
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                    Text(appState.t(.settingsReloadFiles))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else if let msg = syncSuccessMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(msg)
                        }
                        .font(.caption.bold())
                        .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.12))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)
        }
        .padding(18)
        .background(Color(white: 0.5, opacity: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 4. Carte À Propos & Confidentialité

    private var aboutPrivacyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appState.t(.settingsAbout), systemImage: "info.circle")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                DroopiesMascotView(size: 48, hasShadow: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Droopies")
                        .font(.headline.weight(.bold))
                    Text(appState.t(.navStudioTeacher))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("v1.0.0 (Swift 6 Native • Universal)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.t(.settingsPrivacy))
                    .font(.subheadline.bold())

                Text(appState.t(.settingsPrivacyDesc))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(18)
        .background(Color(white: 0.5, opacity: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Composant Radiobutton pour le choix du Cloud

    @ViewBuilder
    private func cloudRadioButton(
        type: AppSettings.StorageProviderType,
        label: String,
        color: Color
    ) -> some View {
        let isSelected = selectedCloudTab == type
        let isActiveService = appState.storageManager.activeProvider.providerType == type && appState.storageManager.activeProvider.isConnected

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedCloudTab = type
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 7) {
                    CloudBrandIconView(type: type, size: 26, isSelected: isSelected)
                        .frame(height: 26)

                    Text(label)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: color.opacity(0.35), radius: 6, y: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Pastille verte indiquant le service actuellement actif
                if isActiveService {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Carte de Configuration Dynamique (Selon le Cloud sélectionné)

    @ViewBuilder
    private var cloudConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch selectedCloudTab {
            case .dropbox:
                dropboxConfigView
            case .nextcloud:
                nextcloudConfigView
            case .oneDrive:
                oneDriveConfigView
            case .googleDrive:
                googleDriveConfigView
            case .local:
                EmptyView()
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 1. Configuration Dropbox

    @ViewBuilder
    private var dropboxConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // En-tête
            HStack {
                CloudBrandIconView(type: .dropbox, size: 20)
                Text("Dropbox")
                    .font(.subheadline.bold())

                Spacer()

                if isDropboxConnected {
                    BadgeView(appState.t(.statusConnected), icon: "checkmark.circle.fill", style: .success)
                } else {
                    BadgeView(appState.t(.statusNotConnected), icon: "exclamationmark.circle.fill", style: .warning)
                }
            }

            Divider()

            // Compte associé
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.t(.cloudAccount))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                if isDropboxConnected {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(dropboxDisplayName)
                                .font(.system(size: 13, weight: .semibold))

                            if let email = dropboxEmail {
                                Text(email)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(role: .destructive) {
                            disconnectDropbox()
                        } label: {
                            Text(appState.t(.cloudDisconnect))
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        connectDropbox()
                    } label: {
                        Label(appState.t(.cloudConnect), systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.0, green: 0.38, blue: 1.0))
                }
            }

            // Dossier Source dans Dropbox
            if isDropboxConnected {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.t(.cloudFolder))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)

                        Text(activeRootPath)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            isFolderPickerPresented = true
                        } label: {
                            Label(appState.t(.navChangeFolder), systemImage: "folder.badge.gearshape")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - 2. Configuration Nextcloud

    @ViewBuilder
    private var nextcloudConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CloudBrandIconView(type: .nextcloud, size: 20)
                Text("Nextcloud / Nuage Éducation")
                    .font(.subheadline.bold())

                Spacer()

                BadgeView(appState.t(.statusConfigurable), icon: "gearshape.fill", style: .warning)
            }

            Text(appState.t(.cloudNextcloudDesc))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Adresse du serveur WebDAV :")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("https://nuage03.apps.education.fr/remote.php/dav/files/...", text: $nextcloudUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Identifiant académique :")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("prenom.nom", text: $nextcloudUser)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mot de passe d'application :")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        SecureField("••••••••••••", text: $nextcloudPass)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Dossier Source dans Nextcloud :")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("/Droopies/2026-2027", text: $nextcloudFolder)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - 3. Information OneDrive

    @ViewBuilder
    private var oneDriveConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CloudBrandIconView(type: .oneDrive, size: 20)
                Text("Microsoft OneDrive")
                    .font(.subheadline.bold())

                Spacer()

                BadgeView(appState.t(.statusComingSoon), icon: "clock.badge.exclamationmark", style: .neutral)
            }

            Text(appState.t(.cloudOneDriveDesc))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.blue)
                Text("Compatible avec les comptes scolaires Microsoft 365 Éducation & Entra ID")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 4. Information Google Drive

    @ViewBuilder
    private var googleDriveConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CloudBrandIconView(type: .googleDrive, size: 20)
                Text("Google Drive")
                    .font(.subheadline.bold())

                Spacer()

                BadgeView(appState.t(.statusComingSoon), icon: "clock.badge.exclamationmark", style: .neutral)
            }

            Text(appState.t(.cloudGoogleDriveDesc))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Text("Compatible avec Google Workspace for Education & Google Classroom")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions Dropbox

    private func connectDropbox() {
        Task {
            do {
                let session = try await DropboxOAuthManager.shared.signInWithDropbox()
                let provider = DropboxStorageProvider()
                provider.configure(session: session, rootFolderPath: appState.currentRootFolderPath)

                await MainActor.run {
                    appState.storageManager.setProvider(provider)
                }
                await appState.loadInitialData()
            } catch {
                // Annulé ou erreur gérée
            }
        }
    }

    private func disconnectDropbox() {
        Task {
            let provider = DropboxStorageProvider()
            try? await provider.disconnect()
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "droopies_dropbox_token")
                UserDefaults.standard.removeObject(forKey: "droopies_dropbox_refresh_token")
                Task {
                    await appState.loadInitialData()
                }
            }
        }
    }
}
