import 'package:flutter/material.dart';
import '../state/view_model.dart';
import 'app_widgets.dart';

Future<void> showValidatedEditor(
  BuildContext context, {
  required ViewModel viewModel,
  required String title,
  required Widget content,
  required bool Function() onSave,
  String saveLabel = 'Save',
}) {
  viewModel.clearError();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: viewModel,
      child: content,
      builder: (context, form) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [form!, ErrorNotice(viewModel.error)],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: viewModel.busy || viewModel.disposed
                ? null
                : () {
                    if (onSave() && dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
            child: Text(saveLabel),
          ),
        ],
      ),
    ),
  );
}
