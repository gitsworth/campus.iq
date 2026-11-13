import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/common.dart';

/// The normal (permanent) timetable as a grid. Teachers tap a cell to edit it.
class WeeklyTimetableScreen extends StatelessWidget {
  final ClassController c;
  const WeeklyTimetableScreen({super.key, required this.c});

  static const _timeW = 78.0, _cellW = 118.0, _cellH = 74.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Weekly timetable')),
          body: c.slots.isEmpty
              ? const EmptyState(
                  icon: Icons.grid_view_rounded,
                  title: 'No time slots yet',
                  message: 'Add time slots from the Timetable tab first.')
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(children: [
                      Row(children: [
                        const SizedBox(width: _timeW),
                        for (var d = 1; d <= 7; d++)
                          SizedBox(
                            width: _cellW,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(weekdayName(d),
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                      ]),
                      for (final slot in c.slots)
                        Row(children: [
                          SizedBox(
                            width: _timeW,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(fmtTime(slot.start),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                                Text(fmtTime(slot.end),
                                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                              ]),
                            ),
                          ),
                          for (var d = 1; d <= 7; d++) _cell(context, slot, d),
                        ]),
                    ]),
                  ),
                ),
          bottomNavigationBar: c.isTeacher
              ? const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Text('Tap a cell to set the subject for that day and period.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5)),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _cell(BuildContext context, TimeSlot slot, int weekday) {
    final cs = Theme.of(context).colorScheme;
    if (slot.isBreak) {
      return Container(
        width: _cellW,
        height: 38,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(slot.label ?? 'Break',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      );
    }
    final e = c.entries.where((x) => x.weekday == weekday && x.slotId == slot.id).firstOrNull;
    final s = c.subjectById(e?.subjectId);
    final color = s == null ? null : colorFromHex(s.colorHex);
    return GestureDetector(
      onTap: c.isTeacher ? () => showSheet(context, (_) => _EditCell(c: c, slot: slot, weekday: weekday, entry: e)) : null,
      child: Container(
        width: _cellW,
        height: _cellH,
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: color == null ? Colors.transparent : tint(context, color, 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color ?? cs.outlineVariant, width: color == null ? 1 : 1.2),
        ),
        child: s == null
            ? Center(child: Icon(c.isTeacher ? Icons.add_rounded : null, size: 18, color: cs.outline))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.15)),
                const Spacer(),
                if (e?.room != null)
                  Text(e!.room!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ]),
      ),
    );
  }
}

class _EditCell extends StatefulWidget {
  final ClassController c;
  final TimeSlot slot;
  final int weekday;
  final TTEntry? entry;
  const _EditCell({required this.c, required this.slot, required this.weekday, this.entry});
  @override
  State<_EditCell> createState() => _EditCellState();
}

class _EditCellState extends State<_EditCell> {
  Subject? _subject;
  final _room = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subject = widget.c.subjectById(widget.entry?.subjectId);
    _room.text = widget.entry?.room ?? '';
  }

  Future<void> _save(Subject? s) async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.c.setEntry(widget.weekday, widget.slot, s, _room.text);
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
          Text('${weekdayName(widget.weekday)}, ${fmtTime(widget.slot.start)}',
              style: Theme.of(context).textTheme.titleLarge),
          Text('Every ${weekdayName(widget.weekday)} from now on.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (c.subjects.isEmpty)
            const Text('No subjects exist yet. Teachers add subjects in class details (the i button).')
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
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy || _subject == null ? null : () => _save(_subject),
            child: const Text('Save'),
          ),
          if (widget.entry != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : () => _save(null),
              child: const Text('Clear this period'),
            ),
          ],
        ]),
      ),
    );
  }
}
