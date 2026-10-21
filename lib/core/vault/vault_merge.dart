import 'vault_payload.dart';

/// Report summarizing the result of merging an imported vault.
class MergeReport {
  const MergeReport({
    this.added = 0,
    this.skippedDuplicates = 0,
    this.updated = 0,
    this.invalid = 0,
    this.groupsCreated = 0,
  });

  final int added;
  final int skippedDuplicates;
  final int updated;
  final int invalid;
  final int groupsCreated;
}

/// Pure merge algorithm for importing another vault into the current vault.
class VaultMerge {
  const VaultMerge._();

  static (VaultPayload, MergeReport) merge({
    required VaultPayload current,
    required VaultPayload imported,
  }) {
    throw UnimplementedError('VaultMerge.merge will be implemented in M2');
  }
}
