// lib/features/chef_studio/domain/wallet_rules.dart
//
// Wallet business rules (chef and member). The BE is the source of truth; the
// mock and the UI copy mirror these values.

/// Platform fee taken from every released booking (same as the web
/// `PLATFORM_FEE_RATE`).
const double kPlatformFeeRate = 0.10;

/// Booking money stays in escrow from payment until this many days after the
/// contract is completed (the chef confirms, or the plan's last day is over
/// with every day delivered). A complaint freezes it until an admin decides on
/// web `/disputes`.
const int kEscrowHoldDays = 7;

/// Smallest withdrawal (VND).
const int kMinWithdrawal = 100000;

/// Fee on [gross], rounded to whole đồng.
int platformFee(int gross) => (gross * kPlatformFeeRate).round();

/// Banks offered in the bank-account form.
const vietnamBanks = [
  'Vietcombank',
  'VietinBank',
  'BIDV',
  'Agribank',
  'Techcombank',
  'MB Bank',
  'ACB',
  'VPBank',
  'TPBank',
  'Sacombank',
];
