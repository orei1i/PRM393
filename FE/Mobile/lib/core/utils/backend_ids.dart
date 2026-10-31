// lib/core/utils/backend_ids.dart

final _objectId = RegExp(r'^[0-9a-fA-F]{24}$');
final _planItemId = RegExp(r'^[0-9a-fA-F]{32}$');

/// A real BE document id (a 24-hex ObjectId). In a hybrid build every other id
/// (`l5`, `menu_1`, `ing_bun`…) belongs to a mock store or a local snapshot.
bool isBackendId(String? id) => id != null && _objectId.hasMatch(id);

/// The BE's id of one dish in a meal slot (a 32-hex uuid). It is not a recipe
/// id: a typed dish has only this one.
bool isBackendPlanItemId(String? id) => id != null && _planItemId.hasMatch(id);
