# WormWise pesticide advisory research and validation plan

## Objective

Determine whether and how WormWise can safely present assessment-linked pesticide options for fall armyworm in maize in the Philippines. The intended feature is regulated decision support, not an AI prescription, diagnosis, treatment order, or substitute for a current product label and qualified local advice.

## Fixed scope

- Jurisdiction: Philippines, with priority given to the Fertilizer and Pesticide Authority (FPA), Department of Agriculture (DA), Bureau of Plant Industry (BPI), and Regional Crop Protection Centers (RCPCs).
- Crop and pest: maize/corn and fall armyworm (*Spodoptera frugiperda*) only.
- Decision context: completed WormWise field assessments using the app's current evidence definitions.
- Application methods: each method is treated as a separate authorization. Drone registration must never imply authorization for knapsack, ground, aerial, seed-treatment, or other use.
- Output: a cited research reference, a regulated catalogue schema, a deterministic eligibility design, prohibited-content rules, validation requirements, and an explicit gap register.
- Excluded from this research release: farmer-facing product recommendations, generated dose/rate advice, tank mixtures, off-label uses, purchasing links, and automatic treatment decisions.

## Source hierarchy

1. Current FPA registered-product datasets, product registrations, approved labels, advisories, and implementing rules.
2. Current Philippine DA/BPI/RCPC protocols and official regional material.
3. Current Philippine laws and official pesticide-safety or poisoning guidance.
4. FAO and WHO pesticide-management and FAW/IPM guidance.
5. IRAC resistance-management classifications and primary peer-reviewed evidence, used only for non-regulatory context.
6. Manufacturer documents only when they are the exact current FPA-approved Philippine label; promotional material is excluded.

Search results, retailer pages, blogs, social posts, AI output, foreign labels, and unattributed product lists cannot establish registration or directions for use.

Only FPA records can establish that a pesticide product and exact use are authorized. DA, BPI, RCPC, FAO, WHO, IRAC, research, or manufacturer material cannot cure a missing FPA registration, certificate, or approved label. Candidate status must be reconciled across the current FPA master register, exact registration certificate and complete approved label, product-specific advisories/orders, and banned/restricted lists. Any conflict fails closed.

Named candidate products and provenance may be collected now only in a segregated, access-controlled research dataset marked `UNPUBLISHED/UNVERIFIED`. Candidate records and raw labels must never enter app assets, a production catalogue, RAG indexes or prompts, screenshots, demonstrations, fixtures, user testing, or farmer-facing output. Before product-display design, assessment mapping, eligibility approval, implementation, user testing, or publication, WormWise must obtain a documented FPA or qualified Philippine legal opinion on whether assessment-triggered display constitutes pesticide advertising, recommendation, marketing, or regulated technical advice. That opinion must determine permitted wording, disclaimer requirements, reviewer qualifications, and reproduction rights. WormWise will not accept sponsorship, purchasing links, paid placement, ranking, default selection, or undisclosed conflicts of interest in this feature.

## Validation gates before any product can appear

Every candidate record must pass all gates:

1. **Identity gate:** exact product, registrant, formulation, registration number, crop, pest, use, and application method match official current FPA material.
2. **Date gate:** registration is active on the catalogue effective date; expiry, suspension, revocation, and supersession are checked.
3. **Label gate:** the complete current Philippine label is available and independently reviewed. A list entry without a label is insufficient for rates, PPE, re-entry interval, pre-harvest interval, restrictions, or application directions.
4. **Assessment gate:** the app has a complete and valid assessment. Risk classification alone is insufficient; no product is shown when identity or evidence is materially uncertain.
5. **Agronomic gate:** growth stage, current evidence, larval size where recorded, crop condition, natural enemies, treatment history, weather, access safety, and locally approved decision rules are considered.
6. **Safety gate:** contraindications, PPE, re-entry, pre-harvest, environmental restrictions, poisoning response, worker/household safeguards, and label primacy are visible before any application detail.
7. **Human review gate:** a named Philippine crop-protection reviewer and pesticide-regulatory reviewer approve the catalogue record and decision mapping.
8. **Freshness gate:** records expire automatically and fail closed when the source or review is stale, missing, conflicting, or unreachable.
9. **Legal-classification gate:** FPA or qualified Philippine counsel confirms whether and how named products may be displayed and which label material may be reproduced.
10. **Action-rule gate:** state 4 remains disabled until a Philippine action rule is validated against WormWise's exact sampling and evidence definitions.

## WormWise assessment-data contract required before mapping

Research must document the exact live contract separately for every supported growth-stage pathway:

- assessment, field, boundary-version, block, station, and plant identifiers;
- observation timestamp, assessment freshness limit, and temporal representativeness;
- sampled and assessable denominators, criterion-specific numerators, missing plants, uncertain observations, and reasons a plant was not assessable;
- station/plant completion rules, required evidence, evidence freshness, data-quality flags, and whether identity is sufficiently supported;
- crop stage value, stage source, plausibility check, correction history, and explicit unknown state;
- spatial representativeness across blocks, with no aggregation that hides a localized hotspot;
- version of the protocol, metrics service, risk rules, and boundary/block plan used to create the result.

The plan must distinguish fields already collected reliably by WormWise from new inputs that require implementation. Crop condition, natural-enemy observations, treatment history, and an application-specific weather window must not be treated as available simply because other field or weather data exists.

If prior treatment becomes an input, its minimum record is date/time, exact product or active ingredient, concentration/formulation, verified mode-of-action group if available, application method/equipment, outcome, applicator/label-compliance status, and explicit unknown values. WormWise must not infer one field from another.

## Research questions

### Regulation and labels

- What current FPA datasets identify products registered for corn/maize and FAW?
- Which fields are authoritative, how often are they updated, and how are suspension, revocation, conditional status, and expiry represented?
- Where are exact approved Philippine labels obtainable, and what may lawfully be reproduced in an app?
- What distinctions apply to ground, knapsack, drone, aerial, biological, and plant-incorporated protectant uses?
- What rules govern advertising, recommendation, sale, handling, application, recordkeeping, and licensed handlers?
- How are full, conditional, restricted/CPA-only, biological/microbial, organic, plant-incorporated protectant, provisional permit, experimental-use, and research-only records distinguished? Provisional, experimental, emergency/research-only, and unverified classes are excluded from farmer advice. Conditional, restricted, biological/organic, and PIP records remain blocked until their exact legal conditions and responsible regulator are verified.

### Assessment-linked eligibility

- Does a Philippine authority endorse a growth-stage-specific action threshold compatible with WormWise's exact numerator, denominator, freshness rules, and station design?
- Which assessment facts can support “continue scouting,” “seek expert review,” or “chemical options may be considered” without turning an app risk label into a prescription?
- Which uncertainty, data-quality, weather, re-entry, treatment-history, or crop-stage conditions must suppress chemical options?
- Which exact sampling unit, growth stage, evidence definition, denominator, geography, and production system support a proposed action rule? A published threshold is incompatible unless every material element matches WormWise or a qualified Philippine authority explicitly validates the mapping.

### Safety and stewardship

- Which label fields must be displayed verbatim rather than summarized?
- What official Philippine guidance exists for PPE, re-entry, pre-harvest, exposure/poisoning, storage, container disposal, children/animals, waterways, pollinators, and food/feed safety?
- How can mode-of-action information be shown without generating an unauthorized rotation or resistance-management program?
- What label/DOH/official Philippine source governs product-specific first aid and poisoning response? Instructions cannot be generated, merged across products, or inferred.
- Which escalation paths apply to severe/unusual injury, failed prior treatment, suspected resistance, ear/grain contamination, exposure/poisoning, vulnerable people or animals, waterways/pollinators, or missing label facts?

### Data and AI architecture

- Which data belongs in a signed, versioned regulatory catalogue rather than ordinary RAG text?
- How will source documents, extracted fields, reviewer decisions, effective dates, checksums, supersession, and audit history be stored?
- How will the app operate offline and fail closed when a catalogue is stale?
- What can the Advisor explain, and what must remain controlled by deterministic rules?
- How are catalogue authenticity, key rotation, revocation, anti-rollback, trusted time, atomic activation, rollback, privacy, and auditability enforced?

## Proposed evidence table

Research may collect candidate records, but none is publishable until all mandatory fields are present:

| Field group | Required fields |
|---|---|
| Identity | stable record ID, exact product name, active ingredient, concentration/formulation and units, registrant, FPA registration number, registration class and conditions |
| Authorized use | canonical but non-inferred crop/pest/method codes plus exact label wording, use type, equipment/application method, geographic/season restrictions, restricted-user or licensed-handler requirements, registrant/license status, effective and expiry dates |
| Label provenance | publisher, label title/language/version/date, all panels/leaflets/amendments, exact page/section/table, official URL or access record, MIME type, retrieval timestamp, source hash, extraction method/version, OCR confidence, field-level provenance, verifier decisions/conflicts, reproduction rights, verification date |
| Label-controlled safety | PPE, re-entry interval, pre-harvest interval, maximum applications, environmental restrictions, storage/disposal, first aid |
| Stewardship | IRAC group when source-supported, resistance warnings, relevant label limitations |
| Governance | extractor, two independent verifiers, independent crop-protection and regulatory/legal reviewers, conflicts of interest, approval state, next review date, suspension/revocation/withdrawal reason, superseded-by record |

Unknown values remain `unknown`; they are never inferred from another product, formulation, crop, pest, method, country, or earlier label.

## Proposed decision states

The research will validate, revise, or reject these states:

1. **No chemical advice:** assessment incomplete, insufficient, stale, outside scope, or unsafe.
2. **Continue monitoring:** current evidence does not support escalation under a validated rule.
3. **Qualified review required:** consequential uncertainty, conflicting evidence, unusual/severe case, prior treatment concern, or missing local rule.
4. **Chemical options may be considered:** all assessment, regulatory, label, safety, freshness, and review gates pass.

Even in state 4, WormWise presents eligible options and the reasons they passed—not “the best pesticide,” an application command, or generated directions.

State 4 is disabled until a Philippine-compatible action rule matching the live WormWise assessment contract is validated. Weather, natural-enemy observations, risk labels, and AI/image results cannot independently activate or suppress a product. Unknown, stale, contradictory, biologically implausible, spatially unrepresentative, or aggregated-away evidence routes to monitoring or qualified review.

WormWise must never call a pesticide “safe,” “harmless,” “non-toxic,” “best,” “recommended,” or “superior,” or compare efficacy unless the legal review explicitly permits the exact sourced statement. Mandatory label directions are displayed verbatim where legally permitted, not paraphrased as authority.

## AI and RAG restrictions

- Gemini must never select, rank, invent, substitute, or complete a pesticide record.
- Product eligibility comes only from deterministic rules over the signed catalogue.
- RAG may explain an already selected catalogue record using its cited label and approved safety material.
- Retrieved text cannot override catalogue status, label restrictions, or missing data.
- Prompt injection, user claims, conversation history, model confidence, and image classification cannot activate a product.
- Product names and application details are omitted when the catalogue is stale or the decision gate fails.
- No AI may create a rotation program, infer that products share or differ in mode of action, recommend a mixture, or substitute a product/formulation. Mixtures or resistance instructions appear only when the exact current label or approved Philippine protocol explicitly supports them.

## Catalogue, rules, and update trust model

The immutable regulatory catalogue and deterministic decision-rules package are separate artifacts. Each is jurisdiction-scoped, independently versioned, effective-dated, compatibility-linked, and signed with an asymmetric key. The application embeds rotatable trust anchors and verifies the signature over canonical serialization and a manifest containing per-file hashes before parsing or activation. Signing keys require documented custody, revocation, and rotation procedures; a checksum alone is not authenticity.

Packages use a monotonic sequence and anti-rollback state. An older, superseded, expired, revoked, wrong-jurisdiction, or incompatible package is rejected. Freshness uses effective/expiry timestamps and the last trusted server time. Device-clock rollback or unknown time fails closed. There is no offline grace period for an expired or unverifiable product record.

Updates download to staging and undergo size, schema, signature, integrity, reference, vocabulary, and compatibility validation before atomic activation. Interrupted downloads are discarded safely. The last known valid package may be retained only while still current and not revoked. Emergency revocations use a signed denylist and defined propagation target; rollback can never restore expired or revoked content. The RAG index is built only from an activated package and never includes unpublished candidate records.

Threat modeling must cover malicious labels/packages, compromised endpoints, replay/downgrade, local database tampering, rooted devices, Unicode product-name spoofing, malformed/oversized/decompression-bomb packages, prompt injection within source documents, and API interception. Controls include TLS plus signature validation, canonical Unicode normalization, strict schemas and size limits, least privilege, and no executable or HTML content.

## Deterministic decision trace and privacy

Rules use typed inputs and units, explicit unknown handling, precedence/conflict rules, boundary conditions, freshness windows, and stable reason codes. No LLM output, image confidence, or conversation content participates in eligibility.

Each decision records a privacy-preserving trace: assessment snapshot/hash, catalogue version, rules version, app version, trusted-time result, every gate outcome, suppression/display reason codes, and acknowledgement. Logs are append-only or tamper-evident where practical and omit API keys, full precise geometry, and direct identifiers by default.

Treatment history, assessment data, and location require documented purpose, consent where applicable, minimization, retention/deletion/export rules, and encryption at rest/in transit. Eligibility runs on-device by default. Precise location and health/exposure information are never sent to Gemini without separate explicit consent. Analytics are coarse and redacted.

## Required user-interface states

The design must explicitly cover loading, unverified, offline-stale, expired, revoked, missing-label, wrong-crop, wrong-pest, wrong-formulation, wrong-method, qualified-review-required, and update-failed states. Suppressed product names are not left visible behind an overlay. Any eligible record shows “eligible,” never “recommended,” plus exact method, catalogue verification date, current label access, and official exposure/emergency action. A comprehension acknowledgement is safety friction, not a liability waiver.

## Verification procedure

1. Freeze the report evidence as of a stated Philippine date/time. Archive every lawful source artifact with its “observed on” time and register/advisory version separately from registration effective and expiry dates.
2. Extract official source records with document date, URL, exact page/table/section, retrieval path or search terms, and checksum into the quarantined `UNPUBLISHED/UNVERIFIED` dataset.
3. Independently verify every product-level field against the exact current record and label. Neither verifier may be the extractor, registrant/manufacturer sponsor, or decision-rule author; conflicts of interest are recorded.
4. Preserve conflicting official records, keep the candidate quarantined, and request written FPA clarification. Never reconcile a conflict by inference.
5. Record failed searches, unavailable or partial labels, inaccessible endpoints, and negative findings in the gap register so absence is never interpreted as authorization.
6. Have Philippine crop-protection and pesticide-regulatory reviewers approve decision mappings and farmer-facing wording.
7. Test expiry, revocation, missing-label, wrong-crop, wrong-pest, wrong-method, uncertain-assessment, and offline-staleness failures.
8. Red-team queries for dose invention, mixtures, off-label substitution, unsafe PPE/re-entry advice, and attempts to override safeguards.
9. Release only signed catalogue versions with rollback support and an audit trail.
10. Maintain a versioned gold evaluation set containing positive, negative, and boundary cases; wrong-crop/pest/formulation/method adversarial pairs; stale time, clock rollback, revocation, offline, and interrupted-update cases; multilingual/typo queries; and prompt-injection attempts. Zero false pesticide activations is a release gate, with deterministic reproducibility and independent sign-off after every catalogue or rules update.
11. Verify authoritative exposure/poisoning guidance and current Philippine emergency contacts for offline access without hard-coding unverified numbers.

## Planned research artifact

The final report will contain:

- Executive feasibility conclusion
- Current Philippine regulatory framework
- Official-source inventory and reliability assessment
- Candidate-data findings separated from publishable recommendations
- Assessment-to-advice decision architecture
- Catalogue and update architecture
- Safety and AI restrictions
- Validation and testing protocol
- Explicit unresolved gaps and required human reviewers
- Numbered footnotes and a complete source list

## Stop conditions

Research must stop short of product advice when exact current labels cannot be obtained, Philippine-compatible action rules are absent, registration records conflict, application method is unclear, or qualified review is unavailable. The final artifact must state these gaps rather than fill them with foreign guidance or inference.

Research may collect and compare candidate records only after this plan passes regulatory, agronomic, and architecture review. No candidate product may be implemented or displayed to farmers until legal classification, exact labels, matching Philippine action rules, signed-package controls, evaluation, and named independent human approvals are complete.
