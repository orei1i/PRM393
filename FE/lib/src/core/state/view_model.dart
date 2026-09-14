import 'package:flutter/foundation.dart';

enum LoadStatus { ready, loading, error }

abstract class ViewModel extends ChangeNotifier {
  bool _disposed = false;
  String? _error;
  LoadStatus _status = LoadStatus.ready;

  bool get disposed => _disposed;
  String? get error => _error;
  LoadStatus get status => _status;
  bool get busy => _status == LoadStatus.loading;

  void clearError() {
    _error = null;
    _status = LoadStatus.ready;
    emit();
  }

  void fail(String message) {
    _error = message;
    _status = LoadStatus.error;
    emit();
  }

  void setBusy(bool value) {
    _status = value ? LoadStatus.loading : LoadStatus.ready;
    if (value) _error = null;
    emit();
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
