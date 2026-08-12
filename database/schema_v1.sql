PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

CREATE TABLE schema_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO schema_metadata (key, value) VALUES
  ('schema_version', '1'),
  ('protocol_source', 'ASSESSMENT_PROTOCOL.md'),
  ('crop_scope', 'maize');

CREATE TABLE people (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  role_label TEXT,
  organization TEXT,
  phone TEXT,
  email TEXT,
  privacy_consent_status TEXT NOT NULL DEFAULT 'not_recorded'
    CHECK (privacy_consent_status IN ('not_recorded', 'granted', 'declined', 'withdrawn')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE fields (
  id TEXT PRIMARY KEY,
  owner_person_id TEXT REFERENCES people(id),
  name TEXT NOT NULL,
  field_code TEXT,
  barangay TEXT,
  municipality_city TEXT,
  province TEXT,
  location_description TEXT,
  active_boundary_version_id TEXT,
  is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE field_boundary_versions (
  id TEXT PRIMARY KEY,
  field_id TEXT NOT NULL REFERENCES fields(id),
  version_number INTEGER NOT NULL CHECK (version_number > 0),
  geometry_geojson TEXT NOT NULL,
  source_method TEXT NOT NULL
    CHECK (source_method IN ('draw', 'mark_corners', 'walk_boundary', 'imagery_suggestion', 'imported', 'other')),
  area_hectares REAL NOT NULL CHECK (area_hectares > 0),
  centroid_latitude REAL CHECK (centroid_latitude BETWEEN -90 AND 90),
  centroid_longitude REAL CHECK (centroid_longitude BETWEEN -180 AND 180),
  average_accuracy_m REAL CHECK (average_accuracy_m IS NULL OR average_accuracy_m >= 0),
  worst_accuracy_m REAL CHECK (worst_accuracy_m IS NULL OR worst_accuracy_m >= 0),
  confidence_code TEXT CHECK (confidence_code IN ('low', 'medium', 'high', 'unrated')),
  confirmation_status TEXT NOT NULL DEFAULT 'draft'
    CHECK (confirmation_status IN ('draft', 'user_confirmed', 'expert_reviewed', 'superseded', 'rejected')),
  confirmed_by_person_id TEXT REFERENCES people(id),
  confirmed_at TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (field_id, version_number)
);

CREATE TABLE crop_cycles (
  id TEXT PRIMARY KEY,
  field_id TEXT NOT NULL REFERENCES fields(id),
  cycle_label TEXT,
  crop_code TEXT NOT NULL DEFAULT 'maize' CHECK (crop_code = 'maize'),
  variety_name TEXT,
  intended_use TEXT CHECK (intended_use IN ('grain', 'green_corn', 'sweet_corn', 'seed', 'silage', 'other', 'unknown')),
  planting_date TEXT,
  planting_date_precision TEXT NOT NULL DEFAULT 'unknown'
    CHECK (planting_date_precision IN ('exact', 'estimated', 'date_only', 'unknown')),
  planting_arrangement TEXT CHECK (planting_arrangement IN ('single_seed_positions', 'multiple_seedlings_per_hill', 'other', 'uncertain')),
  intended_within_row_spacing_cm REAL CHECK (intended_within_row_spacing_cm IS NULL OR intended_within_row_spacing_cm > 0),
  intended_seedlings_per_position INTEGER CHECK (intended_seedlings_per_position IS NULL OR intended_seedlings_per_position > 0),
  water_regime TEXT CHECK (water_regime IN ('irrigated', 'rainfed', 'mixed', 'unknown')),
  intercropping_description TEXT,
  season_conditions TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('planned', 'active', 'harvested', 'failed', 'archived')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE crop_traits (
  id TEXT PRIMARY KEY,
  crop_cycle_id TEXT NOT NULL REFERENCES crop_cycles(id),
  trait_name TEXT NOT NULL,
  transformation_event TEXT,
  active_protein TEXT,
  target_pest TEXT,
  provenance_state TEXT NOT NULL DEFAULT 'reported'
    CHECK (provenance_state IN ('reported', 'estimated', 'ocr_extracted', 'evaluator_confirmed', 'registry_verified', 'expert_confirmed', 'unknown')),
  registry_reference TEXT,
  registry_checked_at TEXT,
  evidence_note TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE field_blocks (
  id TEXT PRIMARY KEY,
  crop_cycle_id TEXT NOT NULL REFERENCES crop_cycles(id),
  boundary_version_id TEXT NOT NULL REFERENCES field_boundary_versions(id),
  block_number INTEGER NOT NULL CHECK (block_number > 0),
  geometry_geojson TEXT NOT NULL,
  area_hectares REAL NOT NULL CHECK (area_hectares > 0),
  separation_reason TEXT,
  is_provisional INTEGER NOT NULL DEFAULT 1 CHECK (is_provisional IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (crop_cycle_id, block_number)
);

CREATE TABLE product_registry_cache (
  id TEXT PRIMARY KEY,
  authority_code TEXT NOT NULL,
  source_url TEXT NOT NULL,
  source_version_or_date TEXT,
  retrieved_at TEXT NOT NULL,
  product_name TEXT NOT NULL,
  active_ingredient TEXT,
  concentration TEXT,
  formulation TEXT,
  registrant TEXT,
  registration_number TEXT,
  registration_status TEXT NOT NULL DEFAULT 'uncertain'
    CHECK (registration_status IN ('verified_full', 'verified_conditional', 'expired', 'mismatch', 'not_found', 'not_checked', 'uncertain')),
  registration_expiry TEXT,
  approved_crop TEXT,
  approved_target TEXT,
  approved_method TEXT,
  label_rate_text TEXT,
  phi_text TEXT,
  rei_text TEXT,
  mode_of_action_group TEXT,
  raw_record_json TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE interventions (
  id TEXT PRIMARY KEY,
  crop_cycle_id TEXT NOT NULL REFERENCES crop_cycles(id),
  intervention_type TEXT NOT NULL
    CHECK (intervention_type IN ('chemical_insecticide', 'microbial_biocontrol', 'beneficial_release', 'botanical_or_homemade', 'physical', 'cultural', 'other_pesticide', 'fertilizer_or_foliar', 'plant_incorporated_protection', 'other', 'uncertain')),
  stated_purpose TEXT,
  target_pest_or_condition TEXT,
  occurred_start_at TEXT,
  occurred_end_at TEXT,
  time_precision TEXT NOT NULL DEFAULT 'unknown'
    CHECK (time_precision IN ('exact', 'estimated', 'date_only', 'unknown')),
  application_method TEXT,
  equipment_description TEXT,
  equipment_calibrated INTEGER CHECK (equipment_calibrated IS NULL OR equipment_calibrated IN (0, 1)),
  applicator_person_id TEXT REFERENCES people(id),
  adviser_person_id TEXT REFERENCES people(id),
  weather_description TEXT,
  wind_description TEXT,
  rainfall_after_description TEXT,
  ppe_reported TEXT,
  incident_description TEXT,
  disposal_description TEXT,
  reporter_person_id TEXT REFERENCES people(id),
  overall_provenance_state TEXT NOT NULL DEFAULT 'reported'
    CHECK (overall_provenance_state IN ('reported', 'estimated', 'ocr_extracted', 'evaluator_confirmed', 'registry_verified', 'expert_confirmed', 'unknown')),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE intervention_inputs (
  id TEXT PRIMARY KEY,
  intervention_id TEXT NOT NULL REFERENCES interventions(id),
  registry_cache_id TEXT REFERENCES product_registry_cache(id),
  reported_product_name TEXT,
  reported_active_ingredient_or_agent TEXT,
  reported_concentration_formulation TEXT,
  reported_registration_number TEXT,
  reported_registration_expiry TEXT,
  reported_crop TEXT,
  reported_target TEXT,
  amount_used_value REAL CHECK (amount_used_value IS NULL OR amount_used_value >= 0),
  amount_used_unit TEXT,
  water_volume_value REAL CHECK (water_volume_value IS NULL OR water_volume_value >= 0),
  water_volume_unit TEXT,
  reported_rate_text TEXT,
  label_rate_text TEXT,
  release_quantity_text TEXT,
  tanks_or_units_count REAL CHECK (tanks_or_units_count IS NULL OR tanks_or_units_count >= 0),
  phi_text TEXT,
  rei_text TEXT,
  mode_of_action_group TEXT,
  registration_status TEXT NOT NULL DEFAULT 'not_checked'
    CHECK (registration_status IN ('verified_full', 'verified_conditional', 'expired', 'mismatch', 'not_found', 'not_checked', 'uncertain')),
  provenance_state TEXT NOT NULL DEFAULT 'reported'
    CHECK (provenance_state IN ('reported', 'estimated', 'ocr_extracted', 'evaluator_confirmed', 'registry_verified', 'expert_confirmed', 'unknown')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE intervention_areas (
  id TEXT PRIMARY KEY,
  intervention_id TEXT NOT NULL REFERENCES interventions(id),
  field_block_id TEXT REFERENCES field_blocks(id),
  coverage_type TEXT NOT NULL CHECK (coverage_type IN ('whole_field', 'whole_block', 'partial_polygon', 'reported_unknown')),
  geometry_geojson TEXT,
  area_hectares REAL CHECK (area_hectares IS NULL OR area_hectares > 0),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE assessments (
  id TEXT PRIMARY KEY,
  crop_cycle_id TEXT NOT NULL REFERENCES crop_cycles(id),
  boundary_version_id TEXT NOT NULL REFERENCES field_boundary_versions(id),
  evaluator_person_id TEXT NOT NULL REFERENCES people(id),
  assessment_type TEXT NOT NULL DEFAULT 'formal'
    CHECK (assessment_type IN ('formal', 'quick_check', 'expert_validation', 'research')),
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'safety_blocked', 'in_progress', 'completed', 'incomplete', 'invalid', 'cancelled')),
  assessment_mode TEXT NOT NULL
    CHECK (assessment_mode IN ('ve_v6', 'v7_v12', 'vt_r2', 'r3_r6')),
  scouting_pattern TEXT NOT NULL CHECK (scouting_pattern IN ('w', 'ladder', 'none')),
  pattern_reason TEXT,
  growth_stage TEXT NOT NULL
    CHECK (growth_stage IN ('ve', 'v1', 'v2', 'v3', 'v4', 'v5', 'v6', 'v7', 'v8', 'v9', 'v10', 'v11', 'v12', 'vt', 'r1', 'r2', 'r3', 'r4', 'r5', 'r6', 'uncertain')),
  growth_stage_best_estimate TEXT,
  growth_stage_uncertain INTEGER NOT NULL DEFAULT 0 CHECK (growth_stage_uncertain IN (0, 1)),
  preferred_language TEXT NOT NULL DEFAULT 'en',
  protocol_version TEXT NOT NULL,
  formula_version TEXT NOT NULL,
  intervention_history_status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (intervention_history_status IN ('yes', 'no', 'unknown', 'farmer_unsure', 'reported_details_unavailable')),
  safety_summary_status TEXT NOT NULL DEFAULT 'history_unknown'
    CHECK (safety_summary_status IN ('no_recent_treatment', 'safe_interval_completed', 'blocked_rei_active', 'cannot_confirm', 'history_unknown')),
  previous_assessment_id TEXT REFERENCES assessments(id),
  weather_context TEXT,
  recent_heavy_rain_at TEXT,
  started_at TEXT,
  completed_at TEXT,
  local_utc_offset_minutes INTEGER,
  validation_status TEXT NOT NULL DEFAULT 'unreviewed'
    CHECK (validation_status IN ('unreviewed', 'provisional', 'expert_reviewed', 'validated', 'rejected')),
  completion_note TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE safety_checks (
  id TEXT PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  intervention_id TEXT REFERENCES interventions(id),
  checked_by_person_id TEXT NOT NULL REFERENCES people(id),
  checked_at TEXT NOT NULL,
  application_end_at_used TEXT,
  rei_text_used TEXT,
  rei_source TEXT,
  phi_text_used TEXT,
  phi_source TEXT,
  result_status TEXT NOT NULL
    CHECK (result_status IN ('no_recent_treatment', 'safe_interval_completed', 'blocked_rei_active', 'cannot_confirm', 'history_unknown')),
  calculated_safe_entry_at TEXT,
  calculation_inputs_verified INTEGER NOT NULL DEFAULT 0 CHECK (calculation_inputs_verified IN (0, 1)),
  warning_acknowledged INTEGER NOT NULL DEFAULT 0 CHECK (warning_acknowledged IN (0, 1)),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE assessment_block_runs (
  id TEXT PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  field_block_id TEXT NOT NULL REFERENCES field_blocks(id),
  block_sequence INTEGER NOT NULL CHECK (block_sequence > 0),
  scouting_pattern TEXT NOT NULL CHECK (scouting_pattern IN ('w', 'ladder', 'none')),
  pattern_reason TEXT,
  route_geojson TEXT,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'in_progress', 'completed', 'incomplete', 'invalid', 'cancelled')),
  edge_bias_warning INTEGER NOT NULL DEFAULT 0 CHECK (edge_bias_warning IN (0, 1)),
  accessibility_notes TEXT,
  started_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (assessment_id, field_block_id),
  UNIQUE (assessment_id, block_sequence)
);

CREATE TABLE stations (
  id TEXT PRIMARY KEY,
  assessment_block_run_id TEXT NOT NULL REFERENCES assessment_block_runs(id),
  station_number INTEGER NOT NULL CHECK (station_number BETWEEN 1 AND 5),
  latitude REAL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL CHECK (longitude BETWEEN -180 AND 180),
  gps_accuracy_m REAL CHECK (gps_accuracy_m IS NULL OR gps_accuracy_m >= 0),
  captured_at TEXT,
  not_located_reason TEXT,
  accessibility_notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (assessment_block_run_id, station_number)
);

CREATE TABLE planting_unit_observations (
  id TEXT PRIMARY KEY,
  station_id TEXT NOT NULL REFERENCES stations(id),
  sequence_number INTEGER NOT NULL CHECK (sequence_number BETWEEN 1 AND 10),
  assessable INTEGER NOT NULL DEFAULT 1 CHECK (assessable IN (0, 1)),
  not_assessable_reason TEXT,
  occupancy_status TEXT
    CHECK (occupancy_status IN ('occupied', 'empty', 'delayed_or_failed_emergence', 'missing_after_emergence', 'uncertain')),
  observed_seedling_count INTEGER CHECK (observed_seedling_count IS NULL OR observed_seedling_count >= 0),
  intended_seedling_count INTEGER CHECK (intended_seedling_count IS NULL OR intended_seedling_count > 0),
  visible_cutting INTEGER CHECK (visible_cutting IS NULL OR visible_cutting IN (0, 1)),
  visible_seedling_injury INTEGER CHECK (visible_seedling_injury IS NULL OR visible_seedling_injury IN (0, 1)),
  confirmed_faw_present INTEGER CHECK (confirmed_faw_present IS NULL OR confirmed_faw_present IN (0, 1)),
  injury_consistent_with_faw INTEGER CHECK (injury_consistent_with_faw IS NULL OR injury_consistent_with_faw IN (0, 1)),
  alternative_cause_code TEXT,
  notes TEXT,
  captured_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (station_id, sequence_number)
);

CREATE TABLE plant_observations (
  id TEXT PRIMARY KEY,
  station_id TEXT NOT NULL REFERENCES stations(id),
  sequence_number INTEGER NOT NULL CHECK (sequence_number BETWEEN 1 AND 10),
  persistent_plant_identifier TEXT,
  assessable INTEGER NOT NULL DEFAULT 1 CHECK (assessable IN (0, 1)),
  not_assessable_reason TEXT,
  plant_status TEXT NOT NULL
    CHECK (plant_status IN ('negative', 'current_positive', 'old_damage_only', 'possible_non_faw', 'uncertain', 'not_assessable')),
  current_faw_evidence INTEGER CHECK (current_faw_evidence IS NULL OR current_faw_evidence IN (0, 1)),
  possible_non_faw_evidence INTEGER CHECK (possible_non_faw_evidence IS NULL OR possible_non_faw_evidence IN (0, 1)),
  uncertain_evidence INTEGER CHECK (uncertain_evidence IS NULL OR uncertain_evidence IN (0, 1)),
  old_damage_present INTEGER NOT NULL DEFAULT 0 CHECK (old_damage_present IN (0, 1)),
  natural_enemy_quick_status TEXT NOT NULL
    CHECK (natural_enemy_quick_status IN ('none_seen', 'observed', 'uncertain', 'not_assessable', 'not_collected')),
  whole_plant_context_note TEXT,
  latitude REAL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL CHECK (longitude BETWEEN -180 AND 180),
  gps_accuracy_m REAL CHECK (gps_accuracy_m IS NULL OR gps_accuracy_m >= 0),
  captured_at TEXT,
  evaluator_notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (station_id, sequence_number),
  CHECK ((assessable = 0 AND plant_status = 'not_assessable') OR assessable = 1)
);

CREATE TABLE vegetative_observations (
  plant_observation_id TEXT PRIMARY KEY REFERENCES plant_observations(id),
  newest_leaves_inspected_count INTEGER CHECK (newest_leaves_inspected_count IS NULL OR newest_leaves_inspected_count BETWEEN 0 AND 4),
  small_fresh_windowpanes INTEGER NOT NULL DEFAULT 0 CHECK (small_fresh_windowpanes IN (0, 1)),
  infested_whorl INTEGER NOT NULL DEFAULT 0 CHECK (infested_whorl IN (0, 1)),
  scraping INTEGER NOT NULL DEFAULT 0 CHECK (scraping IN (0, 1)),
  cutting_or_tearing INTEGER NOT NULL DEFAULT 0 CHECK (cutting_or_tearing IN (0, 1)),
  fresh_frass INTEGER NOT NULL DEFAULT 0 CHECK (fresh_frass IN (0, 1)),
  whorl_feeding_sign INTEGER NOT NULL DEFAULT 0 CHECK (whorl_feeding_sign IN (0, 1)),
  larva_visible INTEGER NOT NULL DEFAULT 0 CHECK (larva_visible IN (0, 1)),
  larval_size TEXT NOT NULL DEFAULT 'none_seen'
    CHECK (larval_size IN ('none_seen', 'small', 'medium', 'large', 'uncertain')),
  egg_mass_visible INTEGER CHECK (egg_mass_visible IS NULL OR egg_mass_visible IN (0, 1)),
  larva_count INTEGER CHECK (larva_count IS NULL OR larva_count >= 0),
  da_bafs_leaf_damage_score INTEGER CHECK (da_bafs_leaf_damage_score IS NULL OR da_bafs_leaf_damage_score BETWEEN 0 AND 9),
  damage_score_uncertain INTEGER NOT NULL DEFAULT 0 CHECK (damage_score_uncertain IN (0, 1)),
  damage_score_reason TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE reproductive_observations (
  plant_observation_id TEXT PRIMARY KEY REFERENCES plant_observations(id),
  tassel_examined INTEGER NOT NULL DEFAULT 0 CHECK (tassel_examined IN (0, 1)),
  ear_base_examined INTEGER NOT NULL DEFAULT 0 CHECK (ear_base_examined IN (0, 1)),
  upper_axil_examined INTEGER NOT NULL DEFAULT 0 CHECK (upper_axil_examined IN (0, 1)),
  lower_axil_examined INTEGER NOT NULL DEFAULT 0 CHECK (lower_axil_examined IN (0, 1)),
  fresh_feeding_present INTEGER NOT NULL DEFAULT 0 CHECK (fresh_feeding_present IN (0, 1)),
  larva_present INTEGER NOT NULL DEFAULT 0 CHECK (larva_present IN (0, 1)),
  larva_count INTEGER CHECK (larva_count IS NULL OR larva_count >= 0),
  percent_infested_positive INTEGER NOT NULL DEFAULT 0 CHECK (percent_infested_positive IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE ear_observations (
  id TEXT PRIMARY KEY,
  plant_observation_id TEXT NOT NULL REFERENCES plant_observations(id),
  ear_sequence INTEGER NOT NULL DEFAULT 1 CHECK (ear_sequence > 0),
  externally_assessable INTEGER NOT NULL DEFAULT 1 CHECK (externally_assessable IN (0, 1)),
  external_damage_present INTEGER CHECK (external_damage_present IS NULL OR external_damage_present IN (0, 1)),
  active_infestation_present INTEGER CHECK (active_infestation_present IS NULL OR active_infestation_present IN (0, 1)),
  silk_damage_present INTEGER CHECK (silk_damage_present IS NULL OR silk_damage_present IN (0, 1)),
  husk_damage_present INTEGER CHECK (husk_damage_present IS NULL OR husk_damage_present IN (0, 1)),
  entry_hole_present INTEGER CHECK (entry_hole_present IS NULL OR entry_hole_present IN (0, 1)),
  frass_present INTEGER CHECK (frass_present IS NULL OR frass_present IN (0, 1)),
  larva_present INTEGER CHECK (larva_present IS NULL OR larva_present IN (0, 1)),
  opening_permission TEXT NOT NULL DEFAULT 'not_requested'
    CHECK (opening_permission IN ('not_requested', 'granted', 'denied', 'not_applicable')),
  opened INTEGER NOT NULL DEFAULT 0 CHECK (opened IN (0, 1)),
  internal_damage_present INTEGER CHECK (internal_damage_present IS NULL OR internal_damage_present IN (0, 1)),
  total_kernels_counted INTEGER CHECK (total_kernels_counted IS NULL OR total_kernels_counted >= 0),
  damaged_kernels_counted INTEGER CHECK (damaged_kernels_counted IS NULL OR damaged_kernels_counted >= 0),
  kernel_count_method TEXT,
  ear_rot_present INTEGER CHECK (ear_rot_present IS NULL OR ear_rot_present IN (0, 1)),
  ear_rot_suspected_type TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (plant_observation_id, ear_sequence),
  CHECK (damaged_kernels_counted IS NULL OR total_kernels_counted IS NULL OR damaged_kernels_counted <= total_kernels_counted),
  CHECK (opened = 0 OR opening_permission = 'granted')
);

CREATE TABLE diagnostic_findings (
  id TEXT PRIMARY KEY,
  plant_observation_id TEXT NOT NULL REFERENCES plant_observations(id),
  is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
  category TEXT NOT NULL
    CHECK (category IN ('confirmed_faw', 'faw_consistent_unconfirmed', 'other_pest', 'non_pest', 'mixed', 'uncertain')),
  candidate_code TEXT,
  candidate_display_group TEXT,
  evidence_strength TEXT NOT NULL DEFAULT 'uncertain'
    CHECK (evidence_strength IN ('weak', 'moderate', 'strong', 'confirmed', 'uncertain')),
  evidence_summary TEXT,
  evaluator_decision TEXT,
  expert_decision TEXT,
  expert_review_required INTEGER NOT NULL DEFAULT 0 CHECK (expert_review_required IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE natural_enemy_observations (
  id TEXT PRIMARY KEY,
  plant_observation_id TEXT NOT NULL REFERENCES plant_observations(id),
  intervention_id TEXT REFERENCES interventions(id),
  observation_type TEXT NOT NULL
    CHECK (observation_type IN ('predator_present', 'direct_predation', 'egg_parasitism', 'larval_parasitism', 'pathogen_mortality', 'uncertain')),
  organism_group TEXT NOT NULL
    CHECK (organism_group IN ('earwig', 'ant', 'spider', 'lacewing', 'predatory_beetle', 'predatory_bug', 'bird', 'parasitoid', 'fungus_like', 'virus_like', 'other', 'uncertain')),
  origin TEXT NOT NULL DEFAULT 'naturally_observed'
    CHECK (origin IN ('naturally_observed', 'intentional_release', 'intentional_application', 'uncertain')),
  prey_faw_status TEXT CHECK (prey_faw_status IN ('confirmed_faw', 'suspected_caterpillar', 'not_observed', 'uncertain')),
  evidence_strength TEXT NOT NULL DEFAULT 'uncertain'
    CHECK (evidence_strength IN ('weak', 'moderate', 'strong', 'confirmed', 'uncertain')),
  count_observed INTEGER CHECK (count_observed IS NULL OR count_observed >= 0),
  expert_confirmation TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE evidence_media (
  id TEXT PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  station_id TEXT REFERENCES stations(id),
  planting_unit_observation_id TEXT REFERENCES planting_unit_observations(id),
  plant_observation_id TEXT REFERENCES plant_observations(id),
  ear_observation_id TEXT REFERENCES ear_observations(id),
  diagnostic_finding_id TEXT REFERENCES diagnostic_findings(id),
  natural_enemy_observation_id TEXT REFERENCES natural_enemy_observations(id),
  intervention_id TEXT REFERENCES interventions(id),
  safety_check_id TEXT REFERENCES safety_checks(id),
  derived_from_media_id TEXT REFERENCES evidence_media(id),
  media_type TEXT NOT NULL CHECK (media_type IN ('photo', 'video', 'audio', 'document')),
  view_type TEXT,
  local_uri TEXT NOT NULL,
  remote_uri TEXT,
  thumbnail_local_uri TEXT,
  mime_type TEXT,
  byte_size INTEGER CHECK (byte_size IS NULL OR byte_size >= 0),
  sha256_checksum TEXT NOT NULL,
  captured_at TEXT,
  latitude REAL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL CHECK (longitude BETWEEN -180 AND 180),
  gps_accuracy_m REAL CHECK (gps_accuracy_m IS NULL OR gps_accuracy_m >= 0),
  quality_status TEXT NOT NULL DEFAULT 'unchecked'
    CHECK (quality_status IN ('unchecked', 'acceptable', 'blurred', 'too_dark', 'too_bright', 'target_missing', 'rejected')),
  upload_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (upload_state IN ('local_only', 'queued', 'uploading', 'uploaded', 'error')),
  is_original INTEGER NOT NULL DEFAULT 1 CHECK (is_original IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE ai_inferences (
  id TEXT PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  task_type TEXT NOT NULL,
  model_name TEXT NOT NULL,
  model_version TEXT NOT NULL,
  inference_mode TEXT NOT NULL CHECK (inference_mode IN ('on_device', 'online', 'queued_online')),
  suggestion_code TEXT,
  suggestion_json TEXT,
  confidence_value REAL CHECK (confidence_value IS NULL OR confidence_value BETWEEN 0 AND 1),
  evidence_explanation TEXT,
  missing_evidence_request TEXT,
  evaluator_resolution TEXT CHECK (evaluator_resolution IN ('pending', 'accepted', 'rejected', 'modified', 'not_applicable')),
  evaluator_final_value TEXT,
  inferred_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE metric_results (
  id TEXT PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  scope_type TEXT NOT NULL CHECK (scope_type IN ('station', 'block', 'assessment', 'field')),
  scope_id TEXT,
  metric_code TEXT NOT NULL,
  numerator REAL,
  denominator REAL CHECK (denominator IS NULL OR denominator >= 0),
  value REAL,
  unit TEXT NOT NULL,
  distribution_json TEXT,
  formula_version TEXT NOT NULL,
  validation_status TEXT NOT NULL DEFAULT 'provisional'
    CHECK (validation_status IN ('unreviewed', 'provisional', 'expert_reviewed', 'validated', 'rejected')),
  warning_code TEXT,
  calculated_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE assessment_comparisons (
  id TEXT PRIMARY KEY,
  crop_cycle_id TEXT NOT NULL REFERENCES crop_cycles(id),
  baseline_assessment_id TEXT NOT NULL REFERENCES assessments(id),
  followup_assessment_id TEXT NOT NULL REFERENCES assessments(id),
  purpose TEXT NOT NULL
    CHECK (purpose IN ('routine_monitoring', 'post_intervention', 'event_triggered', 'agriculture_office', 'research', 'other')),
  linked_intervention_id TEXT REFERENCES interventions(id),
  eligibility_status TEXT NOT NULL
    CHECK (eligibility_status IN ('eligible', 'not_eligible', 'pending_review')),
  compatibility_json TEXT,
  incompatibility_reasons TEXT,
  elapsed_hours REAL CHECK (elapsed_hours IS NULL OR elapsed_hours >= 0),
  attribution_limitation TEXT,
  calculation_version TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  CHECK (baseline_assessment_id <> followup_assessment_id),
  UNIQUE (baseline_assessment_id, followup_assessment_id, purpose)
);

CREATE TABLE comparison_metrics (
  id TEXT PRIMARY KEY,
  comparison_id TEXT NOT NULL REFERENCES assessment_comparisons(id),
  metric_code TEXT NOT NULL,
  baseline_numerator REAL,
  baseline_denominator REAL CHECK (baseline_denominator IS NULL OR baseline_denominator >= 0),
  baseline_value REAL,
  followup_numerator REAL,
  followup_denominator REAL CHECK (followup_denominator IS NULL OR followup_denominator >= 0),
  followup_value REAL,
  observed_count_change REAL,
  percentage_point_change REAL,
  relative_observed_change_percent REAL,
  unit TEXT NOT NULL,
  compatibility_status TEXT NOT NULL CHECK (compatibility_status IN ('compatible', 'not_compatible', 'uncertain')),
  warning_code TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (comparison_id, metric_code)
);

CREATE TABLE comparison_events (
  id TEXT PRIMARY KEY,
  comparison_id TEXT NOT NULL REFERENCES assessment_comparisons(id),
  intervention_id TEXT REFERENCES interventions(id),
  event_type TEXT NOT NULL
    CHECK (event_type IN ('intervention', 'heavy_rain', 'irrigation', 'growth_stage_change', 'assessment_interruption', 'nearby_outbreak', 'other')),
  occurred_at TEXT,
  time_precision TEXT NOT NULL DEFAULT 'unknown'
    CHECK (time_precision IN ('exact', 'estimated', 'date_only', 'unknown')),
  description TEXT,
  provenance_state TEXT NOT NULL DEFAULT 'reported'
    CHECK (provenance_state IN ('reported', 'estimated', 'ocr_extracted', 'evaluator_confirmed', 'registry_verified', 'expert_confirmed', 'unknown')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  comparison_id TEXT REFERENCES assessment_comparisons(id),
  report_type TEXT NOT NULL CHECK (report_type IN ('assessment', 'followup', 'field_history', 'expert_review', 'institutional')),
  report_version INTEGER NOT NULL CHECK (report_version > 0),
  protocol_version TEXT NOT NULL,
  formula_version TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'generated', 'reviewed', 'superseded', 'void')),
  local_uri TEXT,
  remote_uri TEXT,
  sha256_checksum TEXT,
  validation_status TEXT NOT NULL DEFAULT 'unreviewed'
    CHECK (validation_status IN ('unreviewed', 'provisional', 'expert_reviewed', 'validated', 'rejected')),
  institutional_certification_status TEXT NOT NULL DEFAULT 'not_requested'
    CHECK (institutional_certification_status IN ('not_requested', 'pending', 'approved', 'rejected', 'not_applicable')),
  generated_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0,
  UNIQUE (assessment_id, report_type, report_version)
);

CREATE TABLE expert_reviews (
  id TEXT PRIMARY KEY,
  assessment_id TEXT REFERENCES assessments(id),
  reviewer_person_id TEXT NOT NULL REFERENCES people(id),
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_review', 'completed', 'rejected', 'cancelled')),
  decision_code TEXT,
  correction_json TEXT,
  evidence_summary TEXT,
  reviewed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  device_id TEXT,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE audit_log (
  id TEXT PRIMARY KEY,
  actor_person_id TEXT REFERENCES people(id),
  device_id TEXT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('create', 'update', 'soft_delete', 'restore', 'resolve_conflict', 'validate', 'generate')),
  before_json TEXT,
  after_json TEXT,
  reason TEXT,
  occurred_at TEXT NOT NULL,
  sync_state TEXT NOT NULL DEFAULT 'local_only'
    CHECK (sync_state IN ('local_only', 'queued', 'syncing', 'synced', 'conflict', 'error')),
  server_version INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE sync_outbox (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete', 'upload_media')),
  payload_json TEXT,
  dependency_ids_json TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at TEXT,
  last_error TEXT,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'error', 'blocked')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE UNIQUE INDEX idx_boundary_field_version
  ON field_boundary_versions(field_id, version_number);
CREATE INDEX idx_crop_cycles_field_status
  ON crop_cycles(field_id, status);
CREATE INDEX idx_field_blocks_cycle
  ON field_blocks(crop_cycle_id, block_number);
CREATE INDEX idx_registry_product_name
  ON product_registry_cache(product_name, registration_status);
CREATE INDEX idx_interventions_cycle_time
  ON interventions(crop_cycle_id, occurred_start_at);
CREATE INDEX idx_intervention_inputs_intervention
  ON intervention_inputs(intervention_id);
CREATE INDEX idx_assessments_cycle_time
  ON assessments(crop_cycle_id, started_at);
CREATE INDEX idx_assessments_sync
  ON assessments(sync_state, updated_at);
CREATE INDEX idx_safety_checks_assessment
  ON safety_checks(assessment_id, checked_at);
CREATE INDEX idx_block_runs_assessment
  ON assessment_block_runs(assessment_id, block_sequence);
CREATE INDEX idx_stations_block_run
  ON stations(assessment_block_run_id, station_number);
CREATE INDEX idx_planting_units_station
  ON planting_unit_observations(station_id, sequence_number);
CREATE INDEX idx_plants_station
  ON plant_observations(station_id, sequence_number);
CREATE INDEX idx_diagnostics_plant
  ON diagnostic_findings(plant_observation_id, is_primary);
CREATE INDEX idx_natural_enemies_plant
  ON natural_enemy_observations(plant_observation_id, observation_type);
CREATE INDEX idx_media_assessment_upload
  ON evidence_media(assessment_id, upload_state);
CREATE INDEX idx_ai_target
  ON ai_inferences(target_type, target_id, inferred_at);
CREATE UNIQUE INDEX idx_metric_unique_scope
  ON metric_results(assessment_id, scope_type, IFNULL(scope_id, ''), metric_code, formula_version);
CREATE INDEX idx_comparison_baseline
  ON assessment_comparisons(baseline_assessment_id);
CREATE INDEX idx_comparison_followup
  ON assessment_comparisons(followup_assessment_id);
CREATE INDEX idx_reports_assessment
  ON reports(assessment_id, report_type, report_version);
CREATE INDEX idx_expert_reviews_target
  ON expert_reviews(target_type, target_id, status);
CREATE INDEX idx_audit_target
  ON audit_log(entity_type, entity_id, occurred_at);
CREATE INDEX idx_outbox_status
  ON sync_outbox(status, next_attempt_at, created_at);

COMMIT;
