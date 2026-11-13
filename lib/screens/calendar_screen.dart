import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'exam_screen.dart';

class CalendarScreen extends StatefulWidget {
  final ClassController c;
  const CalendarScreen({super.key, required this.c});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = dateOnly(DateTime.now());

  ClassController get c => widget.c;

  List<Object> _itemsOn(DateTime d) {
    final ds = ymd(d);
    return [
      ...c.events.where((e) => e.date == ds),
      ...c.exams.where((e) => e.date == ds),
    ];
  }

  Color _colorOf(Object o) {
    if (o is CalEvent) return o.type == 'holiday' ? Brand.holiday : Brand.deadline;
    return Brand.exam;
  }

  void _add() {
    showSheet(context, (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add to ${fmtDate(_selected)}', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          _AddOption(
            icon: Icons.beach_access_rounded,
            color: Brand.holiday,
            title: 'Holiday',
            subtitle: 'No classes on this day',
            onTap: () {
              Navigator.pop(ctx);
              showSheet(context, (_) => _EventForm(c: c, date: _selected, type: 'holiday'));
            },
          ),
          _AddOption(
            icon: Icons.flag_rounded,
            color: Brand.deadline,
            title: 'Deadline',
            subtitle: 'Assignment, submission or lab record',
            onTap: () {
              Navigator.pop(ctx);
              showSheet(context, (_) => _EventForm(c: c, date: _selected, type: 'deadline'));
            },
          ),
          _AddOption(
            icon: Icons.edit_note_rounded,
            color: Brand.exam,
            title: 'Exam paper',
            subtitle: 'Adds to that week\'s exam timetable',
            onTap: () {
              Navigator.pop(ctx);
              showSheet(context, (_) => ExamForm(c: c, date: _selected));
            },
          ),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _itemsOn(_selected);
    final today = dateOnly(DateTime.now());
    final upcoming = <Object>[
      ...c.events.where((e) => parseYmd(e.date).isAfter(_selected)),
      ...c.exams.where((e) => parseYmd(e.date).isAfter(_selected)),
    ]..sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: c.isTeacher
          ? FloatingActionButton.extended(
              onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Add'))
          : null,
      body: RefreshIndicator(
        onRefresh: () => c.load(silent: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Panel(
              padding: const EdgeInsets.only(bottom: 8),
              child: TableCalendar<Object>(
                firstDay: DateTime(2024),
                lastDay: DateTime(2030, 12, 31),
                focusedDay: _focused,
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                startingDayOfWeek: StartingDayOfWeek.monday,
                eventLoader: _itemsOn,
                onDaySelected: (s, f) => setState(() {
                  _selected = dateOnly(s);
                  _focused = f;
                }),
                onPageChanged: (f) => _focused = f,
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: Theme.of(context).textTheme.titleMedium!,
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  todayDecoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.16), shape: BoxShape.circle),
                  todayTextStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
                  selectedDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                ),
                calendarBuilders: CalendarBuilders<Object>(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    return Positioned(
                      bottom: 4,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final e in events.take(3))
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1.2),
                            decoration: BoxDecoration(color: _colorOf(e), shape: BoxShape.circle),
                          ),
                      ]),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 6, children: const [
              _Legend(Brand.holiday, 'Holiday'),
              _Legend(Brand.deadline, 'Deadline'),
              _Legend(Brand.exam, 'Exam'),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text(
                  _selected == today ? 'Today' : fmtDate(_selected),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ExamTimetableScreen(c: c))),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Exam timetable'),
              ),
            ]),
            const SizedBox(height: 4),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text('Nothing scheduled.', style: TextStyle(color: cs.onSurfaceVariant)),
              )
            else
              for (final o in items) _ItemTile(c: c, item: o),
            if (upcoming.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Coming up', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final o in upcoming.take(6)) _ItemTile(c: c, item: o, showDate: true),
            ],
          ],
        ),
      ),
    );
  }

  DateTime _dateOf(Object o) => parseYmd(o is CalEvent ? o.date : (o as ExamPaper).date);
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]);
}

class _AddOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _AddOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
            backgroundColor: tint(context, color, 0.18), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onTap: onTap,
      );
}

class _ItemTile extends StatelessWidget {
  final ClassController c;
  final Object item;
  final bool showDate;
  const _ItemTile({required this.c, required this.item, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color color;
    IconData icon;
    String title, sub, dateStr;
    VoidCallback? onDelete;

    if (item is CalEvent) {
      final e = item as CalEvent;
      color = e.type == 'holiday' ? Brand.holiday : Brand.deadline;
      icon = e.type == 'holiday' ? Icons.beach_access_rounded : Icons.flag_rounded;
      title = e.title;
      final subj = c.subjectById(e.subjectId)?.name;
      sub = [if (subj != null) subj, if (e.description != null) e.description!].join('  -  ');
      if (sub.isEmpty) sub = e.type == 'holiday' ? 'Holiday' : 'Deadline';
      dateStr = e.date;
      onDelete = () async {
        if (await confirm(context, 'Remove ${e.type}?', '"${e.title}" will be removed for everyone.',
            yes: 'Remove', danger: true)) {
          if (context.mounted) await guarded(context, () => c.deleteEvent(e));
        }
      };
    } else {
      final e = item as ExamPaper;
      color = Brand.exam;
      icon = Icons.edit_note_rounded;
      title = '${c.subjectById(e.subjectId)?.name ?? 'Exam'} - ${e.examName}';
      sub = '${fmtTime(e.start)} - ${fmtTime(e.end)}${e.room != null ? '   Room ${e.room}' : ''}';
      dateStr = e.date;
      onDelete = () async {
        if (await confirm(context, 'Remove exam paper?', 'It will be removed from the exam timetable.',
            yes: 'Remove', danger: true)) {
          if (context.mounted) await guarded(context, () => c.deleteExam(e));
        }
      };
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(children: [
          CircleAvatar(
              radius: 20, backgroundColor: tint(context, color, 0.18), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(showDate ? '${fmtDate(parseYmd(dateStr))}  -  $sub' : sub,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ]),
          ),
          if (c.isTeacher)
            IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant), onPressed: onDelete),
        ]),
      ),
    );
  }
}

class _EventForm extends StatefulWidget {
  final ClassController c;
  final DateTime date;
  final String type;
  const _EventForm({required this.c, required this.date, required this.type});
  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _date = widget.date;
  String? _subjectId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final mine = widget.c.manageableSubjects;
    if (widget.type == 'deadline' && mine.length == 1) _subjectId = mine.first.id;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2024), lastDate: DateTime(2030));
    if (d != null) setState(() => _date = dateOnly(d));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      snack(context, 'Add a title.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.c.addEvent(
        type: widget.type,
        title: _title.text.trim(),
        date: _date,
        description: _desc.text,
        subjectId: _subjectId,
      );
      nav.pop();
    } catch (e) {
      snack(context, friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHoliday = widget.type == 'holiday';
    final mine = widget.c.manageableSubjects;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isHoliday ? 'New holiday' : 'New deadline', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: isHoliday ? 'Holiday name' : 'What is due?'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_rounded),
            label: Text(fmtDate(_date)),
          ),
          if (!isHoliday) ...[
            const SizedBox(height: 14),
            if (mine.isEmpty)
              Text('Add your subject in class details to tag deadlines by subject.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in mine)
                  ChoiceChip(
                    avatar: CircleAvatar(radius: 5, backgroundColor: colorFromHex(s.colorHex)),
                    label: Text(s.name),
                    selected: _subjectId == s.id,
                    onSelected: (v) => setState(() => _subjectId = v ? s.id : null),
                  ),
              ]),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Details (optional)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ]),
      ),
    );
  }
}
