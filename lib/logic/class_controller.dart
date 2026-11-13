import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';
import '../models.dart';
import '../util.dart';

SupabaseClient get db => Supabase.instance.client;
String get myId => db.auth.currentUser!.id;

/// One period of a resolved day (normal timetable + temporary changes applied).
class Period {
  final TimeSlot slot;
  final Subject? subject;
  final String? room;
  final bool cancelled, changed;
  final String? note;
  const Period({
    required this.slot,
    this.subject,
    this.room,
    this.cancelled = false,
    this.changed = false,
    this.note,
  });
  bool get isBreak => slot.isBreak;
  bool get isFree => subject == null && !slot.isBreak && !cancelled;
  bool get isClass => subject != null && !cancelled && !slot.isBreak;
}

class ClassController extends ChangeNotifier {
  final ClassRoom cls;
  final bool isTeacher;
  ClassController(this.cls, this.isTeacher);

  bool loading = true;
  String? error;
  String? teacherCode;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<Subject> subjects = [];
  List<TimeSlot> slots = [];
  List<TTEntry> entries = [];
  List<DayOverride> dayOverrides = [];
  List<SlotOverride> slotOverrides = [];
  List<CalEvent> events = [];
  List<ExamPaper> exams = [];
  List<Announcement> announcements = [];
  List<Note> notes = [];
  List<String> teacherIds = [];
  List<String> studentIds = [];
  Map<String, String> names = {};

  // ---------- loading ----------
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final id = cls.id;
      Future<List<Map<String, dynamic>>> q(String t, {String? order, bool asc = true, int? limit}) {
        var b = db.from(t).select().eq('class_id', id);
        if (order != null) {
          var o = b.order(order, ascending: asc);
          if (limit != null) return o.limit(limit);
          return o;
        }
        return b;
      }

      final r = await Future.wait([
        q('subjects', order: 'name'),
        q('time_slots', order: 'start_time'),
        q('timetable_entries'),
        q('day_overrides'),
        q('slot_overrides'),
        q('calendar_events', order: 'event_date'),
        q('exam_papers', order: 'exam_date'),
        q('announcements', order: 'created_at', asc: false, limit: 300),
        q('notes', order: 'created_at', asc: false),
        q('class_teachers'),
        q('class_students'),
      ]);

      subjects = r[0].map(Subject.fromJson).toList();
      slots = r[1].map(TimeSlot.fromJson).toList();
      entries = r[2].map(TTEntry.fromJson).toList();
      dayOverrides = r[3].map(DayOverride.fromJson).toList();
      slotOverrides = r[4].map(SlotOverride.fromJson).toList();
      events = r[5].map(CalEvent.fromJson).toList();
      exams = r[6].map(ExamPaper.fromJson).toList();
      announcements = r[7].map(Announcement.fromJson).toList();
      notes = r[8].map(Note.fromJson).toList();
      teacherIds = r[9].map((e) => e['user_id'] as String).toList();
      studentIds = r[10].map((e) => e['user_id'] as String).toList();

      final ids = {...teacherIds, ...studentIds};
      if (ids.isNotEmpty) {
        final p = await db.from('profiles').select('id, full_name').inFilter('id', ids.toList());
        names = {for (final m in p) m['id'] as String: (m['full_name'] ?? 'User') as String};
      }
      // Both class codes are visible to every member by product design.
      final codeRow = await db.from('class_codes').select().eq('class_id', id).maybeSingle();
      teacherCode = codeRow?['teacher_code'] as String?;
      error = null;
    } catch (e) {
      error = friendlyError(e);
    }
    loading = false;
    notifyListeners();
  }

  // ---------- lookups ----------
  Subject? subjectById(String? id) =>
      id == null ? null : subjects.where((s) => s.id == id).firstOrNull;
  String nameOf(String? uid) => uid == null ? 'Former teacher' : (names[uid] ?? 'Former teacher');
  List<Subject> get mySubjects => subjects.where((s) => s.teacherId == myId).toList();
  List<Subject> get manageableSubjects =>
      cls.creatorId == myId ? subjects : mySubjects;

  // ---------- timetable resolution ----------
  DayOverride? dayOverrideFor(DateTime d) =>
      dayOverrides.where((o) => o.date == ymd(d)).firstOrNull;

  List<CalEvent> eventsOn(DateTime d) =>
      events.where((e) => e.date == ymd(d)).toList();

  bool isHoliday(DateTime d) => eventsOn(d).any((e) => e.type == 'holiday');

  List<Period> periodsFor(DateTime date) {
    // A holiday takes priority over both the regular timetable and every
    // temporary day/slot override. Removing the holiday restores the schedule.
    if (isHoliday(date)) return const <Period>[];
    final ds = ymd(date);
    final ov = dayOverrideFor(date);
    final weekday = ov?.followWeekday ?? date.weekday;
    final out = <Period>[];
    for (final slot in slots) {
      final entry = entries
          .where((e) => e.weekday == weekday && e.slotId == slot.id)
          .firstOrNull;
      final so = slotOverrides
          .where((o) => o.date == ds && o.slotId == slot.id)
          .firstOrNull;
      if (slot.isBreak) {
        out.add(Period(slot: slot));
        continue;
      }
      Subject? subject = subjectById(entry?.subjectId);
      String? room = entry?.room;
      var cancelled = false, changed = false;
      String? note;
      if (so != null) {
        changed = true;
        note = so.note;
        if (so.cancelled) {
          cancelled = true;
        } else {
          subject = subjectById(so.subjectId) ?? subject;
          room = so.room ?? room;
        }
      }
      out.add(Period(
          slot: slot,
          subject: subject,
          room: room,
          cancelled: cancelled,
          changed: changed,
          note: note));
    }
    return out;
  }

  /// Current and next class, looking up to 14 days ahead for "next".
  ({Period? current, Period? next, DateTime? nextDate, bool inBreak}) liveStatus(DateTime now) {
    final today = dateOnly(now);
    final nowMin = now.hour * 60 + now.minute;
    Period? current, next;
    DateTime? nextDate;
    var inBreak = false;
    if (!isHoliday(today)) {
      for (final p in periodsFor(today)) {
        final s = minutesOf(p.slot.start), e = minutesOf(p.slot.end);
        if (nowMin >= s && nowMin < e) {
          if (p.isBreak) {
            inBreak = true;
          } else if (p.isClass) {
            current = p;
          }
        }
        if (next == null && s > nowMin && p.isClass) {
          next = p;
          nextDate = today;
        }
      }
    }
    if (next == null) {
      for (var i = 1; i <= 14 && next == null; i++) {
        final d = today.add(Duration(days: i));
        if (isHoliday(d)) continue;
        final first = periodsFor(d).where((p) => p.isClass).firstOrNull;
        if (first != null) {
          next = first;
          nextDate = d;
        }
      }
    }
    return (current: current, next: next, nextDate: nextDate, inBreak: inBreak);
  }

  // ---------- generic helpers ----------
  Future<void> _after() => load(silent: true);

  Future<void> autoAnnounce(String title, String body, {String? subjectId}) async {
    await db.from('announcements').insert({
      'class_id': cls.id,
      'subject_id': subjectId,
      'title': title,
      'body': body,
      'is_auto': true,
      'created_by': myId,
    });
  }

  // ---------- subjects ----------
  Future<void> addSubject(String name, String? code, String colorHex) async {
    await db.from('subjects').insert({
      'class_id': cls.id,
      'name': name,
      'code': (code == null || code.trim().isEmpty) ? null : code.trim(),
      'teacher_id': myId,
      'color': colorHex,
    });
    await _after();
  }

  Future<void> deleteSubject(String id) async {
    await db.from('subjects').delete().eq('id', id);
    await _after();
  }

  // ---------- time slots ----------
  Future<void> addSlot(String start, String end, String? label, bool isBreak,
      {bool announce = true}) async {
    await db.from('time_slots').insert({
      'class_id': cls.id,
      'start_time': start,
      'end_time': end,
      'label': (label == null || label.trim().isEmpty) ? null : label.trim(),
      'is_break': isBreak,
    });
    if (announce) {
      await autoAnnounce('Timetable updated',
          '${nameOf(myId)} added a time slot ${fmtTime(start)} - ${fmtTime(end)}.');
    }
    await _after();
  }

  Future<void> quickFillSlots() async {
    const rows = [
      ['09:00:00', '10:00:00', null, false],
      ['10:00:00', '11:00:00', null, false],
      ['11:00:00', '11:15:00', 'Break', true],
      ['11:15:00', '12:15:00', null, false],
      ['12:15:00', '13:15:00', null, false],
      ['13:15:00', '14:00:00', 'Lunch', true],
      ['14:00:00', '15:00:00', null, false],
      ['15:00:00', '16:00:00', null, false],
    ];
    await db.from('time_slots').insert([
      for (final r in rows)
        {
          'class_id': cls.id,
          'start_time': r[0],
          'end_time': r[1],
          'label': r[2],
          'is_break': r[3],
        }
    ]);
    await autoAnnounce('Timetable updated', '${nameOf(myId)} set up the daily time slots.');
    await _after();
  }

  Future<void> deleteSlot(TimeSlot s) async {
    await db.from('time_slots').delete().eq('id', s.id);
    await autoAnnounce('Timetable updated',
        '${nameOf(myId)} removed the slot ${fmtTime(s.start)} - ${fmtTime(s.end)}.');
    await _after();
  }

  // ---------- weekly (permanent) timetable ----------
  Future<void> setEntry(int weekday, TimeSlot slot, Subject? subject, String? room) async {
    final existing = entries
        .where((e) => e.weekday == weekday && e.slotId == slot.id)
        .firstOrNull;
    final when = '${weekdayName(weekday)} ${fmtTime(slot.start)}';
    if (subject == null) {
      if (existing != null) {
        await db.from('timetable_entries').delete().eq('id', existing.id);
        await autoAnnounce('Timetable updated',
            '${nameOf(myId)} cleared $when.');
      }
    } else {
      await db.from('timetable_entries').upsert({
        'class_id': cls.id,
        'weekday': weekday,
        'slot_id': slot.id,
        'subject_id': subject.id,
        'room': (room == null || room.trim().isEmpty) ? null : room.trim(),
      }, onConflict: 'class_id,weekday,slot_id');
      await autoAnnounce('Timetable updated',
          '$when is now ${subject.name}${room != null && room.trim().isNotEmpty ? ' in ${room.trim()}' : ''} (set by ${nameOf(myId)}).');
    }
    await _after();
  }

  // ---------- temporary changes ----------
  Future<void> setSlotOverride(DateTime date, TimeSlot slot,
      {Subject? subject, String? room, bool cancelled = false, String? note}) async {
    await db.from('slot_overrides').upsert({
      'class_id': cls.id,
      'on_date': ymd(date),
      'slot_id': slot.id,
      'subject_id': cancelled ? null : subject?.id,
      'room': (room == null || room.trim().isEmpty) ? null : room.trim(),
      'cancelled': cancelled,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    }, onConflict: 'class_id,on_date,slot_id');
    final what = cancelled
        ? 'is cancelled'
        : 'changes to ${subject?.name ?? 'a different class'}${room != null && room.trim().isNotEmpty ? ' in ${room.trim()}' : ''}';
    await autoAnnounce('Temporary timetable change',
        '${fmtDate(date)}, ${fmtTime(slot.start)} $what. Only for this day. (${nameOf(myId)})');
    await _after();
  }

  Future<void> clearSlotOverride(DateTime date, TimeSlot slot) async {
    await db
        .from('slot_overrides')
        .delete()
        .eq('class_id', cls.id)
        .eq('on_date', ymd(date))
        .eq('slot_id', slot.id);
    await autoAnnounce('Timetable change reverted',
        '${fmtDate(date)}, ${fmtTime(slot.start)} is back to the normal timetable.');
    await _after();
  }

  Future<void> setDayFollows(DateTime date, int weekday, String? note) async {
    await db.from('day_overrides').upsert({
      'class_id': cls.id,
      'on_date': ymd(date),
      'follow_weekday': weekday,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    }, onConflict: 'class_id,on_date');
    await autoAnnounce('Temporary timetable change',
        '${fmtDate(date)} will follow the ${weekdayName(weekday)} timetable. Only for this day. (${nameOf(myId)})');
    await _after();
  }

  Future<void> clearDayFollows(DateTime date) async {
    await db
        .from('day_overrides')
        .delete()
        .eq('class_id', cls.id)
        .eq('on_date', ymd(date));
    await autoAnnounce('Timetable change reverted',
        '${fmtDate(date)} is back to its normal timetable.');
    await _after();
  }

  // ---------- calendar ----------
  Future<void> addEvent({
    required String type,
    required String title,
    required DateTime date,
    String? description,
    String? subjectId,
  }) async {
    await db.from('calendar_events').insert({
      'class_id': cls.id,
      'subject_id': subjectId,
      'title': title,
      'description': (description == null || description.trim().isEmpty) ? null : description.trim(),
      'event_date': ymd(date),
      'event_type': type,
      'created_by': myId,
    });
    final subj = subjectById(subjectId)?.name;
    await autoAnnounce(
      type == 'holiday' ? 'New holiday' : 'New deadline',
      '$title on ${fmtDate(date)}${subj != null ? ' ($subj)' : ''}.'
      '${description != null && description.trim().isNotEmpty ? '\n${description.trim()}' : ''}',
      subjectId: type == 'deadline' ? subjectId : null,
    );
    await _after();
  }

  Future<void> deleteEvent(CalEvent e) async {
    await db.from('calendar_events').delete().eq('id', e.id);
    await autoAnnounce(
        e.type == 'holiday' ? 'Holiday removed' : 'Deadline removed',
        '${e.title} (${fmtDate(parseYmd(e.date))}) was removed.');
    await _after();
  }

  Future<void> addExam({
    required String examName,
    required Subject subject,
    required DateTime date,
    required String start,
    required String end,
    String? room,
  }) async {
    await db.from('exam_papers').insert({
      'class_id': cls.id,
      'exam_name': examName,
      'subject_id': subject.id,
      'exam_date': ymd(date),
      'start_time': start,
      'end_time': end,
      'room': (room == null || room.trim().isEmpty) ? null : room.trim(),
      'created_by': myId,
    });
    await autoAnnounce(
        'Exam scheduled: $examName',
        '${subject.name} on ${fmtDate(date)}, ${fmtTime(start)} - ${fmtTime(end)}'
        '${room != null && room.trim().isNotEmpty ? ', ${room.trim()}' : ''}.');
    await _after();
  }

  Future<void> deleteExam(ExamPaper e) async {
    await db.from('exam_papers').delete().eq('id', e.id);
    await autoAnnounce('Exam removed',
        '${subjectById(e.subjectId)?.name ?? 'An exam'} (${e.examName}) on ${fmtDate(parseYmd(e.date))} was removed.');
    await _after();
  }

  // ---------- files ----------
  Future<Attachment> uploadFile(PlatformFile f) async {
    if (f.path == null) throw Exception('Could not read that file.');
    if (f.size > maxUploadBytes) {
      throw Exception('${f.name} is larger than ${maxUploadBytes ~/ 1024 ~/ 1024} MB.');
    }
    final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${cls.id}/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await db.storage.from('class-files').upload(path, File(f.path!));
    return Attachment(name: f.name, path: path, size: f.size);
  }

  Future<void> openFile(String path, String name) async {
    final url = await db.storage.from('class-files').createSignedUrl(path, 600);
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode}).');
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(res.bodyBytes);
    final r = await OpenFilex.open(file.path);
    if (r.type != ResultType.done) {
      throw Exception('No app found to open this file (${r.message}).');
    }
  }

  // ---------- announcements ----------
  Future<void> postAnnouncement({
    String? subjectId,
    required String title,
    String? body,
    List<PlatformFile> files = const [],
  }) async {
    final atts = <Attachment>[];
    for (final f in files) {
      atts.add(await uploadFile(f));
    }
    await db.from('announcements').insert({
      'class_id': cls.id,
      'subject_id': subjectId,
      'title': title,
      'body': (body == null || body.trim().isEmpty) ? null : body.trim(),
      'attachments': atts.map((a) => a.toJson()).toList(),
      'is_auto': false,
      'created_by': myId,
    });
    await _after();
  }

  Future<void> deleteAnnouncement(Announcement a) async {
    await db.from('announcements').delete().eq('id', a.id);
    await _after();
  }

  // ---------- notes ----------
  Future<void> uploadNote({
    required Subject subject,
    required String label,
    required PlatformFile file,
  }) async {
    final att = await uploadFile(file);
    final previous = await db.from('notes')
        .select('id, version_group_id, version_number')
        .eq('class_id', cls.id)
        .eq('subject_id', subject.id)
        .eq('title', label)
        .order('version_number', ascending: false)
        .limit(1)
        .maybeSingle();
    await db.from('notes').insert({
      'class_id': cls.id,
      'subject_id': subject.id,
      'title': label,
      'file_path': att.path,
      'file_name': att.name,
      'file_size': att.size,
      'uploaded_by': myId,
      if (previous != null) ...{
        'version_group_id': previous['version_group_id'],
        'version_number': (previous['version_number'] as int) + 1,
        'supersedes_id': previous['id'],
      },
    });
    await autoAnnounce('New notes in ${subject.name}',
        '"$label" was uploaded by ${nameOf(myId)}. Open the Notes tab to view it.',
        subjectId: subject.id);
    await _after();
  }

  Future<void> deleteNote(Note n) async {
    await db.from('notes').delete().eq('id', n.id);
    try {
      await db.storage.from('class-files').remove([n.filePath]);
    } catch (_) {}
    await _after();
  }

  // ---------- class management ----------
  Future<void> leaveClass() async {
    final table = isTeacher ? 'class_teachers' : 'class_students';
    await db.from(table).delete().eq('class_id', cls.id).eq('user_id', myId);
  }

  Future<void> removeStudent(String userId) async {
    if (cls.creatorId != myId) {
      throw Exception('Only the class creator can remove students.');
    }
    await db.from('class_students').delete()
        .eq('class_id', cls.id).eq('user_id', userId);
    await _after();
  }

  Future<void> transferOwnership(String newCreatorId) async {
    if (cls.creatorId != myId) {
      throw Exception('Only the current creator can transfer ownership.');
    }
    await db.rpc('transfer_class_ownership', params: {
      'p_class': cls.id,
      'p_new_creator': newCreatorId,
    });
  }

  Future<void> scheduleDelete() => db.rpc('schedule_class_delete', params: {'p_class': cls.id});
  Future<void> cancelDelete() => db.rpc('cancel_class_delete', params: {'p_class': cls.id});
}
