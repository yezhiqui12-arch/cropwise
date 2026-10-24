# Mobile assessment results and recommended steps

Implemented 11 October 2026. This change preserves existing sample and expert calculations.

## Results

- One findings report leads with model damage screening before finalization and mean Davis severity after a valid finalized review loads.
- Provisional sampled infestation, potential larvae/frass/eggs, expert damage incidence and original screening remain separate measurements. Each rate retains its own plant denominator; missing findings stay unavailable.
- Block summaries show the recorded damage distribution against the 20-plant plan. Human-readable Block and Plant labels replace navigation IDs in recommendations.
- Calculation help explains each measurement, including evidence exclusions and the difference between old damage and fresh damage.
- Contextual symbols replace the Material leaf icons across the mobile app.

## Recommendation diagnosis and changes

The previous AI prompt allowed a single recommendation. The secondary list removed the primary recommendation and displayed a collapsed “More steps” section, so a one-item response left no additional useful guidance. Local fallback checks used broad evidence counts rather than the full saved plant findings. Cached advice could preserve that thin response.

The result flow now supplies evidence-matched per-plant results, sign detection coverage, sample completeness, crop stage, finalized findings and saved reviewer messages. Relevant recorded checks are included in the prompt. The response validator rejects monitoring-only advice and adds omitted applicable saved-fact checks with a visible source label. Numerical validation accepts the supplied block/plant identities and counts. Advice is not truncated to four items. Existing unsupported treatment/timing checks remain.

Following design review, field interpretation now leads the Recommendations tab with a short takeaway, provisional signs and one relevant evidence note. Its full explanation and AI controls expand on tap. Recommended steps also start collapsed: titles, source and plant locations remain visible; descriptions and action links appear when opened. Focused widget checks cover both disclosures at normal and 2x text size.

The expert leaf-damage review page uses a severity overview, separate damage/infestation rates and a score distribution. Plant reviews appear directly in a responsive photo-and-review grid, ordered by highest score, without block dropdowns or expandable rows. Each card shows its score guide, freshness and saved expert note beside its submitted evidence. Large text and narrow phones use a single column. Full-screen photo enlargement, refresh, established mean-completeness rules and supplied metric denominators remain. The expert inbox uses three-line case cards (under 100 logical pixels at normal text size) and a single top-right filter menu for All cases, Photos needed and Finalized. Conversation headers, message spacing and finalized-findings notices are compact. Six focused widget checks passed, including normal/2x layouts, incomplete ratings and the existing targeted reply flow; rendered fixture previews were inspected.

The follow-up implementation replaces those disclosures with separate detail modals. Recommendation rows open a modal with an illustrated icon header, plant-location panel, readable guidance and a fixed action button. Field interpretation now shows recorded results only; View results opens the numeric findings modal, while AI controls live in Guidance settings. Saved numeric observation values are validated before entering checkbox controls. Recommendations remain available from provisional screening while expert review is pending. Cache v7 refreshes older advice.

“Recommended steps” displays the complete list, emphasizes the first action, and links specific references to plant evidence. It handles missing photos, unavailable screening/detection, potential signs, incomplete sampling, severe individual ratings and differences between model and expert findings. Finalized expert review supersedes provisional sign follow-ups. Local guidance is labeled separately from AI, and AI errors and retry are visible. The recommendation cache version is now v6 and still checks the saved-facts fingerprint.

## Verification

- Eight focused tests passed: saved-fact recommendations, missing photos, expert precedence, entry safety, zero-damage guidance, actual result/recommendation widgets at normal and 2x text on small screens, and separate finalized metrics.
- PNG previews were rendered from production widgets using an in-memory saved assessment, then visually inspected. These are fixture previews, not screenshots from the installed phone app.
- Static analysis was limited to changed result/recommendation components and checks. No full app or dashboard test suite was run.
- No live AI request, APK build or phone installation was performed. Validate the configured AI service and rebuild the mobile app when deploying these source changes.
