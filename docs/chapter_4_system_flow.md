# CHAPTER 4

# SYSTEM DESIGN, IMPLEMENTATION, AND OPERATION

## 4.1 Introduction

This chapter presents the design and implementation of STALA, a Grand Staff-to-Tablature Translation Music Application. The system was developed as a mobile application that captures or imports a music sheet image, detects the staff and music symbols, interprets the extracted musical information, and generates guitar tablature output. The chapter describes the system architecture, major components, processing workflow, data flow, and implementation details used to convert a grand staff image into a usable tablature result.

STALA combines a Flutter-based user interface with native Android image processing. Flutter manages the user interaction, application navigation, result presentation, saving, import, export, and tablature generation logic. Native Android modules written in Kotlin perform computationally intensive image analysis through OpenCV and ONNX Runtime. The two layers communicate through Flutter method channels.

## 4.2 System Overview

STALA is designed to assist users in translating music notation from a grand staff format into guitar tablature. The user begins by capturing or selecting an image of a music sheet. The system then guides the image through a series of processing stages: document detection, image cropping, symbol detection, staff segmentation, musical interpretation, fretboard mapping, and tablature generation.

The overall system follows an image-to-structure-to-tablature flow. First, the application obtains a clean image of the sheet music. Next, the vision pipeline extracts visual elements such as noteheads, clefs, accidentals, staff lines, ledger lines, stems, beams, and bar lines. These detected elements are then grouped by staff and measure. After grouping, the system resolves pitch information, interprets rhythmic values, maps notes to guitar fretboard positions, and builds the final tablature output.

## 4.3 System Architecture

The system uses a layered architecture composed of the presentation layer, application logic layer, native processing layer, storage layer, and output layer.

**Table 4.1 System Architecture Layers**

| Layer | Main Responsibility | Implementation |
|---|---|---|
| Presentation Layer | Displays camera, processing, result, import, and export screens | Flutter and Dart |
| Application Logic Layer | Coordinates the processing pipeline and music interpretation services | Dart services |
| Native Processing Layer | Performs document detection, ONNX symbol detection, and OpenCV staff segmentation | Kotlin, OpenCV, ONNX Runtime |
| Storage Layer | Saves and loads STALA sessions, images, ZIP files, PNG files, and PDF exports | Dart repositories and Android storage access |
| Output Layer | Generates tablature pages, playback-ready events, and exportable files | Dart generation and export services |

The Flutter application serves as the main controller of the user workflow. Native processing is accessed only when image analysis is required. This separation allows the application to keep the interface responsive while running heavy image operations on background threads.

## 4.4 System Components

### 4.4.1 Camera and Image Acquisition Module

The camera and image acquisition module allows the user to capture a new music sheet image or select an existing image from local storage. It requests the required camera and image permissions, prepares the selected file, and sends the image to the document detection process. The module also supports manual crop adjustment when automatic document detection is uncertain.

The document detection result includes the detected crop bounds, confidence value, validation state, and reason message. If the detected region is strong, the user can continue directly. If the result is weak or failed, the user may adjust the crop box before processing.

### 4.4.2 Document Detection and Cropping Module

The document detection and cropping module is implemented in the native Android layer through `DocumentProcessor`. It uses OpenCV-based detection, music-sheet-aware validation, and heuristic fallbacks to locate the sheet region. The module examines visual properties such as brightness, horizontal line density, edge continuity, and staff-like row patterns.

Once the crop bounds are confirmed, the module performs perspective-aware cropping and saves the cropped image as a new file. This cropped image becomes the primary input for the recognition pipeline.

### 4.4.3 ONNX Symbol Detection Module

The ONNX symbol detection module is implemented in `OnnxDetector`. It loads the trained model file `stala_multiclass_detector.onnx` and applies inference to the cropped image. Before inference, the image is decoded with corrected orientation, enhanced using CLAHE, and resized through letterboxing to the model input size of 1024 by 1024 pixels.

The model returns detected bounding boxes, labels, and confidence scores. These outputs are converted into symbol records containing class names, confidence values, and bounding box coordinates. The system currently recognizes music symbols such as treble clef, bass clef, notehead, sharp, flat, and natural.

### 4.4.4 Staff Segmentation Module

The staff segmentation module is implemented in `StaffSegmentationProcessor` and exposed to Flutter through the `segmentStaffLines` method channel call. It uses OpenCV to convert the input image to grayscale, apply adaptive thresholding, and extract horizontal structures using morphological operations.

The module identifies five-line staff groups, estimates staff spacing, detects ledger lines, detects bar lines, extracts stems and beams, and builds measure boundaries. The output includes validated staffs, staff lines, ledger lines, bar lines, stems, beams, measures, and an overlay image for debugging or visual confirmation.

### 4.4.5 Translation and Music Interpretation Module

After symbol detection and staff segmentation, Dart services interpret the visual results into musical structure. The translation process assigns symbols to staff regions, resolves clefs, maps notehead positions to pitches, applies accidentals and key signature information, groups notes, and forms grand staff pairs.

The major services involved in this stage include:

| Service | Purpose |
|---|---|
| `TranslationGroupingService` | Assigns detected symbols to their staff and measure context |
| `ClefResolutionService` | Resolves staff role using detected clefs |
| `PitchMappingService` | Converts vertical note positions into pitch names |
| `AccidentalService` | Applies accidentals to detected notes |
| `KeySignatureService` | Interprets key signature candidates |
| `NoteGroupingService` | Groups notes that belong together musically |
| `GrandStaffPairingService` | Pairs treble and bass staffs into grand staff units |
| `RhythmInterpretationService` | Uses stems and beams to estimate rhythmic events |

### 4.4.6 Fretboard Mapping and Tablature Module

The fretboard mapping and tablature module converts interpreted musical events into guitar-playable positions. `FretboardMappingService` generates candidate string and fret positions for each note or chord. `EventManagerService` selects playable event sequences, while `ChordVoicingService` chooses chord-friendly positions when multiple notes occur together.

The `TablatureResultAdapter` combines note events, chord voicing results, and rhythm interpretation results into tablature result objects. Finally, `GenerationService` formats these results into display-ready and export-ready tablature pages.

### 4.4.7 Storage, Import, and Export Module

The storage module supports saving and loading STALA session files. A session contains the original image path, cropped image path, preprocessing outputs, detection results, staff segmentation data, interpretation outputs, and generated tablature results. The application can save `.stala` files, export PNG tablature pages, generate PDF tablature documents, and package data into ZIP archives.

Android storage access is implemented through the `stala/storage_access` method channel. This enables the user to select a storage folder and grants the application permission to create, read, rename, delete, import, and export files.

## 4.5 Overall System Flow

The complete system workflow is shown below.

1. The user opens the application and selects the camera or import function.
2. The system captures or receives a music sheet image.
3. The native document processor detects the probable sheet bounds.
4. The user confirms or adjusts the crop region.
5. The confirmed region is cropped and saved.
6. The processing page starts the recognition pipeline.
7. ONNX Runtime detects music symbols from the cropped image.
8. OpenCV staff segmentation detects staff lines, ledger lines, bar lines, stems, beams, and measures.
9. Dart services assign symbols to staffs and measures.
10. The system resolves clefs, pitches, accidentals, note groups, rhythm, and grand staff pairs.
11. Fretboard mapping converts notes into guitar string and fret positions.
12. The tablature adapter builds final tablature result objects.
13. The result page displays the generated tablature and related analysis.
14. The user may save, export, import, rename, delete, or reopen the session.

**Figure 4.1 Overall STALA Processing Flow**

```text
Image Capture or Import
        |
        v
Document Detection and Crop Validation
        |
        v
Confirmed Cropped Sheet Image
        |
        v
ONNX Music Symbol Detection
        |
        v
OpenCV Staff Segmentation
        |
        v
Symbol-to-Staff Grouping
        |
        v
Pitch, Rhythm, and Grand Staff Interpretation
        |
        v
Fretboard Mapping and Chord Voicing
        |
        v
Tablature Generation
        |
        v
Save, Display, Playback, or Export Result
```

## 4.6 Processing Pipeline Description

### 4.6.1 Preparing the Image

The first stage prepares the selected image for analysis. The application corrects orientation, validates that the file exists, and crops the image according to the detected or user-adjusted document bounds. This stage reduces unnecessary background content and improves the quality of later recognition steps.

### 4.6.2 Finding Music Symbols

The cropped image is passed to the native `processImage` method. The ONNX detector copies the model asset into internal storage, creates an ONNX Runtime session, preprocesses the bitmap, converts the image into a float tensor, and performs inference. The resulting boxes, labels, and scores are converted into application-level detection records.

### 4.6.3 Reading Staff Lines

The staff segmentation service analyzes the preprocessed image to locate staff structures. The native OpenCV process detects horizontal staff lines, validates five-line groups, and identifies supporting notation features. This stage is necessary because note pitch depends heavily on vertical position relative to staff and ledger lines.

### 4.6.4 Interpreting Notes

The application groups detected symbols according to staff boundaries, clef context, measure boundaries, and notehead positions. It resolves each note into a musical pitch and groups simultaneous or nearby notes. The system also uses stems and beams to estimate rhythm and event duration.

### 4.6.5 Building Tablature

The final processing stage converts interpreted notes into guitar tablature. The system calculates candidate fretboard positions, selects playable string and fret combinations, applies chord voicing logic, and generates tablature events. These events are then arranged into exportable tablature pages.

## 4.7 Data Flow

The system passes structured data between modules to preserve traceability from image input to tablature output.

**Table 4.2 Major Data Objects**

| Data Object | Description |
|---|---|
| Source image path | File path of the captured or imported image |
| Cropped image path | File path of the confirmed sheet crop |
| Detection list | ONNX output converted into class name, confidence, and bounding box |
| Staff segmentation result | Staff lines, validated staffs, ledger lines, bar lines, stems, beams, and measures |
| Translation groups | Symbols assigned to staff, measure, clef, and pitch context |
| Note groups | Notes grouped by staff and event position |
| Grand staff pairs | Treble and bass staff pairings used for grand staff interpretation |
| Rhythm events | Estimated timing and duration information |
| Fretboard mappings | Candidate guitar string and fret positions |
| Tablature results | Final playable and displayable tablature events |
| Session data | Complete saved project state for reopening and exporting |

## 4.8 Implementation Details

STALA was implemented using Flutter and Dart for the cross-platform user interface and Android Kotlin for native image processing. The Android layer uses OpenCV for document and staff image analysis and ONNX Runtime for trained model inference. The application uses method channels to bridge Dart and native Kotlin code.

The main method channels are:

| Method Channel | Purpose |
|---|---|
| `stala/python_bridge` | Connects Flutter to document detection, cropping, ONNX processing, and staff segmentation |
| `stala/storage_access` | Connects Flutter to Android document and folder access operations |
| `stala_app/accessibility` | Checks and opens Android accessibility settings when needed |

The release build includes ONNX Runtime keep rules so that R8 does not remove or rename Java classes required by native ONNX Runtime JNI calls.

## 4.9 Error Handling and Validation

The system handles processing errors by returning structured error maps instead of immediately terminating the user workflow. Each native operation validates input arguments, such as image paths and crop bounds, before processing. If a file is missing, an image cannot be decoded, a crop is invalid, or inference fails, the system returns a response containing status, message, empty outputs, and an error list.

The document detection stage uses validation states to guide the user. A strong result allows the workflow to continue normally. A weak result asks the user to adjust the crop. A failed result prevents unreliable processing unless the user intentionally corrects the input.

## 4.10 Output and User Result

The final output of the system is a generated guitar tablature result derived from the detected and interpreted music sheet. The result screen displays the generated tablature, related processing information, and export options. Users may save the result as a STALA session, export tablature pages as PNG images, generate a PDF, or package session data into ZIP files.

The session-based design allows users to reopen previous work without repeating the full recognition pipeline. This is useful when reviewing, exporting, or managing multiple translated music sheets.

## 4.11 Summary

This chapter described the design and implementation of STALA. The system uses a hybrid architecture in which Flutter manages the user interface and music interpretation workflow, while native Android modules perform image processing and machine learning inference. The complete workflow begins with image capture or import, continues through document detection, symbol recognition, staff segmentation, musical interpretation, fretboard mapping, and tablature generation, and ends with display, saving, and export of the result.

The modular structure allows each stage of the recognition and translation process to be maintained independently. This design supports clearer debugging, easier future improvement of the detection model, and flexible expansion of tablature generation and export features.
