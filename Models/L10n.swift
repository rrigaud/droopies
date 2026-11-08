//
//  L10n.swift
//  Droopies
//
//  Moteur de localisation complet et réactif pour Droopies.
//  Supporte nativement : Français (France), Français (Canada), English, Español, Italiano, Deutsch.
//

import SwiftUI

public typealias AppLanguage = AppSettings.AppLanguage

public enum L10nKey: String, CaseIterable, Sendable {
    // MARK: - Navigation & Sidebar
    case navCorrection = "nav_correction"

    // MARK: - Barres Flottantes & Modes Principaux
    case tabCorrection = "tab_correction"
    case tabDistribution = "tab_distribution"

    case navStudents = "nav_students"
    case navPortal = "nav_portal"
    case navSettings = "nav_settings"
    case navStudioTeacher = "nav_studio_teacher"
    case navActiveStorage = "nav_active_storage"
    case navSourceFolder = "nav_source_folder"
    case navChangeFolder = "nav_change_folder"
    case navChangeCloud = "nav_change_cloud"
    case navReloadData = "nav_reload_data"
    case navCorrectionFlow = "nav_correction_flow"
    case navSchoolAdmin = "nav_school_admin"
    case navConfiguration = "nav_configuration"

    // MARK: - Réglages
    case settingsTitle = "settings_title"
    case settingsGeneralLang = "settings_general_lang"
    case settingsInterfaceLang = "settings_interface_lang"
    case settingsLangFooter = "settings_lang_footer"
    case settingsCloudStorage = "settings_cloud_storage"
    case settingsCloudFooter = "settings_cloud_footer"
    case settingsSyncCache = "settings_sync_cache"
    case settingsStudentsCount = "settings_students_count"
    case settingsClassesCount = "settings_classes_count"
    case settingsLastSync = "settings_last_sync"
    case settingsJustNow = "settings_just_now"
    case settingsReloadFiles = "settings_reload_files"
    case settingsReloadSuccess = "settings_reload_success"
    case settingsAbout = "settings_about"
    case settingsPrivacy = "settings_privacy"
    case settingsPrivacyDesc = "settings_privacy_desc"

    // MARK: - Statuts Cloud
    case statusConnected = "status_connected"
    case statusConfigurable = "status_configurable"
    case statusNotConnected = "status_not_connected"
    case statusComingSoon = "status_coming_soon"

    // MARK: - Réglages Cloud Détaillés
    case cloudAccount = "cloud_account"
    case cloudFolder = "cloud_folder"
    case cloudDisconnect = "cloud_disconnect"
    case cloudConnect = "cloud_connect"
    case cloudNextcloudDesc = "cloud_nextcloud_desc"
    case cloudOneDriveDesc = "cloud_onedrive_desc"
    case cloudGoogleDriveDesc = "cloud_googledrive_desc"


    // MARK: - Gestion des Élèves
    case studentsTitle = "students_title"
    case studentsAdd = "students_add"
    case studentsImportCSV = "students_import_csv"
    case studentsGenerateFolders = "students_generate_folders"
    case studentsGeneratePasswords = "students_generate_passwords"
    case studentsPrintLabels = "students_print_labels"
    case labelsBatchTitle = "labels_batch_title"
    case labelsFilename = "labels_filename"
    case memoBatchTitle = "memo_batch_title"
    case memoFilename = "memo_filename"
    case btnGeneratePDF = "btn_generate_pdf"
    case missingSharesWarning = "missing_shares_warning"
    case activateMissingShares = "activate_missing_shares"
    case pdfGeneratedSuccess = "pdf_generated_success"
    case studentsSearchPlaceholder = "students_search_placeholder"
    case studentLastName = "student_last_name"
    case studentFirstName = "student_first_name"
    case studentClass = "student_class"
    case studentEmail = "student_email"
    case studentPasscode = "student_passcode"
    case studentEdit = "student_edit"
    case studentDeleteConfirm = "student_delete_confirm"

    // MARK: - Studio de Correction
    case correctionTitle = "correction_title"
    case correctionStep1 = "correction_step1"
    case correctionStep2 = "correction_step2"
    case correctionStep3 = "correction_step3"
    case correctionStep4 = "correction_step4"
    case correctionScore20 = "correction_score_20"
    case correctionCriteria = "correction_criteria"
    case correctionComment = "correction_comment"
    case correctionPrevCopy = "correction_prev_copy"
    case correctionNextCopy = "correction_next_copy"
    case correctionFinish = "correction_finish"

    // MARK: - Portail Élèves
    case portalTitle = "portal_title"
    case portalUrl = "portal_url"
    case portalTheme = "portal_theme"
    case portalPublish = "portal_publish"

    // MARK: - Actions Générales
    case actionSave = "action_save"
    case actionCancel = "action_cancel"
    case actionDelete = "action_delete"
    case actionConfirm = "action_confirm"
    case actionClose = "action_close"
    case actionBack = "action_back"
    case actionNext = "action_next"
    case actionLoading = "action_loading"
}

public struct L10n: Sendable {
    private static let translations: [String: [L10nKey: String]] = [
        // ==========================================
        // 🇫🇷 FRANÇAIS (FRANCE)
        // ==========================================
        "fr": [
            .navCorrection: "Correction d'un devoir",
            .tabCorrection: "Correction",
            .tabDistribution: "Distribution",
            .navStudents: "Gestion des Élèves",
            .navPortal: "Portail Élèves",
            .navSettings: "Réglages & Cloud",
            .navStudioTeacher: "Studio Enseignant",
            .navActiveStorage: "Stockage Actif",
            .navSourceFolder: "Dossier :",
            .navChangeFolder: "Changer de dossier Source...",
            .navChangeCloud: "Changer de compte ou de Cloud...",
            .navReloadData: "Actualiser",
            .navCorrectionFlow: "Flux de Correction",
            .navSchoolAdmin: "Administration Scolaire",
            .navConfiguration: "Configuration",

            .settingsTitle: "Réglages & Cloud",
            .settingsGeneralLang: "Général & Langue",
            .settingsInterfaceLang: "Langue de l'interface",
            .settingsLangFooter: "Par défaut sur 'Automatique', Droopies adopte la langue configurée sur votre iPad ou Mac. Vous pouvez forcer ici une langue spécifique.",
            .settingsCloudStorage: "Stockage & Services Cloud",
            .settingsCloudFooter: "Droopies fonctionne à 100% avec votre Cloud personnel ou institutionnel. Aucun serveur tiers n'intervient.",
            .settingsSyncCache: "Synchronisation & Cache Local",
            .settingsStudentsCount: "Élèves répertoriés",
            .settingsClassesCount: "Classes configurées",
            .settingsLastSync: "Dernière synchronisation",
            .settingsJustNow: "À l'instant",
            .settingsReloadFiles: "Recharger eleves.json et settings.json",
            .settingsReloadSuccess: "Données rechargées avec succès !",
            .settingsAbout: "À Propos",
            .settingsPrivacy: "Confidentialité & RGPD",
            .settingsPrivacyDesc: "Droopies est conçu dans le strict respect de la vie privée des enseignants et des élèves. Les devoirs, les copies corrigées et les listes d'élèves restent exclusivement hébergés dans votre dossier Cloud et sur votre appareil.",

            .statusConnected: "Connecté",
            .statusConfigurable: "Configurable",
            .statusNotConnected: "Non connecté",
            .statusComingSoon: "Bientôt disponible",
            .cloudAccount: "Compte & Connexion",
            .cloudFolder: "Dossier Source Enseignant",
            .cloudDisconnect: "Se déconnecter",
            .cloudConnect: "Se connecter à Dropbox",
            .cloudNextcloudDesc: "Support du protocole WebDAV pour le cloud académique (apps.education.fr) ou serveur personnel.",
            .cloudOneDriveDesc: "Intégration de l'API Microsoft Graph (Microsoft 365 Éducation) en cours de développement.",
            .cloudGoogleDriveDesc: "Intégration de l'API Google Drive v3 (Google Workspace for Education) en cours de développement.",

            .studentsTitle: "Gestion des Élèves",
            .studentsAdd: "Ajouter un élève",
            .studentsImportCSV: "Importer CSV",
            .studentsGenerateFolders: "Générer les dossiers",
            .studentsGeneratePasswords: "Générer mots de passe",
            .studentsPrintLabels: "Imprimer planches",
            .labelsBatchTitle: "Étiquettes de connexion (QR)",
            .labelsFilename: "Droopies - Etiquettes de connexion.pdf",
            .memoBatchTitle: "Mémo des Accès Élèves",
            .memoFilename: "Droopies - Memo Acces Eleves.pdf",
            .btnGeneratePDF: "Générer le PDF",
            .missingSharesWarning: "Certains élèves n'ont pas encore de partage actif. Le QR Code ne peut pas être généré.",
            .activateMissingShares: "Activer les partages manquants",
            .pdfGeneratedSuccess: "Document enregistré dans le dossier Exports et ouvert avec succès !",
            .studentsSearchPlaceholder: "Rechercher par nom, prénom, classe...",
            .studentLastName: "Nom",
            .studentFirstName: "Prénom",
            .studentClass: "Classe",
            .studentEmail: "Email",
            .studentPasscode: "Code d'accès",
            .studentEdit: "Modifier l'élève",
            .studentDeleteConfirm: "Voulez-vous vraiment supprimer cet élève ?",

            .correctionTitle: "Correction d'un devoir",
            .correctionStep1: "Studio de correction",
            .correctionStep2: "Chargement des copies",
            .correctionStep3: "Identification",
            .correctionStep4: "Distribution",
            .correctionScore20: "Note globale sur 20",
            .correctionCriteria: "Grille de critères",
            .correctionComment: "Commentaire enseignant",
            .correctionPrevCopy: "Copie précédente",
            .correctionNextCopy: "Copie suivante",
            .correctionFinish: "Terminer la correction",

            .portalTitle: "Portail Élèves",
            .portalUrl: "URL du portail",
            .portalTheme: "Thème visuel",
            .portalPublish: "Publier les devoirs",

            .actionSave: "Enregistrer",
            .actionCancel: "Annuler",
            .actionDelete: "Supprimer",
            .actionConfirm: "Confirmer",
            .actionClose: "Fermer",
            .actionBack: "Retour",
            .actionNext: "Suivant",
            .actionLoading: "Chargement..."
        ],

        // ==========================================
        // 🇨🇦 FRANÇAIS (CANADA)
        // ==========================================
        "fr-CA": [
            .navCorrection: "Correction d'une évaluation",
            .tabCorrection: "Correction",
            .tabDistribution: "Distribution",
            .navStudents: "Gestion des Élèves",
            .navPortal: "Portail Élèves",
            .navSettings: "Réglages & Nuage",
            .navStudioTeacher: "Studio Enseignant",
            .navActiveStorage: "Stockage Actif",
            .navSourceFolder: "Dossier :",
            .navChangeFolder: "Changer de dossier Source...",
            .navChangeCloud: "Changer de compte ou de nuage...",
            .navReloadData: "Actualiser",
            .navCorrectionFlow: "Flux d'évaluation",
            .navSchoolAdmin: "Administration Scolaire",
            .navConfiguration: "Configuration",

            .settingsTitle: "Réglages & Nuage",
            .settingsGeneralLang: "Général & Langue",
            .settingsInterfaceLang: "Langue de l'interface",
            .settingsLangFooter: "Par défaut sur 'Automatique', Droopies adopte la langue configurée sur votre iPad ou Mac. Vous pouvez forcer ici une langue spécifique.",
            .settingsCloudStorage: "Stockage & Services Nuage",
            .settingsCloudFooter: "Droopies fonctionne à 100% avec votre nuage personnel ou scolaire. Aucun serveur tiers n'intervient.",
            .settingsSyncCache: "Synchronisation & Cache Local",
            .settingsStudentsCount: "Élèves répertoriés",
            .settingsClassesCount: "Groupes configurés",
            .settingsLastSync: "Dernière synchronisation",
            .settingsJustNow: "À l'instant",
            .settingsReloadFiles: "Recharger eleves.json et settings.json",
            .settingsReloadSuccess: "Données rechargées avec succès !",
            .settingsAbout: "À Propos",
            .settingsPrivacy: "Confidentialité & Protection des données",
            .settingsPrivacyDesc: "Droopies respecte la vie privée des enseignants et des élèves. Les devoirs, copies annotées et listes d'élèves restent strictement hébergés dans votre nuage et sur votre appareil.",

            .statusConnected: "Connecté",
            .statusConfigurable: "Configurable",
            .statusNotConnected: "Non connecté",
            .statusComingSoon: "Bientôt disponible",
            .cloudAccount: "Compte & Connexion",
            .cloudFolder: "Dossier Source Enseignant",
            .cloudDisconnect: "Se déconnecter",
            .cloudConnect: "Se connecter à Dropbox",
            .cloudNextcloudDesc: "Support du protocole WebDAV pour le cloud académique (apps.education.fr) ou serveur personnel.",
            .cloudOneDriveDesc: "Intégration de l'API Microsoft Graph (Microsoft 365 Éducation) en cours de développement.",
            .cloudGoogleDriveDesc: "Intégration de l'API Google Drive v3 (Google Workspace for Education) en cours de développement.",

            .studentsTitle: "Gestion des Élèves",
            .studentsAdd: "Ajouter un élève",
            .studentsImportCSV: "Importer CSV",
            .studentsGenerateFolders: "Générer les dossiers",
            .studentsGeneratePasswords: "Générer les NIP",
            .studentsPrintLabels: "Imprimer les étiquettes",
            .labelsBatchTitle: "Étiquettes de connexion (QR)",
            .labelsFilename: "Droopies - Etiquettes de connexion.pdf",
            .memoBatchTitle: "Mémo des Accès Élèves",
            .memoFilename: "Droopies - Memo Acces Eleves.pdf",
            .btnGeneratePDF: "Générer le PDF",
            .missingSharesWarning: "Certains élèves n'ont pas encore de partage actif. Le code QR ne peut pas être généré.",
            .activateMissingShares: "Activer les partages manquants",
            .pdfGeneratedSuccess: "Document PDF enregistré à la racine du dossier Source et ouvert avec succès !",
            .studentsSearchPlaceholder: "Rechercher par nom, prénom, groupe...",
            .studentLastName: "Nom",
            .studentFirstName: "Prénom",
            .studentClass: "Groupe / Classe",
            .studentEmail: "Courriel",
            .studentPasscode: "Code secret (NIP)",
            .studentEdit: "Modifier l'élève",
            .studentDeleteConfirm: "Voulez-vous vraiment supprimer cet élève ?",

            .correctionTitle: "Correction d'une évaluation",
            .correctionStep1: "Studio de correction",
            .correctionStep2: "Chargement des copies",
            .correctionStep3: "Identification",
            .correctionStep4: "Distribution",
            .correctionScore20: "Note globale sur 20",
            .correctionCriteria: "Grille d'évaluation",
            .correctionComment: "Commentaire de l'enseignant",
            .correctionPrevCopy: "Copie précédente",
            .correctionNextCopy: "Copie suivante",
            .correctionFinish: "Terminer la correction",

            .portalTitle: "Portail Élèves",
            .portalUrl: "URL du portail",
            .portalTheme: "Thème visuel",
            .portalPublish: "Publier les évaluations",

            .actionSave: "Enregistrer",
            .actionCancel: "Annuler",
            .actionDelete: "Supprimer",
            .actionConfirm: "Confirmer",
            .actionClose: "Fermer",
            .actionBack: "Retour",
            .actionNext: "Suivant",
            .actionLoading: "Chargement..."
        ],

        // ==========================================
        // 🇬🇧 ENGLISH (US / UK)
        // ==========================================
        "en": [
            .navCorrection: "Grade an Assignment",
            .tabCorrection: "Correction",
            .tabDistribution: "Distribution",
            .navStudents: "Student Management",
            .navPortal: "Student Portal",
            .navSettings: "Settings & Cloud",
            .navStudioTeacher: "Teacher Studio",
            .navActiveStorage: "Active Storage",
            .navSourceFolder: "Folder:",
            .navChangeFolder: "Change Source Folder...",
            .navChangeCloud: "Switch Account or Cloud...",
            .navReloadData: "Refresh",
            .navCorrectionFlow: "Grading Flow",
            .navSchoolAdmin: "School Administration",
            .navConfiguration: "Configuration",

            .settingsTitle: "Settings & Cloud",
            .settingsGeneralLang: "General & Language",
            .settingsInterfaceLang: "Interface Language",
            .settingsLangFooter: "Set to 'Automatic', Droopies matches your iPad or Mac system language. You can override it here at any time.",
            .settingsCloudStorage: "Cloud Storage & Services",
            .settingsCloudFooter: "Droopies connects directly to your own personal or institutional cloud. No third-party servers involved.",
            .settingsSyncCache: "Synchronization & Local Cache",
            .settingsStudentsCount: "Enrolled Students",
            .settingsClassesCount: "Configured Classes",
            .settingsLastSync: "Last Synced",
            .settingsJustNow: "Just now",
            .settingsReloadFiles: "Reload eleves.json and settings.json",
            .settingsReloadSuccess: "Data successfully reloaded!",
            .settingsAbout: "About Droopies",
            .settingsPrivacy: "Privacy & GDPR Compliance",
            .settingsPrivacyDesc: "Droopies is architected to guarantee total teacher and student privacy. Student records, tests, and graded copies remain exclusively in your cloud folder and on your device.",

            .statusConnected: "Connected",
            .statusConfigurable: "Configurable",
            .statusNotConnected: "Not connected",
            .statusComingSoon: "Coming soon",
            .cloudAccount: "Account & Connection",
            .cloudFolder: "Teacher Source Folder",
            .cloudDisconnect: "Sign Out",
            .cloudConnect: "Sign in with Dropbox",
            .cloudNextcloudDesc: "Native WebDAV support for academic clouds (apps.education.fr) or private Nextcloud servers.",
            .cloudOneDriveDesc: "Microsoft Graph API integration (Microsoft 365 Education) currently in development.",
            .cloudGoogleDriveDesc: "Google Drive API v3 integration (Google Workspace for Education) currently in development.",

            .studentsTitle: "Student Management",
            .studentsAdd: "Add a Student",
            .studentsImportCSV: "Import CSV",
            .studentsGenerateFolders: "Generate Folders",
            .studentsGeneratePasswords: "Generate Passcodes",
            .studentsPrintLabels: "Print Label Sheets",
            .labelsBatchTitle: "Connection Labels (QR)",
            .labelsFilename: "Connection Labels (QR).pdf",
            .memoBatchTitle: "Student Access Memo",
            .memoFilename: "Student Access Memo.pdf",
            .btnGeneratePDF: "Generate PDF",
            .missingSharesWarning: "Some students do not have active sharing links. QR code cannot be generated.",
            .activateMissingShares: "Activate Missing Shares",
            .pdfGeneratedSuccess: "PDF document saved to Source folder root and opened successfully!",
            .studentsSearchPlaceholder: "Search by name, class, email...",
            .studentLastName: "Last Name",
            .studentFirstName: "First Name",
            .studentClass: "Class / Grade",
            .studentEmail: "Email",
            .studentPasscode: "Access Code",
            .studentEdit: "Edit Student",
            .studentDeleteConfirm: "Are you sure you want to delete this student?",

            .correctionTitle: "Grade an Assignment",
            .correctionStep1: "Grading Studio",
            .correctionStep2: "Loading Copies",
            .correctionStep3: "Student Matching",
            .correctionStep4: "Distribution",
            .correctionScore20: "Overall Score /20",
            .correctionCriteria: "Evaluation Rubric",
            .correctionComment: "Teacher Feedback",
            .correctionPrevCopy: "Previous Copy",
            .correctionNextCopy: "Next Copy",
            .correctionFinish: "Complete Grading",

            .portalTitle: "Student Portal",
            .portalUrl: "Portal URL",
            .portalTheme: "Color Theme",
            .portalPublish: "Publish Assignments",

            .actionSave: "Save",
            .actionCancel: "Cancel",
            .actionDelete: "Delete",
            .actionConfirm: "Confirm",
            .actionClose: "Close",
            .actionBack: "Back",
            .actionNext: "Next",
            .actionLoading: "Loading..."
        ],

        // ==========================================
        // 🇪🇸 ESPAÑOL
        // ==========================================
        "es": [
            .navCorrection: "Corregir una tarea",
            .tabCorrection: "Corrección",
            .tabDistribution: "Distribución",
            .navStudents: "Gestión de Alumnos",
            .navPortal: "Portal de Alumnos",
            .navSettings: "Ajustes y Nube",
            .navStudioTeacher: "Estudio Docente",
            .navActiveStorage: "Almacenamiento Activo",
            .navSourceFolder: "Carpeta:",
            .navChangeFolder: "Cambiar carpeta de origen...",
            .navChangeCloud: "Cambiar cuenta o nube...",
            .navReloadData: "Recargar datos",
            .navCorrectionFlow: "Flujo de Corrección",
            .navSchoolAdmin: "Administración Escolar",
            .navConfiguration: "Configuración",

            .settingsTitle: "Ajustes y Nube",
            .settingsGeneralLang: "General e Idioma",
            .settingsInterfaceLang: "Idioma de la interfaz",
            .settingsLangFooter: "En 'Automático', Droopies adopta el idioma de tu iPad o Mac. Puedes forzar un idioma específico aquí.",
            .settingsCloudStorage: "Almacenamiento y Servicios Nube",
            .settingsCloudFooter: "Droopies funciona al 100% con tu nube personal o institucional. Ningún servidor externo interviene.",
            .settingsSyncCache: "Sincronización y Caché Local",
            .settingsStudentsCount: "Alumnos registrados",
            .settingsClassesCount: "Clases configuradas",
            .settingsLastSync: "Última sincronización",
            .settingsJustNow: "Hace un momento",
            .settingsReloadFiles: "Recargar eleves.json y settings.json",
            .settingsReloadSuccess: "¡Datos recargados con éxito!",
            .settingsAbout: "Acerca de Droopies",
            .settingsPrivacy: "Privacidad y RGPD",
            .settingsPrivacyDesc: "Droopies está diseñado para proteger la privacidad docente y estudiantil. Los exámenes, notas y listas permanecen exclusivamente en tu nube y dispositivo.",

            .statusConnected: "Conectado",
            .statusConfigurable: "Configurable",
            .statusNotConnected: "No conectado",
            .statusComingSoon: "Próximamente",
            .cloudAccount: "Cuenta y Conexión",
            .cloudFolder: "Carpeta de Origen",
            .cloudDisconnect: "Cerrar sesión",
            .cloudConnect: "Iniciar sesión con Dropbox",
            .cloudNextcloudDesc: "Soporte nativo WebDAV para nube académica o servidor Nextcloud personal.",
            .cloudOneDriveDesc: "Integración con Microsoft Graph API (Microsoft 365 Educación) en desarrollo.",
            .cloudGoogleDriveDesc: "Integración con Google Drive API v3 (Google Workspace for Education) en desarrollo.",

            .studentsTitle: "Gestión de Alumnos",
            .studentsAdd: "Añadir un alumno",
            .studentsImportCSV: "Importar CSV",
            .studentsGenerateFolders: "Generar carpetas",
            .studentsGeneratePasswords: "Generar contraseñas",
            .studentsPrintLabels: "Imprimir etiquetas",
            .labelsBatchTitle: "Etiquetas de conexión (QR)",
            .labelsFilename: "Etiquetas de conexion (QR).pdf",
            .memoBatchTitle: "Memorando de Accesos de Alumnos",
            .memoFilename: "Memorando accesos alumnos.pdf",
            .btnGeneratePDF: "Generar PDF",
            .missingSharesWarning: "Algunos alumnos no tienen enlaces compartidos activos. No se puede generar el código QR.",
            .activateMissingShares: "Activar recursos compartidos",
            .pdfGeneratedSuccess: "¡Documento PDF guardado en la carpeta de origen y abierto con éxito!",
            .studentsSearchPlaceholder: "Buscar por nombre, apellido, clase...",
            .studentLastName: "Apellido",
            .studentFirstName: "Nombre",
            .studentClass: "Clase / Grupo",
            .studentEmail: "Correo electrónico",
            .studentPasscode: "Código de acceso",
            .studentEdit: "Editar alumno",
            .studentDeleteConfirm: "¿Seguro que deseas eliminar este alumno?",

            .correctionTitle: "Corregir una tarea",
            .correctionStep1: "Estudio de corrección",
            .correctionStep2: "Carga de exámenes",
            .correctionStep3: "Identificación de alumnos",
            .correctionStep4: "Distribución",
            .correctionScore20: "Nota global sobre 20",
            .correctionCriteria: "Rúbrica de evaluación",
            .correctionComment: "Comentarios del profesor",
            .correctionPrevCopy: "Copia anterior",
            .correctionNextCopy: "Copia siguiente",
            .correctionFinish: "Finalizar corrección",

            .portalTitle: "Portal de Alumnos",
            .portalUrl: "URL del portal",
            .portalTheme: "Tema visual",
            .portalPublish: "Publicar tareas",

            .actionSave: "Guardar",
            .actionCancel: "Cancelar",
            .actionDelete: "Eliminar",
            .actionConfirm: "Confirmar",
            .actionClose: "Cerrar",
            .actionBack: "Atrás",
            .actionNext: "Siguiente",
            .actionLoading: "Cargando..."
        ],

        // ==========================================
        // 🇮🇹 ITALIANO
        // ==========================================
        "it": [
            .navCorrection: "Correzione di un compito",
            .tabCorrection: "Correzione",
            .tabDistribution: "Distribuzione",
            .navStudents: "Gestione Studenti",
            .navPortal: "Portale Studenti",
            .navSettings: "Impostazioni e Cloud",
            .navStudioTeacher: "Studio Docente",
            .navActiveStorage: "Archiviazione Attiva",
            .navSourceFolder: "Cartella:",
            .navChangeFolder: "Cambia cartella di origine...",
            .navChangeCloud: "Cambia account o cloud...",
            .navReloadData: "Ricarica dati",
            .navCorrectionFlow: "Flusso di Correzione",
            .navSchoolAdmin: "Amministrazione Scolastica",
            .navConfiguration: "Configurazione",

            .settingsTitle: "Impostazioni e Cloud",
            .settingsGeneralLang: "Generale e Lingua",
            .settingsInterfaceLang: "Lingua dell'interfaccia",
            .settingsLangFooter: "Su 'Automatico', Droopies adotta la lingua configurata su iPad o Mac. Puoi scegliere una lingua specifica qui.",
            .settingsCloudStorage: "Archiviazione e Servizi Cloud",
            .settingsCloudFooter: "Droopies funziona al 100% con il tuo cloud personale o scolastico. Nessun server terzo coinvolto.",
            .settingsSyncCache: "Sincronizzazione e Cache Locale",
            .settingsStudentsCount: "Studenti registrati",
            .settingsClassesCount: "Classi configurate",
            .settingsLastSync: "Ultima sincronizzazione",
            .settingsJustNow: "Proprio ora",
            .settingsReloadFiles: "Ricarica eleves.json e settings.json",
            .settingsReloadSuccess: "Dati ricaricati con successo!",
            .settingsAbout: "Informazioni su Droopies",
            .settingsPrivacy: "Privacy e GDPR",
            .settingsPrivacyDesc: "Droopies è progettato nel pieno rispetto della privacy scolastica. Compiti, voti ed elenchi studenti rimangono esclusivamente nel tuo cloud e sul dispositivo.",

            .statusConnected: "Connesso",
            .statusConfigurable: "Configurabile",
            .statusNotConnected: "Non connesso",
            .statusComingSoon: "Prossimamente",
            .cloudAccount: "Account e Connessione",
            .cloudFolder: "Cartella di Origine",
            .cloudDisconnect: "Disconnetti",
            .cloudConnect: "Accedi con Dropbox",
            .cloudNextcloudDesc: "Supporto nativo WebDAV per cloud scolastici o server Nextcloud privati.",
            .cloudOneDriveDesc: "Integrazione Microsoft Graph API (Microsoft 365 Education) in sviluppo.",
            .cloudGoogleDriveDesc: "Integrazione Google Drive API v3 (Google Workspace for Education) in sviluppo.",

            .studentsTitle: "Gestione Studenti",
            .studentsAdd: "Aggiungi studente",
            .studentsImportCSV: "Importa CSV",
            .studentsGenerateFolders: "Genera cartelle",
            .studentsGeneratePasswords: "Genera password",
            .studentsPrintLabels: "Stampa etichette",
            .labelsBatchTitle: "Etichette di connessione (QR)",
            .labelsFilename: "Etichette di connessione (QR).pdf",
            .memoBatchTitle: "Promemoria Accessi Studenti",
            .memoFilename: "Promemoria accessi studenti.pdf",
            .btnGeneratePDF: "Genera PDF",
            .missingSharesWarning: "Alcuni studenti non hanno un link di condivisione attivo. Il codice QR non può essere generato.",
            .activateMissingShares: "Attiva condivisioni mancanti",
            .pdfGeneratedSuccess: "Documento PDF salvato nella cartella Sorgente e aperto con successo!",
            .studentsSearchPlaceholder: "Cerca per nome, cognome, classe...",
            .studentLastName: "Cognome",
            .studentFirstName: "Nome",
            .studentClass: "Classe",
            .studentEmail: "Email",
            .studentPasscode: "Codice di accesso",
            .studentEdit: "Modifica studente",
            .studentDeleteConfirm: "Vuoi davvero eliminare questo studente?",

            .correctionTitle: "Correzione di un compito",
            .correctionStep1: "Studio di correzione",
            .correctionStep2: "Caricamento compiti",
            .correctionStep3: "Identificazione",
            .correctionStep4: "Distribuzione",
            .correctionScore20: "Voto complessivo su 20",
            .correctionCriteria: "Griglia di valutazione",
            .correctionComment: "Commento del docente",
            .correctionPrevCopy: "Compito precedente",
            .correctionNextCopy: "Compito successivo",
            .correctionFinish: "Termina correzione",

            .portalTitle: "Portale Studenti",
            .portalUrl: "URL del portale",
            .portalTheme: "Tema visivo",
            .portalPublish: "Pubblica compiti",

            .actionSave: "Salva",
            .actionCancel: "Annulla",
            .actionDelete: "Elimina",
            .actionConfirm: "Conferma",
            .actionClose: "Chiudi",
            .actionBack: "Indietro",
            .actionNext: "Avanti",
            .actionLoading: "Caricamento..."
        ],

        // ==========================================
        // 🇩🇪 DEUTSCH
        // ==========================================
        "de": [
            .navCorrection: "Aufgabe korrigieren",
            .tabCorrection: "Korrektur",
            .tabDistribution: "Verteilung",
            .navStudents: "Schülerverwaltung",
            .navPortal: "Schülerportal",
            .navSettings: "Einstellungen & Cloud",
            .navStudioTeacher: "Lehrer-Studio",
            .navActiveStorage: "Aktiver Speicher",
            .navSourceFolder: "Ordner:",
            .navChangeFolder: "Quellordner ändern...",
            .navChangeCloud: "Konto oder Cloud wechseln...",
            .navReloadData: "Daten neu laden",
            .navCorrectionFlow: "Korrektur-Workflow",
            .navSchoolAdmin: "Schulverwaltung",
            .navConfiguration: "Konfiguration",

            .settingsTitle: "Einstellungen & Cloud",
            .settingsGeneralLang: "Allgemein & Sprache",
            .settingsInterfaceLang: "Oberflächensprache",
            .settingsLangFooter: "Auf 'Automatisch' passt sich Droopies der Sprache Ihres iPad oder Mac an. Hier können Sie eine Sprache festlegen.",
            .settingsCloudStorage: "Speicher & Cloud-Dienste",
            .settingsCloudFooter: "Droopies arbeitet zu 100% mit Ihrer persönlichen oder schulischen Cloud. Keine Drittanbieter-Server.",
            .settingsSyncCache: "Synchronisierung & Lokaler Cache",
            .settingsStudentsCount: "Erfasste Schüler",
            .settingsClassesCount: "Konfigurierte Klassen",
            .settingsLastSync: "Letzte Synchronisierung",
            .settingsJustNow: "Gerade eben",
            .settingsReloadFiles: "eleves.json und settings.json neu laden",
            .settingsReloadSuccess: "Daten erfolgreich neu geladen!",
            .settingsAbout: "Über Droopies",
            .settingsPrivacy: "Datenschutz & DSGVO",
            .settingsPrivacyDesc: "Droopies garantiert vollständigen Schutz der Privatsphäre von Lehrern und Schülern. Alle Daten verbleiben ausschließlich in Ihrer Cloud und auf Ihrem Gerät.",

            .statusConnected: "Verbunden",
            .statusConfigurable: "Konfigurierbar",
            .statusNotConnected: "Nicht verbunden",
            .statusComingSoon: "Demnächst verfügbar",
            .cloudAccount: "Konto & Verbindung",
            .cloudFolder: "Lehrer-Quellordner",
            .cloudDisconnect: "Abmelden",
            .cloudConnect: "Mit Dropbox anmelden",
            .cloudNextcloudDesc: "Nativer WebDAV-Support für Schul-Clouds oder eigene Nextcloud-Server.",
            .cloudOneDriveDesc: "Microsoft Graph API Integration (Microsoft 365 Education) in Entwicklung.",
            .cloudGoogleDriveDesc: "Google Drive API v3 Integration (Google Workspace for Education) in Entwicklung.",

            .studentsTitle: "Schülerverwaltung",
            .studentsAdd: "Schüler hinzufügen",
            .studentsImportCSV: "CSV importieren",
            .studentsGenerateFolders: "Ordner erstellen",
            .studentsGeneratePasswords: "Passwörter generieren",
            .studentsPrintLabels: "Etiketten drucken",
            .labelsBatchTitle: "Zugangsetiketten (QR)",
            .labelsFilename: "Zugangsetiketten (QR).pdf",
            .memoBatchTitle: "Schüler-Zugangsübersicht",
            .memoFilename: "Schueler-Zugangsuebersicht.pdf",
            .btnGeneratePDF: "PDF erstellen",
            .missingSharesWarning: "Einige Schüler verfügen über keinen aktiven Freigabelink. Der QR-Code kann nicht erstellt werden.",
            .activateMissingShares: "Fehlende Freigaben aktivieren",
            .pdfGeneratedSuccess: "PDF-Dokument im Quellordner gespeichert und erfolgreich geöffnet!",
            .studentsSearchPlaceholder: "Nach Name, Vorname, Klasse suchen...",
            .studentLastName: "Nachname",
            .studentFirstName: "Vorname",
            .studentClass: "Klasse",
            .studentEmail: "E-Mail",
            .studentPasscode: "Zugangscode",
            .studentEdit: "Schüler bearbeiten",
            .studentDeleteConfirm: "Möchten Sie diesen Schüler wirklich löschen?",

            .correctionTitle: "Aufgabe korrigieren",
            .correctionStep1: "Korrekturstudio",
            .correctionStep2: "Arbeiten laden",
            .correctionStep3: "Schülerzuordnung",
            .correctionStep4: "Verteilung",
            .correctionScore20: "Gesamtnote auf 20",
            .correctionCriteria: "Kriterienraster",
            .correctionComment: "Lehrer-Rückmeldung",
            .correctionPrevCopy: "Vorherige Arbeit",
            .correctionNextCopy: "Nächste Arbeit",
            .correctionFinish: "Korrektur abschließen",

            .portalTitle: "Schülerportal",
            .portalUrl: "Portal-URL",
            .portalTheme: "Farbschema",
            .portalPublish: "Aufgaben veröffentlichen",

            .actionSave: "Speichern",
            .actionCancel: "Abbrechen",
            .actionDelete: "Löschen",
            .actionConfirm: "Bestätigen",
            .actionClose: "Schließen",
            .actionBack: "Zurück",
            .actionNext: "Weiter",
            .actionLoading: "Laden..."
        ]
    ]

    /// Récupère la traduction de la clé pour la langue active (ou langue système par défaut)
    public static func t(_ key: L10nKey, lang: AppSettings.AppLanguage? = nil) -> String {
        let activeLang = lang ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "droopies_app_language") ?? "auto") ?? .automatic
        let langCode: String

        switch activeLang {
        case .frenchFR:
            langCode = "fr"
        case .frenchCA:
            langCode = "fr-CA"
        case .english:
            langCode = "en"
        case .spanish:
            langCode = "es"
        case .italian:
            langCode = "it"
        case .german:
            langCode = "de"
        case .automatic:
            let preferred = Locale.preferredLanguages.first ?? "fr"
            if preferred.starts(with: "fr-CA") {
                langCode = "fr-CA"
            } else if preferred.starts(with: "fr") {
                langCode = "fr"
            } else if preferred.starts(with: "en") {
                langCode = "en"
            } else if preferred.starts(with: "es") {
                langCode = "es"
            } else if preferred.starts(with: "it") {
                langCode = "it"
            } else if preferred.starts(with: "de") {
                langCode = "de"
            } else {
                langCode = "fr"
            }
        }

        if let dict = translations[langCode], let str = dict[key] {
            return str
        }

        // Repli sur le français de base
        if let fallbackDict = translations["fr"], let str = fallbackDict[key] {
            return str
        }

        return key.rawValue
    }
}
