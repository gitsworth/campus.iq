import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../util.dart';
import '../widgets/common.dart';

class JoinCreateScreen extends StatefulWidget {
  final bool hasStudentClass, isFirstRun;
  final ValueChanged<String> onJoined;
  const JoinCreateScreen({
    super.key,
    required this.hasStudentClass,
    required this.isFirstRun,
    required this.onJoined,
  });
  @override
  State<JoinCreateScreen> createState() => _JoinCreateScreenState();
}

class _JoinCreateScreenState extends State<JoinCreateScreen> {
  bool _busy = false;

  Future<void> _run(Future<dynamic> Function() job, String okMsg) async {
    setState(() => _busy = true);
    try {
      final id = await job();
      if (!mounted) return;
      snack(context, okMsg);
      if (!widget.isFirstRun) Navigator.of(context).pop();
      widget.onJoined(id.toString());
    } catch (e) {
      snack(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _create() async {
    final name = await askText(context,
        title: 'Name your class', hint: 'e.g. CSE - Section A', confirmLabel: 'Create');
    if (name == null || name.isEmpty) return;
    await _run(() => db.rpc('create_class', params: {'p_name': name}), 'Class created');
  }

  Future<void> _joinTeacher() async {
    final code = await askText(context,
        title: 'Teacher code',
        hint: 'Starts with T, e.g. TK4P9XM',
        confirmLabel: 'Join',
        caps: TextCapitalization.characters);
    if (code == null || code.isEmpty) return;
    await _run(() => db.rpc('join_as_teacher', params: {'p_code': code}), 'Joined as teacher');
  }

  Future<void> _joinStudent() async {
    final code = await askText(context,
        title: 'Student code',
        hint: 'Starts with S, e.g. S7QH2WD',
        confirmLabel: 'Join',
        caps: TextCapitalization.characters);
    if (code == null || code.isEmpty) return;
    await _run(() => db.rpc('join_as_student', params: {'p_code': code}), 'Joined as student');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isFirstRun,
        actions: [
          if (widget.isFirstRun)
            TextButton.icon(
              onPressed: () => db.auth.signOut(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign out'),
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          Text(widget.isFirstRun ? 'Welcome to CampusIQ' : 'Add a class',
              style: text.headlineMedium),
          const SizedBox(height: 8),
          Text('How do you want to use this class?',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
          const SizedBox(height: 22),
          _Choice(
            icon: Icons.add_circle_outline_rounded,
            color: const Color(0xFF3D4BDB),
            title: 'Create a class',
            subtitle: 'You get a teacher code and a student code to share.',
            onTap: _create,
          ),
          _Choice(
            icon: Icons.co_present_outlined,
            color: const Color(0xFF0E9F8E),
            title: 'Join as a teacher',
            subtitle: 'Use the teacher code from the class creator, then add your subjects.',
            onTap: _joinTeacher,
          ),
          _Choice(
            icon: Icons.backpack_outlined,
            color: const Color(0xFFF08A00),
            title: 'Join as a student',
            subtitle: widget.hasStudentClass
                ? 'You are already in a class. Leave it first to join another.'
                : 'Use the student code from your teacher. You can only be in one class.',
            onTap: widget.hasStudentClass ? null : _joinStudent,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ]),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _Choice({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Panel(
          onTap: onTap,
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tint(context, color, 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.35, fontSize: 13.5)),
              ]),
            ),
            if (!disabled) Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

