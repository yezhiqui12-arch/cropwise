# DA assessment results screen

Implemented 6 October 2026. New assessments using `wormwise-da-scattered-20-v1` open the redesigned **Plants** and **Recommendations** results tabs. Legacy assessments retain their **Stations** results section. Submission, exports, calculations and AI services retain their existing behavior.

## Visible changes

- **Sample completion:** recorded plants, required sample count, saved/reviewed plants, and plants not yet recorded. Required counts use the saved assessment outline and existing 20-plants-per-block policy. Preliminary or invalid samples are not presented as completed.
- **Damage screening:** positive / assessable sampled plants × 100, screened negatives, and recorded plants with unavailable screens. Missing plants and unavailable screens are not counted as negatives. A zero denominator shows `Not available`. Three photographs of the same plant still represent one plant.
- **Expert severity:** the mean of actual finalized Davis scores, on the 0–9 scale. Zero scores contribute to the sum and denominator; insufficient evidence and unscored plants do not. The card states how many of the expected sampled plants were scored and displays the finalization date. Until a review is available, it shows `Awaiting expert review`. Fetch failures and incomplete/ambiguous ratings have separate unavailable states and retry controls.
- **Next action:** continue an incomplete sample, submit completed evidence, follow an existing expert case, or open finalized expert findings. A separate link opens Recommendations. The existing submission dialog still collects required details and handles connectivity and account requirements.
- **Sampled plants:** Plant 1–20 per block, photo cards, screening status/confidence, photo counts, a notes indicator and finalized Davis ratings when available. Filters show counts for all, positive and screening-unavailable plants, without selected checkmarks. Opening a recorded plant shows its existing read-only details and evidence. Larger text and narrow screens use a single-column layout.
- **Results map:** individual plants use numbered P pins with positive/negative/unavailable symbols. No station percentage bands or connecting walking lines are applied to the new sampling protocol. Generated targets remain distinguishable from actual phone GPS locations.

## Calculation and review rules

`DaSampleResults` reads one active plant record at each unique block/location. Ready, non-deleted photos are counted separately. This presentation does not write screening metrics or convert model suggestions into confirmed infestation.

The existing cloud review service supplies cases linked to this exact assessment. The results section selects the latest available finalized review and loads its plant ratings. The saved median is not reused as an average. The actual ratings must match the finalized summary's reviewed, scored, and insufficient-evidence counts. Ratings outside 0–9, duplicate plant keys, and ambiguous associations produce no average.

The backend's actual unscored outcome is `insufficient_evidence`; the implementation matches that schema. The 6 October block-identity revision now includes block identifiers in evidence and expert ratings and supports a validated multi-block mean. Unresolved historical associations remain withheld. See [BLOCK_SCOPED_EXPERT_REVIEW.md](BLOCK_SCOPED_EXPERT_REVIEW.md) for the source changes, migration and deployment state.

Expert findings remain a separate measurement from automatic damage screening. No percentage or hectares of damaged field area are inferred from Davis scores. This phase does not change the PDF contents, dashboard analytics, scoring workflow, or live backend schema.

## Files

- `lib/models/da_assessment_results.dart`: unique plant counts and validated expert mean.
- `lib/screens/assess/da_assessment_results_section.dart`: completion, screening, severity, action, and plant-list cards.
- `lib/screens/assess/assessment_results_screen.dart`: DA/legacy routing, tab label, and map behavior.
- `test/models/da_assessment_results_test.dart`: calculation and evidence-count checks.
- `test/screens/da_assessment_results_test.dart`: screen, retry, stale-review, action, accessibility, and legacy-destination checks.
- `test/support/da_results_fixture.dart`: persisted 20-plant assessment fixture using the real completion service.

## Verification

Fourteen results tests passed: seven model tests and seven widget tests. They cover 4/20 = 20%, unavailable and missing plants, unavailable denominators, multiple photographs of one plant, missing/deleted evidence, zero-inclusive Davis means, insufficient evidence, invalid/duplicate/ambiguous ratings, retry, changed review loading, positive filtering, submit action, 200% text at 320-pixel width, and DA/legacy result destinations.

The combined results/scouting regression run also passed 24 tests. The existing broad legacy results suite was attempted but stalled during fixture setup under Flutter's fake clock; the new focused legacy-destination test uses real asynchronous fixture setup and passes. A few existing nullable-boundary fixture references were corrected so these tests compile. The full application suite is not claimed to pass.

The results-card widget render was visually checked with real fonts. Device navigation and a live finalized review still need verification with a connected account and handset. No remote data was changed, and no build was installed on the user's phone.

## Next phase

7 October update: DA observational PDF export is now implemented through the mobile Export PDF action. It uses Itlog/Larba/Pupa/Pinsala presence checkboxes, saved rainfall, optional farmer corrections and block natural-enemy confirmation. Davis severity stays separate. See [DA_MONITORING_EXPORT_IMPLEMENTATION.md](DA_MONITORING_EXPORT_IMPLEMENTATION.md) for the implemented scope.

Update the generated report to use the same plant counts, screening availability, expert mean and review coverage, then implement the separately requested barangay positive-case percentage with an explicit case-status rule and reporting period.

## Full visual revision

The DA results destination now uses a compact field header, a forest-green screening summary with a rate ring and separate positive/negative/unavailable counts, smaller completion and severity cards, and one action panel. The formula is available through the summary information button rather than repeated explanatory paragraphs. Preliminary samples and unavailable scores remain explicit, and the stored calculation rules above are unchanged.

Sampled plants use two-column photo cards with short status labels, confidence, photo counts and finalized scores. Empty filters have a dedicated state; missing photo files show a placeholder. Filter selection is shown by color without checkmarks. Ready photos remain real saved evidence; no stock photos are inserted into assessment records.

Recommendations keeps the existing AI/local step selection and action handlers. Its primary step is compact, with Details available on demand. Field interpretation, submission and management open as expandable sections. Each section has its own saved expansion key, so expansion state does not conflict with the scroll position. The AI opt-in, data sharing and reporting services are unchanged.

The field header, tab controls, plant cards and persistent map/export bar were inspected in Flutter renders. Tab labels, large numbers and toolbar labels fit their available space. At 200% text size the interface remains scrollable and the controls remain reachable.

Validation: all 16 focused tests passed across test/screens/da_assessment_results_test.dart and test/models/da_assessment_results_test.dart. They include the actual results destination and both tabs, no-checkmark filters, empty/unavailable states, photo-card navigation, finalized zero-inclusive Davis scores, failed fetch/retry, review changes, legacy destination and large text. Analysis of the three changed source/test files found no errors or warnings, with two style information messages. A broader legacy screen-suite attempt stalled at its initial assessment-details navigation test and was stopped; the full suite is not claimed to pass.

The screenshot photo fixture uses existing maize reference assets only in tests. The production thumbnail source is saved assessment evidence. Screenshots are saved in C:/Users/marka/Documents/Codex/2026-10-02/an/outputs/results-visual-after. The pre-change files are retained in outputs/results-visual-before. Device installation and physical-phone verification were not performed in this revision.
