import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ChatMessage {
  const _ChatMessage(
    this.text, {
    required this.fromUser,
    this.isError = false,
  });

  final String text;
  final bool fromUser;
  final bool isError;
}

const List<String> _exampleQuestions = [
  'Is mahine kitna profit hua?',
  'Which product sold the most this month?',
  'Kis customer ka udhaar baqi hai?',
  'Kaunsi cheezein khatam hone wali hain?',
];

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;
  int? _remaining;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    if (_sending) return;

    final question = (preset ?? _controller.text).trim();
    if (question.isEmpty) return;

    if (question.length > 500) {
      setState(() {
        _messages.add(
          const _ChatMessage(
            'Keep the question under 500 characters.',
            fromUser: false,
            isError: true,
          ),
        );
      });
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(question, fromUser: true));
      _sending = true;
    });
    _controller.clear();
    _scrollToEnd();

    _ChatMessage reply;
    int? remaining;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'ai-assistant',
        body: {'question': question},
      );
      final data = response.data;
      String? answer;
      if (data is Map) {
        answer = data['answer']?.toString();
        final r = data['remaining'];
        if (r is num) remaining = r.toInt();
      }
      reply = (answer == null || answer.trim().isEmpty)
          ? const _ChatMessage(
              'The assistant gave no answer. Please try again.',
              fromUser: false,
              isError: true,
            )
          : _ChatMessage(answer.trim(), fromUser: false);
    } on FunctionException catch (e) {
      final details = e.details;
      final text = (details is Map && details['error'] != null)
          ? details['error'].toString()
          : 'The assistant could not answer right now. Please try again.';
      reply = _ChatMessage(text, fromUser: false, isError: true);
    } catch (_) {
      reply = const _ChatMessage(
        'Could not reach the assistant. Check your internet and try again.',
        fromUser: false,
        isError: true,
      );
    }

    if (!mounted) return;
    setState(() {
      _messages.add(reply);
      if (remaining != null) _remaining = remaining;
      _sending = false;
    });
    _scrollToEnd();
  }

  Widget _bubble(_ChatMessage message) {
    final colors = Theme.of(context).colorScheme;
    final background = message.isError
        ? colors.errorContainer
        : message.fromUser
            ? colors.primaryContainer
            : colors.surfaceContainerHighest;

    return Align(
      alignment:
          message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(message.text),
        ),
      ),
    );
  }

  Widget _intro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ask a question about your business in English, Urdu or Roman '
          'Urdu. Answers come from your own numbers: sales, profit, stock, '
          'customers and udhaar.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final question in _exampleQuestions)
              ActionChip(
                label: Text(question),
                onPressed: _sending ? null : () => _send(question),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('AI assistant')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                if (_messages.isEmpty) _intro(),
                for (final message in _messages) _bubble(message),
                if (_sending)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Thinking...'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 500,
                    buildCounter: (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) =>
                        null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Type your question',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send question',
                  onPressed: _sending ? null : () => _send(),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _remaining == null
                  ? 'The assistant can only read your data. It cannot change anything.'
                  : 'Questions left today: $_remaining. The assistant can only read your data.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
