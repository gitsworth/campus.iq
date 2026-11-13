import 'dart:convert';

class ClassRoom {
  final String id, name, studentCode, creatorId;
  final DateTime? deleteAfter;
  const ClassRoom({
    required this.id,
    required this.name,
    required this.studentCode,
    required this.creatorId,
    this.deleteAfter,
  });
  factory ClassRoom.fromJson(Map<String, dynamic> j) => ClassRoom(
        id: j['id'],
        name: j['name'],
        studentCode: j['student_code'],
        creatorId: j['creator_id'],
        deleteAfter: j['delete_after'] == null
            ? null
            : DateTime.parse(j['delete_after']).toLocal(),
      );
}

class Membership {
  final ClassRoom cls;
  final bool isTeacher;
  const Membership(this.cls, this.isTeacher);
}

class Subject {
  final String id, name, colorHex;
  final String? teacherId;
  final String? code;
  const Subject({
    required this.id,
    required this.name,
    required this.teacherId,
    required this.colorHex,
    this.code,
  });
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'],
        name: j['name'],
        code: j['code'],
        teacherId: j['teacher_id'],
        colorHex: j['color'] ?? '#3D4BDB',
      );
}

class TimeSlot {
  final String id, start, end;
  final String? label;
  final bool isBreak;
  const TimeSlot({
    required this.id,
    required this.start,
    required this.end,
    this.label,
    required this.isBreak,
  });
  factory TimeSlot.fromJson(Map<String, dynamic> j) => TimeSlot(
        id: j['id'],
        start: j['start_time'],
        end: j['end_time'],
        label: j['label'],
        isBreak: j['is_break'] ?? false,
      );
}

class TTEntry {
  final String id, slotId, subjectId;
  final int weekday;
  final String? room;
  const TTEntry({
    required this.id,
    required this.weekday,
    required this.slotId,
    required this.subjectId,
    this.room,
  });
  factory TTEntry.fromJson(Map<String, dynamic> j) => TTEntry(
        id: j['id'],
        weekday: j['weekday'],
        slotId: j['slot_id'],
        subjectId: j['subject_id'],
        room: j['room'],
      );
}

class DayOverride {
  final String id, date;
  final int? followWeekday;
  final String? note;
  const DayOverride({
    required this.id,
    required this.date,
    this.followWeekday,
    this.note,
  });
  factory DayOverride.fromJson(Map<String, dynamic> j) => DayOverride(
        id: j['id'],
        date: j['on_date'],
        followWeekday: j['follow_weekday'],
        note: j['note'],
      );
}

class SlotOverride {
  final String id, date, slotId;
  final String? subjectId, room, note;
  final bool cancelled;
  const SlotOverride({
    required this.id,
    required this.date,
    required this.slotId,
    this.subjectId,
    this.room,
    this.note,
    required this.cancelled,
  });
  factory SlotOverride.fromJson(Map<String, dynamic> j) => SlotOverride(
        id: j['id'],
        date: j['on_date'],
        slotId: j['slot_id'],
        subjectId: j['subject_id'],
        room: j['room'],
        note: j['note'],
        cancelled: j['cancelled'] ?? false,
      );
}

class CalEvent {
  final String id, title, date, type; // type: holiday | deadline
  final String? subjectId, description, createdBy;
  const CalEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    this.subjectId,
    this.description,
    this.createdBy,
  });
  factory CalEvent.fromJson(Map<String, dynamic> j) => CalEvent(
        id: j['id'],
        title: j['title'],
        date: j['event_date'],
        type: j['event_type'],
        subjectId: j['subject_id'],
        description: j['description'],
        createdBy: j['created_by'],
      );
}

class ExamPaper {
  final String id, examName, subjectId, date, start, end;
  final String? room;
  const ExamPaper({
    required this.id,
    required this.examName,
    required this.subjectId,
    required this.date,
    required this.start,
    required this.end,
    this.room,
  });
  factory ExamPaper.fromJson(Map<String, dynamic> j) => ExamPaper(
        id: j['id'],
        examName: j['exam_name'],
        subjectId: j['subject_id'],
        date: j['exam_date'],
        start: j['start_time'],
        end: j['end_time'],
        room: j['room'],
      );
}

class Attachment {
  final String name, path;
  final int? size;
  const Attachment({required this.name, required this.path, this.size});
  factory Attachment.fromJson(Map<String, dynamic> j) =>
      Attachment(name: j['name'], path: j['path'], size: j['size']);
  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'size': size};
}

class Announcement {
  final String id, title;
  final String? subjectId, body, createdBy;
  final List<Attachment> attachments;
  final bool isAuto;
  final DateTime createdAt;
  const Announcement({
    required this.id,
    required this.title,
    this.subjectId,
    this.body,
    this.createdBy,
    required this.attachments,
    required this.isAuto,
    required this.createdAt,
  });
  factory Announcement.fromJson(Map<String, dynamic> j) {
    var raw = j['attachments'];
    if (raw is String) raw = jsonDecode(raw);
    return Announcement(
      id: j['id'],
      title: j['title'],
      subjectId: j['subject_id'],
      body: j['body'],
      createdBy: j['created_by'],
      isAuto: j['is_auto'] ?? false,
      createdAt: DateTime.parse(j['created_at']).toLocal(),
      attachments: ((raw ?? []) as List)
          .map((e) => Attachment.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class Note {
  final String id, subjectId, title, filePath, fileName;
  final int? fileSize;
  final int versionNumber;
  final String? uploadedBy;
  final DateTime createdAt;
  const Note({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.filePath,
    required this.fileName,
    this.fileSize,
    this.versionNumber = 1,
    this.uploadedBy,
    required this.createdAt,
  });
  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'],
        subjectId: j['subject_id'],
        title: j['title'],
        filePath: j['file_path'],
        fileName: j['file_name'],
        fileSize: j['file_size'],
        versionNumber: j['version_number'] ?? 1,
        uploadedBy: j['uploaded_by'],
        createdAt: DateTime.parse(j['created_at']).toLocal(),
      );
}
