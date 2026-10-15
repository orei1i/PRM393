// lib/features/chef_studio/domain/chef_client_rules.dart
import '../../chef/domain/entities/chef.dart';
import '../../commerce/data/models/order_model.dart';
import '../../commerce/domain/commerce_status.dart';

/// "Khách hàng" tabs. Wire values are the `status` the BE computes for
/// `GET /chefs/me/clients?status=` (mirrored by the mock with the same rules).
enum ClientBucket {
  active('Active', 'Đang dùng gói'),
  expiringSoon('ExpiringSoon', 'Sắp hết hạn'),
  ended('Ended', 'Đã kết thúc');

  const ClientBucket(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ClientBucket fromApi(Object? value) {
    final raw = (value?.toString() ?? '').replaceAll('_', '').toLowerCase();
    return values.firstWhere((b) => b.apiValue.toLowerCase() == raw,
        orElse: () => ClientBucket.active);
  }
}

/// A package running out within this many days is "Sắp hết hạn".
const expiringSoonDays = 7;

/// Where one order puts its buyer:
/// - a paid Course / VIP Menu with an active grant: [ClientBucket.active],
///   or [ClientBucket.expiringSoon] in its last [expiringSoonDays] days;
/// - a paid consult still on the calendar (waiting for the chef, confirmed
///   or in progress): [ClientBucket.active];
/// - anything finished, expired, refunded or revoked: [ClientBucket.ended].
ClientBucket packageBucket(OrderDto order, DateTime now) {
  final grant = order.accessGrant;
  if (order.status != OrderStatus.paid ||
      grant == null ||
      grant.statusAt(now) != GrantStatus.active) {
    return ClientBucket.ended;
  }
  if (order.type == ServiceType.consult) {
    final c = order.consultation;
    final upcoming = c != null &&
        (c.status == ConsultationStatus.pending ||
            c.status == ConsultationStatus.confirmed ||
            c.status == ConsultationStatus.inProgress) &&
        c.endAt.isAfter(now);
    return upcoming ? ClientBucket.active : ClientBucket.ended;
  }
  final expiresAt = grant.expiresAt;
  if (expiresAt == null) return ClientBucket.active;
  return expiresAt.difference(now) <= const Duration(days: expiringSoonDays)
      ? ClientBucket.expiringSoon
      : ClientBucket.active;
}

/// A client with any package about to run out is "Sắp hết hạn" (a renewal
/// to follow up), otherwise "Đang dùng gói" while anything is live, else
/// "Đã kết thúc".
ClientBucket clientBucketOf(List<OrderDto> packages, DateTime now) {
  final buckets = packages.map((o) => packageBucket(o, now)).toSet();
  if (buckets.contains(ClientBucket.expiringSoon)) {
    return ClientBucket.expiringSoon;
  }
  if (buckets.contains(ClientBucket.active)) return ClientBucket.active;
  return ClientBucket.ended;
}

/// Whole days left on a package (rounded up), `null` without an end date.
int? daysLeft(OrderDto order, DateTime now) {
  final end = packageEnd(order);
  if (end == null) return null;
  final hours = end.difference(now).inHours;
  if (hours <= 0) return 0;
  return (hours / 24).ceil();
}

/// When access ends: the grant's expiry (24 h after the appointment for a
/// consult).
DateTime? packageEnd(OrderDto order) => order.accessGrant?.expiresAt;

/// The package a client card leads with: one in the client's own bucket
/// (of [type] when filtering), the soonest to end first while live, the
/// latest to have ended otherwise.
OrderDto? primaryPackage(
    List<OrderDto> packages, ClientBucket bucket, DateTime now,
    {ServiceType? type}) {
  final pool = packages
      .where((o) => type == null || o.type == type)
      .where((o) => packageBucket(o, now) == bucket)
      .toList();
  final candidates = pool.isNotEmpty
      ? pool
      : packages.where((o) => type == null || o.type == type).toList();
  if (candidates.isEmpty) return packages.firstOrNull;
  int compare(OrderDto a, OrderDto b) {
    final ea = packageEnd(a) ?? DateTime(9999);
    final eb = packageEnd(b) ?? DateTime(9999);
    return bucket == ClientBucket.ended ? eb.compareTo(ea) : ea.compareTo(eb);
  }

  return (candidates..sort(compare)).first;
}

/// Consults on the calendar for this client, soonest first.
OrderDto? nextConsultation(List<OrderDto> packages, DateTime now) {
  final upcoming = packages
      .where((o) =>
          o.type == ServiceType.consult &&
          packageBucket(o, now) == ClientBucket.active)
      .toList()
    ..sort(
        (a, b) => a.consultation!.startAt.compareTo(b.consultation!.startAt));
  return upcoming.firstOrNull;
}

/// "Đề xuất món" goes to members with a live package.
bool canSuggestTo(List<OrderDto> packages, DateTime now) =>
    packages.any((o) => packageBucket(o, now) != ClientBucket.ended);

/// Live VIP Menu or consult: the members a chef plans meals for, listed
/// first on "Đề xuất món cho khách".
bool hasMenuPackage(List<OrderDto> packages, DateTime now) =>
    packages.any((o) =>
        (o.type == ServiceType.vipMenu || o.type == ServiceType.consult) &&
        packageBucket(o, now) != ClientBucket.ended);
