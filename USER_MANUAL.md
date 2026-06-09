# STALA User's Manual

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Features](#2-system-features)
3. [Application Navigation](#3-application-navigation)
4. [Capturing or Importing Sheet Music](#4-capturing-or-importing-sheet-music)
5. [Processing Workflow](#5-processing-workflow)
6. [Guitar Tablature Generation](#6-guitar-tablature-generation)
7. [Results Interface](#7-results-interface)
8. [Saving and Exporting](#8-saving-and-exporting)
9. [Search and Recent Sessions](#9-search-and-recent-sessions)
10. [Settings and Preferences](#10-settings-and-preferences)
11. [Notifications and System Messages](#11-notifications-and-system-messages)
12. [Troubleshooting](#12-troubleshooting)
13. [Tips and Best Practices](#13-tips-and-best-practices)
14. [Glossary](#14-glossary)
15. [Appendix](#15-appendix)

## 1. Introduction

STALA is a mobile application designed to translate sheet music into guitar tablature. The application guides the user from image capture or file import through document cropping, music-symbol recognition, staff-line analysis, musical interpretation, fretboard mapping, tablature viewing, playback, saving, and export.

The system is intended for music learners, guitar players, educators, and users who need a practical way to review piano grand staff notation in a guitar-oriented format. STALA is especially useful when a user has printed or image-based sheet music and wants to obtain a playable tablature representation.

The application presents the workflow through a guided interface with page tours, contextual help, validation overlays, progress indicators, and user messages. Processing quality depends strongly on the clarity of the source image and the accuracy of the selected crop.

<p align="center">
  <img src="./docs/STALA-UM/1.jpg" alt="Screenshot of Splash Page" width="50%" />
</p>

## 2. System Features

STALA provides the following major capabilities:

- Capture a music sheet image using the device camera.
- Import an existing image from the device gallery.
- Detect probable document boundaries automatically.
- Manually adjust crop corners and crop edges before processing.
- Validate the crop using strong, weak, and fail detection states.
- Recognize music symbols such as notes, clefs, accidentals, stems, beams, staff lines, ledger lines, and bar lines.
- Interpret notes, rhythm, staff positions, grand staff structure, and pitch information.
- Convert interpreted music into guitar string and fret positions.
- Generate tablature views including `Treble Only` and `Grand Staff` modes when available.
- Play generated events using audio playback controls.
- Display a fretboard map for the currently selected note or chord.
- Auto-save completed translations as `.stala` project files when enabled.
- Export tablature as PNG page files or PDF documents.
- Import `.stala` files and ZIP archives containing `.stala` files.
- Rename, delete, select, and bulk export saved STALA files.
- Provide tutorial tours on supported screens.
- Provide optional debug views for development and diagnostic review.

Some controls are intentionally limited in the current implementation. The Settings screen shows `Save format` as STALA format only (`.stala`). ZIP and cloud save controls are described as future-ready and are not exposed as ordinary save-format choices.

## 3. Application Navigation

After launch, STALA displays an animated splash screen and then opens the main dashboard. The header shows the application name `STALA` and the tagline `Read Notes. Play Strings`.

<p align="center">
  <img src="./docs/STALA-UM/15.jpg" alt="Screenshot of Home Page" width="50%" />
</p>

The main navigation includes the following user-facing areas:

- `Home`: Displays recent projects and provides access to saved work.
- `Import`: Opens the import workflow for existing STALA files and supported archives.
- Camera button: Opens the camera workflow for capturing or selecting a sheet music image.
- Settings icon: Opens application controls, permissions, storage folder selection, and information.
- Help icon: Opens the relevant `How to Use` dialog and may start a guided tour.

The guided tour controls use the labels `Skip`, `Previous`, and `Next`. Help dialogs include `Start Tour` and `Close`.

Before the camera workflow is opened, STALA may require the user to choose a storage folder. The dialog is titled `Choose Save Folder` and explains that STALA uses the folder to save and import `.stala`, `.zip`, PNG, and PDF files. The dialog actions are `Cancel` and `Pick Folder`.

## 4. Capturing or Importing Sheet Music

### Camera Workflow

The camera screen provides a live camera preview with a visual grid, a shutter button, a gallery button, a back button, and a camera settings button.

<p align="center">
  <img src="./docs/STALA-UM/46.png" alt="Screenshot of Camera Page" width="50%" />
</p>

The user may:

- Tap the shutter button to capture a photo.
- Tap the gallery button to select an existing image.
- Tap the camera settings button to open `Camera Settings`.
- Return to the previous screen using the back button.

<p align="center">
  <img src="./docs/STALA-UM/47.png" alt="Screenshot of Camera Page (Settings)" width="50%" />
</p>

The `Camera Settings` sheet includes:

- `HD Capture`: switches between high-resolution and medium-resolution capture.
- `Flash Mode`: allows `OFF`, `AUTO`, or `ON`.
- `Current: OFF`, `Current: AUTO`, or `Current: ON`, depending on the selected flash state.

### Image Import from Gallery

The gallery workflow requires `Gallery / Photos Permission`. If permission is denied, STALA displays messages such as `Gallery permission was not granted.` or `Gallery permission is permanently denied. Please enable it in app settings.`

After an image is captured or selected, STALA opens the `Image Preview` crop interface. The source label may show `Captured Photo` or `From Gallery`.

### Document Detection and Crop Validation

<p align="center">
  <img src="./docs/STALA-UM/18.jpg" alt="Screenshot of Image Preview and Crop Page" width="50%" />
</p>

The crop interface allows the user to place the full music sheet inside the crop frame. The user can drag corner handles or edge handles. The main actions are:

- `Retry`: returns to the camera or image selection step.
- `Reset`: restores the detected or initial crop frame.
- `Continue`: validates the selected crop and proceeds to processing when acceptable.

The crop tour explains:

- `Line Up the Sheet`: keep the full sheet music page inside the crop area.
- `Adjust the Corners`: drag handles until the frame follows the page edges.
- `Crop Status`: review warnings when STALA detects a possible crop problem.
- `Reset Crop`: return the crop frame to its starting position.
- `Continue`: proceed when the sheet is lined up and ready to read.

STALA uses three crop validation states:

- Strong: the selected crop appears reliable and proceeds normally.
- Weak: the selected crop may be usable, but STALA asks the user to review it. The dialog title is `Music sheet needs review`, with actions `Adjust` and `Proceed`.
- Fail: the selected crop does not appear reliable. The dialog title is `Music sheet not confidently detected`, with actions `Adjust` and `Hold to Proceed`. A normal tap on the override button displays `Press and hold to proceed.`

Common crop messages include:

- `Crop is not allowed. Please fix the document bounds or tap Reset.`
- `Adjustment not allowed. Keep the crop as a quadrilateral.`
- `The selected crop may not be a reliable music-sheet region. Adjust the box or proceed?`
- `The selected crop does not appear to be a reliable music-sheet region. Please adjust the box, or press and hold to continue anyway.`
- `Crop reset.`

## 5. Processing Workflow

After the crop is confirmed, STALA opens the `Reading Sheet` page.

<p align="center">
  <img src="./docs/STALA-UM/28.jpg" alt="Screenshot of Processing Page" width="50%" />
</p>

The Processing Page displays a thumbnail of the cropped sheet, a status pill, a progress bar, and the number of completed steps. The main status labels are:

- `Working`
- `Ready`
- `Needs Retry`

The page title changes according to processing state:

- `Reading Your Music`
- `Tablature Ready`
- `Could Not Read Sheet`

The processing stages are:

1. `Preparing Image`: cleaning up the crop so notes and staff lines are easier to read.
2. `Finding Music Symbols`: looking for notes, accidentals, and clefs.
3. `Reading Staff Lines`: locating each staff so STALA can understand note positions.
4. `Interpreting Notes`: matching detected marks to pitches and guitar-friendly choices.
5. `Building Tablature`: creating the guitar tab and playback-ready result.

Each stage may show `Waiting`, `Working`, `Done`, or `Failed`. While processing is active, the footer displays `Keep this screen open while STALA reads the sheet.` If processing succeeds, the footer action becomes `Review Result`. If processing fails, the footer action becomes `Retry`.

System status messages include:

- `Getting your music sheet ready...`
- `Finding the notes and symbols on the page...`
- `Scanning the music symbols...`
- `Music symbols found. Reading the staff lines next...`
- `Reading staff lines and note positions...`
- `Connecting notes to their staff positions...`
- `Building your tablature result...`
- `Your guitar tablature is ready to review.`
- `Something went wrong while reading the sheet.`
- `No processing result available yet.`

## 6. Guitar Tablature Generation

STALA converts interpreted sheet music into tablature by resolving musical events and mapping them to guitar positions. The application groups detected notation by staff and measure, resolves clef and pitch context, interprets rhythm, pairs treble and bass staves when applicable, and selects playable string and fret combinations.

The generated tablature follows standard guitar string order:

- `E`: low sixth string
- `A`: fifth string
- `D`: fourth string
- `G`: third string
- `B`: second string
- `e`: high first string

When multiple notes occur together, STALA treats the event as a chord or multi-note event and selects fretboard candidates that are playable on guitar. The chord voicing logic favors practical fretboard movement and playable combinations. When only treble information is used, the result may appear under `Treble Only`. When grand staff interpretation is available, the result may appear under `Grand Staff`.

Because the generated output depends on image quality and symbol recognition, the user should review the tablature, playback, and fretboard map before relying on the result.

## 7. Results Interface

The `Result` page displays the generated tablature and related controls.

<p align="center">
  <img src="./docs/STALA-UM/36.jpg" alt="Screenshot of Result Page" width="50%" />
</p>

The top field is labeled `Filename`. The user may edit the filename and tap the check icon with tooltip `Apply filename`. If a duplicate title is used, STALA displays `A file named "[name]" already exists.` If the update fails, STALA displays `Failed to update filename: [error]`.

The result interface includes:

- `Choose a Tab Style`: switches between available generated modes, such as `Treble Only` and `Grand Staff`.
- `Tablature`: displays the generated tab. The subtitle states `Tap a fret number to jump to that event.`
- `Listen and Check`: provides playback controls.
- `Fretboard Map`: shows where the selected note or chord is played on the guitar neck. The subtitle states `Highlighted positions update per event.`

The tablature viewer allows the user to tap a fret number to focus on that event. The focused event is highlighted and synchronized with the playback and fretboard display.

Playback controls include:

- Go to first event.
- Move to previous event.
- Play or pause.
- Move to next event.
- Go to last event.

The playback panel also includes:

- `Speed`: selectable values from `0.50x` to `2.00x`.
- `Sustain notes`: keeps notes ringing longer during playback when enabled.

When the user taps a highlighted fretboard position, STALA opens a `Fretboard Position` sheet showing:

- `Pitch: [pitch]`
- `String [number], Fret [number]`

If no generated tablature is available, the Result page displays `No generated tablature available.`

## 8. Saving and Exporting

STALA supports session saving, PNG export, PDF export, ZIP package generation, and bulk ZIP export.

### STALA Session Files

Completed translations can be saved as `.stala` files. A `.stala` file stores the project name, original and cropped image paths, detected symbols, segmentation data, pitch and fretboard data, debug snapshots, generated tablature results, timestamps, model version, and auto-save metadata.

When `Enable Auto-save` is active, STALA automatically keeps each finished translation in the selected STALA library. The result page may display:

- `Auto-saved successfully.`
- `Auto-save failed. Manual export is still available.`

### PNG Export

The Result page includes an export button with tooltip `Save as PNG`. A successful PNG export displays `Saved PNG page(s) successfully.` A failed export displays `Failed to save PNG: [error]`.

PNG files are written to a generated folder under the selected storage location. The export orientation follows the `Tablature export orientation` setting.

### PDF Export

The Result page includes an export button with tooltip `Save as PDF`. A successful PDF export displays `Saved PDF successfully.` A failed export displays `Failed to save PDF: [error]`.

PDF files are written under the selected storage location. The export orientation follows the `Tablature export orientation` setting.

### ZIP Export

STALA can create ZIP packages containing STALA data and tablature images. Bulk export from the Home screen creates a ZIP archive containing selected `.stala` files and a manifest. A successful bulk export displays `Exported [number] STALA file(s) as ZIP.` A failed bulk export displays `Bulk export failed: [error]`.

### Storage Folder Requirement

Saving, exporting, importing, renaming, and deleting files require a selected STALA storage folder. If no folder has been selected, STALA may display `Choose a storage folder before importing or saving files.`

## 9. Search and Recent Sessions

The Home tab displays recent STALA projects from the selected storage folder. The number shown before `View all` is controlled by the `Recent file limit` setting. Saved items can be opened to restore a previous session without repeating the full recognition pipeline.

<p align="center">
  <img src="./docs/STALA-UM/39.jpg" alt="Screenshot of Home Page - Recent Files" width="50%" />
</p>

Recent project actions include:

- Open a saved project by tapping it.
- `Rename`: changes the visible project title and stored session title.
- `Delete`: removes a saved item after confirmation.
- Pin or unpin items in the internal recent-item model.
- Enter selection mode for bulk operations.
- Export selected items using the `Export selected` action.
- Delete selected items using the `Delete selected` action.

Deletion dialogs include:

- `Delete File`: asks `Delete "[title]" from saved items?`
- `Delete Files`: asks `Delete [number] selected STALA file(s)?`

The available actions are `Cancel` and `Delete`.

The Import tab lists saved and imported files from the selected STALA folder. If no local STALA files are found, it displays `No local STALA files found.`

The repository includes search behavior that filters saved items by title or file type. Where search is exposed by the interface, search results are based on the current saved item list and are case-insensitive.

## 10. Settings and Preferences

<p align="center">
  <img src="./docs/STALA-UM/48.png" alt="Screenshot of Settings Page" width="50%" />
</p>

The Settings page contains three expandable panels: `Controls`, `Permissions`, and `Information`.

### Controls

`Controls` is described as `Adjust how STALA saves completed translations.`

Available controls include:

- `Enable Auto-save`: automatically keeps each finished translation in the STALA library.
- `Save format`: currently displays STALA format only (`.stala`). The screen states: `STALA format only (.stala). ZIP and cloud save controls can be added when those workflows are ready.`
- `Recent file limit`: chooses how many recent items Home shows before View all.
- `Tablature export orientation`: chooses the layout used when exporting tablature PNG and PDF files.

The orientation control offers `Portrait` and `Landscape`.

Developer options may be unlocked from the `About Us` row after repeated taps. When unlocked, STALA displays `Developer debug option unlocked.` The developer controls include:

- `Reset tutorials`: shows first-visit page tours again on supported screens. The action button is `Reset`, and completion displays `Tutorials reset.`
- `Enable Debug Page`: controls whether the debug page appears before the Result page. The subtitle changes between `Debug page will appear before the Result page.` and `Processing will go directly to the Result page.`

### Permissions

`Permissions` is described as `Review and control app access permissions.`

The permissions panel includes:

- `Camera Access Permission`: required for capturing music sheet images.
- `Gallery / Photos Permission`: required for choosing source images from the gallery.
- `STALA Storage Folder`: used for visible `.stala`, `.zip`, and PNG exports.
- `Notification Permission`: required for save status and reminder notifications.

The storage folder row may show `Choose`, `Change`, or `Reset`. The file access dialog is titled `Allow STALA File Access` and explains that STALA uses the selected folder to save, import, export, rename, and delete `.stala` and `.zip` files. The actions are `Cancel` and `Choose Folder`.

When disabling permissions inside the app is not possible, STALA opens a dialog titled `[Permission Name] Permission`, explaining that the user will be redirected to App Settings. The actions are `Cancel` and `Open Settings`.

The accessibility prompt is titled `Enable Accessibility` and explains that accessibility access must be enabled manually in device settings.

### Information

`Information` is described as `Read the app version and project background.`

The panel displays:

- `Version: STALA v2.0.0`
- `Description: STALA helps translate piano grand staff notation into guitar tablature so musicians can review, save, and reopen playable guitar-focused results.`
- `About Us: STALA is developed by a student team building practical tools for music learners and guitar players who need a clearer path from sheet music to tablature.`

## 11. Notifications and System Messages

STALA uses dialogs, validation overlays, snackbars, and status labels to guide the user.

### Tutorial and Help Messages

The main help dialogs are:

- `Welcome to STALA`: introduces the camera button, Import tab, and image quality advice.
- `Start a Project`: explains that users can capture sheet music, choose an image, or reopen saved work.
- `Import and Continue`: explains file import and folder selection.
- `Prepare the Sheet`: explains crop adjustment, Reset, and Continue.
- `Reading the Music`: explains that processing may take time and recommends trying a clearer photo if reading fails.
- `Review the Tablature`: explains reviewing, playback, fretboard checking, mode switching, and export.

If a tour cannot start, STALA displays `The tour could not start on this screen. Please try again.`

### Common Dialogs

- `Choose Save Folder`: prompts the user to select a folder before camera use.
- `Choose Import Folder`: prompts the user to select the folder used for imported and exported files.
- `Rename File`: includes the input hint `Enter new title` and actions `Cancel` and `Save`.
- `Delete File`: confirms single-item deletion.
- `Delete Files`: confirms bulk deletion.
- `Music sheet needs review`: asks whether to adjust or proceed with a weak crop.
- `Music sheet not confidently detected`: requires adjustment or a long-press override.

### Common Snackbars and Alerts

- `Failed to initialize camera: [error]`
- `Failed to change flash mode: [error]`
- `Failed to capture image: [error]`
- `Failed to open gallery: [error]`
- `Failed to open saved item: [error]`
- `Failed to import file: [error]`
- `Import failed: [error]`
- `Imported [number] STALA file(s).`
- `Skipped [number] duplicate(s).`
- `Skipped [number] invalid file(s).`
- `ZIP does not contain any .stala files.`
- `Choose a .stala or .zip file.`
- `Invalid .stala file: missing session data.`
- `A file named "[name]" already exists.`
- `Saved PNG page(s) successfully.`
- `Saved PDF successfully.`

## 12. Troubleshooting

### Camera Does Not Open

If STALA displays `Camera unavailable`, use `Retry`. If permission is missing or permanently denied, tap `Settings` and enable camera access in Android App Settings.

### Gallery Import Fails

Ensure `Gallery / Photos Permission` is enabled. If the permission is permanently denied, enable it in Android App Settings. Use clear image files that contain the complete sheet music page.

### Crop Cannot Continue

If STALA displays `Crop is not allowed. Please fix the document bounds or tap Reset.`, adjust the crop into a valid four-sided shape or tap `Reset`. If the message says `Adjustment not allowed. Keep the crop as a quadrilateral.`, move the handles so the crop remains a proper page-shaped region.

### Music Sheet Is Not Confidently Detected

Use `Adjust` to refine the crop. The `Hold to Proceed` option should only be used when the user intentionally accepts the risk of reduced recognition quality. A better image usually produces a better result than overriding a failed validation.

### Processing Fails

If the Processing Page shows `Could Not Read Sheet` or `Needs Retry`, tap `Retry`. If repeated attempts fail, return to the capture step and use a clearer, flatter, better-lit image. Avoid glare, shadows, skew, and missing staff lines.

### No Generated Tablature Appears

If STALA displays `No generated tablature available.`, the processing pipeline did not produce a usable tablature result. Reprocess a clearer image or use a more accurate crop.

### Export Fails

If PNG, PDF, or ZIP export fails, verify that a STALA storage folder has been selected and that the app still has access to it. Reopen Settings, choose or change `STALA Storage Folder`, and retry the export.

### Import Fails

Only `.stala` files and ZIP archives containing `.stala` files are supported. If the file is duplicated, rename or remove the existing saved item. If the ZIP contains no valid `.stala` file, STALA will reject it.

### Filename Update Fails

If a duplicate filename message appears, choose a different filename. STALA sanitizes filenames by replacing unsupported filename characters and spaces.

## 13. Tips and Best Practices

For best recognition quality:

- Capture the sheet in bright, even lighting.
- Keep the whole sheet visible in the frame.
- Avoid shadows, glare, blur, and strong perspective tilt.
- Place the page flat before taking the photo.
- Make sure clefs, staff lines, notes, accidentals, stems, beams, and bar lines are visible.
- Use `HD Capture` when image detail is important.
- Use `Reset` if manual crop adjustments make the crop invalid.
- Review the generated tablature before exporting or sharing.
- Use playback and the `Fretboard Map` to identify unusual results.
- Keep a selected STALA storage folder so save, import, export, rename, and delete operations remain available.

## 14. Glossary

- Accidental: A symbol such as sharp, flat, or natural that changes pitch.
- Auto-save: The setting that automatically stores a completed translation in the STALA library.
- Bar line: A vertical line separating measures in staff notation.
- Chord voicing: The selected arrangement of chord notes across guitar strings and frets.
- Crop: The selected image region containing the sheet music page.
- Fretboard Map: The visual guitar-neck display showing the current string and fret positions.
- Grand Staff: A combined treble and bass staff system, commonly used in piano notation.
- Ledger line: A short staff extension used for notes above or below the staff.
- Measure: A segment of music separated by bar lines.
- Notehead: The oval part of a note symbol used to determine pitch position.
- Processing pipeline: The sequence of image analysis, music interpretation, and tablature generation stages.
- STALA file: A `.stala` project file containing saved session and tablature data.
- Tablature: Guitar notation that indicates string and fret positions.
- Treble Only: A generated mode based on treble-staff interpretation.

## 15. Appendix

### Supported User Workflows

- Capture a new music sheet image.
- Select an existing image from the gallery.
- Confirm or adjust a detected crop.
- Process the cropped sheet into tablature.
- Review generated tablature.
- Play or step through generated events.
- Inspect fretboard positions.
- Rename a result file.
- Export as PNG.
- Export as PDF.
- Auto-save and reopen `.stala` sessions.
- Import `.stala` files.
- Import ZIP archives containing `.stala` files.
- Bulk export selected STALA files as ZIP.
- Open optional debug results when developer debug mode is enabled.

### Supported Formats and Locations

- `.stala`: primary STALA session format.
- `.zip`: supported for importing archives containing `.stala` files and for bulk export.
- `.png`: tablature image export.
- `.pdf`: tablature document export.

STALA writes saved sessions under a `saved` area in the selected storage folder. PNG exports are written under a generated photo export folder. PDF exports are written under a PDF export area. ZIP exports are written under a ZIP export area.

### Debug Page

When `Enable Debug Page` is active, STALA can show `Debug Results` before or from the result workflow. This page is intended for diagnostic review and includes:

- `Input & Crop`
- `Detection Results`
- `Staff Validation`
- `Structural Segmentation`
- `Musical Interpretation`
- `Tablature Generation`
- `Reports`

The debug page may also show empty-state messages such as `No cropped image available yet.`, `No detected image available yet.`, `No segment image available yet.`, `No translation data available yet.`, `No note groups available yet.`, `No rhythm estimates available yet.`, and `No report data available yet.`

### Processing Summary

The complete STALA workflow can be summarized as:

1. Image capture or import.
2. Document detection and crop validation.
3. Confirmed cropped sheet image.
4. Music symbol detection.
5. Staff segmentation.
6. Symbol-to-staff grouping.
7. Pitch, rhythm, and grand staff interpretation.
8. Fretboard mapping and chord voicing.
9. Tablature generation.
10. Result review, playback, save, and export.
