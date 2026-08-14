export 'scouting_workflow_repository.dart';

import 'scouting_workflow_repository.dart';

/// Compatibility facade for the completed Station 1 API.
///
/// New five-station code uses [ScoutingWorkflowRepository]. Existing callers
/// retain their tested constructor and behavior during the Increment A rollout.
class Station1WorkflowRepository extends ScoutingWorkflowRepository {
  Station1WorkflowRepository(super.database);
}
