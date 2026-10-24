# WormWise assessment-linked pesticide advice: deep research reference

**Status:** Internal research only — not approved for farmer-facing pesticide advice  
**Jurisdiction:** Philippines  
**Crop and pest:** Maize/corn and fall armyworm (*Spodoptera frugiperda*)  
**Evidence cutoff:** 14 September 2026, Asia/Manila

## Executive conclusion

An assessment-linked pesticide-advice feature is technically possible, but it is **not yet safe or sufficiently supported to release**. WormWise may currently provide scouting results, non-product IPM education, continued-monitoring prompts, and referral to a qualified local crop-protection adviser. It must not yet display product names, rates, mixtures, application commands, rankings, or an AI-selected pesticide.

The decisive reason is not a lack of candidate products. The FPA public register contains discoverable corn/FAW records. The problem is that a register row is not the complete current approved Philippine label, does not consistently expose full versus conditional registration, sometimes contains expired rows, and does not establish that an application method such as knapsack, ground boom, directed-whorl, or drone is authorized. The law also makes claims and use conditions registration-dependent.[^1][^2]

Agronomically, WormWise uses a structured field sample, but a superficially similar sample design does not make its evidence fields interchangeable with a published threshold. No located Philippine national or Region 2 protocol supplies a complete, authoritative action rule matching WormWise's exact crop-stage paths, numerators, denominators, evidence freshness, uncertainty handling, and divided blocks.[^3][^4][^5]

Accordingly, the release state is:

- **Allowed now:** describe observations; explain uncertainty; continue structured scouting; show general IPM; refer severe, unusual, post-treatment, reproductive-stage, or grain-safety cases for qualified review.
- **Research-only:** collect named FPA candidates in a quarantined dataset marked `UNPUBLISHED/UNVERIFIED`.
- **Blocked:** farmer-facing named products, rates, application directions, product ranking, purchasing links, or AI-generated treatment advice.

## 1. Validated safety boundary

This report was prepared under the separately validated [research plan](PESTICIDE_ADVISORY_RESEARCH_PLAN.md). Separate regulatory, agronomic, and software-architecture research reviews found that plan suitable **only for quarantined candidate research**; this is not approval by licensed Philippine professionals. No candidate may enter app assets, production RAG, prompts, screenshots, fixtures, demonstrations, or user tests until every legal, label, rule, update-security, and named human-review gate passes.

WormWise must describe the feature as decision support, not diagnosis, prescription, or a substitute for the current label. It must never call a pesticide “safe,” “harmless,” “non-toxic,” “best,” or “recommended.” It must not accept sponsorship, paid placement, default selection, efficacy ranking, or purchasing links.

## 2. Philippine regulatory findings

Presidential Decree No. 1144 created the Fertilizer and Pesticide Authority (FPA) and empowers it to regulate pesticide registration, labeling, distribution, storage, transport, use, and disposal, determine specific uses and manner of use, and restrict or ban pesticides. It prohibits dealing in products whose registration is absent, expired, suspended, or revoked, making claims different from registration, and using pesticides contrary to good agricultural practice.[^1]

The FPA pesticide guidelines distinguish full registration, conditional registration, and experimental-use permits. Conditional registration is not equivalent to full registration. Experimental-use and emergency/minor-use permissions are limited to their approved conditions and cannot be generalized into ordinary farmer use. The same guidelines restrict advertising and off-label claims and require label-controlled warnings, precautions, poisoning signs, first aid, and physician information.[^2]

The legal category of an assessment-triggered named-product display remains unresolved. Before product UI design or public testing, WormWise needs a written determination from FPA or qualified Philippine counsel covering:

1. whether the display is advertising, regulated recommendation, marketing, or another technical-advice category;
2. exact permitted wording and required disclaimers;
3. required reviewer or applicator qualifications;
4. whether and how labels, excerpts, translations, and offline copies may be reproduced;
5. treatment of conditional, restricted, biological, organic, PIP, drone, and emergency-use registrations.

FPA stated in January 2026 that it does not authorize online pesticide sales and that transactions remain limited to authorized physical establishments operated by licensed dealers or distributors. WormWise therefore must not link to pesticide purchases or operate as a marketplace.[^6]

### 2.1 What each official source can establish

| Source | Can establish | Cannot establish by itself |
|---|---|---|
| FPA registration certificate and complete current approved label | Exact product identity, authorized crop/pest/use/method, directions, restrictions, PPE, PHI, REI, first aid and other label facts | Continued validity if a later suspension, revocation, amendment or ban exists |
| FPA registered-products dataset | Candidate identity, registration number, expiry shown, crop/pest rows and selected fields | Complete label, current class/conditions, every authorized method, or publishability |
| FPA banned/restricted list and advisories | Denials, restrictions, warnings and policy changes | Positive authorization for a particular product/use |
| FPA licensed-handlers list | Current status of listed handlers and drone operators | Product registration or authorization of a particular use |
| FPA drone list | A separate drone-use candidate and stated class/expiry | Knapsack or ground use; complete drone label; operator/equipment conditions |
| FPA PIP list | Registered plant-incorporated traits/events | A spray-product option |
| BAFS organic-input records | Organic-input registration within BAFS scope | FPA pesticide status or equivalence between “organic,” “biological,” and “microbial” |

The FPA live site provides the registered-products, handler, advisory, and banned/restricted resources, but they must be reconciled rather than trusted in isolation.[^7][^8][^9]

### 2.2 Quarantined candidate inventory

The following exact corn + fall-armyworm rows were observed in the July 31, 2026 pesticide PDF linked from FPA's official Registered Products page and served from FPA's mirrored document host.[^23] Every conventional candidate's **registration class is unknown**. They are recorded only to show that catalogue research is feasible. **None is verified, eligible, recommended, or approved for WormWise display. No rate or use direction from these rows should be implemented.**

| Candidate | Registrant shown | Active ingredient/formulation shown | Registration no. | Expiry shown | Blocking facts |
|---|---|---|---|---|---|
| AVANZA 40 WG | The LichempHil International Inc. | chlorantraniliprole + thiamethoxam, 200+200 g/kg WG | 590-416-7244 | 10-Nov-2028 | Exact label, class and method absent |
| CHLORANEX 5 SC | Nexchem Corporation | chlorantraniliprole, 50 g/L SC | 702-393-6331 | 2-Aug-2029 | Exact label, class and method absent |
| CLEVEROLE 50 SC | Rainbow Agrosciences Philippines Inc. | chlorantraniliprole, 50 g/L SC | 539-393-6238 | 2-Aug-2029 | Exact label, class and method absent |
| CLORAL 50 SC | Philagrow Incorporated | chlorantraniliprole, 50 g/L SC | 372-393-7088 | 10-Jul-2028 | Exact label, class and method absent |
| EXALT 60 SC | Corteva Asia Pacific Inc.–Philippine Branch | spinetoram, 60 g/L SC | 737-452-3600 | 7-Nov-2027 | Exact conventional label/class absent; separate conditional drone listing exists |
| PLEO 10 EC | Leads Agricultural Products Corp. | pyridalyl, 100 g/L EC | 099-381-2519 | 8-Jan-2028 | Exact label/class/equipment absent |
| PLEO 10 EC | Sumitomo Corporation Philippines | pyridalyl, 100 g/L EC | 472-381-2592 | 18-May-2028 | Separate registrant/number; no substitution permitted |
| PREVATHON SC | FMC Agro Philippines Inc. | chlorantraniliprole, 50 g/L SC | 598-393-4410 | 28-Jun-2027 | Exact label, class and method absent |
| STEWARD 30 WDG | FMC Agro Philippines Inc. | indoxacarb, 300 g/kg WDG | 598-353-4412 | 28-Jun-2027 | Exact label/class/equipment absent |
| YEOVAL SC 200 | Bayer CropScience Inc. | tetraniliprole, 200 g/L SC | 284-515-4869 | 4-Nov-2026 | Near expiry; exact label/class absent; drone entry is conditional |
| BIOPHERO | Vann Hawk Agro Chemicals Inc. | pheromone lure | 295-521-4958 | 17-Jan-2027 | Monitoring tool, not a spray treatment |

The drone list separately showed MATCH 050 EC, EXALT 60 SC, ARIBA 2.5 EC, and YEOVAL SC 200 for corn/FAW as conditional entries. Those rows cannot authorize any ground or knapsack use. Exact UAS labels, certificates, conditions, operator requirements, and registration numbers were not available in the list.[^10]

This inventory also exposed conflicting or historical rows: products with past expiries appear alongside current-looking records, and a product can have different apparent status by crop or method. Therefore the catalogue must fail closed on any conflict and request written FPA clarification; it may never infer status from the page title, a different crop row, a similarly named formulation, or a drone record.

### 2.3 Biological, organic and PIP boundaries

PIP corn events with FAW claims exist in FPA lists, but they are plant traits and must never be presented as post-assessment spray choices.[^11] “Biological,” “microbial,” “biochemical,” and “organic bio-control agent” are not interchangeable legal classes. FPA guidelines contain microbial/biochemical pesticide requirements, while Republic Act No. 11511 assigns BAFS registration of organic inputs, including organic bio-control agents. Each candidate requires written product-specific FPA/BAFS classification before catalogue inclusion.[^12]

## 3. Agronomic findings

### 3.1 Protocol comparison

| Evidence source | Sampling and decision concept | WormWise compatibility |
|---|---|---|
| FAO Guidance Note 2 | For small fields, W pattern; 5 stops × 10 consecutive plants; current infestation based on recent injury or fresh frass; scout weekly or more often during change | Strong structural support for scouting UI, but it intentionally supplies no chemical action threshold |
| CIMMYT Asia guide (2021) | Five representative locations **per hectare**; W for small plants, ladder for tall plants; distinct `%SFW`, `%IW`, and `%IP` metrics; stage-specific threshold ranges | Candidate expert reference only; WormWise fields are not yet semantically proven equivalent |
| DA-Bicol/BPI protocol[^22] | Philippine surveillance, early signs, frass, larvae, pheromone monitoring and IPM | Identification/context support; no complete auditable national threshold table located |
| DA Region 2/RCPC field report (2025) | Reports an early-season biological-control project and a 10% split | Locally relevant lead, but denominator, design, validation population, economics and approval scope are missing |
| DA Memorandum Order 26 (2021)[^21] | Monitoring, surveillance, LGU/RCPMC reporting and technical support | Supports escalation/referral, not product activation |

FAO's 5 × 10 design aligns with WormWise's field structure, but FAO counts a specific current-infestation proxy. WormWise's broad “current FAW evidence” and evaluator result are not automatically identical.[^3]

CIMMYT's Asian guide uses the following candidate thresholds: V1–V6: 20% (range 10–30%) with small fresh windowpanes and/or infested whorls; V7–V12: 50% (range 40–60%); and VT–R2: 20% (range 10–30%) percent infested plants, with strong late-spray exposure and PPE caution.[^4] These are contextual ranges, not universal commands. They cannot be copied into WormWise because:

- WormWise begins some paths at V3 and has a separate VE–V2 contract;
- `%SFW`, `%IW`, and `%IP` are not yet field-by-field mapped to WormWise data;
- VT–R2 target zones and evaluator results are richer but not necessarily `%IP`;
- R3–R6 lies outside the located CIMMYT threshold table;
- CIMMYT specifies five representative locations per hectare, requiring validation of WormWise blocks over 1 ha;
- threshold ranges require local production/economic judgement.

The Region 2 report's 10% figure must not be used until the underlying DA-BAR/RCPC protocol, trial report, numerator, denominator, crop stages, cultivars, production system, validation population, economic assumptions, and approval scope are obtained.[^5]

Other published systems demonstrate why thresholds cannot be transplanted. The 2018 FAO/CIMMYT Africa guide uses about 20% (10–30%) for VE–V6, about 40% (30–50%) for V7–VT, and different tassel/silk advice, while the 2021 Asia guide uses 50% (40–60%) for V7–V12 and 20% `%IP` for VT–R2. A 2017 CABI evidence note gives age-based examples of 20% damaged whorls below 40 days after planting and 10% at 40–60 days.[^24][^25] The Africa and age-based systems are incompatible with Piat/WormWise unless a qualified Philippine authority validates an exact crosswalk; their disagreement is evidence against choosing a convenient number.

### 3.2 Freshness, larval size, weather and natural enemies

Evidence freshness should be biological, not merely a timestamp. FAO counts recent injury and fresh whorl frass and excludes damage limited to older leaves. CIMMYT focuses vegetative inspection on the newest three to four whorl leaves. Neither provides a universal elapsed-time cutoff; ambiguous evidence requires reassessment.[^3][^4]

CIMMYT associates small fresh windowpanes with early instars and notes that large larvae protected in whorls are harder to reach. The treatment implications of WormWise's size categories, including third-instar ambiguity, need local validation. Larval size may raise urgency for qualified review; it must not independently activate a pesticide.

Heavy rain may kill small larvae and justify delaying a borderline decision and scouting again, but the guide does not define “heavy,” “imminent,” “borderline,” or a universal number of days. Weather may trigger reassessment or block an unsafe label-specific application window; it cannot independently decide treatment need.[^4]

Natural enemies should be recorded and conserved as part of IPM. No validated arithmetic rule was located that lets WormWise subtract predators, parasitoids, or pathogens from an infestation percentage. Their presence cannot automatically activate or suppress product options.

### 3.3 Prior treatment and resistance

A failed response is not proof of resistance. Misidentification, larval stage, timing, coverage, equipment, weather, product status, and label compliance are alternative causes. The minimum treatment-history record is date/time, exact product or active ingredient, concentration/formulation, method/equipment, verified mode-of-action group if available, outcome, and explicit unknowns.

IRAC supports alternating different modes of action across successive pest generations and following local spray windows, but this does not authorize WormWise to invent a rotation program, infer a product's MoA, or suggest a substitute or mixture.[^13] Failure or uncertainty routes to a qualified adviser.

### 3.4 Reproductive stage and grain safety

The located CIMMYT threshold table ends at R2. WormWise's R3–R6 external-ear observations and opened-ear subsample therefore have no validated threshold mapping. Subsample findings must not be extrapolated to field prevalence.

Ear feeding, mold/rot-like signs, odor, discoloration, or uncertain grain status should trigger harvest and food/feed-safety escalation and appropriate testing—not a pesticide suggestion or a toxin diagnosis. Research finds context-dependent associations between insect ear injury, ear rot and mycotoxin contamination, varying with pest, hybrid, fungal pressure, stress and weather. Visible injury or mold can neither confirm nor exclude aflatoxin/fumonisin contamination.[^14][^26][^27]

## 4. Conservative decision model

Until a Philippine-compatible rule is approved, WormWise should expose only these states:

1. **Assessment unusable — no chemical advice:** incomplete stations/plants; invalid denominator; unknown or implausible stage; stale/conflicting evidence; poor spatial representation; uncertain identity; out-of-scope stage; or missing catalogue/label facts.
2. **Continue structured monitoring:** descriptive assessment is valid, but no local action rule supports escalation. Show exact numerator, denominator, stage, fresh-evidence definition, limitations, and next scouting prompt. Do not claim treatment is unnecessary.
3. **Qualified review required:** severe/rapid change; consequential current evidence or uncertainty; larger/protected larvae; uncertain identity; hotspot hidden by aggregation; prior treatment/failure; reproductive/ear injury; grain-safety concern; weather/application-safety problem; or contradictory block results. A “candidate threshold signal” is an internal research comparison only: it must not be calculated for or shown to farmers and cannot trigger an app state. Until a reviewed deterministic escalation rule exists, consequential evidence routes directly to qualified review without citing a numeric threshold.
4. **Chemical options may be considered:** **disabled** until the exact WormWise data contract, a Philippine-compatible action rule, current label/registration, legal-display permission, signed catalogue controls, and independent human approvals all pass.

Risk labels, weather, natural enemies, image-model confidence, user prompts, and AI output may never independently activate state 4.

## 5. Required product catalogue and rule architecture

Use two separately signed artifacts:

- `regulatory-catalogue`: immutable, field-level facts extracted from verified registrations and complete labels;
- `decision-rules`: deterministic, reviewed mappings from typed WormWise inputs to the four states.

Each package needs schema and content versions, Philippine jurisdiction, monotonically increasing sequence, issue/effective/expiry timestamps, app compatibility, counterpart-package compatibility, payload hashes/sizes, signer identity/role, revocation version, and asymmetric signature. A valid signature authenticates content but does not replace signer authorization. Use offline trust anchors, authorize keys by package role, use protected signing keys, documented rotation/revocation, and preferably threshold approval.[^15][^16][^17]

The app must reject rollback, replay, expired or revoked packages, incompatible package pairs, unknown trusted time, and device-clock rollback. Persist the highest authenticated server time and highest accepted catalogue, rules, and revocation sequences in platform-protected storage; effective time may never move backward. Loss/corruption of that state after initialization, rollback detection, or inability to authenticate current time suppresses named-product content. There is no offline grace after signed expiry.

Download to staging with both compressed and expanded size limits. Verify the manifest signature and signer role **before parsing payloads**, then reject duplicate object keys, unknown critical fields, Unicode confusables, hash/reference failures and invariant violations. Build the retrieval index only from verified payloads. Activate catalogue, rules, derived index and active-manifest pointer in one atomic transaction. Partial or interrupted updates must never reach the engine.

### 5.1 Mandatory field-level provenance

Every catalogue fact requires exact product/registrant/formulation/registration identity; exact crop, pest, use and method wording; document/publisher/version/date; page/panel/section/table/row; official acquisition URL; retrieval time; MIME type and byte hash; extraction method/OCR confidence; extractor and two independent verifiers; reviewer decisions/conflicts; rights determination; and supersession/suspension/revocation history.

Keep `verbatimLabelValue`, `normalizedMachineValue`, and `normalizationRuleVersion` separate. Never infer a missing fact from another product, formulation, method, crop, pest, jurisdiction, or older label. If exact PPE, REI, PHI, maximum applications, environmental restrictions, first aid, or application directions are unavailable, suppress the entire named-product view.

## 6. RAG and AI restrictions

The deterministic engine alone validates package state, assessment completeness, exact legal/label matching, and decision-rule eligibility. The Advisor's RAG may only explain a decision already produced from an approved record projection. It cannot activate, rank, substitute, complete, or suppress a product; calculate a rate; infer an interval; design a mixture/rotation; interpret a missing label; or use model confidence as evidence.

RAG documents are untrusted data. Authenticate source packages before indexing, remove active content, normalize Unicode, keep record IDs/source locations/hashes on every chunk, and validate generated explanations against a constrained schema and the deterministic result. Discard any explanation containing unsupported product identifiers or claims. Prompt injection remains possible even with RAG and must be handled as an ingestion and output-validation threat.[^18]

Candidate records in this report must never enter the current FAW guide RAG. This file is an authorized research-only exception under the plan's quarantined-candidate clause, not a legal authorization. Repository policy and build checks must deny `docs/PESTICIDE_ADVISORY_DEEP_RESEARCH.md` and any record marked `UNPUBLISHED/UNVERIFIED` from Flutter assets, generated indexes, prompts, fixtures, demos and release packages; prose markings alone are insufficient.

## 7. Privacy, audit and emergency handling

The Philippine Data Privacy Act IRR requires legitimate and declared purposes, proportional collection, organizational/physical/technical safeguards, access control, retention limits, incident procedures, and security evaluation. NPC also publishes guidance specifically addressing AI systems processing personal data.[^19][^20]

Run eligibility on-device by default. Whether field location or treatment data is personal data depends on identifiability, but precise location can contribute to farmer profiling. Do not send identity, precise coordinates, boundary geometry, treatment history, health/exposure narratives, or full assessment photographs to Gemini by default. Optional sharing must be granular, explicit, revocable, and minimized.

Before deployment, disclose data categories, purpose and lawful basis, recipients/processors, retention, automated logic and consequences, controller/DPO contact, and applicable access, correction, portability, deletion/blocking and objection rights.[^28][^29] Complete a privacy-impact assessment, records of processing, processor contracts, encryption at rest/in transit, periodic access review, deletion/export/objection workflows, restoration and incident plans, and determine NPC registration/notification obligations. Qualifying breaches require notification under NPC's criteria and 72-hour rule.[^30]

Audit logs should record pseudonymous/local decision ID, assessment snapshot hash, catalogue/rules/app/schema versions, trusted-time result, every gate and stable reason code, records considered/suppressed, and whether an AI explanation was accepted or discarded. Do not log API keys, precise geometry, full photos, or exposure narratives by default.

Product-specific first aid must come from the exact label plus current certificate/register, advisories, bans/restrictions, suspension/revocation and method reconciliation. It must never be generated or merged across products. This research did not find an authoritative current DOH poison-centre directory suitable for hard-coding. Until one is obtained, use cautious label-led escalation: seek urgent medical help; stop exposure if it is safe to do so; preserve and bring the readable label or exact product name for the clinician. Do not instruct a user to transport a contaminated container, and do not invent a hotline.[^31][^32]

## 8. Validation and release gates

The deterministic safety suite must include exact matches and every near-match or failure: missing fields, wrong crop/pest/formulation/concentration/method, expiry boundaries, revoked/superseded records, no trusted time, clock rollback, prolonged offline state, bad signatures, replay/freeze/rollback, key rotation, malformed or oversized packages, duplicate keys, Unicode confusables, partial atomic updates, boundary/block denominator errors, stale evidence, implausible crop stage, prior-treatment unknowns, prompt injection, requests for rates/mixtures/off-label use/rankings, hallucinated citations, privacy leakage, localization, accessibility and low-connectivity behavior.

Release requires:

- zero false product activations across the complete gold safety suite;
- deterministic reproduction of every decision trace;
- every displayed fact resolving to approved field-level provenance;
- fail-closed behavior on signature, time, expiry, revocation, compatibility, label or rule failure;
- proof that AI cannot alter decision state;
- independent Philippine crop-protection, pesticide-regulatory/legal, security, privacy, accessibility, and representative-user approvals;
- complete regression and new sign-off after every catalogue, rule, app, trust-anchor, model, retrieval or prompt-policy change.

## 9. Implementation sequence

1. **Obtain legal classification before product use.** Before any named-product UI design, implementation, demonstration, public/user testing, or publication, request written FPA/counsel determination on display, wording, reviewer qualifications and reproduction/translation rights. Quarantined evidence research may continue under this plan.
2. **Freeze the WormWise assessment contract.** Document every stage-specific raw field, numerator, denominator, completion rule, freshness rule, boundary/block version and uncertainty state.
3. **Obtain Philippine technical validation.** Acquire the underlying Region 2 protocol and have named RCPC/qualified maize-IPM experts approve or reject mappings to WormWise metrics.
4. **Acquire source packets.** Through FPA/FOI and registrants where required, obtain CPR, complete current label, amendments, status history and rights for each candidate.
5. **Build quarantined research tooling.** Use the catalogue schema, dual independent verification, conflict preservation and negative-search log. Keep it outside app assets/RAG.
6. **Implement signe catalogue infrastructure.** Trust anchors, key custody, anti-rollback, trusted time, revocation, atomic updates and tamper-evident audit.
7. **Implement deterministic states 1–3.** These can improve current monitoring and referral without exposing products.
8. **Validate state 4 offline in a research build.** Use synthetic/approved gold cases; do not use farmer-facing names or public tests.
9. **External review and limited governed pilot.** Only after all gates pass, with no purchasindg/ranking and with rapid revocation capability.

## 10. What is still missing

The following are blockers, not optional enhancements:

1. Written FPA or qualified Philippine legal opinion on product display and terminology.
2. Complete current FPA-approved labels, CPRs, amendments, status histories, registration classes and reproduction/translation permission.
3. Product-specific reconciliation against current register, banned/restricted list, advisories, suspensions, revocations and handler/applicator requirements.
4. Underlying DA-BAR/Region 2/RCPC trial protocol and validation behind the reported 10% split.
5. A Philippine action rule matching every WormWise stage, numerator, denominator, freshness and block rule; R3–R6 is particularly unsupported.
6. Semantic crosswalk from WormWise raw observations to an approved metric; generic risk level is insufficient.
7. Validated evidence-freshness, larval-size, natural-enemy, weather and post-treatment rules for Cagayan Valley.
8. Philippine grain/feed-safety testing and referral protocol for ear injury and suspected mold/mycotoxin risk.
9. Written FPA/BAFS product-by-product jurisdiction for biological, microbial and organic inputs; separate PIP stewardship.
10. Named independent Philippine crop-protection and pesticide-regulatory reviewers with conflict-of-interest controls.
11. An authoritative maintained Philippine poisoning/emergency-contact source.
12. Production signing authority, trusted-time service, revocation channel, privacy-impact assessment and zero-false-activation evaluation.

Until these are resolved, the correct WormWise behavior is to **withhold product names and application details**, preserve the user's assessment evidence, explain the uncertainty, continue IPM/scouting guidance, and route consequential cases to qualified local support.

## Sources

[^1]: Republic of the Philippines, [Presidential Decree No. 1144](https://lawphil.net/statutes/presdecs/pd1977/pd_1144_1977.html), 30 May 1977.
[^2]: Fertilizer and Pesticide Authority, [Pesticide Regulatory Policies and Implementing Guidelines](https://fpa.da.gov.ph/wp-content/uploads/2024/05/PoliciesandImplementingGuidelines2020-P.pdf), 2019 edition, FPA-hosted copy.
[^3]: FAO, [Fall Armyworm Scouting — Guidance Note 2](https://www.fao.org/fileadmin/templates/fcc/Fall_Armyworm/web_FINAL-guidance-note-2.pdf), January 2018.
[^4]: McGrath et al., [Fall Armyworm Scouting, Action Thresholds, and Monitoring](https://repository.cimmyt.org/bitstreams/7f2802ea-6d21-41da-9bc3-e8473c06b7ed/download), in *Fall Armyworm in Asia: A Guide for Integrated Pest Management*, CIMMYT, 2021.
[^5]: DA Regional Field Office 02, [Combating Fall Armyworm Using Biological Control Through IPM](https://cagayanvalley.da.gov.ph/2025/05/19/combating-fall-armyworm-using-biological-control-see-the-increase-in-yields-and-income-through-ipm/), 19 May 2025.
[^6]: FPA, [Clarification on unauthorized online selling of fertilizers and pesticides](https://fpa.da.gov.ph/fpa-clarifies-regulatory-action-on-unauthorized-online-selling-of-fertilizers-and-pesticides/), 22 January 2026.
[^7]: FPA, [Registered Products](https://fpa.da.gov.ph/resources/reports/registered-products/), observed 14 September 2026.
[^8]: FPA, [List of Banned and Restricted Pesticides](https://fpa.da.gov.ph/resources/reports/list-of-banned-and-restricted-pesticides/), observed 14 September 2026.
[^9]: FPA, [Advisories](https://fpa.da.gov.ph/issuances/advisories/), [Memorandum Circulars](https://fpa.da.gov.ph/issuances/memorandum-circulars/), and [Licensed Handlers](https://fpa.da.gov.ph/resources/reports/licensed-handlers/), observed 14 September 2026.
[^10]: FPA, [Registered Agricultural Pesticides under Drone Use](https://fpa.da.gov.ph/wp-content/uploads/2026/04/UPDATED-LIST-OF-PESTICIDE-PRODUCTS-UNDER-DRONE-USE-As-of-April-1-2026-PMID.pdf), 1 April 2026; live page observed 14 September 2026.
[^11]: FPA, [List of Registered Plant-Incorporated Protectants](https://fpa.da.gov.ph/wp-content/uploads/2025/04/List-of-Registered-PIP-Mar-2025.pdf), March 2025.
[^12]: Republic of the Philippines, [Republic Act No. 11511](https://lawphil.net/statutes/repacts/ra2020/ra_11511_2020.html), 23 December 2020; DA-BAFS, [Registration of Organic Input Product](https://bafs.da.gov.ph/index.php/registration-of-organic-input-product/), observed 14 September 2026.
[^13]: IRAC, [Mode of Action and resistance-management guidance](https://irac-online.org/mode-of-action/), observed 14 September 2026.
[^14]: FAO, [On-farm Mycotoxin Control in Food and Feed Grain](https://www.fao.org/4/a1416e/a1416e00.pdf), 2011.
[^15]: IETF, [RFC 9019: A Firmware Update Architecture for Internet of Things](https://www.rfc-editor.org/rfc/rfc9019.html), April 2021.
[^16]: IETF, [RFC 9124: A Manifest Information Model for Firmware Updates in IoT Devices](https://www.rfc-editor.org/rfc/rfc9124.html), January 2022.
[^17]: NIST, [SP 800-218 v1.1: Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final), February 2022.
[^18]: OWASP, [LLM01:2025 Prompt Injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/) and [RAG Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/RAG_Security_Cheat_Sheet.html), observed 14 September 2026.
[^19]: National Privacy Commission, [Implementing Rules and Regulations of the Data Privacy Act of 2012](https://privacy.gov.ph/implementing-rules-regulations-data-privacy-act-2012/).
[^20]: National Privacy Commission, [Advisories and Circulars, including AI systems processing personal data](https://privacy.gov.ph/pips-and-pics/advisories-circulars/), observed 14 September 2026.
[^21]: Philippine Department of Agriculture, [Memorandum Order No. 26, s.2021](https://www.da.gov.ph/wp-content/uploads/2021/04/mo26_s2021.pdf), 2021.
[^22]: DA Regional Field Office V / BPI, [FAW Surveillance and Management Protocol](https://bicol.da.gov.ph/wp-content/uploads/2021/04/FAW-SURVEILANCE-AND-MANAGEMENT-PROTOCOL_10272020.pdf), 27 October 2020.
[^23]: FPA, [Updated List of Registered Pesticide Products as of July 31, 2026](https://mirrored.fpa-gov.ph/wp-content/uploads/2026/08/UPDATED-LIST-OF-REGISTERED-PRODUCTS-As-of-July-31-2026-PMID.pdf), linked from the official Registered Products page and observed 14 September 2026.
[^24]: FAO and partners, [Integrated Management of the Fall Armyworm on Maize: A Guide for Farmer Field Schools in Africa](https://ipm.ifas.ufl.edu/pdfs/FallArmyworm_IPM_Guide_forAfrica.pdf), 2018.
[^25]: Day et al., [Fall Armyworm: Impacts and Implications for Africa — Evidence Note Summary](https://www.armyworm.org/wp-content/uploads/2018/08/FAW_EvidenceNoteSummary2017.pdf), CABI/DFID, September 2017.
[^26]: Njeru et al., [Impact of push–pull cropping system on pest management and occurrence of ear rots and mycotoxin contamination of maize in western Kenya](https://doi.org/10.1111/ppa.13259), *Plant Pathology* 69, 2020.
[^27]: Ni et al., [Association of Insect-Derived Ear Injury With Yield and Aflatoxin of Maize Hybrids Varying in Bt Transgenes](https://pubmed.ncbi.nlm.nih.gov/31586402/), *Journal of Economic Entomology*, 2019.
[^28]: National Privacy Commission, [The Right to Be Informed](https://privacy.gov.ph/the-right-to-be-informed/), observed 14 September 2026.
[^29]: National Privacy Commission, [NPC Circular No. 2022-04](https://privacy.gov.ph/wp-content/uploads/2023/09/Circular-2022-04.pdf), registration of data-processing systems and automated decision-making/profiling operations.
[^30]: National Privacy Commission, [Breach Reporting](https://privacy.gov.ph/pips-and-pics/breach-reporting/), observed 14 September 2026.
[^31]: FPA, [FPA educates first aid management tips for safe agriculture](https://fpa.da.gov.ph/fpa-educates-first-aid-management-tips-for-safe-agriculture-on-air/), observed 14 September 2026.
[^32]: FPA, [Pesticide-handling training guidance in Leyte](https://fpa.da.gov.ph/25-aews-in-leyte-undergo-pesticide-handling-training/), 21 June 2022.
