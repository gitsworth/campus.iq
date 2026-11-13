import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'class_shell.dart';
import 'join_create_screen.dart';

/// Loads every class the user belongs to and decides what to show.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  List<Membership> _memberships = [];
  ClassController? _ctrl;
  bool _loading = true;
  String? _error;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _loadMemberships();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _loadMemberships({String? selectId}) async {
    setState(() {
      _loading = _memberships.isEmpty;
      _error = null;
    });
    try {
      final t = await db.from('class_teachers').select('class_id').eq('user_id', myId);
      final s = await db.from('class_students').select('class_id').eq('user_id', myId);
      final teacherIds = t.map((e) => e['class_id'] as String).toSet();
      final studentIds = s.map((e) => e['class_id'] as String).toSet();
      final all = {...teacherIds, ...studentIds};
      final list = <Membership>[];
      if (all.isNotEmpty) {
        final rows = await db.from('classes').select().inFilter('id', all.toList());
        for (final r in rows) {
          final c = ClassRoom.fromJson(r);
          list.add(Membership(c, teacherIds.contains(c.id)));
        }
        list.sort((a, b) => a.cls.name.toLowerCase().compareTo(b.cls.name.toLowerCase()));
      }
      _memberships = list;
      final want = selectId ?? _activeId;
      final m = list.where((e) => e.cls.id == want).firstOrNull ?? list.firstOrNull;
      if (m != null &&
          (m.cls.id != _ctrl?.cls.id || m.cls.deleteAfter != _ctrl?.cls.deleteAfter || m.cls.creatorId != _ctrl?.cls.creatorId)) {
        _ctrl?.dispose();
        _ctrl = ClassController(m.cls, m.isTeacher)..load();
        _activeId = m.cls.id;
      } else if (m == null) {
        _ctrl?.dispose();
        _ctrl = null;
        _activeId = null;
      }
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _switchTo(Membership m) {
    if (m.cls.id == _activeId) return;
    _ctrl?.dispose();
    setState(() {
      _ctrl = ClassController(m.cls, m.isTeacher)..load();
      _activeId = m.cls.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Could not load your classes',
          message: _error!,
          action: FilledButton(
            onPressed: () => _loadMemberships(),
            child: const Text('Try again'),
          ),
        ),
      );
    }
    if (_ctrl == null) {
      return JoinCreateScreen(
        hasStudentClass: false,
        isFirstRun: true,
        onJoined: (id) => _loadMemberships(selectId: id),
      );
    }
    return ClassShell(
      key: ValueKey(_ctrl!.cls.id),
      controller: _ctrl!,
      memberships: _memberships,
      hasStudentClass: _memberships.any((m) => !m.isTeacher),
      onSwitch: _switchTo,
      onMembershipsChanged: ({String? selectId}) => _loadMemberships(selectId: selectId),
    );
  }
}
