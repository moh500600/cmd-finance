import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v4 primary keys (same ids locally and in Supabase).
String newId() => _uuid.v4();

/// Idempotency keys are generated once per form/operation so a double tap or a
/// retried sync never records the same operation twice.
String newIdempotencyKey() => 'op_${_uuid.v4()}';
