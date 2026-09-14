class TrialChatLimit {
  const TrialChatLimit({this.used = 0, this.maximum = 3});
  final int used, maximum;
  int get remaining => (maximum - used).clamp(0, maximum);
  bool get depleted => remaining == 0;
}
