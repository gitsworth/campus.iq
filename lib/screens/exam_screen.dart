import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Exam timetable: papers grouped by exam name, sorted by date.
class ExamTimetableScreen extends StatelessWidget {
  final ClassController c;
  const ExamTimetableScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final groups = <String, List<ExamPaper>>{};
        for (final e in c.exams) {
          groups.putIfAbsent(e.examName, () => []).add(e);
        }
        final names = groups.keys.toList()
          ..sort((a, b) => groups[a]!.first.date.compareTo(groups[b]!.first.date));

        return Scaffold(
          appBar: AppBar(title: const Text('Exam timetable')),
          floatingActionButton: c.isTeacher
              ? FloatingActionButton.extended(
                  onPressed: () => showSheet(context, (_) => ExamForm(c: c, date: DateTime.now())),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add paper'),
                )
              : null,
          body: names.isEmpty
              ? const EmptyState(
                  icon: Icons.edit_note_rounded,
                  title: 'No exams scheduled',
                  message: 'Exam papers added by teachers appear here, grouped by exam.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    for (final n in names) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
                        child: Row(children: [
                          Container(width: 5, height: 22, decoration: BoxDecoration(color: Brand.exam, borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 10),
                          Text(n, style: Theme.of(context).textTheme.titleLarge),
                        ]),
                      ),
                      for (final e in (groups[n]!..sort((a, b) => '${a.date}${a.start}'.compareTo('${b.date}${b.start}'))))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Panel(
                            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                            child: Row(children: [
                              SizedBox(
                                width: 56,
                                child: Column(children: [
                                  Text(weekdayShort(parseYmd(e.date).weekday),
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                                  Text('${parseYmd(e.date).day}',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                                  Text(fmtDateShort(parseYmd(e.date)).split(' ').last,
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                ]),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c.subjectById(e.subjectId)?.name ?? 'Subject',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                                  Text('${fmtTime(e.start)} - ${fmtTime(e.end)}${e.room != null ? '   Room ${e.room}' : ''}',
                                      style: TextStyle(color: cs.onSurfaceVariant)),
                                ]),
                              ),
                              if (c.isTeacher)
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
                                  onPressed: () async {
                                    if (await confirm(context, 'Remove exam paper?', 'It will be removed for everyone.',
                                        yes: 'Remove', danger: true)) {
                                      if (context.mounted) await guarded(context, () => c.deleteExam(e));
                                    }
                                  },
                                ),
                            ]),
                          ),
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class ExamForm extends StatefulWidget {
  final ClassController c;
  final DateTime date;
  const ExamForm({super.key, required this.c, required this.date});
  @override
  State<ExamForm> createState() => _ExamFormState();
}

class _ExamFormState extends State<ExamForm> {
  late final _name = TextEditingController(text: _suggestName());
  final _room = TextEditingController();
  late DateTime _date = dateOnly(widget.date);
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 13, minute: 0);
  Subject? _subject;
  bool _busy = false;

  String _suggestName() {
    final existing = widget.c.exams.map((e) => e.examName).toList();
    return existing.isEmpty ? 'Mid-semester exams' : existing.last;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2024), lastDate: DateTime(2030));
    if (d != null) setState(() => _date = dateOnly(d));
  }

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (t != null) setState(() => start ? _start = t : _end = t);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _subject == null) {
      snack(context, 'Add an exam name and pick a subject.');
      return;
    }
    final s = timeOfDayToDb(_start), e = timeOfDayToDb(_end);
    if (minutesOf(e) <= minutesOf(s)) {
      snack(context, 'End time must be after start time.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.c.addExam(
          examName: _name.text.trim(), subject: _subject!, date: _date, start: s, end: e, room: _room.text);
      nav.pop();
    } catch (err) {
      snack(context, friendlyError(err));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New exam paper', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Exam name', helperText: 'Papers with the same name form one exam timetable'),
          ),
          const SizedBox(height: 14),
          if (c.subjects.isEmpty)
            const Text('No subjects exist yet.')
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in c.subjects)
                ChoiceChip(
                  avatar: CircleAvatar(radius: 5, backgroundColor: colorFromHex(s.colorHex)),
                  label: Text(s.name),
                  selected: _subject?.id == s.id,
                  onSelected: (_) => setState(() => _subject = s),
                ),
            ]),
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event_rounded), label: Text(fmtDate(_date))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: () => _pickTime(true), child: Text('Starts ${_start.format(context)}'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton(
                    onPressed: () => _pickTime(false), child: Text('Ends ${_end.format(context)}'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _room, decoration: const InputDecoration(labelText: 'Room / hall (optional)')),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Add exam paper')),
        ]),
      ),
    );
  }
}
