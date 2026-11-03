# 🐶 Dropies — Studio de Correction & Distribution de Copies

> **Application native Universal (iPadOS & macOS) écrite en Swift 6 & SwiftUI**  
> Successeur moderne de Droopy, conçu « iPad-First » avec Apple Pencil et le Neural Engine d'Apple.

---

## ✨ Points Forts & Philosophie

- **✏️ Correction au Stylet 120 Hz ProMotion (PencilKit)** : Corrigez vos paquets de copies scannées directement sur iPad avec votre Apple Pencil (annotations vectorielles non-destructives, gomme, surligneur, rejet de paume).
- **✂️ Découpage Intelligent** : Découpe automatique des gros fichiers PDF issus du photocopieur avec calcul du ratio de pages par élève.
- **🔍 Reconnaissance Manuscrite Locale (Apple Vision OCR)** : Le Neural Engine de la puce Apple Silicon identifie automatiquement le nom écrit à la main en haut de la copie et le compare avec l'effectif de la classe (algorithme de Levenshtein).
- **📋 Export Pronote & Tableur en 1 Clic** : Copiez d'un tap l'ensemble des notes de la classe au format tabulé prêt à coller dans Excel, Numbers ou Pronote.
- **☁️ Multi-Cloud & Envoi en Arrière-Plan** : Distribue les copies dans les dossiers respectifs des élèves sur Dropbox, Nextcloud / Apps Éducation ou Stockage Local. Grâce à `URLSession.background`, l'iPad poursuit l'envoi même lorsque l'application est fermée.
- **🔒 Confidentialité RGPD & Zero-Knowledge** : Traitement 100 % en local sur l'appareil. Les élèves accèdent à leurs copies via une empreinte chiffrée SHA-256 sans qu'aucun serveur central n'ait accès à leurs données.

---

## 🧭 Le Workflow Enseignant en 3 Étapes

```text
┌───────────────────────────────────────────────────────────────┐
│         FLUX QUOTIDIEN DE CORRECTION DROPIES (4 ÉTAPES)       │
└───────────────────────────────────────────────────────────────┘
  │
  ├── 1️⃣ ÉTAPE 1 : ATELIER STYLET (Apple Pencil & Multitâche)
  │   Correction asynchrone de plusieurs paquets dans `Evaluations/A corriger/`
  │   Marquage d'un scan terminé avec le préfixe `CORRIGE_`
  │
  ├── 2️⃣ ÉTAPE 2 : CHARGEMENT DES COPIES & MODE RATTRAPAGE
  │   Pré-sélection automatique des scans `CORRIGE_`
  │   OU Sélection d'une évaluation déjà distribuée (`Evaluations/Backup/`) pour les absents
  │   Auto-remplissage de la Classe, Date et Titre
  │
  ├── 3️⃣ ÉTAPE 3 : DÉCOUPAGE & IDENTIFICATION (Vision OCR)
  │   Filtrage intelligent : ne propose que les élèves sans note/sans copie en mode rattrapage
  │   Lecture manuscrite du nom (Apple Vision) + Saisie de note ultra-rapide au clavier
  │
  └── 4️⃣ ÉTAPE 4 : DISTRIBUTION & SYNTHÈSE (Cloud Background)
      Moyenne de classe, min/max ➔ Export Pronote en 1 clic
      Fusion automatique du PDF avec le Backup existant (ajout des copies des absents)
      Envoi silencieux vers les dossiers élèves sur le Cloud
```

---

## 📁 Structure du Projet

```text
Dropies/
├── App/
│   └── DropiesApp.swift                 # Point d'entrée principal (@main)
├── Models/                              # Modèles métier compatibles eleves.json & settings.json
│   ├── Student.swift
│   ├── ClassGroup.swift
│   ├── StudentCopy.swift
│   ├── Evaluation.swift
│   └── AppSettings.swift
├── Services/                            # Moteurs locaux & connecteurs
│   ├── Storage/                         # Local, Dropbox v2 REST, Nextcloud WebDAV
│   ├── PDFEngine/                       # Découpage, compression & CoreGraphics
│   └── OCREngine/                       # Apple Vision & Fuzzy Match Levenshtein
├── ViewModels/
│   └── AppState.swift                   # État réactif global (@Observable)
├── Views/                               # Interfaces natives SwiftUI
│   ├── MainSplitView.swift              # Navigation adaptative
│   ├── Components/                      # Badges, Cartes KPI, PDFKitView, PencilCanvasOverlay, QR Code
│   ├── Correction/                      # Stepper des 3 étapes (Studio, Identification, Distribution)
│   ├── Students/                        # Gestion élèves, Assistant CSV, Étiquettes découpables
│   ├── Portal/                          # Réglages & thèmes du portail web
│   └── Settings/                        # Configuration dossiers & Cloud
└── Logo/                                # Déclinaisons graphiques de la mascotte Low-Poly
```

---

## 🛠️ Configuration & Pré-requis

- **iPadOS** 17.0+ (Optimisé pour iPad Pro / iPad Air avec Apple Pencil)
- **macOS** 14.0+ Sonoma / Sequoia (Puce Apple Silicon M1/M2/M3/M4)
- **Xcode** 15.0+ ou 16.0+ avec Swift 6

---

## 📄 Licence

Distribué sous licence **GNU General Public License v3.0 (GPLv3)**.  
Consultez le fichier [LICENSE](LICENSE) pour plus de détails.
