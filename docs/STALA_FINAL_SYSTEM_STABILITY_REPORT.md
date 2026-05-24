# STALA Final System Stability Report

## System Status

STALA is stable for thesis/demo use. The current architecture should be treated as a structure-aware OMR pipeline rather than a pure detector pipeline: ONNX proposes symbols, OpenCV extracts staff structures, Dart validation filters symbols semantically and structurally, and the translation services consume only validated or explicitly inferred musical structures.

Status by subsystem:

| Subsystem | Status | Notes |
| --- | --- | --- |
| ONNX symbol detection | Stable | Produces raw proposals in original image coordinates. Remaining misses are model/input dependent. |
| OpenCV staff segmentation | Partially variable | Sensitive to crop margins, foreground density, thresholding, and projection strength. |
| Staff locking and handoff | Stable | Validated staffs are locked, sorted deterministically, and preserve original image coordinate space. |
| Semantic filtering | Stable | Clef, key-signature, and time-signature regions are differentiated. |
| Clef safety | Stable with edge cases | Core/expansion/transition penalties and bass-clef dominance suppression exist. |
| Time-signature suppression | Stable | Vertical stack detection and semantic penalties reject numeral-like noteheads without weakening key signatures. |
| Ledger validation | Stable with minor variability | Raw ledger noteheads now receive small preservation bias only when ledger support and geometry are plausible. |
| Barline refinement | Stable | Uses relational staff alignment, span checks, and stem/notehead collision rejection. |
| Translation pipeline | Stable | Consumes validated structures without coordinate conversion or graph mutation. |
| Debug overlays/reports | Stable | Overlays use the same staff, ledger, stem, beam, barline, semantic-region, and symbol graph records emitted by processing. |

## Current Architecture

The processing flow is:

1. Image capture/import and crop selection.
2. Native OpenCV document/crop validation.
3. ONNX multiclass symbol detection.
4. Native OpenCV staff segmentation, including staff lines, ledger lines, stems, beams, barlines, and measures.
5. Dart structural filtering over raw ONNX detections.
6. Semantic-region filtering for clef/key/time areas.
7. Symbol graph creation with detected, rejected, and inferred states.
8. Barline refinement and measure rebuilding.
9. Translation grouping by staff and measure.
10. Clef, key signature, accidental, pitch, rhythm, grand-staff, fretboard, and tablature interpretation.
11. Debug snapshot, visual overlay, save/export output.

The architecture is modular and should not be redesigned for the remaining issues.

## Confirmed Stable

- Original-image coordinate space is preserved across native and Dart stages.
- Staffs are frozen with stable line ordering, canonical spacing, `locked: true`, and `coordinateSpace: original_image`.
- Staff ordering now uses deterministic tie-breaks in segmentation, processing freeze, barline refinement, and translation grouping.
- Clefs are preserved as musical anchors while nearby notehead-like artifacts are penalized.
- Key signatures are valid semantic structures and are not globally rejected for being near clefs.
- Time-signature-like vertical notehead stacks are still suppressed inside time-signature semantic regions.
- Ledger-note inference is non-recursive and requires validated ledger/stem structure.
- Barline validation is relational rather than purely local.
- Translation consumes graph-filtered symbols and does not inject invalid downstream symbols.
- Debug overlays are synchronized with the same processing records used by interpretation.

## Improvements Already Applied

- Clef safety regions with core, expansion, and transition areas.
- Bass-clef core dominance suppression.
- Center-stem suppression near clef and semantic regions.
- Pre-measure semantic roles: clef transition, key signature, and time signature.
- Key-signature preservation for sharps/flats in the key-signature semantic region.
- Vertical time-signature-like stack rejection.
- Ledger validation using staff virtual lines, geometry, notehead/stem support, thickness, and fragment checks.
- Small ledger continuity support in native ledger extraction.
- Raw-detected ledger-note preservation bias in Dart structural validation.
- Deterministic staff candidate sorting and handoff ordering.
- Barline refinement with grand-staff alignment and collision checks.
- Pipeline reporting for staff, symbols, segmentation counts, ledger diagnostics, validation, translation, and coordinates.

## Structural Validation Hierarchy

The validator follows a layered hierarchy:

1. Geometry and coordinate validity.
2. Staff or ledger region support.
3. Notehead morphology and staff/virtual-line alignment.
4. Structural support from ledger, edge stem, beam, chord/nearby note, or rhythmic neighbor.
5. Semantic conflict checks for clef, time signature, and post-clef regions.
6. Clef safety core/expansion/transition penalties.
7. Time-signature stack penalties.
8. Final score threshold.
9. Optional inferred ledger recovery only when a validated ledger and stem exist.

This hierarchy prevents raw detections from bypassing structural context while allowing musically plausible ledger notes to survive minor threshold variation.

## Ledger Validation Logic

Native ledger validation:

- Searches virtual ledger rows above and below each staff.
- Requires plausible horizontal segment width, thickness, and low text-like fragmentation.
- Requires supporting notehead or stem structure.
- Deduplicates ledger segments deterministically.
- Applies small continuity support when neighboring ledger structures are aligned.

Dart notehead validation:

- Treats raw ONNX noteheads with ledger support as ledger candidates.
- Applies a small preservation bias only when confidence, morphology, and alignment are plausible.
- Adds small edge compensation for ledger candidates without neighbor context.
- Adds small continuity relaxation when neighboring ledger structure exists.
- Blocks preservation when semantic conflict, clef core conflict, or isolated center-stem conflict exists.

This is intentionally a bias, not an override.

## Semantic Filtering Logic

Semantic regions are divided by role:

- `clef`: immediate transition after clef, still suppressive.
- `keySignature`: valid accidentals are preserved.
- `timeSignature`: notehead-like vertical stacks are suppressive.

This prevents key signatures from inheriting notehead/time-signature penalties while preserving time-signature suppression.

## Clef Safety Logic

Clef safety uses:

- Direct clef preservation.
- Clef safety regions around detected clefs.
- Core overlap penalties.
- Expansion and transition penalties.
- Center-stem penalties near clefs.
- Bass-clef core reinforcement.
- Rhythmic/ledger/beam/chord exceptions outside the clef core.

Remaining bass-clef leakage is usually caused by ONNX notehead boxes landing just outside the core region or by local crop/threshold variance creating plausible stem support.

## Stem Attachment Logic

Stem attachment is classified as:

- left edge
- right edge
- center
- unknown

Edge stems can support noteheads. Center stems are treated suspiciously near clefs/time signatures and are penalized more strongly when beam/rhythmic support is missing.

## Barline Validation Logic

Barlines are detected natively from vertical morphology and refined in Dart. Refinement checks:

- adjacent staff alignment
- grand-staff span
- whether the barline exists only inside one staff
- collision with noteheads
- collision with stems

This is preferable to hard global rejection because real barlines vary by score style and crop.

## Staff Stabilization Logic

Staff segmentation uses:

- row strength
- row continuity
- longest-run support
- projection strength
- five-line candidate validation
- spacing consistency
- symbol support
- deterministic candidate sorting
- locked validated spacing

Remaining drift is primarily OpenCV/image variability from crop spacing, thresholding, foreground/background ratio, and line-density changes.

## Debug and Report Infrastructure

Debug output includes:

- staff integrity checks
- coordinate lock logs
- segmentation counts
- semantic region counts
- clef region stats
- rejection stats
- inferred symbol counts
- ledger diagnostics
- `LEDGER_STABILITY` logs for raw ledger candidates, preserved candidates, rejected candidates, edge candidates, continuity relaxations, and ledger rejection reasons
- frozen debug snapshot for overlays and reports

## Deterministic, Probabilistic, Threshold-Sensitive, and Crop-Sensitive Systems

Deterministic systems:

- staff freeze and ordering
- symbol graph state assignment
- semantic-region generation from detected clefs/staffs
- clef/key/time semantic role handling
- barline refinement ordering
- translation grouping and pitch mapping
- debug snapshot construction

Probabilistic/OpenCV-sensitive systems:

- raw ONNX symbol confidence and box placement
- staff-row extraction after thresholding
- ledger segment extraction
- stem/beam extraction
- barline morphology extraction

Threshold-sensitive systems:

- staff row continuity and projection thresholds
- ledger virtual-line tolerance
- ledger segment width and thickness checks
- notehead morphology/alignment thresholds
- time-signature stack grouping
- clef overlap and center-stem penalties

Crop-sensitive systems:

- staff spacing estimation
- foreground/background ratio
- row projection strength
- edge/end ledger notes
- measure-ending and phrase-ending context

## Root Causes of Remaining Instability

Remaining instability is not primarily architectural. It is mostly caused by image-processing variability:

- crop margins alter staff spacing and row projection strength
- thresholding changes foreground density
- OpenCV morphology can split or merge thin ledger/staff segments
- edge ledger notes have less neighboring support
- final notes at phrase/measure endings have weaker rhythmic context
- notehead boxes near clefs/time signatures may overlap suppressive semantic regions
- isolated vertical artifacts can resemble stems or barlines when aligned with staff height

## Architectural Safety Verification

- No coordinate drift: coordinates remain in original image space.
- No recursive inference loops: inferred ledger notes are generated only once from validated ledger/stem structure.
- No destructive filtering: rejected symbols remain visible in symbol graph/debug data.
- No circular notehead validation: validation uses raw symbols and structural detections, not recursively validated noteheads.
- No invalid downstream symbol injection: translation consumes `translationDetections`, not rejected nodes.
- No translation graph corruption: symbol state and validation metadata are additive.
- No overlay desynchronization: overlays consume the same structures emitted by processing.

## Known Limitations

- Bad crops can still alter staff spacing and ledger extraction.
- Very weak edge ledger notes can remain unstable if ledger segments are missing.
- Text artifacts can survive if their geometry mimics notehead/stem structure.
- Isolated vertical artifacts can survive if they align like barlines across staff pairs.
- Bass-clef leakage is reduced but not impossible when detections fall outside the clef core.
- Time-signature suppression depends on detected notehead-like boxes forming a vertical stack.

## Post-Defense Safe Improvements

- Add a small golden-image regression suite for representative clef, time-signature, ledger, and barline cases.
- Store per-stage diagnostic snapshots for before/after structural validation.
- Add configurable debug-only threshold visualizations for staff and ledger extraction.
- Add a non-ML crop quality score that warns users when staff margins or foreground density are risky.
- Add optional per-measure ledger continuity grouping after barline refinement.
- Add more explicit symbol provenance in saved `.stala` sessions.

## Final Assessment

The current architecture is sufficiently stable. The remaining instability is mostly expected OpenCV/crop variability and threshold sensitivity, not a design flaw. Future work should focus on test fixtures, diagnostics, and input-quality guidance rather than architecture rewrites.
