import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

class ClassInfoScreen extends StatelessWidget {
  final ClassController c;
  final VoidCallback onLeftOrDeleted;
  const ClassInfoScreen({super.key, required this.c, required this.onLeftOrDeleted});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final isCreator = c.cls.creatorId == myId;
        return Scaffold(
          appBar: AppBar(title: const Text('Class details')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
            Text(c.cls.name, style: text.headlineMedium),
            const SizedBox(height: 4),
            Text('${c.teacherIds.length} teacher${c.teacherIds.length == 1 ? '' : 's'}  -  ${c.studentIds.length} of 100 students',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 18),
            if (c.teacherCode != null)
              _CodeCard(
                title: 'Teacher code',
                hint: 'Share with other teachers so they can join and add their subjects.',
                code: c.teacherCode!,
                color: Brand.primary,
              ),
            _CodeCard(
              title: 'Student code',
              hint: c.isTeacher
                  ? 'Share with students. Each student can join only one class.'
                  : 'Keep this handy. It is the code your class uses.',
              code: c.cls.studentCode,
              color: Brand.deadline,
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text('Subjects', style: text.titleLarge)),
              if (c.isTeacher)
                TextButton.icon(
                  onPressed: () => showSheet(context, (_) => _AddSubjectSheet(c: c)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add subject'),
                ),
            ]),
            const SizedBox(height: 6),
            if (c.subjects.isEmpty)
              Panel(
                  child: Text(
                      c.isTeacher
                          ? 'No subjects yet. Add the subject you teach so you can fill the timetable, post updates and upload notes.'
                          : 'No subjects yet.',
                      style: TextStyle(color: cs.onSurfaceVariant)))
            else
              for (final s in c.subjects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    child: Row(children: [
                      Container(width: 6, height: 38, decoration: BoxDecoration(color: colorFromHex(s.colorHex), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${s.code != null ? '${s.code}  -  ' : ''}${c.nameOf(s.teacherId)}',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        ]),
                      ),
                      if (s.teacherId == myId || isCreator)
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
                          onPressed: () async {
                            if (await confirm(context, 'Delete ${s.name}?',
                                'Its timetable slots, announcements, notes and exam papers are deleted too.',
                                yes: 'Delete', danger: true)) {
                              if (context.mounted) await guarded(context, () => c.deleteSubject(s.id));
                            }
                          },
                        ),
                    ]),
                  ),
                ),
            const SizedBox(height: 16),
            Text('Teachers', style: text.titleLarge),
            const SizedBox(height: 8),
            Panel(
              child: Column(children: [
                for (final id in c.teacherIds)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const CircleAvatar(radius: 16, child: Icon(Icons.co_present_outlined, size: 18)),
                    title: Text('${c.nameOf(id)}${id == c.cls.creatorId ? '  (creator)' : ''}${id == myId ? '  (you)' : ''}'),
                    trailing: isCreator && id != myId
                        ? TextButton(
                            onPressed: () async {
                              final ok = await confirm(
                                context,
                                'Transfer class ownership?',
                                '${c.nameOf(id)} will become the creator and receive creator permissions. You will remain a teacher until you leave.',
                                yes: 'Transfer',
                              );
                              if (!ok || !context.mounted) return;
                              try {
                                await c.transferOwnership(id);
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                onLeftOrDeleted();
                              } catch (e) {
                                if (context.mounted) snack(context, friendlyError(e));
                              }
                            },
                            child: const Text('Make creator'),
                          )
                        : null,
                  ),
              ]),
            ),
            if (c.isTeacher) ...[
              const SizedBox(height: 16),
              Text('Students (${c.studentIds.length})', style: text.titleLarge),
              const SizedBox(height: 8),
              Panel(
                child: c.studentIds.isEmpty
                    ? Text('Nobody has joined yet.', style: TextStyle(color: cs.onSurfaceVariant))
                    : Column(children: [
                        for (final id in c.studentIds)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const CircleAvatar(radius: 16, child: Icon(Icons.person_outline, size: 18)),
                            title: Text(c.nameOf(id)),
                            trailing: isCreator
                                ? IconButton(
                                    tooltip: 'Remove student',
                                    icon: const Icon(Icons.person_remove_outlined),
                                    onPressed: () async {
                                      final ok = await confirm(
                                        context,
                                        'Remove this student?',
                                        '${c.nameOf(id)} will immediately lose access to this class. Their account will remain active.',
                                        yes: 'Remove',
                                        danger: true,
                                      );
                                      if (!ok || !context.mounted) return;
                                      await guarded(context, () => c.removeStudent(id),
                                          success: 'Student removed');
                                    },
                                  )
                                : null,
                          ),
                      ]),
              ),
            ],
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: isCreator ? null : () async {
                final ok = await confirm(context, 'Leave this class?',
                    c.isTeacher
                        ? 'You will lose access. Your subjects stay in the class.'
                        : 'You will lose access. You can then join a different class.',
                    yes: 'Leave', danger: true);
                if (!ok || !context.mounted) return;
                final nav = Navigator.of(context);
                try {
                  await c.leaveClass();
                  nav.pop();
                  onLeftOrDeleted();
                } catch (e) {
                  if (context.mounted) snack(context, friendlyError(e));
                }
              },
              icon: const Icon(Icons.logout_rounded),
              label: Text(isCreator
                  ? (c.teacherIds.length > 1
                      ? 'Transfer ownership before leaving'
                      : 'Add another teacher before leaving')
                  : 'Leave class'),
            ),
            if (isCreator && c.cls.deleteAfter == null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                onPressed: () async {
                  final ok = await confirm(context, 'Delete this class?',
                      'The class is deleted for everyone after 30 days. You can undo it any time before then.',
                      yes: 'Schedule deletion', danger: true);
                  if (!ok || !context.mounted) return;
                  final nav = Navigator.of(context);
                  try {
                    await c.scheduleDelete();
                    nav.pop();
                    onLeftOrDeleted();
                  } catch (e) {
                    if (context.mounted) snack(context, friendlyError(e));
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete class'),
              ),
            ],
            if (isCreator && c.cls.deleteAfter != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  try {
                    await c.cancelDelete();
                    nav.pop();
                    onLeftOrDeleted();
                  } catch (e) {
                    if (context.mounted) snack(context, friendlyError(e));
                  }
                },
                icon: const Icon(Icons.undo_rounded),
                label: Text('Cancel deletion (set for ${fmtDate(c.cls.deleteAfter!)})'),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String title, hint, code;
  final Color color;
  const _CodeCard({required this.title, required this.hint, required this.code, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tint(context, color, 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: SelectableText(
                code,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    letterSpacing: 3, fontSize: 30, color: color),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) snack(context, '$title copied');
              },
            ),
          ]),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35)),
        ]),
      ),
    );
  }
}

class _AddSubjectSheet extends StatefulWidget {
  final ClassController c;
  const _AddSubjectSheet({required this.c});
  @override
  State<_AddSubjectSheet> createState() => _AddSubjectSheetState();
}

class _AddSubjectSheetState extends State<_AddSubjectSheet> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  late String _color = Brand.subjectColors[widget.c.subjects.length % Brand.subjectColors.length];
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      snack(context, 'Add the subject name.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.c.addSubject(_name.text.trim(), _code.text, _color);
      nav.pop();
    } catch (e) {
      snack(context, friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add your subject', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Subject name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Subject code (optional)'),
          ),
          const SizedBox(height: 16),
          const Text('Colour', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final h in Brand.subjectColors)
              GestureDetector(
                onTap: () => setState(() => _color = h),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colorFromHex(h),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _color == h ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                  ),
                  child: _color == h ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                ),
              ),
          ]),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Add subject')),
        ]),
      ),
    );
  }
}
