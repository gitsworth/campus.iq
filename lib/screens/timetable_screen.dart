import 'dart:async';
import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'slots_screen.dart';
import 'weekly_timetable_screen.dart';

class TimetableScreen extends StatefulWidget {
  final ClassController c;
  const TimetableScreen({super.key, required this.c});
  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  DateTime _selected = dateOnly(DateTime.now());
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  ClassController get c => widget.c;

  DateTime get _weekStart => _selected.subtract(Duration(days: _selected.weekday - 1));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (d != null) setState(() => _selected = dateOnly(d));
  }

  Future<void> _followDay() async {
    final ov = c.dayOverrideFor(_selected);
    final picked = await showSheet<int>(context, (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Run another day\'s timetable', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${fmtDate(_selected)} will follow the timetable you choose. Only this date changes.',
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var w = 1; w <= 7; w++)
                ChoiceChip(
                  label: Text(weekdayName(w)),
                  selected: ov?.followWeekday == w,
                  onSelected: (_) => Navigator.pop(ctx, w),
                ),
            ]),
            if (ov != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 0),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Go back to the normal timetable'),
              ),
            ],
          ]),
        ),
      );
    });
    if (picked == null || !mounted) return;
    if (picked == 0) {
      await guarded(context, () => c.clearDayFollows(_selected), success: 'Back to normal');
    } else {
      await guarded(context, () => c.setDayFollows(_selected, picked, null),
          success: 'Updated for ${fmtDateShort(_selected)}');
    }
  }

  Future<void> _periodActions(Period p) async {
    if (!c.isTeacher || p.isBreak) return;
    await showSheet<void>(context, (ctx) => _PeriodSheet(c: c, p: p, date: _selected));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final live = c.liveStatus(now);
    final periods = c.periodsFor(_selected);
    final holidays = c.eventsOn(_selected).where((e) => e.type == 'holiday').toList();
    final ov = c.dayOverrideFor(_selected);
    final isToday = _selected == dateOnly(now);

    return RefreshIndicator(
      onRefresh: () => c.load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _NowCard(c: c, live: live, now: now),
          const SizedBox(height: 18),
          Row(children: [
            IconButton.filledTonal(
              onPressed: () => setState(() => _selected = _selected.subtract(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_left_rounded),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    fmtDate(_selected),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => setState(() => _selected = _selected.add(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_right_rounded),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: _DayCell(
                date: _weekStart.add(Duration(days: i)),
                selected: _weekStart.add(Duration(days: i)) == _selected,
                today: _weekStart.add(Duration(days: i)) == dateOnly(now),
                marked: c.isHoliday(_weekStart.add(Duration(days: i))),
                changed: c.dayOverrideFor(_weekStart.add(Duration(days: i))) != null ||
                    c.slotOverrides.any((o) => o.date == ymd(_weekStart.add(Duration(days: i)))),
                onTap: () => setState(() => _selected = _weekStart.add(Duration(days: i))),
              )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (!isToday)
              ActionChip(
                avatar: const Icon(Icons.today_rounded, size: 18),
                label: const Text('Today'),
                onPressed: () => setState(() => _selected = dateOnly(DateTime.now())),
              ),
            if (!isToday) const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text('Weekly grid'),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WeeklyTimetableScreen(c: c))),
            ),
            const Spacer(),
            if (c.isTeacher)
              PopupMenuButton<String>(
                icon: const Icon(Icons.tune_rounded),
                onSelected: (v) {
                  if (v == 'slots') {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SlotsScreen(c: c)));
                  } else if (v == 'follow') {
                    _followDay();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'follow', child: Text('Run another day\'s timetable on this date')),
                  PopupMenuItem(value: 'slots', child: Text('Manage time slots')),
                ],
              ),
          ]),
          const SizedBox(height: 8),
          for (final h in holidays)
            _Banner(color: Brand.holiday, icon: Icons.beach_access_rounded, text: 'Holiday: ${h.title}'),
          if (ov?.followWeekday != null)
            _Banner(
              color: Brand.deadline,
              icon: Icons.swap_horiz_rounded,
              text: 'Today only: following the ${weekdayName(ov!.followWeekday!)} timetable',
            ),
          const SizedBox(height: 4),
          if (c.slots.isEmpty)
            EmptyState(
              icon: Icons.schedule_outlined,
              title: 'No time slots yet',
              message: c.isTeacher
                  ? 'Set up the daily periods first, then fill in each day.'
                  : 'Your teachers have not set up the timetable yet.',
              action: c.isTeacher
                  ? FilledButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SlotsScreen(c: c))),
                      child: const Text('Set up time slots'),
                    )
                  : null,
            )
          else
            for (final p in periods)
              _PeriodRow(
                p: p,
                isNow: isToday && live.current?.slot.id == p.slot.id,
                onTap: c.isTeacher && !p.isBreak ? () => _periodActions(p) : null,
              ),
          if (c.isTeacher && c.slots.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Tap a period to change it for this date only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  final ClassController c;
  final ({Period? current, Period? next, DateTime? nextDate, bool inBreak}) live;
  final DateTime now;
  const _NowCard({required this.c, required this.live, required this.now});

  @override
  Widget build(BuildContext context) {
    final cur = live.current;
    final nxt = live.next;
    double progress = 0;
    if (cur != null) {
      final s = minutesOf(cur.slot.start), e = minutesOf(cur.slot.end);
      final n = now.hour * 60 + now.minute + now.second / 60;
      progress = ((n - s) / (e - s)).clamp(0.0, 1.0);
    }
    String nextText() {
      if (nxt == null) return 'No upcoming classes found';
      final sameDay = live.nextDate == dateOnly(now);
      final when = sameDay
          ? 'at ${fmtTime(nxt.slot.start)}'
          : '${live.nextDate == dateOnly(now).add(const Duration(days: 1)) ? 'tomorrow' : fmtDate(live.nextDate!)}, ${fmtTime(nxt.slot.start)}';
      return '${nxt.subject!.name} $when${nxt.room != null ? ' - ${nxt.room}' : ''}';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.ink,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: cur != null ? Brand.marigold : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(cur != null ? 'Happening now' : (live.inBreak ? 'Break time' : 'No class right now'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        if (cur != null) ...[
          Text(cur.subject!.name,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontSize: 30)),
          const SizedBox(height: 4),
          Text(
            '${fmtTime(cur.slot.start)} - ${fmtTime(cur.slot.end)}'
            '${cur.room != null ? '   Room ${cur.room}' : ''}'
            '   ${c.nameOf(cur.subject!.teacherId)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Brand.marigold),
            ),
          ),
        ] else
          Text(
            c.slots.isEmpty ? 'Timetable not set up' : (live.inBreak ? 'Enjoy the break' : 'You are free'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontSize: 28),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.arrow_forward_rounded, color: Brand.marigold, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Next: ${nextText()}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final bool selected, today, marked, changed;
  final VoidCallback onTap;
  const _DayCell({
    required this.date,
    required this.selected,
    required this.today,
    required this.marked,
    required this.changed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: today && !selected ? Border.all(color: cs.primary, width: 1.5) : null,
        ),
        child: Column(children: [
          Text(weekdayShort(date.weekday),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('${date.day}',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: selected ? cs.onPrimary : cs.onSurface)),
          const SizedBox(height: 4),
          SizedBox(
            height: 6,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (marked)
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.holiday, shape: BoxShape.circle)),
              if (marked && changed) const SizedBox(width: 3),
              if (changed)
                Container(width: 6, height: 6, decoration: BoxDecoration(color: selected ? Brand.marigold : Brand.deadline, shape: BoxShape.circle)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tint(context, color, 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class _PeriodRow extends StatelessWidget {
  final Period p;
  final bool isNow;
  final VoidCallback? onTap;
  const _PeriodRow({required this.p, required this.isNow, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeCol = SizedBox(
      width: 64,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fmtTime(p.slot.start).replaceAll(' ', '\u00A0'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        Text(fmtTime(p.slot.end).replaceAll(' ', '\u00A0'),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );

    Widget card;
    if (p.isBreak) {
      card = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(children: [
          Icon(Icons.coffee_outlined, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(p.slot.label ?? 'Break', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ]),
      );
    } else if (p.cancelled) {
      card = Panel(
        onTap: onTap,
        color: tint(context, Brand.holiday, 0.10),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.subject?.name ?? 'Class',
                  style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.lineThrough)),
              if (p.note != null) Text(p.note!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ]),
          ),
          const Tag('Cancelled today', color: Brand.holiday),
        ]),
      );
    } else if (p.isFree) {
      card = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(children: [
          Text('Free period', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          if (onTap != null) ...[
            const Spacer(),
            Icon(Icons.add_rounded, size: 18, color: cs.onSurfaceVariant),
          ],
        ]),
      );
      if (onTap != null) card = InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: card);
    } else {
      final color = colorFromHex(p.subject!.colorHex);
      card = Material(
        color: tint(context, color, isNow ? 0.28 : 0.15),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: isNow ? Border.all(color: color, width: 2) : null,
            ),
            child: Row(children: [
              Container(width: 4, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.subject!.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(
                    [if (p.room != null) 'Room ${p.room}', if (p.subject!.code != null) p.subject!.code!].join('   '),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  if (p.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(p.note!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ),
                ]),
              ),
              if (p.changed) const Tag('Today only', color: Brand.deadline, icon: Icons.bolt_rounded),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 12), child: timeCol),
        Expanded(child: card),
      ]),
    );
  }
}

class _PeriodSheet extends StatefulWidget {
  final ClassController c;
  final Period p;
  final DateTime date;
  const _PeriodSheet({required this.c, required this.p, required this.date});
  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  Subject? _subject;
  final _room = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subject = widget.p.subject;
    _room.text = widget.p.room ?? '';
  }

  Future<void> _save({bool cancel = false}) async {
    if (!cancel && _subject == null) {
      snack(context, 'Pick a subject.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.c.setSlotOverride(widget.date, widget.p.slot,
          subject: _subject, room: _room.text, cancelled: cancel, note: _note.text);
      nav.pop();
    } catch (e) {
      snack(context, friendlyError(e));
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
          Text('${fmtTime(widget.p.slot.start)} - ${fmtTime(widget.p.slot.end)}',
              style: Theme.of(context).textTheme.titleLarge),
          Text('Changes apply to ${fmtDate(widget.date)} only. The normal timetable returns after.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (c.subjects.isEmpty)
            const Text('No subjects exist yet. Teachers add subjects in class details.')
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
          TextField(controller: _room, decoration: const InputDecoration(labelText: 'Room (optional)')),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Reason (optional)')),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : () => _save(),
            child: const Text('Change for this day'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _save(cancel: true),
                child: const Text('Cancel this class'),
              ),
            ),
            if (widget.p.changed) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final nav = Navigator.of(context);
                          await guarded(context, () => c.clearSlotOverride(widget.date, widget.p.slot));
                          nav.pop();
                        },
                  child: const Text('Revert to normal'),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
