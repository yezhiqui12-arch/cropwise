# WormWise Fall Armyworm Assessment Protocol

## Document status

- **Status:** Draft functional specification for expert review and application development
- **Crop scope:** Maize/corn only
- **Excluded crop:** Rice
- **Purpose:** Define how WormWise should collect consistent Fall Armyworm (FAW) field-assessment data using a phone
- **Important limitation:** This document is not yet an official Philippine assessment standard, pesticide prescription, insurance certification rule, or substitute for an agriculturist's judgment.
- **Required validation:** The Municipal/City Agriculture Office or another qualified Philippine crop-protection specialist must review the marked provisional items before WormWise presents them as validated recommendations.
- **Project-document warning:** The thesis system architecture is still subject to correction, and Chapters 4 and 5 are still being developed. This protocol therefore describes the intended assessment behavior without treating the paper or architecture as finished.

---

## 1. Problem this protocol addresses

WormWise is intended to reduce the following problems in maize FAW assessment:

1. Subjective and inconsistent damage estimation.
2. FAW and symptom misidentification.
3. Lack of quantitative infestation measurements.
4. Manual and incomplete recording of field observations.
5. Inconsistent use of GPS for mapping assessed locations.
6. Difficulty comparing assessments performed by different evaluators.
7. Lack of usable offline field-data collection.
8. Lack of spatial visibility across a maize field.
9. Confusion between active FAW infestation, old FAW damage, and possible damage from other pests.
10. Lack of structured photo evidence for AI-assisted diagnosis and human validation.

The protocol standardizes **where the evaluator walks, which plants are selected, what is inspected, what photographs are taken, what calculations are made, and what the app is allowed to conclude**.

---

## 2. Core protocol decisions

### 2.1 Formal assessment patterns

Only two patterns are used for a formal WormWise assessment:

- **W pattern:** Used when maize plants are short enough and the field can be crossed safely without damaging the crop.
- **Ladder pattern:** Used when maize is tall, rows are closely packed, crossing the crop is difficult, or plants are at reproductive stages.

The app must select the pattern according to **actual field accessibility**, not only the recorded growth-stage label. For example, a vegetative field with tall, dense plants may use the ladder pattern.

### 2.2 Zigzag rapid surveillance

Zigzag rapid surveillance is **not a formal WormWise severity-assessment pattern**.

Expert literature recognizes zigzag sampling for extensive surveys, but its number of plants and spacing depend on field size. It is suitable for rapid pest-presence surveillance, not for WormWise's standardized quantitative result.

If it is added in the future, it must be labeled **Quick Field Check** and must not:

- Produce an official severity classification.
- Replace the W or ladder assessment.
- Be used for an insurance or agriculture-office certification report.
- Be combined mathematically with a completed formal assessment.

### 2.3 Sampling unit

The recommended WormWise formal sampling unit is:

- **One assessment block:** Up to 1 hectare.
- **Stations per block:** 5.
- **Plants per station:** 10 consecutive maize plants.
- **Plants per completed block:** 50.

This follows the CIMMYT Asia recommendation of five representative locations and ten plants per location per hectare.

### 2.4 Fields larger than one hectare

A field larger than one hectare must be divided into approximately one-hectare assessment blocks.

Example:

- 0.8 ha field: 1 block, 5 stations, 50 plants.
- 1.0 ha field: 1 block, 5 stations, 50 plants.
- 2.0 ha field: 2 blocks, 10 stations, 100 plants.
- 2.5 ha field: provisionally 3 blocks, 15 stations, 150 plants.

The treatment of a remaining partial hectare is **provisional**. Until a Philippine expert approves a different rule, WormWise should use a complete additional block rather than reduce the sample without evidence.

### 2.5 When one mapped field must be assessed separately

Even inside one boundary, separate assessment blocks or assessment sessions are required when areas differ substantially in:

- Planting date.
- Maize variety.
- Growth stage.
- Irrigation or drainage condition.
- Intercropping practice.
- Fertilizer or pest-management history.
- Clearly different crop health or infestation pattern.

This prevents unlike crop areas from being averaged into a misleading result.

### 2.6 Philippine-aligned leaf-damage severity standard

WormWise uses the **DA-BAFS 0-9 Fall Armyworm leaf-damage scale** as its detailed vegetative leaf-severity assessment. The scale is published by the Philippine Department of Agriculture - Bureau of Agriculture and Fisheries Standards (DA-BAFS) in its manual for efficacy trials of Organic Bio-Control Agents (OBCA).

This choice provides a Philippine institutional basis, but its scope must be stated accurately:

- The DA-BAFS scale is an efficacy-trial method, not a national farmer treatment threshold.
- It does not define official low, moderate, or high infestation classes.
- It does not replace FAO/CIMMYT current-infestation measurements based on SFW, IW, fresh frass, larvae, or %IP.
- A severity score must not automatically generate a pesticide recommendation.
- It principally describes leaf and whorl damage. It must not be used as an ear-damage score.

The internationally proposed Simple 1-5 whole-plant scale is not used as the primary WormWise scale because no public Philippine DA or BPI source was identified as specifically adopting it for FAW. WormWise must not mix the 0-9 DA-BAFS scale with a 1-5 scale in one dataset.

---

## 3. Assessment modes by maize growth stage

| Assessment mode | Growth stage | Preferred pattern | Main inspection area | Primary output |
|---|---|---|---|---|
| Early vegetative | VE/V1-V6 | W if accessible; ladder if necessary | Planting position and seedling base at VE-V2; newest 3-4 leaves and whorl | VE-V2 establishment/cutting supplement; % with SFW/IW; DA-BAFS 0-9 score when stage is eligible |
| Late vegetative | V7-V12 | W or ladder according to accessibility | Newest 3-4 leaves and whorl | % with SFW/IW and DA-BAFS 0-9 leaf-damage profile |
| Early reproductive | VT-R2 | Ladder | Tassel, ear base, and leaf axils above/below ear | % infested plants (%IP) |
| Late reproductive / maturity | R3-R6 | Ladder | Ear, husk, kernels, ear base, and nearby axils | External damage, active infestation, and permitted opened-ear/kernel severity metrics |

### 3.1 Growth-stage confirmation

The app should not rely only on days after planting. The evaluator must select or confirm the visible growth stage using an illustrated guide.

If uncertain, the app records:

- `growth_stage = uncertain`
- The evaluator's best estimate.
- At least one whole-plant context photograph.
- A note or LLM-guided description.

The result must then be flagged for review because the correct inspection target and reference threshold depend on growth stage.

---

## 4. Required data before entering the field

The evaluator records or confirms:

### 4.1 Field and crop information

- Field identifier and farmer/owner identifier.
- Field boundary or selected assessment block.
- Calculated field/block area in hectares.
- Barangay, municipality/city, province, and available address description.
- Maize variety, if known.
- Intended crop use, if known: grain, green corn, sweet corn, seed, silage, or other.
- Planting date or best estimate.
- Planting arrangement for VE-V2: single-seed positions, multiple seedlings per hill, or uncertain.
- Intended within-row spacing and intended seedlings per hill/position, when known. These values provide context and must not be guessed from phone GPS.
- Current growth stage.
- Irrigated or rainfed condition.
- Relevant seasonal conditions.
- Intercropping, if present.

### 4.2 Assessment context

- Assessment date and start time.
- Evaluator identity and role.
- Preferred GUI language: English, Tagalog, Ilocano, or supported local language.
- Recent heavy rainfall and date, if known.
- Current/forecast weather when available; absence of internet must not block assessment.
- Previous pesticide or biological-control application and date, if known.
- Product name/active ingredient, if known.
- Re-entry interval status when a pesticide was recently applied.
- Previous FAW assessment for the same field, if available.

When any intervention is reported, create or link the full Section 16 intervention event rather than leaving these values only as free-text metadata. When a compatible previous assessment exists, record whether the current session is a Section 17 follow-up.

### 4.3 Safety gate

The app must ask whether the field was recently treated with pesticide.

- If the re-entry interval has not expired, the app blocks field entry and records the postponed assessment.
- If the re-entry interval is unknown, the app warns the evaluator not to enter until the farmer, product label, or agriculture officer confirms safety.
- The app must never guess a re-entry interval.

---

## 5. Preparing the assessment block

1. Load the saved field boundary or create/confirm it using the separate field-boundary workflow.
2. Display the field area and proposed assessment blocks.
3. Allow the evaluator to correct block division when there are physical barriers, different planting dates, or visibly different crop conditions.
4. Give every block a unique identifier.
5. Keep stations away from border-only bias. Enter approximately 5 meters before inspecting the first station when field dimensions permit.
6. Do not deliberately select only damaged, healthy, convenient, or photogenic plants.
7. Record a GPS position and phone-reported accuracy for every station.

Phone GPS coordinates are assessment-location evidence; they are not centimeter-accurate survey coordinates.

---

## 6. Selecting the scouting pattern

The app asks the evaluator these questions:

1. Can you safely cross between crop rows without stepping over, breaking, or pushing through tall maize?
2. Are the plants tall or closely packed enough that repeated cross-field travel is difficult?
3. Is the crop at VT or a reproductive stage?

### 6.1 Pattern decision

- Select **W pattern** when crossing the field is practical and safe.
- Select **ladder pattern** when the maize is tall, dense, at reproductive stage, or difficult to cross.
- If the suggested route is obstructed, the evaluator may adjust it, but all five stations must remain spatially distributed across the block.
- The app records whether the suggested or adjusted route was used and why it was changed.

The route should guide coverage; it should not force the evaluator to damage plants or enter an unsafe area.

---

## 7. W-pattern procedure

Use the W pattern for accessible maize fields.

1. Start near one side or corner of the block.
2. Walk approximately 5 meters into the crop before Station A, when possible.
3. Follow a W-shaped route that distributes five stations across the block.
4. At each station, select 10 consecutive plants in a row.
5. Inspect the selected plants in order from Plant 1 through Plant 10.
6. Do not replace a selected plant simply because it is difficult to photograph or has no damage.
7. Save the station after all ten plant records are complete.
8. Continue until Stations A-E are complete.

The W shape is a coverage guide. GPS drift does not invalidate an assessment merely because the recorded route is not a perfect letter W.

---

## 8. Ladder-pattern procedure

Use the ladder pattern for tall, dense, or reproductive-stage maize.

1. Enter through a passable middle alley or row.
2. Walk approximately 5 meters from the field edge before the first station, when possible.
3. Move along the central path.
4. For Station A, turn into an accessible side row and inspect 10 consecutive plants.
5. Return to the central path.
6. Move farther into the block.
7. Alternate the station side when possible: right, left, right, left, right.
8. Complete five spatially separated stations.

The ladder pattern avoids repeatedly walking across tall plants. The side rows act like the rungs of a ladder.

---

## 9. Selecting plants at a station

At every station:

- Inspect exactly 10 consecutive plants unless a recorded exception applies.
- Count missing planting positions separately; do not silently replace them.
- Do not choose plants because they appear infested.
- Do not skip healthy-looking plants.
- Do not use plants only from the field border.
- Assign sequential identifiers such as `B01-SC-P07` for Block 1, Station C, Plant 7.

### 9.1 Permitted exception

A plant may be marked `not assessable` when it is:

- Missing or dead for a clearly non-FAW reason.
- Physically unreachable because of a safety hazard.
- So damaged that the required plant structure cannot be inspected.
- Obscured by an immovable obstruction.

The app must retain the record and reason. It must not automatically substitute another plant. See Section 21 for incomplete-assessment rules.

---

## 10. Vegetative assessment: VE/V1-V12

### 10.1 Inspection target

For every selected plant, physically inspect the newest three or four leaves emerging from the whorl.

The evaluator records the presence or absence of:

- Small fresh windowpanes or pinhole-like translucent feeding (**SFW**).
- Fresh scraping.
- Fresh cutting or tearing.
- Fresh frass in or around the whorl.
- Characteristic whorl-feeding signs.
- Visible larva.
- Approximate larval size when visible.
- Egg mass, if visible.
- Old damage without evidence of current feeding.
- Possible non-FAW symptoms.

### 10.2 Classification used for calculation

- **SFW positive:** Small, fresh windowpanes indicating recent feeding commonly associated with small larvae.
- **IW positive:** Fresh scraping, cutting, tearing, frass, or whorl-feeding signs indicating an infested whorl.
- **Currently infested for the field calculation:** Plant has SFW and/or IW.
- **Old damage only:** Damage exists on older leaves, but no SFW, IW, fresh frass, larva, or other fresh feeding evidence is found in the target area.
- **Uncertain:** Evidence is incomplete, conflicting, or may be caused by a different pest.

Do not count `old damage only` as current infestation.

### 10.3 Larval size

If a larva is visible, record one of these field-friendly groups:

- Small: approximately 1st-2nd instar.
- Medium: approximately 3rd instar.
- Large: approximately 4th-6th instar.
- Exact stage unknown.

The app should not force an exact instar from an unclear photograph.

### 10.4 Vegetative formulas

For a complete 50-plant block:

```text
Vegetative current infestation (%) =
  (number of plants with SFW and/or IW / number of assessable plants) × 100
```

Additional outputs:

```text
SFW percentage = (plants with SFW / assessable plants) × 100
IW percentage  = (plants with IW / assessable plants) × 100
```

A plant containing both SFW and IW is counted only once in the overall current-infestation numerator.

### 10.5 VE-V2 seedling establishment and cutting supplement

#### 10.5.1 Why this supplement is needed

The normal SFW/IW assessment examines living maize plants for fresh Fall Armyworm feeding. That assessment can miss an important early-stage problem: a young plant may already have been cut, killed, or removed before the evaluator reaches it.

Fall Armyworm can sometimes behave like a cutworm and cut young maize seedlings. However, a missing, wilted, dead, or cut seedling is not automatically FAW damage. Similar crop-establishment problems can result from:

- Cutworms, seedling maggot, wireworms, or other insects.
- Failed or delayed germination.
- Seed or seedling disease.
- Flooding, drought, or other weather conditions.
- Herbicide injury.
- Birds, rodents, livestock, or people.
- Planting or mechanical damage.

For this reason, WormWise must answer two separate questions:

1. **How well did the maize establish?** This is measured from occupied, empty, injured, and unassessable planting units.
2. **How much of the visible seedling injury has evidence associated with FAW?** This requires fresh injury and supporting pest evidence.

The app must never turn every missing plant into a FAW claim.

This is a provisional WormWise field supplement. Philippine BPI/DA-Bicol material recognizes FAW seedling cutting, but no public Philippine DA/BPI standard defining a FAW-specific seedling stand-loss formula or treatment threshold was identified in the sources reviewed. A qualified Philippine maize or crop-protection specialist must validate this procedure before it is presented as a finalized local standard.

#### 10.5.2 Applicable stage and emergence check

- Apply this supplement only at VE, V1, or V2.
- At VE, ask whether emergence is still continuing.
- At V1-V2, retain an emergence warning when delayed emergence remains plausible.
- When emergence is continuing, label occupancy and gap results `preliminary - emergence may be incomplete`.
- If rows, hills, or expected planting positions cannot be identified reliably, mark planting-position results `not assessable` and continue the ordinary SFW/IW inspection on living seedlings.
- Do not use phone GPS to infer individual seed spacing. Phone GPS is not accurate enough for within-row planting positions.

#### 10.5.3 Phone-only sampling design

A conventional plant-population assessment may measure a fixed length of row. Accurate fixed-length measurement normally requires a tape, marked rope, wheel, or another physical reference. Phone GPS is unsuitable for this short distance, and phone augmented-reality measurement may be inconsistent under field conditions.

To keep the WormWise procedure possible with a phone only:

- Use the same five formal stations already selected for the one-hectare assessment block.
- At every station, assess ten consecutive **planting units** along one maize row.
- Record up to 50 planting-unit records per block.
- Keep empty, injured, and uncertain units in their original sequence. Do not replace them with healthy units.

A planting unit means:

- One expected single-seed position; or
- One hill when multiple maize seeds were planted together.

Begin at the row position associated with the station and continue in one recorded direction. Use visible hills, the regular planting pattern, and farmer-provided spacing to identify consecutive units. Record `position uncertain` rather than inventing a position when the pattern is unclear. Count the number of living seedlings in every occupied unit because one hill may contain more than one plant.

#### 10.5.4 Relationship to the existing 50-plant assessment

The seedling-establishment records supplement rather than replace the existing living-plant FAW assessment:

- **Up to 50 planting units:** Used for establishment, unexplained gaps, and cutting/injury measurements.
- **50 living plants:** Used for the normal SFW/IW current-infestation calculation.

At a station, first record the ten consecutive planting units. Then complete SFW/IW observations on ten living plants. When gaps mean that fewer than ten living plants occur inside the planting-unit sequence, continue in the same row and direction until ten living plants have been examined. Do not change the planting-unit records or hide the gaps.

These denominators remain separate because they answer different questions. Combining them would make the infestation result misleading.

#### 10.5.5 Planting-unit condition

Assign one primary condition to every planting unit:

- **Occupied and apparently healthy:** At least one living seedling is present without visible injury.
- **Occupied with feeding injury:** A living seedling has fresh leaf, whorl, stem-base, or cutting injury.
- **Visibly cut or severed:** A seedling or recognizable fresh remnant is cut at or near the soil surface.
- **Wilted or dead seedling present:** A seedling or recognizable remnant is visible, but its primary cause has not been established.
- **Empty or unexplained:** No living seedling or recognizable seedling remnant is visible.
- **Position uncertain:** The evaluator cannot confidently determine the expected planting position.
- **Not assessable:** The position is obscured, unsafe, or otherwise impossible to inspect.

For an injured unit, separately record:

- Number of living seedlings.
- Injury location: leaf, whorl, stem base, below/at/above the soil line, or uncertain.
- Injury freshness: fresh, old, mixed, or uncertain.
- Live larva present or absent.
- Approximate larval size when visible.
- Fresh frass present or absent.
- Seed, root, or stem rot, tunneling, discoloration, or other non-FAW evidence when visible without unnecessary destructive sampling.
- Possible environmental, disease, planting, herbicide, animal, or mechanical cause.
- Evaluator confidence and remarks.

#### 10.5.6 Cause and FAW-evidence classifications

- **Confirmed FAW present:** A larva with sufficient FAW identification evidence is found and photographed at the affected planting unit. This confirms FAW presence at that unit; it does not prove that FAW caused every nearby missing plant.
- **Injury consistent with FAW:** Fresh feeding or cutting is compatible with FAW, but a clearly identifiable larva or sufficient diagnostic evidence was not obtained.
- **Possible other pest:** Evidence may indicate cutworm, seedling maggot, wireworm, or another pest.
- **Likely non-pest cause:** Evidence supports failed/delayed emergence, disease, weather, herbicide, animal, planting, or mechanical injury.
- **Uncertain:** Evidence is incomplete, conflicting, or insufficient.

Damage shape alone is insufficient for confirmed FAW identification. A cut seedling without a diagnostic larva must remain `injury consistent with FAW`, `possible other pest`, or `uncertain` according to the evidence.

An empty position must never be counted as FAW injury unless a visible seedling remnant and supporting evidence show that a seedling emerged and was subsequently attacked.

#### 10.5.7 Calculations

Calculate these planting-unit indicators separately from current SFW/IW infestation:

```text
Planting-unit occupancy (%) =
  (assessable planting units containing at least one living seedling /
   assessable planting units) x 100

Unexplained gap (%) =
  (empty or unexplained planting units /
   assessable planting units) x 100

Observed seedling injury (%) =
  (assessable established units with visible injury /
   assessable established planting units) x 100

FAW-associated seedling injury (%) =
  (injured established units with confirmed FAW present or injury consistent with FAW /
   assessable established planting units) x 100
```

For these formulas, an `established planting unit` is an occupied unit or a unit containing a recognizable cut, wilted, or dead maize seedling/remnant. Empty unexplained units are excluded from the injury denominator because the evaluator cannot prove that a maize seedling emerged there.

Always display the numerator and denominator. Report `confirmed FAW present` and `injury consistent with FAW` counts separately even when both contribute to the FAW-associated indicator.

When the intended number of seedlings per unit is known, WormWise may compare the observed living-seedling count with the farmer's stated planting target. Label it `comparison with stated planting plan`, not `FAW loss`.

Do not add unexplained gaps to FAW-associated injury. Do not merge any of these indicators with the SFW/IW current-infestation percentage.

#### 10.5.8 Worked example

Suppose one completed block contains 50 assessable planting units:

- 42 contain at least one living seedling.
- 5 contain a visible cut or dead maize remnant.
- 3 are empty with no evidence showing why.
- Of the 5 visibly injured units, 2 have confirmed FAW present, 1 is consistent with FAW, and 2 have another or uncertain cause.

The results are:

```text
Occupancy = 42 / 50 = 84.0%
Unexplained gaps = 3 / 50 = 6.0%

Established units = 42 living/occupied + 5 visible remnants = 47
Observed seedling injury = 5 / 47 = 10.6%
FAW-associated seedling injury = (2 confirmed + 1 consistent) / 47 = 6.4%
```

The correct interpretation is not `16% of seedlings were lost to FAW`. The app can say that occupancy was 84%, three positions were unexplained, visible injury occurred in 10.6% of established units, and 6.4% had injury associated with confirmed or possible FAW evidence.

#### 10.5.9 Photograph and evidence requirements

For each station, require:

- One row-context image showing the assessed planting-unit sequence as clearly as practical.
- One whole-seedling image for every visibly injured or uncertain seedling.
- One close-up of every visibly cut/severed seedling or remnant.
- One close-up of the stem base and the evidence used to classify the injury.
- When a larva is present, clear body/dorsal and head images when safely obtainable.
- Images of frass, diseased roots, rotting seed, tunneling, discoloration, or other evidence used to suggest a cause.

One image is not expected to prove row context, whole-seedling condition, stem-base injury, and larval identity at the same time.

#### 10.5.10 Permitted output and limitations

WormWise may report:

- Planting-unit occupancy.
- Unexplained-gap percentage.
- Observed seedling-injury percentage.
- FAW-associated seedling-injury percentage.
- Separate confirmed-FAW and consistent-with-FAW counts.
- Other suspected causes, uncertainty, station locations, and photographic evidence.
- Whether emergence was complete, continuing, or uncertain.

This assessment alone must not determine:

- Exact yield loss.
- Whether the field should be replanted.
- Whether pesticide application is justified.
- That every missing seedling was killed by FAW.
- An official PCIC compensable-loss percentage.
- An official DA/BPI severity class.

FAO recommends scouting at least weekly and more often when field conditions are changing rapidly. WormWise may display that as general monitoring guidance. Any shorter reassessment interval, local action threshold, replanting rule, or management recommendation must be approved for the Philippine project setting.

### 10.6 DA-BAFS 0-9 leaf-damage severity assessment

#### 10.6.1 Purpose

This assessment measures the **visible extent of FAW-consistent leaf damage** on each sampled maize plant. It answers a different question from current infestation:

- **Current infestation:** Is there evidence of current FAW activity on the plant?
- **Leaf-damage severity:** How extensive is the visible leaf damage?

A plant can have severe old damage but no current infestation. A newly infested plant can have only minor visible damage. The app must store both values separately.

#### 10.6.2 Eligible crop stage

The DA-BAFS scale is based on Davis/Williams leaf- and whorl-damage rating systems. It is most defensible during vegetative whorl stages when the required leaf structures are present and assessable.

- Use it during eligible vegetative stages, provisionally V3-V12.
- At VE/V1-V2, record SFW/IW, larva, seedling cutting, stand loss, and photographs, but mark the 0-9 score `not applicable` unless a Philippine specialist approves early-stage use.
- A Philippine UPLB study reported that its available 1-9 FAW damage scale was unsuitable for infestation occurring at 6-12 days after planting. This supports a cautious early-stage restriction.
- At VT-R2, keep %IP as the primary metric. A residual leaf score may be recorded for research continuity only and must not replace ear-base/axil inspection.
- At R3-R6, use the separate late-season ear-damage workflow. Do not interpret the leaf score as ear or yield-loss severity.

The provisional V3 starting point requires confirmation by a Philippine maize/FAW specialist before production validation.

#### 10.6.3 Per-plant scoring table

Use the DA-BAFS scale exactly as versioned below:

| Score | DA-BAFS leaf-damage description |
|---:|---|
| 0 | No visible leaf damage |
| 1 | Only pin-hole damage to the leaves |
| 2 | Pin-hole and shot-hole damage to the leaves |
| 3 | Small elongated lesions, approximately 5-10 mm, on 1-3 leaves |
| 4 | Mid-sized lesions, approximately 10-30 mm, on 4-7 leaves |
| 5 | Elongated lesions longer than 30 mm and small portions eaten on 3-5 leaves |
| 6 | Elongated lesions longer than 30 mm and large portions eaten on 3-5 leaves |
| 7 | Elongated lesions longer than 30 mm and approximately 50% of a leaf eaten |
| 8 | Elongated lesions longer than 30 mm and approximately 70% of a leaf eaten |
| 9 | Most leaves have long lesions and complete defoliation is observed |

Source: DA-BAFS Table 21, based on Davis et al. (1992) and Williams et al. (2007). The app must record the scale source and protocol version with every assessment so results are not confused with the related 1-9 CIMMYT/Prasanna scale used in some Philippine research.

#### 10.6.4 Scoring procedure

For every eligible plant among the same 50 plants already selected for the formal block:

1. Complete the SFW/IW and current-infestation inspection first.
2. Inspect the visible leaf and whorl damage required by the scale.
3. Compare the plant with the DA-BAFS description and approved visual reference for scores 0-9.
4. Select one score.
5. Record whether the observed damage is `consistent with FAW`, `possible FAW`, `likely non-FAW`, or `uncertain`.
6. Record whether damage appears fresh, old, or mixed.
7. Capture the required context and close-up evidence.
8. If two adjacent scores cannot be distinguished, record the evaluator's chosen score plus `rating uncertain`; do not enter a decimal score.

The app and evaluator must not attribute every hole or lesion to FAW. Corn borers, other caterpillars, mechanical injury, weather, and other causes must remain part of differential assessment.

#### 10.6.5 Field summaries

The 0-9 score is ordinal. WormWise should retain the complete score distribution rather than relying only on an arithmetic average.

Primary block outputs:

- Count and percentage of plants at every score from 0 through 9.
- Median score.
- 25th and 75th percentiles or interquartile range when supported.
- Minimum and maximum observed scores.
- Number of uncertain ratings.
- Station-level score distribution and median.

For compatibility with Philippine efficacy or research reporting, WormWise may also show a **mean field damage score**, but it must be labelled as a secondary summary of ordinal ratings. It must never be converted automatically into a percentage by dividing by 9.

Do not create low/moderate/high bands from the 0-9 score until the exact bands and intended use are approved by a Philippine authority or qualified project expert.

#### 10.6.6 Relationship to treatment decisions

The DA-BAFS 0-9 score documents visible severity. It is not an action threshold. Treatment-decision support continues to use:

- Growth stage.
- Percentage of plants with current SFW/IW or %IP.
- Larval size and accessibility.
- Weather and recent rain.
- Crop variety, value, and condition.
- Locally approved Philippine recommendations.

A high damage score with no fresh activity must not trigger treatment. Similarly, a low damage score may coexist with current small-larva activity that requires continued scouting.

---

## 11. Early reproductive assessment: VT-R2

### 11.1 Required pattern

Use the ladder pattern.

### 11.2 Inspection target

For every selected plant:

1. Examine the tassel for relevant fresh feeding.
2. Gently pull the developing ear away from the stem without breaking it.
3. Examine the base of the developing ear.
4. Examine the leaf axil immediately above the ear.
5. Examine the leaf axil immediately below the ear.
6. Look for a larva of any size or any fresh feeding sign.

Record:

- Larva present or absent.
- Fresh feeding present or absent.
- Frass present or absent.
- Ear/husk penetration visible or not visible.
- Possible non-FAW symptom.
- Whether the plant is currently infested, not currently infested, or uncertain.

### 11.3 Definition of an infested plant

For VT-R2, count a plant as currently infested when the target area has:

- Any larva, regardless of size; or
- Any sign of fresh feeding.

### 11.4 Formula

```text
Percentage of infested plants (%IP) =
  (currently infested plants / assessable plants) × 100
```

---

## 12. Late-season ear and kernel damage assessment: R3-R6

### 12.1 Purpose and plain-language meaning

R3-R6 uses a separate assessment because the structured CIMMYT early-reproductive worksheet ends at R2. By R3-R6, larvae may already be protected inside the ear, and the normal opportunity for an effective rescue treatment may have passed.

The earlier version of this section measured whether an ear was damaged, but not how much kernel damage was present. This extension answers separate questions:

1. How many selected ears have externally visible damage?
2. How many selected ears show current activity such as a live larva or fresh feeding/frass?
3. Among the limited ears that the farmer permits the evaluator to open, how many kernels are visibly damaged?
4. How many opened ears show mold or rot that requires separate review?

This mode documents damage, possible harvest risk, spatial distribution, and evidence for expert review. It does **not** automatically recommend spraying or convert kernel injury into yield or insurance loss.

### 12.2 Evidence status

Philippine BPI/DA-Bicol guidance confirms that late-season FAW larvae can feed on husks, silk, cobs, and developing kernels, affecting grain yield and quality. The DA-BAFS manual provides a FAW leaf-damage scale but does not provide a Philippine FAW ear-severity scale; its Table 19 ear scale is specifically for corn earworm and must not be relabelled for FAW.

CIMMYT publishes a 1-9 FAW ear/kernel rating for germplasm research at harvest, and a South African government procedure provides another 1-9 field scale. Neither is an official Philippine farmer-field standard. WormWise therefore uses raw counts and percentages as its primary result and marks this late-season extension provisional pending Philippine expert validation.

### 12.3 Crop use, harvest status, and permission

Opening an ear is destructive because it may reduce its market or seed value. This is especially important for green corn and sweet corn, which may be harvested before R6 and sold with intact ears.

Before any ear is opened, record:

- Intended crop use: grain, green corn, sweet corn, seed, silage, or other.
- Current reproductive stage and whether commercial harvest has started.
- Whether the selected ears are already part of the harvest.
- Farmer/authorized-person permission: granted, refused, or not available.
- Maximum number of ears permitted to be opened.
- Reason for opening: severity documentation, expert validation, research, harvest inspection, or other.
- Person granting permission, evaluator, timestamp, and remarks.

If permission is refused or unavailable, complete the external assessment and record internal kernel damage as `not assessed`, never zero.

### 12.4 Pattern and two-level sample

- Use the ladder pattern.
- Provisionally retain five stations and ten plants per station per one-hectare block.
- Designate the same type of ear consistently, normally the primary or uppermost marketable ear.
- Record a plant with no ear separately; do not silently substitute a healthier plant.

#### Level 1: external assessment

Inspect the designated ear on all ten selected plants per station, producing up to 50 external-ear observations per block.

#### Level 2: opened-ear severity subsample

When permission is granted, provisionally open two preselected ears per station, for a target of ten opened ears per block.

- The app must choose the plant identifiers before the evaluator inspects their damage. A fixed rule such as Plants 3 and 8 or an app-generated random selection can prevent selection of only visibly damaged ears.
- If a preselected ear is unassessable, retain the failed selection and reason. Any replacement must follow a predefined app order rather than evaluator preference.
- At physiological maturity or during grain harvest, the farmer may authorize opening more than ten or all 50 ears. Preserve the exact opened-ear denominator.
- Ten opened ears is a provisional research subsample, not a locally validated Philippine minimum.

### 12.5 External-ear inspection

For every selected designated ear, record:

- Ear present, absent, or not assessable.
- Ear/husk exterior and ear-tip condition.
- Ear base, shank, silk when present, and nearby leaf axils.
- Husk or silk feeding.
- Visible entry or exit holes.
- Fresh, old, mixed, or uncertain frass.
- Live larva and approximate size, when visible.
- Fresh, old, mixed, or uncertain feeding.
- Visible mold or rot-like symptoms.
- Possible FAW, corn earworm, corn borer, disease, animal, mechanical, or uncertain cause.

An unopened ear may contain hidden kernel damage. Record internal kernel condition as `not assessed` unless the kernels are genuinely visible or the ear is opened under the approved subsample.

### 12.6 Opened-ear and kernel inspection

For every permitted opened ear, record:

- Plant, station, and ear identifier.
- Whether the husk was intact before opening.
- Live larva and larval-identification evidence.
- Fresh or old frass.
- Damaged-kernel count.
- Total assessable-kernel count when it can be counted reliably.
- Ear-tip damage length when measurable with an available reference.
- Cob damage.
- Broken, missing, or incompletely developed kernels, recorded separately from feeding damage when the cause is unclear.
- Visible mold or rot.
- Mold/rot-affected kernel count when reasonably countable.
- Confirmed FAW present, injury consistent with FAW, possible other pest, likely non-pest cause, or uncertain.

Kernel counting may be manual or AI-assisted. Any AI count must be displayed to the evaluator for confirmation, correction, or rejection. When a reliable total-kernel denominator is unavailable, report the damaged-kernel count and mark the percentage unavailable rather than inventing it.

### 12.7 Late-season classifications

- **Active ear infestation:** A live larva or convincing fresh feeding/frass is present at the designated ear.
- **Externally damaged ear:** Visible husk, silk, ear-tip, entry/exit, or other external feeding injury is present.
- **Internally damaged opened ear:** At least one kernel or internal ear structure has visible feeding damage.
- **Old damage only:** Damage exists but no evidence of continuing activity is found.
- **Ear rot/mold present:** Visible rot or mold-like symptoms are present; their cause is not automatically assigned to FAW.
- **Possible other pest/non-pest cause:** Evidence better supports another pest, disease, animal, weather, or mechanical cause.
- **Uncertain:** Inspection or evidence is insufficient.

FAW presence and damage severity remain separate. A larva may be present with little visible kernel damage, while an ear may have severe old damage but no current larva.

### 12.8 Quantitative calculations

#### 12.8.1 Externally visible damaged-ear incidence

```text
Externally visible damaged ears (%) =
  (externally assessable ears with visible feeding damage /
   externally assessable ears) x 100
```

This does not claim that unopened ears have no hidden damage.

#### 12.8.2 Active ear infestation

```text
Active ear infestation (%) =
  (assessable ears with a live larva or convincing fresh feeding/frass /
   assessable ears) x 100
```

#### 12.8.3 Opened-ear damage incidence

```text
Opened-ear damage incidence (%) =
  (assessable opened ears with internal feeding damage /
   assessable opened ears) x 100
```

Always display the numerator and smaller opened-ear denominator, for example `4 of 10 opened ears (40%)`.

#### 12.8.4 Per-ear damaged-kernel percentage

```text
Damaged kernels for one ear (%) =
  (visibly feeding-damaged kernels on that ear /
   assessable kernels on that ear) x 100
```

Calculate only when the total assessable-kernel count is reliable.

#### 12.8.5 Pooled damaged-kernel percentage

```text
Pooled damaged kernels (%) =
  (total visibly feeding-damaged kernels across opened ears /
   total assessable kernels across opened ears) x 100
```

Preserve every per-ear result so one severely damaged ear is not hidden by the pooled total.

#### 12.8.6 Mean damaged kernels

```text
Mean damaged kernels per opened ear =
  (total visibly feeding-damaged kernels /
   assessable opened ears)
```

#### 12.8.7 Ear-rot incidence

```text
Ear-rot incidence (%) =
  (assessable opened ears with visible mold or rot /
   assessable opened ears) x 100
```

Ear-rot incidence must remain separate from FAW damage because the app cannot conclude that FAW caused every mold or rot symptom.

All of these are documentation indicators, not validated treatment, yield-loss, marketability, food-safety, or insurance thresholds.

### 12.9 Worked example

Suppose 50 ears are externally assessable. Twelve show external feeding damage and four show a live larva or convincing fresh activity:

```text
Externally visible damaged ears = 12 / 50 = 24%
Active ear infestation = 4 / 50 = 8%
```

The farmer permits ten preselected ears to be opened. Five contain internal feeding damage. Across the ten ears, 2,400 kernels are assessable, 180 are visibly feeding-damaged, and two ears show mold:

```text
Opened-ear damage incidence = 5 / 10 = 50%
Pooled damaged kernels = 180 / 2,400 = 7.5%
Ear-rot incidence = 2 / 10 = 20%
```

The app must not report `the field lost 7.5% of its yield`. The opened ears are a limited sample, damaged-kernel percentage is not identical to yield loss, and rot may have multiple causes.

### 12.10 Ear-image evidence

When an ear is opened, the minimum guided evidence should represent:

- The whole ear before husk removal.
- The opened ear from one side.
- The opposite or rotated side of the opened ear.
- A close-up when larva, frass, kernel damage, cob injury, mold, or an uncertain feature requires diagnostic detail.

The app may adapt the exact number of images to the evidence needed; one image must not be treated as proof of all sides of an ear. External-only ears follow the general representative-evidence rules in Section 13 unless an individual positive or uncertain observation requires its own photograph.

### 12.11 CIMMYT 1-9 ear scale

Do not automatically calculate or present the CIMMYT 1-9 ear score as the normal WormWise result because:

- It was designed mainly for rating maize germplasm at harvest.
- Its resistant/susceptible labels do not describe the condition or management of a single farmer's field.
- Its source is identified as a CIMMYT unpublished protocol.
- Its descriptions mix damaged-kernel counts and damage percentages.
- The published percentage descriptions leave an unclear interval between approximately 25% and 35% damage.

Store raw counts and percentages first. The CIMMYT score may be added later only in an explicitly labelled expert/research mode after a Philippine specialist approves its local use, resolves the ambiguous ranges, and decides whether kernel count or damage percentage has priority.

### 12.12 Permitted output, recommendations, and restrictions

WormWise may:

- Preserve the assessment, permission record, and photo evidence.
- Report external-ear, active-infestation, opened-ear, kernel, and rot indicators with exact denominators.
- Request validation from the Municipal/City Agriculture Office or qualified crop specialist.
- Recommend expert review of harvest planning, ear handling, and possible rot or food-safety concerns.
- Recommend continued monitoring when active feeding is present.

WormWise must not use this assessment alone to determine:

- Exact yield or financial loss.
- PCIC compensable loss.
- Marketability or food safety.
- That every damaged kernel or mold symptom was caused by FAW.
- An official Philippine low/moderate/high ear-severity class.
- Whether a pesticide should be applied.

WormWise must not automatically recommend a pesticide for R3-R6.

---

## 13. Photo and AI evidence protocol

### 13.1 One image is not a complete plant assessment

One image usually cannot show the newest three or four leaves, whorl interior, both visible feeding damage and frass, a concealed larva, larval identification features, and possible non-FAW symptoms.

The application must not claim that one photograph proves the complete status of a plant.

### 13.2 Physical inspection versus AI inspection

WormWise must distinguish two uses of photographs:

1. **Evidence-assisted human assessment:** The evaluator physically inspects the plant and uses photographs as supporting evidence.
2. **AI-assisted plant diagnosis:** The AI analyzes guided views and suggests findings, which the evaluator confirms or corrects.

AI output is advisory until the image model has been validated on representative Philippine maize and FAW data.

### 13.3 Guided images

When AI is expected to evaluate a sampled plant, use:

- **Image 1 — Context/target overview:** Whole whorl and newest three or four leaves for VE-V12; ear region and nearby axils for VT-R6.
- **Image 2 — Close-up:** Fresh damage, frass, whorl interior, ear base, or other target evidence.
- **Image 3 — Conditional identification view:** Larva, egg mass, ear penetration, kernel damage, or confusing symptom when present.

Minimum interpretation:

- One clear image may support one visible observation.
- At least two guided views are needed before AI may suggest a whole-plant status.
- A third view is required when identification depends on a larva or a hidden/ambiguous symptom.
- If required views are missing or blurred, return `insufficient image evidence`; do not guess.

For the DA-BAFS 0-9 leaf-damage assessment, the interface must also display an approved visual reference for the selected score. The initial visual guide may be based on the DA-BAFS Annex C reference, subject to reproduction permission and local expert review. WormWise should preferably build its own expert-labelled Philippine reference-image set rather than copying third-party images without permission.

### 13.4 Workload-safe evidence option

If storing two or three images for all 50 plants is too burdensome, the protocol may operate as evidence-assisted human assessment:

- The evaluator completes the structured checklist for all 50 plants.
- Require guided photos for every positive and uncertain plant.
- Require at least one context image per station, including stations with no positive plants.
- Clearly state that AI did not independently verify every negative plant.

The thesis and app must not describe this workload-safe option as full AI verification of all 50 plants.

### 13.5 Image quality checks

Before accepting an image, check:

- Focus and motion blur.
- Adequate light.
- Target plant part is visible.
- Target fills a useful portion of the frame.
- Lens is not blocked.
- Image is not an unrelated gallery image unless gallery import is explicitly permitted and timestamp provenance is retained.

Keep the original image, captured timestamp, GPS metadata when available, station/plant identifier, and AI model version.

---

## 14. Maize FAW pest-and-symptom differential assessment

### 14.1 Purpose and scope

WormWise is a maize Fall Armyworm application, not a complete encyclopedia for every maize pest and disease. The differential assessment includes only organisms and conditions that:

- Produce damage that can realistically be confused with FAW.
- Have larvae or life stages that can resemble FAW.
- Feed in the same maize structures as FAW, including seedlings, leaves, whorls, stalks, tassels, silks, ears, or kernels.
- Could cause an incorrect FAW assessment or management decision if ignored.
- Are documented as relevant to maize in the Philippines or are necessary non-pest explanations for FAW-like symptoms.

The Philippine Fertilizer and Pesticide Authority lists FAW together with Asian corn borer, common cutworm, corn earworm, and corn semilooper among target pests associated with Philippine corn protection products. These are therefore the priority named alternatives. Other observations use broader groups when species-level diagnosis is unnecessary or cannot be supported from phone evidence.

The objective is not always to name the exact alternative. Preventing an unsupported FAW diagnosis is already a valid result.

### 14.2 Three evidence layers

For every positive or uncertain observation, evaluate three layers separately:

1. **Organism evidence:** Egg, larva, pupa, adult, frass, honeydew, webbing, tunnel, mold, or no organism evidence.
2. **Plant-part and damage evidence:** Where the symptom occurs and what physical pattern it forms.
3. **Field-context evidence:** Growth stage, spatial distribution, recent weather, pesticide/herbicide use, flooding, planting problems, animals, and other relevant events.

Damage alone rarely proves the caterpillar species. A diagnostic organism image provides stronger identification evidence, but it must still be consistent with the observed plant part and damage.

### 14.3 Priority named pest alternatives

#### 14.3.1 Fall Armyworm — *Spodoptera frugiperda*

Evidence supporting a confirmed FAW larva includes the combined presence of:

- A dark head with a pale inverted Y-shaped marking.
- Four raised dark spots forming a square near the rear of the body, on the eighth abdominal or second-to-last segment as described in field guides.
- Raised body spots on the other segments in a different arrangement.
- Body, head, and rear-segment images that belong to the same specimen.
- A damage location and feeding pattern compatible with FAW.

Coarse frass in the whorl, windowpanes, shot holes, and ragged whorl feeding support FAW-consistent activity but do not independently confirm the species.

Important limitations:

- The diagnostic markings may be unclear on young larvae.
- An inverted Y alone is insufficient because other caterpillars may show a similar head pattern.
- Blurry, incomplete, or mismatched specimen images cannot support confirmed identification.
- Damage without a diagnostic larva is classified `damage consistent with FAW; pest not confirmed`.

#### 14.3.2 Asian corn borer — *Ostrinia furnacalis*

Evidence favoring Asian corn borer includes:

- Several relatively parallel or aligned holes on newly opened leaves.
- Boreholes in the stalk, tassel, ear shank, or cob.
- Frass emerging from a borehole rather than accumulating mainly in the whorl.
- Internal tunneling.
- Broken tassel, weakened/broken stalk, or dead internal growing tissue associated with tunneling.
- A pale, cream, pinkish, or brownish larva inside a tunnel without the FAW rear four-spot square.

Young borer larvae may feed in whorl leaves and resemble general FAW injury. Older larvae characteristically enter internal stem, shank, tassel, or cob tissue. An external photograph cannot rule out corn borer when internal tunneling has not been inspected.

#### 14.3.3 Corn earworm — *Helicoverpa armigera*

Evidence favoring corn earworm includes:

- Feeding concentrated around silk and the ear tip after silking.
- Eggs laid singly on silk or plant surfaces rather than a typical scaled FAW egg mass.
- A moderately hairy or visually rough larva whose color may vary from yellow or green to red, brown, or nearly black.
- Ear-tip kernel feeding without the complete FAW diagnostic combination.

FAW can also enter ears, so ear-tip injury alone cannot identify corn earworm. A usable larval image or expert inspection is required for a named conclusion.

#### 14.3.4 Common cutworm — Philippine *Spodoptera litura* context

Evidence favoring common cutworm includes:

- Young maize cut near or slightly below ground level.
- Feeding beginning at leaf edges or severe seedling defoliation.
- A larva found near the soil or plant base.
- Larger larvae with prominent paired dark markings behind the head rather than the FAW rear four-spot square.

International publications sometimes use `common cutworm` for a different species. WormWise must store the scientific name when available and use Philippine-reviewed references for *Spodoptera litura* rather than importing a foreign common-name description without verification.

#### 14.3.5 Other armyworm or *Spodoptera* suspected

This group includes larvae such as *Spodoptera exigua*, other locally occurring *Spodoptera*, and *Mythimna* armyworms when the exact species cannot be established.

Use this result when:

- The larva is too young for reliable FAW markings.
- The head or rear abdominal segments are not visible.
- The specimen resembles an armyworm but lacks the complete FAW evidence combination.
- Identification features conflict.

Do not force every striped caterpillar into FAW.

#### 14.3.6 Corn semilooper — *Chrysodeixis* group

Evidence favoring a semilooper includes:

- General leaf chewing or defoliation rather than characteristic whorl-centered activity.
- A looping movement caused by the body's locomotion pattern.
- Absence of the FAW rear four-spot square.

A still image cannot reliably record movement. WormWise may ask the evaluator whether looping movement was observed and retain the result as a secondary candidate pending expert review.

#### 14.3.7 Other chewing or sucking pest

Use grouped results rather than an unsupported species name for:

- Grasshoppers, beetles, or unidentified caterpillars producing leaf-edge notching or scattered chewing.
- Corn aphids or other sucking insects associated with colonies, sticky honeydew, stunting, or black sooty mold.

Sticky honeydew and sooty mold must not be confused with caterpillar frass or automatically labelled ear rot.

### 14.4 Non-insect differential groups

#### 14.4.1 Disease-like leaf lesion

Evidence favoring disease rather than chewing includes:

- Discolored leaf tissue that is initially still physically present.
- Elongated tan, brown, gray, water-soaked, or spreading lesions.
- Lesions distributed from lower toward middle or upper leaves.
- No fresh chewing edge, larva, or caterpillar frass.

The app may report `disease-like leaf lesion`, but it must not name a pathogen without sufficient evidence or expert/laboratory confirmation.

#### 14.4.2 Ear rot or mold

Record feeding damage and mold/rot separately. An insect may create an entry wound, but WormWise cannot assume that FAW caused the infection or determine food-safety/aflatoxin status from an ordinary phone image.

#### 14.4.3 Possible nutrient or soil-related symptom

Evidence includes yellowing, chlorosis, scorched-looking margins, purpling, stunting, poor root growth, or similar patterns across multiple plants without fresh chewing, larvae, or frass.

WormWise must not prescribe a fertilizer product or rate from photographs alone.

#### 14.4.4 Water, herbicide, or planting/emergence problem

Evidence includes uneven emergence, widespread wilting, root injury, discoloration following spray paths, twisted growth, flooding history, or symptoms appearing after an application without caterpillar evidence.

Use grouped outputs such as `possible water stress`, `possible herbicide injury`, `possible planting/emergence problem`, or `uncertain crop stress`.

#### 14.4.5 Hail, wind, or mechanical damage

Evidence includes sudden onset after severe weather, similar damage across exposed plants, bruised/shredded tissue, broken or lodged stalks, damage concentrated on exposed leaves, and absence of larvae or fresh frass. Newly emerging leaves after the event may be unaffected.

#### 14.4.6 Bird, rodent, livestock, or other animal damage

Evidence includes large torn husk sections, gnawed or missing kernels, tooth/beak/claw-like marks, droppings, tracks, or damage too large and differently shaped for caterpillar feeding. Use a grouped `possible animal damage` output.

### 14.5 Structured diagnostic workflow

For every positive or uncertain plant or ear:

1. Confirm that the crop is maize and record its visible growth stage.
2. Record symptom freshness: fresh, old, mixed, or uncertain.
3. Record every affected plant part: seedling base, leaf edge/surface, whorl, midrib, stalk, axil, tassel, silk, husk, ear tip, kernel, cob, or root.
4. Record damage patterns: windowpane, pinhole, shot hole, aligned holes, elongated chewing, leaf-edge feeding, ragged/shredded leaf, cut stem, borehole, tunnel, broken tassel/stalk, silk feeding, ear-tip feeding, kernel feeding, discoloration, mold/rot, wilting, lodging, other, or uncertain.
5. Record organism evidence: egg/mass, larva, pupa, adult, frass, honeydew, webbing, tunnel, mold, none found, or uncertain.
6. If a larva is present, document its entire body, head, rear abdominal segments, side, approximate size, and location on the plant as clearly as practical.
7. Record field distribution: scattered, clustered, field-edge concentrated, widespread, or uncertain.
8. Record relevant recent events: heavy rain, hail, strong wind, flooding, drought, herbicide/pesticide/fertilizer application, field operation, or animal activity.
9. Allow more than one organism or cause when evidence is mixed.

The evaluator must not be instructed to touch an unknown larva merely to test skin texture.

### 14.6 Primary diagnostic results

Assign one primary result while retaining secondary candidate tags:

1. **Confirmed FAW present:** A sufficiently clear diagnostic FAW larva or expert/laboratory confirmation is available.
2. **Damage consistent with FAW; pest not confirmed:** Fresh FAW-like feeding evidence exists without a diagnostic specimen.
3. **Mixed infestation or mixed causes:** FAW evidence occurs together with another pest or non-pest injury.
4. **Another named maize pest suspected:** Evidence favors Asian corn borer, corn earworm, common cutworm, or another locally validated candidate.
5. **Other caterpillar/chewing/sucking pest suspected:** A broad pest group is supported but exact species is not.
6. **Disease-like or rot-like symptom:** Evidence favors disease or rot without sufficient pathogen confirmation.
7. **Nutrient, water, herbicide, weather, animal, planting, or mechanical cause suspected.**
8. **Uncertain — expert review required.**
9. **No relevant symptom or pest evidence.**

The primary category prevents double counting in summary percentages. Secondary tags preserve mixed candidates and observations.

### 14.7 Mixed infestations and causes

WormWise must support multiple findings on the same plant or within one ear, for example:

- FAW in the whorl and Asian corn borer tunneling in the stalk.
- FAW-consistent feeding together with hail damage.
- FAW or corn earworm feeding together with ear rot.
- Old FAW injury followed by a new non-FAW event.

A single-choice pest field is insufficient. Store the primary result, all secondary candidate tags, and the evidence supporting or contradicting each candidate.

### 14.8 Differential summary calculations

Keep these diagnostic outputs separate from leaf-damage severity and treatment thresholds:

```text
Confirmed FAW presence (%) =
  (assessable plants with confirmed FAW present as primary or mixed evidence /
   assessable plants) x 100

FAW-consistent but unconfirmed (%) =
  (assessable plants primarily classified as FAW-consistent without confirmation /
   assessable plants) x 100

Likely other-pest observations (%) =
  (assessable plants primarily classified as another named or grouped pest /
   assessable plants) x 100

Likely non-pest observations (%) =
  (assessable plants primarily classified as disease, nutrient, water, herbicide,
   weather, animal, planting, or mechanical cause /
   assessable plants) x 100

Uncertain observations (%) =
  (uncertain assessable plants / assessable plants) x 100
```

Always retain counts and denominators. Report mixed-cause records separately because secondary tags may overlap and should not be forced into mutually exclusive candidate percentages.

SFW/IW, %IP, leaf-severity, and ear-severity indicators remain raw field-observation results. The differential result explains the strength of pest attribution; it must not silently overwrite the evaluator's original symptom records.

### 14.9 Evidence requirements

Use the general evidence strategy in Section 13 rather than requiring a fixed number of images for every plant. For a positive or uncertain differential case, the guided evidence must represent, when applicable:

- Whole-plant or affected-plant-part context.
- Close-up damage pattern.
- Entire specimen.
- Specimen head.
- Rear abdominal segments.
- Borehole/tunnel, frass, silk/ear-tip, stem base, root, mold, or non-pest feature used in the decision.

If the necessary feature is not visible, record it as unavailable. Do not infer it from another plant or a reference image.

### 14.10 AI and LLM rules

The AI may:

- Suggest ranked candidates.
- State evidence supporting and contradicting every candidate.
- Ask for a missing head, rear-body, stem, whorl, soil-line, silk, ear, or context view.
- Suggest an inspection action that does not unnecessarily destroy the crop.
- Convert evaluator-confirmed observations into structured remarks.

The AI must not:

- Confirm FAW from leaf damage or the inverted Y alone.
- Force species identification for young, hidden, or unclear larvae.
- Hide plausible alternatives or mixed causes.
- Invent an organism feature or field event.
- Replace `uncertain` with the most probable label merely to complete the form.
- Recommend a pesticide based on image classification alone.

Store the AI suggestion, confidence, evidence explanation, model version, and evaluator-confirmed result separately.

### 14.11 Expert escalation and limitations

Request qualified review when:

- The organism remains uncertain after guided evidence collection.
- Identification will affect treatment, certification, food safety, seed use, or insurance documentation.
- A possible new or unusual outbreak is observed.
- Mixed infestations materially affect interpretation.
- The diagnosis would require dissecting stems/ears or laboratory/molecular confirmation.
- AI and evaluator results conflict on a consequential case.

WormWise may accurately conclude `not enough evidence to confirm FAW`. It is not required to identify the exact alternative organism before preserving and reporting the observation.

---

## 15. Natural-enemy and biological-control observation supplement

### 15.1 Purpose and scope

This supplement records field-observable organisms and signs that may represent natural biological suppression of FAW. It supports sustainable integrated pest management without claiming that an observed organism caused a measured amount of pest control.

Use the same five stations and 50 selected maize plants as the main assessment. Do not create another route or automatically increase the plant sample. This supplement applies at every maize growth stage whenever the relevant plant parts can be inspected safely.

At each selected plant, make one quick record:

- `No natural-enemy evidence seen`.
- `Natural-enemy evidence observed`.
- `Uncertain organism or evidence`.
- `Not assessable`.

Open the detailed evidence form only for `observed` or `uncertain`. Record intentional biological-control releases or applications once for the field assessment rather than once per plant.

`No evidence seen` means only that none was detected during this assessment. It does not prove that natural enemies are absent from the field.

### 15.2 Observation categories

#### A. Predator present

Record the broadest group that the evidence supports:

- Earwig.
- Ant.
- Spider.
- Lacewing or lacewing larva.
- Predatory beetle, including a lady beetle when supported.
- Predatory bug.
- Bird.
- Other possible predator.
- Predator group uncertain.

Predator presence is not proof of FAW predation. Do not count an organism merely resting on the maize plant as a confirmed FAW-control event.

#### B. Direct predation observed

Use this stronger category only when the evaluator directly sees a predator feeding on, carrying, or capturing a suspected or confirmed FAW egg, larva, pupa, or moth. Store the predator group, FAW life stage, plant part, and evidence quality.

Keep `direct predation on confirmed FAW` separate from `direct predation on a suspected caterpillar` when the prey cannot be identified reliably.

#### C. Possible egg parasitism

Possible signs include:

- Uneven darkening within an egg mass.
- Small emergence holes.
- A tiny wasp emerging from or closely associated with the egg mass.

Darkening alone is not confirmation because normally developing FAW eggs can also change color. Use one of these results:

- `Possible egg parasitism`.
- `Strong field evidence of egg parasitism`.
- `Expert or laboratory confirmed egg parasitism`.
- `Uncertain egg-mass change`.

#### D. Possible larval parasitism

Possible signs include:

- White or pale silken cocoons beside or attached to a larva.
- Visible parasitoid emergence.
- An abnormal or dead larva associated with parasitoid material.

Ordinary phone images must not be used to confirm a small parasitoid species. Field findings remain `possible` unless a qualified expert or laboratory confirms them. A research-level confirmation may require collecting and rearing the host under an approved specimen protocol.

#### E. Possible pathogen-associated mortality

Record a dead or dying larva when it has potentially relevant signs such as:

- Fungal-looking growth or coating.
- An unusually hard, dry, soft, or liquefied cadaver.
- An unusual attachment position on the plant.
- Several larvae with a similar appearance in the same area.

Do not identify *Metarhizium*, *Beauveria*, a virus, or another pathogen from appearance alone. A dead larva may instead result from a pesticide, rain, heat, injury, predation, or another unknown cause. The field result must therefore remain `possible pathogen-associated mortality` unless confirmed.

#### F. Intentional biological-control history

Ask once per assessment whether a biological-control organism or product was intentionally released or applied. When known, record:

- Agent or product name.
- Type: predator, parasitoid, fungus, virus, or other.
- Release or application date.
- Quantity, rate, or number of release cards.
- Source or supplier.
- Person or organization that recommended it.
- Area treated.
- Package, release-card, receipt, or field-evidence photograph.
- Chemical applications before or after the release.

Keep intentionally released agents separate from naturally occurring organisms. Their presence after release does not by itself prove establishment or effectiveness.

### 15.3 Guided observation workflow

For each selected plant:

1. Complete the normal FAW plant assessment first.
2. Check the same visible whorl, leaf surfaces, egg masses, larvae, ear, and nearby plant parts for natural-enemy evidence without destructively searching the whole plant.
3. Choose the quick observation result.
4. If observed or uncertain, select the evidence category and broad organism group.
5. Record whether interaction with confirmed or suspected FAW was directly observed.
6. Capture guided evidence when safe and practical.
7. Preserve uncertainty and request review when the claim would require species or pathogen confirmation.

Do not handle an unknown organism or cadaver when this creates a safety risk. Do not remove organisms for laboratory work unless an approved collection, containment, labelling, and submission procedure exists.

### 15.4 Evidence photographs

Do not require natural-enemy photographs for all 50 plants. When evidence is observed or uncertain, request:

1. A context image showing the plant part and where the evidence was found.
2. A close image of the organism, interaction, egg mass, cocoon, or cadaver.
3. An additional angle when the first images cannot show the important feature.

Link all images to the assessment, block, station, and plant or specimen identifier. Preserve time, location, image-quality status, evaluator interpretation, and any later expert correction.

### 15.5 Calculations and interpretation

Calculate presence indicators only when the denominator is valid:

```text
Natural-enemy observation rate (%)
  = plants with any natural-enemy evidence / assessable plants x 100
```

```text
Direct-predation observation rate (%)
  = plants with directly observed predation / assessable plants x 100
```

When egg masses were deliberately examined:

```text
Possible egg-parasitism evidence rate (%)
  = egg masses with possible or stronger parasitism evidence
    / egg masses actually examined x 100
```

Always retain the numerator and denominator. Report suspected larval parasitism and possible pathogen-associated deaths as counts unless a separate expert-approved study protocol supplies a valid denominator.

Do not calculate a single `biological-control effectiveness percentage`. Do not subtract natural-enemy observations from FAW infestation or damage results. Do not conclude `no treatment is needed` from natural-enemy presence alone.

### 15.6 AI and LLM rules

The AI may:

- Suggest a broad organism or evidence group.
- Point out visible features and missing views.
- Explain why confirmation is uncertain.
- Recommend expert review.

The AI must not:

- Confirm a tiny parasitoid species from an ordinary phone photograph.
- Confirm a fungal, bacterial, or viral species from appearance alone.
- Treat every dark egg mass as parasitized.
- Treat every dead larva as biological-control mortality.
- Claim that an observed or released organism controlled a particular percentage of FAW.
- Generate release rates or product instructions without an approved current local source.

Store the AI suggestion separately from the evaluator result and any expert-confirmed result.

### 15.7 Expert escalation

Request qualified review when:

- A parasitoid or pathogen species is being claimed.
- The finding will influence a treatment, official report, certification, or insurance decision.
- Unusual or widespread caterpillar mortality is observed.
- A biological-control release or application is being recommended.
- The evidence conflicts with recent pesticide history.
- Laboratory collection, rearing, microscopy, or molecular confirmation is needed.

Project-specific release rates or schedules reported by a particular DA region may be recorded as treatment history but must not become automatic nationwide WormWise recommendations without approval from the appropriate Philippine authority for the location and use.

---

## 16. Field-intervention, pesticide, and exposure-safety history protocol

### 16.1 Purpose and scope

This protocol records anything applied, released, sprayed, or deliberately done that may affect FAW, maize symptoms, natural enemies, evaluator safety, or interpretation of later assessments. It applies once per intervention event and is linked to every assessment conducted after that event.

Before field entry, ask:

> Has anything been sprayed, released, applied, or done to this field since the previous assessment?

Allowed answers are `yes`, `no`, `unknown`, `farmer unsure`, and `reported but details unavailable`. Never force the user to invent missing information.

### 16.2 Intervention categories

Record the intervention as one or more of:

- Chemical insecticide.
- Registered microbial or other biological-control product.
- Released beneficial organism, including parasitoid cards or predators.
- Botanical, household, or farmer-prepared mixture.
- Physical/mechanical control, such as hand-picking larvae or crushing egg masses.
- Cultural action, such as weeding, irrigation, intercropping, hilling-up, or residue removal.
- Other pesticide or agrochemical, including herbicide, fungicide, rodenticide, adjuvant, or plant-growth regulator.
- Fertilizer or foliar plant treatment.
- Plant-incorporated protection or known Bt maize trait.
- Other or uncertain intervention.

A deliberately applied microbial product belongs in intervention history. A fungus found naturally on a larva remains a natural-enemy observation unless evidence links it to a recorded product application.

### 16.3 Progressive recording workflow

Use a short first question and display detailed fields only when an intervention is reported:

1. Select intervention category and stated purpose.
2. Record when and where it occurred.
3. Photograph available labels, packages, cards, receipts, or other evidence.
4. Record the product/agent and application details that are known.
5. Complete the re-entry safety gate before allowing field assessment.
6. Save unknown, estimated, reported, OCR-extracted, evaluator-confirmed, and externally verified values with different provenance states.

An intervention record must not be duplicated for each plant. Link the single event to its field, treated polygon or blocks, and relevant assessments.

### 16.4 Product or agent identity

When applicable, record:

- Brand or product name.
- Active ingredient or biological agent.
- Concentration and formulation.
- Product type.
- Registration number and displayed expiry date.
- Manufacturer, registrant, or supplier.
- Batch or lot number, when available.
- Crop and target pest printed on the label.
- Front-label photograph.
- Back-label and instruction photographs.
- Package, release-card, receipt, or other source evidence.

OCR may extract label text, but the evaluator must confirm it. Do not identify a product from bottle color, shape, smell, or an unreadable image.

For a claimed Bt or other plant-incorporated protection trait, store the variety/event evidence and source. Do not infer the trait merely from a farmer's statement that the seed was `resistant`.

### 16.5 Application or release details

Record, when known:

- Date and start/end time, with `exact`, `estimated`, or `unknown` precision.
- Stated target pest or condition.
- Product/agent amount and water volume.
- Application rate or release quantity exactly as reported.
- Number of tanks, loads, cards, or release units.
- Application method and equipment.
- Equipment calibration status.
- Applicator and person/organization that recommended the action.
- Whole-field or partial-field coverage.
- Treated field polygon or selected blocks.
- Weather, wind, and rainfall around application.
- Rainfall shortly after application.
- PPE reportedly used.
- Spill, exposure, drift, equipment failure, or other incident.
- Disposal information when available.

Reported rate and label rate are separate fields. WormWise must not silently correct, convert, or approve a reported rate.

### 16.6 Safety gate

For a recently treated field, record from the product label or another approved source:

- Re-entry interval (REI).
- Pre-harvest interval (PHI).
- Required PPE.
- Warning/toxicity information.
- Relevant first-aid and restricted-use information.

Before field entry, assign one result:

- `No recent treatment reported`.
- `Safe-entry interval reportedly completed`.
- `Do not enter - REI has not expired`.
- `Entry safety cannot be confirmed`.
- `Treatment history unknown`.

If the application time or REI is unknown, do not guess. Postpone entry until the label, farmer, applicator, dealer, or agriculture office confirms that entry is safe. A phone calculation may add a verified REI to a verified application end-time, but it must show the source and must not replace label instructions.

### 16.7 Registration and label verification

When internet is available, WormWise may compare the confirmed product to the current Philippine competent-authority record and check:

- Current registration status and expiry.
- Whether corn is an approved crop.
- Whether FAW or the stated target is covered.
- Registered application method.
- Label rate, PHI, and REI when available.
- Full, conditional, expired, or unresolved status.

Because registrations change, store the verification date and source version. An offline cached entry must show its age. When evidence is incomplete or mismatched, report `registration or label use not verified` and request review; do not automatically accuse the user of illegal use.

### 16.8 Resistance-management context

Store the active ingredient and insecticide mode-of-action group only when obtained from a reliable current source. The app may display repeated use of the same group for expert review, but it must not prescribe a rotation, mixture, dose, or product. Resistance cannot be diagnosed from one field's poor response.

### 16.9 AI and LLM restrictions

AI may extract label text, identify missing fields, suggest a possible registry match, and calculate elapsed time from verified values.

AI must not:

- Invent a product, active ingredient, rate, REI, PHI, registration, or application time.
- Recommend mixing products, increasing the dose, shortening an interval, or re-spraying.
- Approve an unverified use.
- tell the evaluator to enter when safety is uncertain.
- Convert an image diagnosis into a pesticide prescription.

Store OCR output, AI interpretation, evaluator confirmation, registry verification, and expert correction separately.

---

## 17. Follow-up assessment, intervention response, and trend-comparison protocol

### 17.1 Purpose and limitation

This protocol links repeated WormWise assessments so the app can report what changed over time. It supports routine monitoring, assessment history, maps, charts, and post-intervention observation.

A normal farmer-field comparison is observational. Without randomized treatment allocation, an untreated comparison, replication, and controlled conditions, WormWise must not label the result a pesticide or biological-control `efficacy test`. Weather, new egg laying, larval development, crop stage, natural enemies, application coverage, and undocumented actions may all affect the result.

### 17.2 Follow-up types

Record the follow-up purpose as:

- Routine monitoring.
- Post-intervention observation linked to a Section 16 event.
- Event-triggered reassessment after rain, a new outbreak report, rapid symptom change, crop-stage transition, or questionable earlier assessment.
- Agriculture-office or research follow-up.
- Other or uncertain purpose.

This protocol is conditional. A standalone assessment remains valid without a follow-up.

### 17.3 Timing

Routine field scouting should normally recur approximately weekly while the crop remains at risk, and more often during rapid changes when directed by a competent local source.

For an intervention response:

1. Obtain a complete baseline as close as practical before the intervention, when safe.
2. Use follow-up timing specified by the registered label, approved local protocol, or qualified agriculture officer.
3. When no product-specific timing is available, use the normal weekly assessment and label it an observational follow-up, not an efficacy check.
4. Record the exact interval between baseline, intervention, and follow-up.

Do not impose one universal 24-, 48-, 72-hour, or seven-day response rule. Chemical products, microbial agents, parasitoid releases, predators, and cultural actions operate differently.

### 17.4 Comparison eligibility

Before calculating change, confirm that assessments use:

- The same mapped field and compatible block geometry.
- The same formal sampling design and protocol version, or a documented compatible version.
- The same stage-specific indicator.
- Comparable plant-selection rules and actual denominators.
- The same station areas when practical, using saved GPS anchors.
- Reliable dates, times, and intervention chronology.

The same individual plants may be revisited when identifiers remain reliable and the plants were not destructively sampled. Otherwise, assess a new representative plant sequence in the same station area and compare at station/block level.

If eligibility fails, display the assessments side by side but do not calculate a formal change result.

### 17.5 Growth-stage and metric compatibility

Do not calculate one continuous trend across incompatible indicators:

- Vegetative SFW/IW and VT-R2 %IP remain separate.
- Leaf-damage severity and R3-R6 ear damage remain separate.
- R3-R6 external-ear and opened-ear/kernel indicators retain their own denominators.
- DA-BAFS 0-9 scores describe visible damage that does not heal; persistent old damage is not automatic evidence of control failure.

When the crop changes assessment mode, place a stage-transition marker on the timeline and begin the new stage-specific series.

### 17.6 Observed-change calculations

For compatible proportions, retain both counts and denominators and calculate:

```text
Observed percentage-point change
  = follow-up percentage - baseline percentage
```

```text
Observed positive-count change
  = follow-up positive count - baseline positive count
```

When the baseline percentage is greater than zero, the app may secondarily calculate:

```text
Relative observed change (%)
  = (follow-up percentage - baseline percentage)
    / baseline percentage x 100
```

Always label the result `observed change`, not `treatment effectiveness`. Small samples and incomplete assessments must show additional uncertainty warnings.

Example:

```text
Baseline: 18 of 50 currently infested (36%)
Follow-up: 8 of 50 currently infested (16%)
Observed change: -10 sampled plants and -20 percentage points
```

Do not convert that example into `55.6% pesticide effectiveness`, even though the optional relative observed change is -55.6%.

### 17.7 Information compared

When compatible, compare:

- Current-positive plant counts and stage-specific percentages.
- SFW and IW separately.
- Confirmed FAW and FAW-consistent-unconfirmed findings separately.
- Fresh and old damage separately.
- DA-BAFS score distributions with the persistence limitation stated.
- R3-R6 metrics with matching assessment method and denominator.
- Natural-enemy, direct-predation, possible-parasitism, and possible-pathogen observations separately.
- Station-level distribution, missing data, uncertainty, and image-evidence quality.

### 17.8 Events and attribution limits

Place every relevant event on the field timeline, including interventions, heavy rain, irrigation, crop-stage change, and major assessment interruption. When multiple events occur between assessments, state that their individual contributions cannot be determined.

Allowed wording:

> Current FAW evidence decreased from 18 of 50 plants to 8 of 50 plants, an observed reduction of 20 percentage points after the recorded intervention.

Required limitation when relevant:

> Other factors, including rainfall, natural enemies, crop development, new pest movement, application coverage, and unrecorded events, were not controlled.

### 17.9 Invalid or restricted comparisons

Do not calculate a formal trend when:

- Field/block boundaries or sampling designs are incompatible.
- Growth stages require different indicators.
- One assessment deliberately selected damaged plants.
- Important denominators, dates, or locations are missing.
- A follow-up has too few assessable plants for the intended validated result.
- Multiple undocumented interventions occurred.
- The protocol changed incompatibly.
- The assessment occurred before the applicable REI expired.

Do not declare product failure or insecticide resistance from one field comparison.

### 17.10 Map, AI, and decision-support rules

Maps may show station-level increase, decrease, no observed change, and not-comparable results. Interpolation between stations remains an estimate and must not imply observation of every field location.

The app may recommend confirming current FAW, reviewing treatment and weather history, checking label/registration information, consulting the Municipal/City Agriculture Office, or scheduling another safe assessment.

It must not automatically recommend re-spraying, doubling a dose, mixing products, shortening a label interval, or changing products. AI-generated causal explanations must remain hypotheses and must never replace the recorded event timeline.

---

## 18. Reference action thresholds

The following are **CIMMYT Asia starting points**, not automatically validated Philippine treatment rules:

| Growth stage | Indicator | Reference starting point | Published range |
|---|---|---:|---:|
| VE/V1-V6 | Plants with SFW and/or IW | 20% | 10-30% |
| V7-V12 | Plants with SFW and/or IW | 50% | 40-60% |
| VT-R2 | Percentage of infested plants (%IP) | 20% | 10-30% |
| R3-R6 | No agreed WormWise treatment threshold | Not applicable | Not applicable |

### 18.1 Rules for app use

Until locally approved, WormWise may display these values only as:

> Research reference — requires local expert interpretation.

WormWise must not convert crossing a reference threshold directly into a pesticide instruction. Interpretation also depends on:

- Maize variety and tolerance.
- Crop value and intended use.
- Larval size and whether larvae are accessible.
- Weather and recent/expected heavy rain.
- Pest pressure and prior assessments.
- Control cost and likely benefit.
- Registered products and current Philippine label requirements.
- Applicator safety, PPE, pre-harvest interval, and re-entry interval.

### 18.2 Severity colors

Do not label a low/moderate/high color system as an official **FAO color-coded classification** unless the project identifies an authoritative FAO source defining the exact categories and calculations being used.

Until then:

- Store the calculated percentages as the primary result.
- If colors are needed for the GUI, label them `WormWise provisional display bands`.
- Keep display severity separate from treatment action thresholds.
- Require expert approval for the band limits.

### 18.3 DA-BAFS severity scores are not action thresholds

The DA-BAFS 0-9 leaf-damage score must remain separate from the CIMMYT infestation reference thresholds in Section 18. A score such as 6 or 7 does not, by itself, mean that a treatment is justified. The score may represent old damage, inaccessible large larvae, or damage accumulated under earlier conditions.

Do not describe any grouping of 0-9 scores as official DA-BAFS `low`, `moderate`, or `high` field infestation unless DA-BAFS or another competent Philippine authority publishes or approves that mapping for this use.

---

## 19. Recommendations and decision support

### 19.1 Always-allowed recommendations

The app may safely recommend:

- Reassess at a recorded date or after a major rain event.
- Preserve natural enemies and avoid unnecessary disturbance.
- Consult the Municipal/City Agriculture Office when the result is uncertain or above a locally approved action level.
- Confirm the pest before any control decision.
- Follow registered product labels and official local advice.
- Use appropriate PPE and observe re-entry and pre-harvest intervals.
- Review the recorded intervention, label evidence, weather, and natural-enemy context before interpreting a follow-up.
- Schedule a safe follow-up using a verified label, approved local protocol, qualified officer instruction, or routine weekly scouting.

### 19.2 Restricted recommendations

WormWise must not independently prescribe:

- A pesticide product.
- Mixing concentration or application rate.
- Application frequency.
- Unregistered household or improvised pesticide mixtures.
- Treatment when the user has not confirmed crop stage and current infestation.
- Treatment based only on old damage.
- Immediate re-spraying, a larger dose, a shorter interval, or a product mixture after an unfavorable follow-up.
- A declaration of product efficacy, product failure, or insecticide resistance from an ordinary field comparison.

Any future product-specific recommendation must come from current Philippine registration information and qualified agricultural approval, not from the LLM's general knowledge.

---

## 20. Required calculations and results

### 20.1 Station result

For each station, store:

- Assessable plant count.
- Current-positive plant count.
- Old-damage-only count.
- Uncertain count.
- Possible non-FAW count.
- Primary differential-category count and all secondary candidate tags.
- Confirmed-FAW, FAW-consistent-unconfirmed, likely-other-pest, likely-non-pest, mixed-cause, and uncertain counts.
- Stage-specific indicator percentage.
- SFW and IW counts for vegetative maize.
- VE-V2 planting-unit occupancy, unexplained gaps, observed seedling injury, and FAW-associated seedling injury, when eligible.
- Separate confirmed-FAW-present and injury-consistent-with-FAW counts at VE-V2.
- VE-V2 emergence-completeness and planting-position-assessability warnings.
- DA-BAFS 0-9 score for every eligible vegetative plant.
- Score distribution, median, range, and uncertain-rating count for each eligible station.
- Externally assessable, externally damaged, and actively infested ear counts for R3-R6.
- Opened-ear permission, sample size, internal-damage incidence, damaged-kernel counts/percentages, and ear-rot incidence when destructive sampling is permitted.
- Natural-enemy quick-observation status for every assessable plant.
- Counts of plants with natural-enemy evidence, uncertain evidence, and directly observed predation.
- Suspected egg or larval parasitism and possible pathogen-associated mortality counts, kept separate from confirmed records.
- GPS position and accuracy.
- Completion and photo-evidence status.

### 20.2 Block result

Calculate results from plant totals, not by averaging rounded station percentages.

Correct:

```text
Block percentage =
  (sum of positive plants across all stations /
   sum of assessable plants across all stations) × 100
```

### 20.3 Whole-field result

For multiple blocks, preserve each block result. A whole-field percentage may be calculated from combined plant counts only when the blocks use the same assessment mode and compatible growth stage.

Do not combine:

- Vegetative SFW/IW results with VT-R2 %IP.
- Early reproductive results with R3-R6 damaged-ear results.
- R3-R6 external-ear percentages with opened-ear or kernel percentages without showing their different denominators.
- Assessments from substantially different planting dates or crop conditions without displaying them separately.

For DA-BAFS 0-9 severity results, combine raw plant-score distributions only when blocks used the same protocol version and eligible growth-stage interpretation. Preserve block-specific medians even when a whole-field distribution is also displayed.

For differential results, preserve primary categories and secondary candidate tags at plant, station, and block level. Do not merge `confirmed FAW`, `FAW-consistent but unconfirmed`, `another pest`, `non-pest`, `mixed`, and `uncertain` into a single definitive FAW count.

For natural-enemy results, preserve observation, direct-predation, possible-parasitism, possible-pathogen, and expert-confirmed results separately. Do not combine them into a biological-control effectiveness score or subtract them from the FAW infestation result.

### 20.4 Spatial result

Display station-level results on the field map. Interpolation between stations must be clearly marked as an estimate. Five stations per hectare do not prove the condition of every location in the field.

### 20.5 Intervention and follow-up result

At field or block level, store:

- Linked intervention identifiers, types, dates, treated areas, and evidence status.
- Product/agent identity and registration-verification state when applicable.
- REI/PHI sources and entry-safety result.
- Baseline and follow-up assessment identifiers and elapsed intervals.
- Comparison-eligibility result and any incompatibility reasons.
- Baseline and follow-up counts, denominators, and percentages.
- Observed count change, percentage-point change, and optional relative observed change.
- Relevant intervening events and attribution limitations.

Never store `treatment effective` as a calculated fact from an ordinary before-and-after field comparison.

---

## 21. Incomplete, interrupted, and invalid assessments

### 21.1 Complete assessment

A block is complete when:

- Five stations are recorded.
- Ten plant positions are recorded per station.
- Required growth-stage and field information is present.
- Intervention-history question and field-entry safety gate are completed.
- Every plant has a status or documented `not assessable` reason.
- Every assessable plant has a natural-enemy quick-observation result, with a documented reason when that observation was not assessable.
- Required station/photo evidence is present for the selected evidence mode.
- GPS and timestamps are stored, or an explicit GPS-unavailable warning is accepted.
- For an eligible VE-V2 supplement, all ten planting-unit positions per station are recorded or the app stores why the planting-unit sequence was not assessable.
- For a claimed follow-up comparison, baseline link, timing, compatibility result, and all comparison denominators are present; otherwise the assessment remains complete but the trend result is marked not comparable.

### 21.2 Incomplete assessment

If fewer than 50 plants are assessable:

- Calculate a provisional observed percentage using the actual denominator.
- Display the numerator and denominator, for example `8 of 43 assessable plants (18.6%)`.
- Mark the block `incomplete — not suitable for validated classification`.
- Do not silently scale the count to 50 plants.
- Do not issue certification-ready output.

### 21.3 Interrupted assessment

The app must save progress offline after each plant and station. On resume, it must show:

- Completed block/station/plant identifiers.
- Time since interruption.
- Whether conditions such as rainfall changed.
- Whether continuing the same session is still appropriate.

If a long delay or major weather/control event occurred, start a new assessment rather than combining incompatible observations.

### 21.4 Invalid assessment conditions

Flag for review when:

- The evaluator deliberately sampled only damaged plants.
- Stations are concentrated at the field edge without explanation.
- Plant identifiers or images are duplicated.
- Recorded growth stages conflict substantially within a block.
- GPS locations fall outside the field/block beyond reasonable phone-GPS error.
- Required evidence is missing.
- The field was entered before a pesticide re-entry interval expired.

---

## 22. Offline-first requirements

The entire field procedure must work without internet after required map resources are prepared.

Offline storage must include:

- Field/block geometry.
- Assessment route and stations.
- Crop and assessment metadata.
- All plant observations.
- Intervention events, treated-area links, reported application/release details, and safety-gate results.
- Label/package evidence, OCR output, cached registry match, source version, and verification date.
- Assessment-to-intervention and baseline-to-follow-up links.
- Event timeline, comparison-eligibility status, and observed-change calculations.
- Original photographs and thumbnails.
- GPS coordinates, accuracy, and timestamps.
- Calculation results.
- Language used for questions and remarks.
- AI result, confidence, and model version when on-device AI is used.
- Sync status and conflict information.

The app must not require an online LLM to complete the formal checklist. When an online AI service is unavailable, save the structured observation and queue only the optional analysis for later.

---

## 23. Data provenance and audit trail

Every assessment should preserve:

- Creator and device identifier.
- Creation and last-edit timestamps.
- Original and edited values.
- Reason for manual correction.
- AI suggestion and evaluator-confirmed value separately.
- Expert-review status and reviewer identity.
- Boundary version used for the assessment.
- Calculation/protocol version.
- Sync history.

Every intervention and follow-up comparison should additionally preserve:

- Reporter, evidence source, and whether each value is exact, estimated, reported, OCR-extracted, evaluator-confirmed, registry-verified, or expert-corrected.
- Original label images and confirmed transcription.
- Registration lookup source and lookup date.
- Safety decision, its inputs, and any override attempt.
- Baseline/follow-up identifiers, compatibility decision, excluded comparisons, and calculation version.

Do not overwrite the evaluator's observation with the AI result. Store both so disagreements can be studied during validation.

---

## 24. Report content

A completed report should contain:

- Field and farmer identifiers permitted by the project's privacy policy.
- Field/block map and area.
- Crop variety, planting date, and growth stage.
- Assessment date, evaluator, and protocol version.
- Pattern used and reason.
- Five station locations per block.
- Plant totals and calculated percentages.
- SFW/IW distribution for vegetative maize.
- VE-V2 planting-unit occupancy, unexplained-gap percentage, observed seedling-injury percentage, and FAW-associated seedling-injury percentage, with numerators and denominators.
- Separate confirmed-FAW-present and injury-consistent-with-FAW counts for VE-V2.
- A warning when VE-V2 emergence is incomplete or planting positions could not be assessed reliably.
- DA-BAFS 0-9 leaf-damage distribution, median, range, and uncertainty count for eligible vegetative maize.
- A statement that the DA-BAFS scale is used for severity documentation and is not itself a treatment threshold.
- %IP for VT-R2.
- Externally visible damage and active-ear-infestation percentages for R3-R6.
- Opened-ear sample size and permission status, internal-damage incidence, per-ear and pooled kernel-damage results, and ear-rot incidence when assessed.
- A statement that unopened ears have unassessed internal condition and that kernel damage is not a direct yield- or insurance-loss percentage.
- Representative photo evidence.
- Possible non-FAW and uncertain observations.
- Differential-category distribution, confirmed-FAW count, FAW-consistent-unconfirmed count, named/grouped alternative candidates, mixed causes, and evidence limitations.
- A statement that symptom similarity or AI probability does not by itself confirm the pest species.
- Natural-enemy observation and direct-predation counts and rates, using exact numerators and denominators.
- Possible egg/larval parasitism and possible pathogen-associated mortality counts, clearly separated from expert-confirmed findings.
- Intentional biological-control release/application history and evidence when provided.
- A statement that natural-enemy presence does not prove a particular amount of FAW control or independently decide whether treatment is needed.
- Intervention history, treated area, product/agent evidence, and registration-verification status when provided.
- REI/PHI source and field-entry safety status without exposing unnecessary personal information.
- A chronological event timeline for every follow-up report.
- Compatible baseline/follow-up counts, denominators, observed count change, and percentage-point change.
- A statement that an ordinary before-and-after result is observational and does not establish product efficacy or sole causation.
- Weather, rainfall, and recent-control context when available.
- Data-quality and completeness status.
- Research-reference threshold comparison, clearly labelled when not locally validated.
- Reviewer/validation status.

Certification language for PCIC or an agriculture office must be added only after the responsible institution defines and approves the required form, signatory, evidence, and validation workflow.

---

## 25. Validation required before production use

The following must be reviewed or tested before WormWise claims a validated assessment:

1. Approval of the one-hectare block and partial-hectare rule in the Philippine setting.
2. Agreement on when W becomes impractical and ladder should be used.
3. Local verification of SFW, IW, and %IP interpretation.
4. VE-V2 planting-unit identification, emergence gate, condition categories, calculations, and feasibility of completing both planting-unit and living-plant samples.
5. Local differentiation of FAW seedling injury from cutworms, seedling maggot, wireworms, disease, failed/delayed emergence, and environmental or mechanical injury.
6. Confirmation of the eligible growth-stage range for the DA-BAFS 0-9 leaf-damage scale, especially its lower vegetative boundary.
7. Inter-evaluator agreement for every DA-BAFS score, especially adjacent scores 4-8.
8. Approval of the Philippine reference-image set for scores 0-9.
9. Local validation of any severity-color bands.
10. Philippine action thresholds by maize variety, season, location, and crop use.
11. R3-R6 external-ear and opened-ear sampling, the provisional ten-ear subsample, replacement rules, destructive-sampling consent, kernel-count feasibility, and interpretation.
12. Local validation of FAW versus corn earworm, corn borer, disease, and non-pest causes on reproductive ears.
13. Required images per plant and opened ear for acceptable AI performance.
14. Philippine validation of the priority differential list, scientific/common/local names, specimen features, damage-pattern rules, and non-pest categories.
15. Inter-evaluator agreement and AI accuracy for confirmed FAW, FAW-consistent damage, locally important look-alike pests, mixed causes, and non-pest symptoms.
16. Approval and licensing of Philippine reference images for FAW, Asian corn borer, corn earworm, common cutworm, other armyworms, semiloopers, and non-pest mimics.
17. Philippine validation of the natural-enemy groups, field signs, broad-group image references, and terminology used in the supplement.
18. Inter-evaluator agreement for predator presence, direct predation, suspected parasitism, and possible pathogen-associated mortality.
19. Rules for distinguishing naturally occurring organisms from intentionally released biological-control agents.
20. Locally approved sources, rates, schedules, safety requirements, and reporting rules for any biological-control recommendation.
21. Minimum intervention fields, evidence states, label-photo requirements, and usability for farmers who do not know product details.
22. Current Philippine pesticide/biocontrol registry source, update method, offline-cache age, matching rules, and mismatch wording.
23. REI/PHI capture, time calculations, unknown-safety handling, field-entry blocking, and expert override policy.
24. Treatment-area mapping, partial-field intervention links, and rules for undocumented or overlapping interventions.
25. Follow-up timing by intervention type and approved local source; no universal product-response interval is assumed.
26. Comparison-eligibility gates, same-station feasibility, stage-transition handling, observed-change formulas, and uncertainty presentation.
27. Language proving that field trends are observational rather than controlled efficacy estimates.
28. GPS accuracy and station-assignment tolerances on supported phones.
29. Time required and usability for a complete 50-plant block, including VE-V2 planting-unit records, differential evidence, natural-enemy observations, treatment history, and any opened-ear subsample.
30. Offline data integrity and later synchronization.
31. Report and certification requirements of the Municipal/City Agriculture Office and PCIC.
32. Translation review for Tagalog, Ilocano, and other supported languages.

### 25.1 Minimum field-validation design recommendation

For validation studies:

- Give plants fixed identifiers so evaluators inspect the same plants.
- Have at least two trained evaluators assess them independently.
- Have a qualified expert adjudicate disagreements.
- Compare human checklist, photo-based AI, and final expert labels.
- Report sensitivity, specificity, precision, recall, confusion matrix, and inter-rater agreement.
- Test across crop stages, varieties, lighting, phone models, locations, and seasons.

---

## 26. Recommended application workflow

```text
Select/create maize field
        ↓
Confirm boundary and field area
        ↓
Split field into assessment blocks (up to 1 ha each)
        ↓
Enter crop, planting, weather, and treatment context
        ↓
Create/link intervention events and capture available label or release evidence
        ↓
Confirm safety/re-entry status
        ↓
Confirm visible growth stage
        ↓
Choose W or ladder according to accessibility and stage
        ↓
Navigate to five representative stations per block
        ↓
At VE-V2, record 10 consecutive planting units per station
        ↓
Inspect 10 consecutive plants per station
        ↓
Record current infestation and eligible DA-BAFS 0-9 leaf severity separately
        ↓
Capture required guided evidence and structured observations
        ↓
Classify FAW evidence, alternative pests, mixed causes, non-pest symptoms, or uncertainty
        ↓
Record natural-enemy quick status and open detailed evidence only when observed or uncertain
        ↓
Save each plant and station offline
        ↓
Calculate stage-specific quantitative indicators
        ↓
For permitted R3-R6 sampling, calculate opened-ear and kernel metrics separately
        ↓
Run completeness and bias checks
        ↓
Show map, counts, percentages, uncertainty, and reference context
        ↓
If this is a compatible follow-up, calculate and label observed change with attribution limits
        ↓
Request expert review when required
        ↓
Generate a report with protocol and validation status
```

---

## 27. Implementation priority

Build the protocol in this order:

1. Field/block and crop metadata.
2. Growth-stage confirmation.
3. Intervention-event history, label evidence, and mandatory field-entry safety gate.
4. W/ladder route and five station records.
5. Ten-plant structured checklist per station.
6. VE-V2 planting-unit, emergence, cutting, and establishment supplement.
7. DA-BAFS 0-9 score selection, visual references, and uncertainty recording.
8. Guided camera and image-quality checks.
9. Maize FAW differential decision tree, mixed-cause records, and expert-escalation rules.
10. Stage-specific formulas and ordinal severity summaries.
11. R3-R6 external-ear and permission-controlled opened-ear/kernel severity workflow.
12. Natural-enemy quick status, conditional evidence form, and field-level biological-control history.
13. Follow-up links, comparison-eligibility gates, event timeline, and observed-change calculations.
14. Incomplete-assessment and data-quality rules.
15. Offline persistence and synchronization.
16. Map and report presentation.
17. AI suggestions with evaluator confirmation.
18. Expert-review and institutional certification workflows.

The structured assessment and reliable offline records must work before AI-generated advice is treated as a core dependency.

---

## 28. Primary references used

1. CIMMYT. *Fall Armyworm in Asia: A Guide for Integrated Pest Management.*
   https://repository.cimmyt.org/bitstreams/7f2802ea-6d21-41da-9bc3-e8473c06b7ed/download

2. FAO. *Fall Armyworm Guidance Note 2: Fall Armyworm Scouting.*
   https://www.fao.org/fileadmin/templates/fcc/Fall_Armyworm/web_FINAL-guidance-note-2.pdf

3. IITA-aligned scouting brief. *Scouting or Sampling for Fall Armyworm in Maize Fields.*
   https://ckan.madiphs.org/dataset/20213b67-fba1-4f51-88db-eab4db1bfc20/resource/ad85cb2f-8466-4c7d-9117-dc1c95d4fbc0/download/scouting-for-faw-in-maize-fields.pdf

4. Mississippi State University Extension. *2025 Insect Control Guide for Agronomic Crops.*
   https://extension.msstate.edu/sites/default/files/publications/P2471_2025_web.pdf

5. Department of Agriculture - Bureau of Agriculture and Fisheries Standards. *DA-BAFS Manual: Minimum Requirements for the Conduct of Efficacy Trial for Organic Bio-Control Agents*, Table 21 and Annex C.
   https://bafs.da.gov.ph/wp-content/uploads/2024/10/Draft-for-ISBN.-OBCA-Manual-2nd-Edition-1-compressed.pdf

6. Department of Agriculture - Bicol Region / Bureau of Plant Industry. *Fall Armyworm Surveillance and Management Protocol.*
   https://bicol.da.gov.ph/wp-content/uploads/2021/04/FAW-SURVEILANCE-AND-MANAGEMENT-PROTOCOL_10272020.pdf

7. Department of Agriculture. *Memorandum Order No. 26, Series of 2021: General Guidelines on the Implementation of the Fall Armyworm Management Project.*
   https://www.da.gov.ph/wp-content/uploads/2021/04/mo26_s2021.pdf

8. Caasi-Lit, M.T. and Marmeto, A.M.D. (2022). *Maize Response to Fall Armyworm and Asian Corn Borer in the Philippines.* SABRAO Journal of Breeding and Genetics 54(5): 1231-1240.
   https://sabraojournal.org/wp-content/uploads/2022/12/SABRAO-J-Breed-Genet-54-5-1231-1240-MS22-81.pdf

9. Toepfer, S. et al. (2021). *Streamlining Leaf Damage Rating Scales for the Fall Armyworm on Maize.* Journal of Pest Science 94: 1075-1089.
   https://link.springer.com/article/10.1007/s10340-021-01359-2

10. Iowa State University Extension. *Stand Assessments - Corn.* Supporting agronomic reference for separating plant-population assessment from diagnosis of its possible causes; not a Philippine FAW standard.
    https://crops.extension.iastate.edu/encyclopedia/stand-assessments-corn

11. CIMMYT. *Fall Armyworm in Africa: A Guide for Integrated Pest Management*, Chapter 4 ear and kernel germplasm rating. Research reference; not a Philippine farmer-field standard.
    https://repository.cimmyt.org/bitstream/10883/19204/1/59133.pdf

12. South African Department of Agriculture. *Fall Armyworm Damage Assessment Procedure*, Annexure C. Supporting non-Philippine reference for limited ear sampling; not adopted as a WormWise severity scale.
    https://www.nda.gov.za/images/outbreaks/Fall%20Army%20Worm/FallArmyworm%20outbreak%20update/FAW%20Damage%20assessment%20form.pdf

13. FAO and CABI. *Community-Based Fall Armyworm Monitoring, Early Warning and Management: Training of Trainers Manual.* Diagnostic FAW features and comparison with related caterpillars; candidate species require Philippine localization.
    https://www.cabi.org/wp-content/uploads/ToT-manual.pdf

14. Fertilizer and Pesticide Authority. *List of Registered Plant-Incorporated Protectants Derived from Modern Biotechnology.* Philippine corn target-pest context.
    https://fpa.da.gov.ph/wp-content/uploads/2024/05/PIP-list-mar2024-1.pdf

15. Marmeto, A.M.D. et al. (2024). *Philippine Traditional Maize with Resistance to Asian Corn Borer Leaf and Stalk Feeding Damage.* Philippine Journal of Science 153(3): 805-826.
    https://philjournalsci.dost.gov.ph/images/pdf/pjs_pdf/vol153_No3_Jun2024/Philippine_traditional_maize_with_resistance_to_Asian_corn_borer_.pdf

16. Department of Agriculture - Cordillera Administrative Region, Regional Crop Protection Center. *Corn Pest and Management: Earworm.*
    https://car.da.gov.ph/wp-content/uploads/2024/02/Corn-Pest_earworm_Ver02_Final-1.pdf

17. Bureau of Soils and Water Management. *Chemical Characteristics and Fertilizer Requirements: Misamis Oriental*, supporting Philippine corn nutrient-symptom context.
    https://www.bswm.da.gov.ph/wp-content/uploads/Misamis-Oriental.pdf

18. University of Minnesota Extension. *Wind and Hail Damage to Pollination Corn.* Supporting abiotic differential reference; not a Philippine management standard.
    https://extension.umn.edu/growing-corn/wind-and-hail-damage-pollination-corn

19. FAO. *Fall Armyworm Guidance Note 2: Fall Armyworm Scouting.* Field observation of predators, parasitoids, and pathogen-associated mortality during FAW scouting.
    https://www.fao.org/fileadmin/templates/fcc/Fall_Armyworm/web_guidance-note-2.pdf

20. Department of Agriculture. *DA allots P150M to help farmers control Fall Armyworm.* Philippine program context for *Trichogramma chilonis*, earwigs, and *Metarhizium* species.
    https://www.da.gov.ph/da-allots-p150m-to-help-farmers-control-fall-armyworm/

21. Department of Agriculture - Cagayan Valley. *Combating Fall Armyworm Using Biological Control.* Regional project context for earwigs, *Trichogramma chilonis*, *Metarhizium*, and *Beauveria*; project-specific practices are not treated as automatic nationwide recommendations.
    https://cagayanvalley.da.gov.ph/2025/05/19/combating-fall-armyworm-using-biological-control-see-the-increase-in-yields-and-income-through-ipm/

22. Valdez, L.A. et al. (2024). *Novel Records of Parasitoids Targeting Fall Armyworm Spodoptera frugiperda in the Philippines.* Journal of Biological Control. Supporting evidence that suspected parasitism may require host rearing and specialist identification.
    https://openurl.ebsco.com/contentitem/doi%3A10.18311%2Fjbc%2F2024%2F36513?id=ebsco%3Adoi%3A10.18311%2Fjbc%2F2024%2F36513&sid=ebsco%3Aplink%3Acrawler

23. DA-BAFS. *PNS/BAFS 20:2018 - Good Agricultural Practices for Corn.* Philippine requirements supporting registered pesticide use, trained/certified application, purchase/application/disposal records, equipment maintenance/calibration, PPE, and withholding/pre-harvest intervals.
    https://ppssd.buplant.da.gov.ph/storage/app/public/LegalReference/PNS_BAFS%2020_2018%20Code%20of%20GAP%20for%20Corn.pdf

24. Fertilizer and Pesticide Authority. *Registered Products.* Current Philippine product-registration source; because entries and statuses change, every lookup must retain its source date/version.
    https://fpa.da.gov.ph/resources/reports/registered-products/

25. Fertilizer and Pesticide Authority. *GAP Trainees in Isabela Learn Responsible Use of Agricultural Pesticides.* Supporting Philippine guidance on label dosage, compatibility, REI, PHI, and PPE.
    https://fpa.da.gov.ph/gap-trainees-in-isabela-learns-responsible-use-of-agricultural-pesticides/

26. Insecticide Resistance Action Committee. *Mode of Action.* Supporting reference for recording mode-of-action context and repeated selection pressure; it is not used by WormWise to prescribe products or rotations automatically.
    https://irac-online.org/mode-of-action/

---

## 29. Current approval record

Decisions incorporated from the project discussion:

- Maize/corn is the only crop in scope.
- W pattern is retained for accessible maize.
- Ladder pattern is retained for tall/dense and reproductive-stage maize.
- Zigzag rapid surveillance is excluded from the formal assessment result.
- Formal sampling uses five stations and ten plants per station per one-hectare assessment block.
- At VE-V2, a separate ten-planting-unit sequence per station records establishment, unexplained gaps, and visible injury while keeping those results separate from the 50-living-plant SFW/IW assessment.
- Empty planting positions are not automatically attributed to FAW, and confirmed FAW presence is reported separately from injury merely consistent with FAW.
- The maize FAW differential assessment names only priority Philippine-relevant look-alikes and uses grouped results when an exact alternative cannot be supported.
- Confirmed FAW, FAW-consistent but unconfirmed damage, mixed causes, other pests, non-pest symptoms, and uncertainty remain separate diagnostic results.
- The app must not confirm FAW from damage or the inverted-Y head mark alone, must allow mixed infestations, and may validly conclude that evidence is insufficient.
- Natural-enemy observation is included as a quick status on the same 50 plants; a detailed evidence form opens only when evidence is observed or uncertain.
- Predator presence, direct predation, possible parasitism, possible pathogen-associated mortality, and expert-confirmed findings remain separate results.
- Intentional biological-control releases/applications are recorded once per field assessment and kept separate from naturally occurring organisms.
- The protocol does not calculate a biological-control effectiveness percentage or use natural-enemy presence alone to decide whether treatment is needed.
- A quick intervention-history and field-entry safety check is required before every formal assessment.
- Each reported spray, release, product, physical action, or cultural action is stored as a field/block intervention event rather than duplicated per plant.
- Unknown product, rate, date, REI, PHI, or application details remain explicitly unknown; the app must not force or generate guesses.
- The app blocks field entry when an REI has not expired or entry safety cannot be confirmed.
- Product-label OCR, evaluator confirmation, registry verification, and expert correction remain separate provenance states.
- A previous and current assessment may be compared only after field, block, protocol, growth-stage indicator, sampling, denominator, and chronology compatibility checks.
- Follow-up results report observed count and percentage-point change, not pesticide or biological-control efficacy.
- Overlapping interventions, weather, crop development, natural enemies, pest movement, and other events are displayed as attribution limitations.
- Routine reassessment is approximately weekly while risk remains, but intervention-specific timing comes from a verified label, approved local protocol, or qualified agriculture officer.
- Eligible vegetative plants receive a separate Philippine-aligned DA-BAFS 0-9 FAW leaf-damage score.
- The 0-9 severity score remains separate from SFW/IW current infestation, %IP, treatment thresholds, and R3-R6 ear damage.
- The internationally proposed Simple 1-5 scale is not used as the primary WormWise severity scale.
- One photograph is not treated as a complete plant assessment.
- Guided multi-view photography is required when AI is expected to assess the whole plant.
- R3-R6 uses all selected ears for non-destructive external assessment and a provisional ten-ear opened subsample only when permission is granted.
- Raw external-ear, active-infestation, opened-ear, damaged-kernel, and ear-rot indicators remain separate and retain their exact denominators.
- The CIMMYT 1-9 ear scale is not automatically generated; it is reserved for possible future expert/research use after Philippine validation.
- R3-R6 damage documentation does not automatically generate a pesticide, yield-loss, marketability, food-safety, or insurance conclusion.
- The project architecture and Chapters 4-5 are not treated as completed.

Items marked provisional remain subject to expert validation.
