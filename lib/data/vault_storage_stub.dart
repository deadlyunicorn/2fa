import 'vault_storage.dart';

/// Fallback factory for platforms without a specialized [VaultStorage].
VaultStorage createDefaultVaultStorage() =>
    throw UnsupportedError('No VaultStorage implementation for this platform.');
