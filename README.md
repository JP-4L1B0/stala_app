# STALA - Sheet Music to Guitar Tablature Translator

---

## Overview

STALA (Sheet Music to Guitar Tablature Translator Application) is a mobile-based Optical Music Recognition (OMR) system designed to convert Grand Staff sheet music into playable guitar tablature. The application combines artificial intelligence, computer vision, musical interpretation, and guitar fretboard mapping techniques to automatically translate sheet music images into monophonic guitar tablature.

The project was developed as an undergraduate thesis to address the difficulty many beginner guitarists experience when reading traditional sheet music notation. By transforming detected musical notes into tablature, STALA provides an accessible bridge between standard music notation and guitar performance.

STALA implements a complete end-to-end processing pipeline that captures or imports sheet music images, detects musical symbols using an ONNX-based object detection model, interprets musical information from Grand Staff notation, maps notes onto the guitar fretboard, and generates mobile-friendly tablature outputs.

---

# Research Context

This study falls under the fields of:

- Optical Music Recognition (OMR)
  
- Computer Vision
  
- Artificial Intelligence
  
- Music Information Retrieval
  
- Mobile Computing
  

The application demonstrates how machine learning and mobile technologies can be integrated to assist music education and self-directed learning.

---

# Features

## Music Recognition

- Import sheet music images from gallery
  
- Capture sheet music using the device camera
  
- AI-based musical symbol detection
  
- Grand Staff notation support
  
- Automatic pitch interpretation
  
- Musical symbol visualization
  

## Guitar Tablature Generation

- Pitch-based tablature generation
  
- Guitar fretboard mapping
  
- Playability-aware note assignment
  
- Position continuity optimization
  
- Monophonic tablature output
  
- Readable mobile-friendly tablature format
  

## Storage and Export

- Save processing sessions
  
- Reopen previous sessions
  
- Export tablature as PNG
  
- Export tablature as STALA project files
  
- Debug visualization support
  

## User Experience

- Beginner-friendly interface
  
- Guided processing workflow
  
- Lightweight mobile implementation
  
- Android-optimized design
  

---

# System Workflow

STALA follows a multi-stage processing pipeline:

```text
Image Capture / Import
          │
          ▼
Image Preprocessing
          │
          ▼
Musical Symbol Detection
          │
          ▼
Staff Structure Analysis
          │
          ▼
Musical Interpretation
          │
          ▼
Guitar Mapping
          │
          ▼
Tablature Generation
          │
          ▼
Save / Export Results
```

## Workflow Description

### 1. Image Acquisition

Users may either:

- Capture a sheet music image using the device camera
  
- Import an existing image from device storage
  

The acquired image serves as the input to the recognition pipeline.

### 2. Musical Symbol Detection

The system uses an ONNX-based object detection model to identify musical symbols such as:

- Treble Clef
  
- Bass Clef
  
- Notes
  
- Rests
  
- Accidentals
  
- Time Signatures
  
- Bar Lines
  

Each detected symbol is assigned:

- Bounding Box
  
- Class Label
  
- Confidence Score
  

### 3. Staff Structure Analysis

Detected symbols are assigned to corresponding staff systems.

This stage determines:

- Staff locations
  
- Symbol-to-staff relationships
  
- Symbol ordering
  
- Structural grouping
  

### 4. Musical Interpretation

The interpreted symbols are translated into musical information including:

- Pitch
  
- Octave
  
- Duration
  
- Accidentals
  

The resulting output is represented as musical note events.

### 5. Guitar Mapping

Interpreted notes are mapped onto a virtual guitar fretboard.

The mapping algorithm considers:

- Pitch accuracy
  
- Fret distance optimization
  
- Position continuity
  
- Playability constraints
  

### 6. Tablature Generation

The mapped notes are converted into guitar tablature notation.

Generated tablature is formatted for readability and mobile display.

### 7. Storage and Export

Users may:

- Save processing sessions
  
- Reopen saved projects
  
- Export tablature outputs
  
- Generate debugging reports
  

---

# Technologies Used

## Mobile Development

- Flutter
  
- Dart
  

## Artificial Intelligence

- ONNX Runtime
  
- Faster R-CNN
  
- Computer Vision
  

## Music Processing

- Optical Music Recognition (OMR)
  
- Musical Interpretation Algorithms
  
- Staff Analysis Algorithms
  
- Guitar Fretboard Mapping
  

## Development Tools

- Android Studio
  
- Visual Studio Code
  
- Git
  
- GitHub
  

---

# Repository Structure

```text
stala_app/
│
├── android/
│   └── app/
│       └── src/
│           └── main/
│               ├── kotlin/
│               └── assets/
│                   └── model.onnx
│
├── assets/
│   ├── images/
│   ├── icons/
│   └── fonts/
│
├── docs/
│   ├── User Manual
│   ├── Thesis Documents
│   ├── Technical Documentation
│   └── Source Code Appendix
│
├── lib/
│   ├── models/
│   ├── pages/
│   ├── services/
│   ├── widgets/
│   └── utils/
│
├── test/
│
├── pubspec.yaml
├── pubspec.lock
├── README.md
└── LICENSE
```

---

# AI Model Information

The trained ONNX object detection model used by STALA is bundled directly within the Android application assets.

```text
android/app/src/main/assets/
```

Because the model file is included in the repository, users do not need to download or configure the model separately after cloning the project.

All files required for musical symbol detection, interpretation, guitar mapping, and tablature generation are contained within the repository.

---

# Prerequisites

Before building STALA, install the following software:

| Software | Purpose |
| --- | --- |
| Flutter SDK | Application Framework |
| Android Studio | Android Development |
| Android SDK | Android Platform Tools |
| Git | Version Control |
| JDK 17+ | Android Build Support |

---

# Development Environment Setup

## 1. Install Flutter

Download Flutter SDK:

https://flutter.dev/docs/get-started/install

Verify installation:

```bash
flutter doctor
```

Resolve all reported issues before proceeding.

---

## 2. Install Android Studio

Download Android Studio:

https://developer.android.com/studio

Install:

- Android SDK
  
- Android SDK Platform Tools
  
- Android Emulator
  

Verify installation:

```bash
flutter doctor
```

---

## 3. Install Git

Download Git:

https://git-scm.com/downloads

Verify installation:

```bash
git --version
```

---

# Cloning the Repository

Clone the repository:

```bash
git clone https://github.com/<username>/<repository-name>.git
```

Example:

```bash
git clone https://github.com/JP-4L1B0/stala_app.git
```

Navigate to the project directory:

```bash
cd stala_app
```

---

# Opening the Project

## Android Studio

1. Open Android Studio
  
2. Select **Open**
  
3. Choose the cloned repository folder
  
4. Wait for Gradle synchronization
  
5. Allow Flutter indexing to complete
  

## Visual Studio Code

1. Open VS Code
  
2. Select **Open Folder**
  
3. Choose the cloned repository
  
4. Install Flutter and Dart extensions if prompted
  

---

# Installing Dependencies

Download all required Flutter packages:

```bash
flutter pub get
```

Verify package installation:

```bash
flutter pub deps
```

---

# Running the Application

## Check Connected Devices

```bash
flutter devices
```

Example output:

```text
Pixel 7 Pro • emulator-5554 • android-arm64
```

---

## Run in Debug Mode

```bash
flutter run
```

---

## Run on a Specific Device

```bash
flutter run -d emulator-5554
```

---

## Hot Reload

While running:

```text
r = Hot Reload
R = Hot Restart
q = Quit
```

---

# Building the Application

## Debug APK

```bash
flutter build apk --debug
```

Output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

---

## Release APK

```bash
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

---

## Android App Bundle (Google Play)

```bash
flutter build appbundle --release
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

---

# Repository Reproducibility

This repository contains all source code, assets, Android configuration files, Flutter dependencies, and AI model files required to rebuild STALA from scratch.

Included:

```text
✓ Flutter source code
✓ Android configuration files
✓ ONNX detection model
✓ Application assets
✓ Documentation
✓ Dependency declarations
```

Not included:

```text
✗ build/
✗ .dart_tool/
✗ android/app/build/
✗ android/.gradle/
```

These directories are automatically regenerated during compilation and therefore do not need to be stored in version control.

A fresh clone of the repository can be rebuilt using:

```bash
git clone https://github.com/JP-4L1B0/stala_app

cd stala_app

flutter pub get

flutter run
```

No additional model downloads or external configuration steps are required.

---

# Updating the Project

Pull the latest repository changes:

```bash
git pull origin main
```

Update dependencies:

```bash
flutter pub get
```

If build issues occur:

```bash
flutter clean
flutter pub get
```

---

# Troubleshooting

## Flutter Doctor Issues

```bash
flutter doctor
```

Resolve all reported issues.

---

## Packages Not Found

```bash
flutter pub get
```

---

## Build Failures

```bash
flutter clean
flutter pub get
flutter run
```

---

## Device Not Detected

```bash
flutter devices
```

Ensure that:

- USB Debugging is enabled
  
- Device drivers are installed
  
- USB connection is configured for File Transfer
  

---

## Android SDK Errors

```bash
flutter config --android-sdk <path>
flutter doctor
```

---

## ONNX Model Not Found

Verify that the model exists inside:

```text
android/app/src/main/assets/
```

Ensure the repository was cloned completely and no project files were omitted.

---

# Documentation

Additional project documents are available in the `docs/` directory.

Included documents may include:

- User Manual
  
- Technical Documentation
  
- Thesis Manuscript
  
- Source Code Appendix
  
- Testing and Evaluation Reports
  
- Research References
  

---

# Researchers

- John Philip A. Alibo
  
- Alexander James A. Dumalogdog
  
- Richard Kristoffer Leigh M. Ramos
  

---

# Adviser

- Mr. Karlo Jose E. Nabablit

---

# Citation

If you use STALA in academic work, please cite the corresponding thesis manuscript and project documentation.

---

# License

This project was developed for academic, educational, and research purposes as part of an undergraduate thesis project.

© 2026 STALA Research Team. All Rights Reserved.
