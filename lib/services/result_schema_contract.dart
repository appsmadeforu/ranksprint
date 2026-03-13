/// Canonical analytics/result contract:
/// - `testAttempts/{attemptId}` stores the live attempt state
/// - `results/{attemptId}` stores the finalized result for that attempt
///
/// New writes must always use the same `attemptId` for both documents.
/// Legacy readers may still fall back to timestamp matching for older data.
class ResultSchemaContract {
  const ResultSchemaContract._();

  static const String attemptCollection = 'testAttempts';
  static const String resultCollection = 'results';
}
