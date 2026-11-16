import 'package:ai_business_os/app/app_theme.dart';
import 'package:ai_business_os/features/assistant/presentation/assistant_screen.dart';
import 'package:flutter/material.dart';

const List<String> _panelQuestions = [
  'Is mahine kitna profit hua?',
  'Which product sold the most this month?',
  'Kis customer ka udhaar baqi hai?',
  'Kaunsi cheezein khatam hone wali hain?',
];

/// The "Ask your business" card on the Home screen. Typing a question or
/// tapping a suggestion opens the full chat and sends it.
class AssistantPanel extends StatefulWidget {
  const AssistantPanel({super.key});

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openChat([String? question]) {
    final text = (question ?? _controller.text).trim();
    _controller.clear();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssistantScreen(
          initialQuestion: text.isEmpty ? null : text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const purple = Color(0xFF7C3AED);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: purple.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: purple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask your business',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'English, Urdu or Roman Urdu',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _openChat,
                  child: const Text('Full chat'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in _panelQuestions)
                      SizedBox(
                        width: width,
                        child: Material(
                          color: colors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openChat(q),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Text(
                                q,
                                style: TextStyle(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _openChat(),
                    decoration: const InputDecoration(
                      hintText: 'Kuch bhi poochein...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primaryLight, AppColors.primaryDark],
                    ),
                  ),
                  child: IconButton(
                    tooltip: 'Ask',
                    onPressed: _openChat,
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Reads your data only. Cannot change anything.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
