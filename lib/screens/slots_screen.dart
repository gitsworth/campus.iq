import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/common.dart';

class SlotsScreen extends StatelessWidget {
  final ClassController c;
  const SlotsScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Time slots')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showSheet(context, (_) => _AddSlotSheet(c: c)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add slot'),
          ),
          body: c.slots.isEmpty
              ? EmptyState(
                  icon: Icons.schedule_outlined,
                  title: 'No slots yet',
                  message: 'Slots are the rows of the timetable, shared by every day of the week.',
                  action: FilledButton(
                    onPressed: () => guarded(context, c.quickFillSlots, success: 'Slots added'),
                    child: const Text('Add 6 periods with breaks'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: c.slots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = c.slots[i];
                    return Panel(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                      child: Row(children: [
                        Icon(s.isBreak ? Icons.coffee_outlined : Icons.menu_book_outlined,
                            color: cs.onSurfaceVariant),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${fmtTime(s.start)} - ${fmtTime(s.end)}',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(s.isBreak ? (s.label ?? 'Break') : (s.label ?? 'Class period'),
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          ]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            if (await confirm(context, 'Remove this slot?',
                                'Classes placed in it on every day will be removed too.',
                                yes: 'Remove', danger: true)) {
                              if (context.mounted) await guarded(context, () => c.deleteSlot(s));
                            }
                          },
                        ),
                      ]),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _AddSlotSheet extends StatefulWidget {
  final ClassController c;
  const _AddSlotSheet({required this.c});
  @override
  State<_AddSlotSheet> createState() => _AddSlotSheetState();
}

class _AddSlotSheetState extends State<_AddSlotSheet> {
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);
  final _label = TextEditingController();
  bool _break = false, _busy = false;

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (t != null) setState(() => start ? _start = t : _end = t);
  }

  Future<void> _save() async {
    final s = timeOfDayToDb(_start), e = timeOfDayToDb(_end);
    if (minutesOf(e) <= minutesOf(s)) {
      snack(context, 'End time must be after start time.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.c.addSlot(s, e, _label.text, _break);
      nav.pop();
    } catch (err) {
      snack(context, friendlyError(err));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add a time slot', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.login_rounded),
                label: Text('Starts ${_start.format(context)}'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.logout_rounded),
                label: Text('Ends ${_end.format(context)}'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Label (optional, e.g. Lunch)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('This is a break'),
            value: _break,
            onChanged: (v) => setState(() => _break = v),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Add slot')),
        ]),
      ),
    );
  }
}
