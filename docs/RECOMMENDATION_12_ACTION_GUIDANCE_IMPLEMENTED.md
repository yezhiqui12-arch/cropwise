# Recommendation 12: actions while scouting

Implemented on 2026-10-07 in the mobile application. Updated the same day to make a modal notification the primary entry point after a finding is detected, following the user's correction that inline guidance could be missed. This change adds immediate action guidance and offline photo comparison during DA guided scouting. Dated follow-up notifications remain separate work.

## Farmer experience

1. Capture or import the plant's photos and screen them using the existing computer-vision flow.
2. Screening raises a **Damage detected**, **Larva detected**, **Eggs detected**, **Frass detected**, or combined **Findings detected** modal. It shows the plant number, comparison photos and action steps. **Continue scouting** stays visible below the scrolling content; dismissing the modal does not claim an action was performed. It appears even when the draggable plant sheet is collapsed and the map is expanded.
3. Each action type automatically notifies once per assessment. Additional photos, the same finding on later plants, or resuming the assessment do not repeatedly interrupt the farmer. A new action type can raise another modal. A notice waits until the camera/import route closes. Stale loads from a previous plant and completed plant reviews cannot raise automatic notices. Clear and unavailable results do not raise action notices.
4. A compact **At this plant** card remains below the photos in the scouting sheet, and the shared guide remains available in plant-pin details and saved DA plant details. Imported or saved evidence uses **When you inspect this plant** instead of implying that an old photo describes what is present now.
5. **Your photo** appears beside a licensed reference. Tap either image to open a zoomable view. Reference photographs are bundled and work offline.
6. **How** expands the guide at any time. **Show less** remembers the card preference for that farmer across assessments. It does not suppress the first automatic notice in a new assessment. Merely displaying or dismissing a guide does not record that the farmer read it or performed an action.
7. Optional **Removed and destroyed**, **Destroyed**, or **Checked** records the farmer's reported action. **Undo** reverses it. Saving and moving to the next plant remains available without recording an action.
8. Assessment results show **Actions recorded** when records exist. Counts represent plants with reported actions, not numbers of larvae or eggs, and do not claim the field is now pest-free.

## Finding-to-action rules

| Finding | Guide | Reference |
| --- | --- | --- |
| Detected larva | Compare identifying features. For identified, reachable young FAW larvae, use tweezers or small forceps, avoid tearing the whorl, and crush the removed larva with the tool on a firm surface. | Real FAW larva photograph |
| Detected eggs | Compare the cluster. Destroy an identified FAW egg mass with a small tool and firm backing without tearing the leaf. Do not destroy unknown insects or beneficial organisms. | Magnified FAW egg photograph, including some hatched shells |
| Frass without a detected larva | Inspect the whorl and newest leaves for a feeding larva; compare any larva found and optionally add a closer photo. | Larva reference, explicitly labelled as the larva to look for rather than a frass photograph |
| Damage without detected larvae, eggs or frass | Inspect damaged leaves and the whorl, preserve evidence before intervention, and avoid treating old damage as proof of current feeding. | Real leaf feeding damage photograph |

Multiple photos and boxes produce one guide per action type per plant. A detected larva suppresses redundant frass inspection guidance; eggs can have a separate action on the same plant. Current optional DA observation corrections affect guidance, while stale corrections with a different evidence signature do not. Corrections and actions do not rewrite original model output.

[FAO's management guidance](https://www.fao.org/newsroom/detail/FAO-launches-guide-to-tackle-Fall-Armyworm-in-Africa-head-on/en) supports manual crushing of identified egg masses and young larvae. The explicit tool-handling instructions are a practical application adaptation, not a quotation of a DA procedure. This distinction and source are available in the guide's information dialog. No automatic pesticide selection, treatment threshold, dosage or spray instruction was added.

## Implementation

| Component | Responsibility |
| --- | --- |
| `lib/models/plant_action_guidance.dart` | Fixed guide text, finding resolution, versioned preferences, reference metadata and action record model |
| `lib/data/repositories/plant_action_repository.dart` | Persist first offers, collapsed preferences, active optional actions and undo history |
| `lib/screens/scan/plant_action_guidance_panel.dart` | Shared card, comparison, zoom, source information, scoped asynchronous loading and optional action buttons |
| `lib/screens/scan/plant_action_notice_host.dart` | Modal notification outside the draggable panel, one per action type per assessment, route-aware timing and stale-load protection |
| `lib/screens/scan/plant_action_summary.dart` | Watch and display saved action counts in results |
| `lib/providers/five_station_workflow_provider.dart` | Expose the scoped action repository and refresh guidance after an optional observation correction |
| Guided walk, pin details, plant inspector and saved plant details | Mount the same shared card without altering camera or model navigation |
| `assets/images/faw_actions/` and `pubspec.yaml` | Bundle three licensed, offline reference photographs |

Production comparison selects a saved evidence file matching the relevant detection's source filename/path when possible; it falls back to the first available evidence photo. It does not read arbitrary paths supplied by model metadata. Reference licensing is documented in the asset README and the retained provenance JSON.

Records are stored in existing local `AppPreferences`, scoped by farmer, assessment, block run and plant number. Block 1 / Plant 7 cannot overwrite Block 2 / Plant 7. Actions preserve the evidence signature and original action time; adding another photograph does not pretend that an earlier action was performed again. Records retain undo history and use the existing private SQLite account-backup change event.

Automatic notice history is separate (`plant_action_notices_v1_<owner>_<assessment>`). It records only that an action type was displayed, after its modal reaches a frame. It neither records removal nor marks the guide learned. A remembered collapsed card cannot hide the first notice of a new assessment.

**No local schema change or Supabase migration is required.** Existing AI models, prompts, detection thresholds, Davis calculations, DA observation values and assessment infestation denominators remain unchanged by action recording. No expert dashboard action-sync schema or new operating-system notification scheduling is included in this change. Explicit dated follow-up notifications remain separate work.

One related responsive fix increases the existing Guidelines category-card height with text scaling to remove an overflow found during results-to-guidelines navigation testing.

## Validation

Validation covers guide deduplication, twenty affected plants, current/stale corrections, persistent preferences, owner/block isolation, recording and undo, real offline image decoding/rendering, zoom, large text, guided map/plant details, results navigation, DA completion and legacy workflow behavior. Modal-specific tests verify automatic display over an expanded map, repeated-photo/plant suppression, a new finding type, persistence after resume, unchanged action records on dismissal, small screens with 200% text, clear/unavailable/completed results, stale previous-plant loads, and waiting for the camera route to close.

```powershell
flutter test --no-pub test/screens/plant_action_guidance_test.dart test/screens/guided_plant_walk_step_test.dart test/screens/guided_plant_details_sheet_test.dart test/screens/da_assessment_results_test.dart test/screens/da_plant20_confirmation_test.dart test/database/da_guided_scouting_test.dart --reporter expanded
```

Optional widget previews: set `WORMWISE_ACTION_PREVIEW=1`; the action test writes `work/plant-action-modal.png`, `work/plant-action-first-use.png` and `work/plant-action-repeat-use.png`. Their farmer photograph is fixture evidence, not a new real field observation. Device camera capture and installation have not been verified on the physical phone in this change.
