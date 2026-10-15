// lib/features/chef_studio/domain/wallet_rules.dart
//
// Chef wallet business rules. The BE is the source of truth; the mock and the
// UI copy mirror these values.

/// Platform fee taken from every sale. Business placeholder: the real rate
/// (and whether it varies per service type) is not decided yet.
const double kPlatformFeeRate = 0.10;

/// Course / VIP Menu money is held this long after payment (refund window)
/// before it can be withdrawn. Consults are released when completed.
const int kPackageHoldDays = 7;

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
