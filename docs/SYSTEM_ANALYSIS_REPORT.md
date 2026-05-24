# STALA App - System Analysis Report

## PROJECT OVERVIEW
**STALA** is a GrandStaff-to-Tablature Translation Music Application—a sophisticated Flutter mobile app for Android that uses computer vision and machine learning to convert sheet music images into guitar tablature.

**Version:** 2.0.2+3  
**SDK:** Dart ^3.9.2  
**Status:** Active development with mature architecture

---

## ARCHITECTURE & TECH STACK

### Frontend (Flutter)
- **Framework:** Flutter with Material Design
- **Key Libraries:**
    - `camera` v0.11.0+2 — Real-time camera capture
    - `image_picker` v1.1.2 — Image selection from gallery
    - `flutter_midi_pro` v3.1.6 — Audio playback (acoustic guitar soundfont)
    - `showcaseview` v5.0.2 — Tutorial/UI walkthrough system
    - `shared_preferences` v2.3.5 — Local storage
    - `permission_handler` v11.3.1 — Runtime permissions
    - `gallery_saver_plus` v3.2.1 — Export PNG functionality
    - `image` v4.1.3 — Image processing utilities

### Backend/Native (Android/Kotlin)
- **Target SDK:** Flutter's latest (compileSdk/targetSdk managed by Flutter)
- **Min SDK:** Flutter's default (likely 21+)
- **Build System:** Gradle KTS (Kotlin DSL)
- **Languages:** Kotlin (main), C++ (OpenCV)

### Vision & ML Pipeline
- **OpenCV 4.x** — Image processing, document detection, staff line segmentation
- **ONNX Runtime** v1.17.3 — ML inference for symbol detection (multiclass detector)
- **Custom Native Code:**
    - Document boundary detection/validation
    - Staff line segmentation
    - Image preprocessing & cropping
    - Symbol detection via ONNX model

### Assets
- App branding (STALA logo, animated GIF, static PNG, icon)
- Acoustic guitar SoundFont (SF2 format)

---

## PROJECT STRUCTURE

### Codebase Organization

lib/\
├── main.dart                        # App entry, RestartWidget + ShowCaseView\
├── app_restart_widget.dart          # Hot reload support widget\
├── camera_logic.dart                # 2491 lines — Main camera capture workflow\
├── camera_panel.dart                # Camera UI panel\
├── processing_page.dart             # 4335 lines — Processing pipeline orchestration\
├── result_page.dart                 # Results display & playback\
├── menu_page.dart                   # Main menu/navigation\
├── dummy_page.dart                  # Dev placeholder\
├── pages/\
│   └── splash_page.dart            # Launch screen\
├── core/\
│   └── theme/\
│       ├── app_colors.dart         # Design system colors\
│       └── app_text_styles.dart    # Typography\
├── models/\
│   ├── session_data.dart           # 181 lines — Comprehensive session state\
│   ├── tablature_result.dart       # Tab output models\
│   ├── saved_item_data.dart        # Persistence models\
│   └── translation_group_models.dart # Music staff/note grouping\
├── services/ (24 specialized services)\
│   ├── Staff Processing:\
│   │   ├── staff_segmentation_service.dart      # 526 lines\
│   │   ├── barline_refinement_service.dart\
│   │   ├── translation_grouping_service.dart    # 712 lines\
│   │   └── note_grouping_service.dart\
│   ├── Music Theory:\
│   │   ├── clef_resolution_service.dart\
│   │   ├── key_signature_service.dart\
│   │   ├── pitch_mapping_service.dart\
│   │   ├── accidental_service.dart\
│   │   ├── grand_staff_pairing_service.dart\
│   │   ├── rhythm_interpretation_service.dart\
│   │   ├── musical_interpretation_service.dart\
│   │   └── chord_voicing_service.dart\
│   ├── Fretboard Mapping:\
│   │   ├── fretboard_mapping_service.dart\
│   │   ├── playability_scoring_service.dart\
│   │   └── polyphonic_to_monophonic_service.dart\
│   ├── Output Generation:\
│   │   ├── generation_service.dart              # 332+ lines (tab layout engine)\
│   │   ├── tablature_result_adapter.dart\
│   │   ├── save_export_service.dart\
│   │   └── audio_playback_service.dart\
│   ├── System:\
│   │   ├── event_manager_service.dart\
│   │   ├── storage_access_service.dart\
│   │   ├── processing_session_navigation.dart\
│   │   └── tutorial_service.dart\
├── data/\
│   ├── app_settings_repository.dart\
│   ├── debug_settings_repository.dart\
│   └── recent_items_repository.dart\
└── models/


### Android Native Code

android/\
├── app/\
│   ├── build.gradle.kts                         # App-level config\
│   ├── src/main/\
│   │   ├── AndroidManifest.xml                  # 72 lines\
│   │   └── kotlin/com/example/stala_app/\
│   │       └── MainActivity.kt                  # 967 lines\
│   │           ├── MethodChannel handlers:\
│   │           │   - stala/python_bridge (vision pipeline)\
│   │           │   - stala/storage_access (SAF integration)\
│   │           │   - stala_app/accessibility (a11y service)\
│   │           ├── OnnxDetector setup\
│   │           ├── Document/folder picker (ACTION_OPEN_DOCUMENT_TREE)\
│   │           ├── SAF (Scoped Access Framework) integration\
│   │           └── OpenCV initialization\
├── opencv/                                      # OpenCV module (C++)\
│   ├── build.gradle\
│   ├── native/\
│   └── java/\
├── build.gradle.kts\
└── settings.gradle.kts

---

## KEY FEATURES & WORKFLOW

### 1. Camera Capture Workflow (camera_logic.dart — 2491L)
- Real-time camera feed with document boundary detection
- Live visualization of detected corners
- Three validation states: **strong** (confident) / **weak** (partial) / **fail** (unreliable)
- Manual corner adjustment UI
- Long-press override for failed detections
- Permission handling (camera access)

### 2. Processing Pipeline (processing_page.dart — 4335L)
Multi-stage orchestrated pipeline:

1. Image Preprocessing\
   └─ detect/crop/validate via OpenCV

2. Symbol Detection\
   └─ ONNX multiclass inference

3. Staff Processing\
   ├─ Segmentation (staff lines, ledger lines)\
   ├─ Barline refinement\
   ├─ Translation grouping (staff_n construction)\
   └─ Note grouping

4. Music Theory Resolution\
   ├─ Clef detection\
   ├─ Pitch mapping to each detected clef\
   ├─ Key signature analysis\
   ├─ Accidental management\
   └─ Grand staff pairing (treble + bass)

5. Fretboard Conversion\
   ├─ Polyphonic-to-monophonic conversion\
   ├─ Fretboard mapping (pitch → string/fret)\
   ├─ Playability scoring\
   └─ Voicing selection

6. Output Generation\
   ├─ Tablature layout engine\
   ├─ Measure/column positioning\
   ├─ Export page pagination\
   ├─ Audio playback sync\
   └─ Save/export (PNG, JSON, etc.)

### 3. Session State Management (SessionData — 181L)
Immutable data class tracks:
- Source & processed images (original, cropped, preprocessed, detection output)
- Intermediate pipeline snapshots (symbols, segmentation, pitch data)
- Final tablature results
- Processing metadata (timestamp, model version)
- Auto-save state

### 4. Storage & Export
- **SAF Integration:** Document tree picker + persistent URI grants
- **Public Storage:** /STALA directory for user access
- **Format Support:** ZIP, JSON, PNG exports
- **Device Storage:** Selectable folders via system picker

### 5. Audio Playback
- Acoustic guitar SoundFont (SF2)
- Audio playback service with sync to tablature events
- MIDI Pro integration

---

## NATIVE INTEGRATION (Kotlin/Android)

### MethodChannels (Dart ↔ Kotlin Communication)

| Channel | Methods | Purpose |
|---------|---------|---------|
| \`stala/python_bridge\` | detectDocumentBounds, validateSelectedCrop, cropDocumentImage, processImage, segmentStaffLines | Vision pipeline (OpenCV + ONNX) |
| \`stala/storage_access\` | pickStorageFolder, getStorageFolder, listFiles, writeTextFile, writeBinaryFile, readTextFile, deleteDocument, renameDocument, etc. | SAF & file I/O |
| \`stala_app/accessibility\` | isAccessibilityEnabled, openAccessibilitySettings | Accessibility service control |

### OpenCV & ONNX
- **OpenCVLoader:** Initialize at app creation
- **OnnxDetector:** Loads \`models/stala_multiclass_detector.onnx\` on first use
- **Document Processing:** DocumentProcessor (native C++ via JNI)
- **Staff Segmentation:** StaffSegmentationProcessor

### Permissions (AndroidManifest.xml)
- \`CAMERA\` — Real-time capture
- \`READ_EXTERNAL_STORAGE\` (Android ≤12)
- \`READ_MEDIA_IMAGES\` (Android 13+)
- \`WRITE_EXTERNAL_STORAGE\` — Export
- \`MANAGE_EXTERNAL_STORAGE\` — Public storage access
- \`POST_NOTIFICATIONS\` (Android 13+)

---

## DATA FLOW OVERVIEW

Camera/Gallery Image\
↓\
[Document Boundary Detection] ← OpenCV\
↓\
[User Crop Validation]\
↓\
[Preprocessing + ONNX Inference] ← ONNX detector\
↓\
Detected Symbols + Raw Image Segmentation\
↓\
[Staff & Note Processing]\
↓\
Music Theory Services (clef, pitch, key, accidentals, grand staff)\
↓\
[Fretboard Mapping + Playability Analysis]\
↓\
Generated Tablature (columns, rows, measures, events)\
↓\
[Output Generation & Rendering]\
↓\
Result Display + Audio Playback + Export\
↓\
[Save to Storage] ← SAF/public storage


---

## KEY DESIGN PATTERNS

1. **Immutable Models** — SessionData, GeneratedTabResult use \`const\` constructors + copyWith
2. **Service Architecture** — 24+ single-responsibility services for music logic
3. **Fallback Mechanisms** — Native failures gracefully fallback to Dart implementations
4. **MethodChannel Abstraction** — Clean Kotlin↔Dart boundary
5. **SAF Integration** — Modern Android storage with persistent URI permissions
6. **ShowCaseView Integration** — Built-in tutorial system

---

## CONFIGURATION & BUILD

- **Build System:** Gradle KTS with Flutter plugin
- **JVM Target:** Java 11
- **ABI Filters:** armeabi-v7a, arm64-v8a
- **Packaging:** Legacy JNI packaging enabled for OpenCV
- **ProGuard:** flutter_proguard_rules.pro applied

---

## ANALYSIS SUMMARY

| Aspect | Status |
|--------|--------|
| **Architecture** | Well-structured, modular (24 services) |
| **Complexity** | High (music theory + computer vision) |
| **Code Size** | ~10,000+ Dart LOC + 967 Kotlin LOC |
| **Native Integration** | Mature (OpenCV + ONNX + JNI) |
| **State Management** | Immutable models, session-based |
| **Storage** | Modern SAF + public directory support |
| **Error Handling** | Native-to-Dart fallbacks implemented |
| **Testing** | Widget test template present |
| **Linting** | flutter_lints enabled |

---

## POTENTIAL OBSERVATIONS

1. **Large Monolithic Files:** processing_page.dart (4335L) and camera_logic.dart (2491L) are substantial—candidates for refactoring into smaller widgets
2. **No State Management Framework:** No Provider/Riverpod/BLoC—state management is manual; could benefit from reactive patterns
3. **Fallback Architecture:** Staff segmentation & other services have Dart fallbacks to handle native failures gracefully
4. **Debug Settings:** debug_settings_repository.dart suggests development/toggle features
5. **Accessibility Service:** MyAccessibilityService for extended functionality (likely multi-staff support)
6. **Recent Items Tracking:** App tracks recent sessions for quick re-access

---

**Report Generated:** May 24, 2026  
**Analysis Type:** Architecture & System Structure Review  
**Scope:** Flutter + Android Native Integration

