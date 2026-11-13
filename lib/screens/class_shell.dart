import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'announcements_screen.dart';
import 'assistant_screen.dart';
import 'calendar_screen.dart';
import 'class_info_screen.dart';
import 'join_create_screen.dart';
import 'notes_screen.dart';
import 'timetable_screen.dart';

class ClassShell extends StatefulWidget {
  final ClassController controller;
  final List<Membership> memberships;
  final bool hasStudentClass;
  final ValueChanged<Membership> onSwitch;
  final void Function({String? selectId}) onMembershipsChanged;
  const ClassShell({
    super.key,
    required this.controller,
    required this.memberships,
    required this.hasStudentClass,
    required this.onSwitch,
    required this.onMembershipsChanged,
  });
  @override
  State<ClassShell> createState() => _ClassShellState();
}

class _ClassShellState extends State<ClassShell> {
  int _tab = 0;

  ClassController get c => widget.controller;

  void _openSwitcher() {
    showSheet(context, (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your classes', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final m in widget.memberships)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: tint(ctx, m.isTeacher ? Brand.primary : Brand.deadline, 0.18),
                  child: Icon(m.isTeacher ? Icons.co_present_outlined : Icons.backpack_outlined,
                      color: m.isTeacher ? Brand.primary : Brand.deadline, size: 20),
                ),
                title: Text(m.cls.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(m.isTeacher ? 'Teacher' : 'Student'),
                trailing: m.cls.id == c.cls.id ? const Icon(Icons.check_circle_rounded) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSwitch(m);
                },
              ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
              title: const Text('Create or join a class', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JoinCreateScreen(
                    hasStudentClass: widget.hasStudentClass,
                    isFirstRun: false,
                    onJoined: (id) => widget.onMembershipsChanged(selectId: id),
                  ),
                ));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.logout_rounded)),
              title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                db.auth.signOut();
              },
            ),
          ]),
        ),
      );
    });
  }

  void _openInfo() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClassInfoScreen(
  c: c,
  onLeftOrDeleted: () => widget.onMembershipsChanged(),
),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final pages = <Widget>[
          AnnouncementsScreen(c: c),
          TimetableScreen(c: c),
          CalendarScreen(c: c),
          NotesScreen(c: c),
          AssistantScreen(c: c),
        ];
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openSwitcher,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.cls.name, overflow: TextOverflow.ellipsis),
                      Text(c.isTeacher ? 'Teacher' : 'Student',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.unfold_more_rounded, size: 20, color: cs.onSurfaceVariant),
                ]),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Class details and codes',
                onPressed: _openInfo,
                icon: const Icon(Icons.info_outline_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(children: [
            if (c.cls.deleteAfter != null)
              _DeleteBanner(c: c, onUndone: () => widget.onMembershipsChanged()),
            Expanded(
              child: c.loading
                  ? const Center(child: CircularProgressIndicator())
                  : c.error != null
                      ? EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load this class',
                          message: c.error!,
                          action: FilledButton(onPressed: c.load, child: const Text('Try again')),
                        )
                      : IndexedStack(index: _tab, children: pages),
            ),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.campaign_outlined),
                  selectedIcon: Icon(Icons.campaign_rounded),
                  label: 'Feed'),
              NavigationDestination(
                  icon: Icon(Icons.schedule_outlined),
                  selectedIcon: Icon(Icons.schedule_rounded),
                  label: 'Timetable'),
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Calendar'),
              NavigationDestination(
                  icon: Icon(Icons.folder_open_outlined),
                  selectedIcon: Icon(Icons.folder_rounded),
                  label: 'Notes'),
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome_rounded),
                  label: 'Ask'),
            ],
          ),
        );
      },
    );
  }
}

class _DeleteBanner extends StatelessWidget {
  final ClassController c;
  final VoidCallback onUndone;
  const _DeleteBanner({required this.c, required this.onUndone});

  @override
  Widget build(BuildContext context) {
    final isCreator = c.cls.creatorId == myId;
    final when = fmtDate(c.cls.deleteAfter!);
    return Container(
      width: double.infinity,
      color: tint(context, Brand.holiday, 0.16),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        const Icon(Icons.delete_outline_rounded, color: Brand.holiday, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text('This class will be deleted on $when.',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        ),
        if (isCreator)
          TextButton(
            onPressed: () => guarded(context, () async {
              await c.cancelDelete();
              onUndone();
            }, success: 'Deletion cancelled'),
            child: const Text('Undo'),
          ),
      ]),
    );
  }
}
