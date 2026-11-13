import 'package:flutter/material.dart';
import '../constants.dart';
import '../logic/chat_context.dart';
import '../logic/class_controller.dart';
import '../theme.dart';
import '../util.dart';

class _Msg {
  final String text;
  final bool user;
  final bool error;
  _Msg(this.text, {required this.user, this.error = false});
}

class AssistantScreen extends StatefulWidget {
  final ClassController c;
  const AssistantScreen({super.key, required this.c});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;

  static const _suggestions = [
    'What class is on now?',
    'What is next?',
    'All deadlines next week',
    'Is next Monday following Saturday\'s timetable?',
    'When are the exams?',
    'Where are the notes?',
  ];

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _msgs.add(_Msg(text, user: true));
      _busy = true;
    });
    _toBottom();

    try {
      // fresh data every question so answers are never stale
      await widget.c.load(silent: true);
      if (widget.c.error != null) {
        throw Exception('I could not refresh this class data. Please try again.');
      }
      final system = chatSystemRules + buildChatContext(widget.c, DateTime.now());
      final history = _msgs
          .where((m) => !m.error)
          .toList()
          .reversed
          .take(8)
          .toList()
          .reversed
          .map((m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text})
          .toList();

      final res = await db.functions.invoke(chatFunctionName, body: {
        'system': system,
        'messages': history,
      });
      final data = res.data;
      final reply = (data is Map ? data['reply'] : null) as String?;
      final err = (data is Map ? data['error'] : null) as String?;
      if (reply == null || reply.trim().isEmpty) {
        throw Exception(err ?? 'No reply from the assistant.');
      }
      setState(() => _msgs.add(_Msg(reply.trim(), user: false)));
    } catch (e) {
      setState(() => _msgs.add(_Msg(
          'The assistant could not answer: ${friendlyError(e)}',
          user: false,
          error: true)));
    }
    if (mounted) setState(() => _busy = false);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: _msgs.isEmpty
            ? ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(26)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.auto_awesome_rounded, color: Brand.marigold, size: 28),
                    const SizedBox(height: 12),
                    Text('Ask about your class',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(
                      'I answer from your timetable, calendar, notes and announcements. If it is not there, I will say so instead of guessing.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.4),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in _suggestions)
                    ActionChip(label: Text(s), onPressed: () => _send(s)),
                ]),
              ])
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: _msgs.length + (_busy ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _msgs.length) return const _Typing();
                  final m = _msgs[i];
                  return Align(
                    alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                      decoration: BoxDecoration(
                        color: m.user
                            ? cs.primary
                            : (m.error
                                ? cs.errorContainer
                                : (Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1C1F3D)
                                    : Colors.white)),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(m.user ? 18 : 4),
                          bottomRight: Radius.circular(m.user ? 4 : 18),
                        ),
                        border: m.user ? null : Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: SelectableText(
                        m.text,
                        style: TextStyle(
                          height: 1.4,
                          color: m.user ? cs.onPrimary : (m.error ? cs.onErrorContainer : cs.onSurface),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      if (_msgs.isNotEmpty)
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final s in _suggestions.take(4))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(label: Text(s), onPressed: _busy ? null : () => _send(s)),
                ),
            ],
          ),
        ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Ask about your class'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _busy ? null : () => _send(),
              icon: const Icon(Icons.arrow_upward_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.primary),
        ),
      ),
    );
  }
}
