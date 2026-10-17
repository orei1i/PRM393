// lib/features/chef_studio/domain/wallet_rules.dart
//
// Chef wallet business rules. The BE is the source of truth; the mock and the
// UI copy mirror these values.

/// Platform fee taken from every released booking (same as the web
/// `PLATFORM_FEE_RATE`).
const double kPlatformFeeRate = 0.10;

/// Booking money stays in escrow until the plan's end date 23:59
/// (Asia/Ho_Chi_Minh) + this many days — the complaint window. A complaint
/// freezes it until an admin decides on web `/disputes`.
const int kEscrowHoldDays = 3;

/// Smallest withdrawal (VND).
const int kMinWithdrawal = 100000;

/// Withdrawals above this need an admin's approval; smaller ones are paid out
/// automatically.
const int kAutoApproveLimit = 5000000;

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
