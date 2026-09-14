class AdminMetric {
  const AdminMetric(this.label, this.value, this.context);
  final String label, value, context;
}

class SystemLog {
  const SystemLog(this.title, this.detail, {this.warning = false});
  final String title, detail;
  final bool warning;
}

class AiMetric {
  const AiMetric(this.label, this.value);
  final String label, value;
}

class ActivitySample {
  const ActivitySample(this.day, this.contributions);
  final String day;
  final int contributions;
}
