class AiModelLog {
  const AiModelLog({
    required this.id,
    required this.prompt,
    required this.response,
    required this.confidence,
    required this.latencyMs,
    this.overrideText,
    this.reason,
  });
  final String id, prompt, response;
  final double confidence;
  final int latencyMs;
  final String? overrideText, reason;
  bool get overridden => overrideText != null;
  bool get needsReview => confidence < .8 && !overridden;
  AiModelLog override(String text, String reason) => AiModelLog(
    id: id,
    prompt: prompt,
    response: response,
    confidence: confidence,
    latencyMs: latencyMs,
    overrideText: text,
    reason: reason,
  );
}

class ModelPerformanceMetric {
  const ModelPerformanceMetric(this.label, this.value, this.unit);
  final String label, value, unit;
}
