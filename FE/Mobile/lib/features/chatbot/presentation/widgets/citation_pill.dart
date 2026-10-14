// lib/features/chatbot/presentation/widgets/citation_pill.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/chat_message.dart';
import 'citation_drawer.dart';

/// "[1] NIH ODS · Iron fact sheet" — tap opens the citation drawer.
class CitationPill extends StatelessWidget {
  const CitationPill({super.key, required this.citation});

  final Citation citation;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final label = citation.sourceType == CitationSourceType.userData
        ? citation.title
        : '${_shortPublisher(citation.publisher)} · ${citation.title}';

    return Semantics(
      button: true,
      label: 'Nguồn ${citation.index}: $label',
      excludeSemantics: true,
      child: Material(
        color: context.colors.surface,
        shape: StadiumBorder(side: BorderSide(color: vl.aiBorder)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showCitationDrawer(context, citation),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36, maxWidth: 300),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: vl.aiContainer, shape: BoxShape.circle),
                    child: Text('${citation.index}', style: AppTypography.mono(size: 11, color: vl.onAiContainer)),
                  ),
                  const SizedBox(width: 6),
                  Icon(citationIcon(citation.sourceType), size: 14, color: vl.muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelMedium,
                    ),
                  ),
                  if (citation.verified && citation.sourceType == CitationSourceType.chefDocument) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded, size: 14, color: context.colors.primary),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _shortPublisher(String publisher) {
    const known = {
      'NIH Office of Dietary Supplements': 'NIH ODS',
      'World Health Organization': 'WHO',
      'Harvard T.H. Chan School of Public Health': 'Harvard',
    };
    return known[publisher] ?? publisher.split(' · ').first;
  }
}
