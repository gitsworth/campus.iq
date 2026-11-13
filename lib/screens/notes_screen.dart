import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/common.dart';

class NotesScreen extends StatefulWidget {
  final ClassController c;
  const NotesScreen({super.key, required this.c});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String? _subjectId;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final cs = Theme.of(context).colorScheme;
    final list = _subjectId == null ? c.notes : c.notes.where((n) => n.subjectId == _subjectId).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: c.isTeacher
          ? FloatingActionButton.extended(
              onPressed: () {
                if (c.manageableSubjects.isEmpty) {
                  snack(context, 'Add your subject first (i button, top right), then upload notes.');
                  return;
                }
                showSheet(context, (_) => _UploadSheet(c: c, initial: _subjectId));
              },
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Upload'),
            )
          : null,
      body: Column(children: [
        const SizedBox(height: 4),
        SubjectChips(
          subjects: c.subjects,
          selectedId: _subjectId,
          allLabel: 'All notes',
          onSelected: (id) => setState(() => _subjectId = id),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => c.load(silent: true),
            child: list.isEmpty
                ? ListView(children: [
                    SizedBox(
                      height: 360,
                      child: EmptyState(
                        icon: Icons.folder_open_outlined,
                        title: 'No notes yet',
                        message: c.isTeacher
                            ? 'Upload a file under one of your subjects. New uploads with the same subject and label become a new version.'
                            : 'Notes your teachers upload will appear here, sorted by subject.',
                      ),
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final n = list[i];
                      final s = c.subjectById(n.subjectId);
                      final color = s == null ? cs.primary : colorFromHex(s.colorHex);
                      return Panel(
                        onTap: () => guarded(context, () => c.openFile(n.filePath, n.fileName)),
                        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                        child: Row(children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: tint(context, color, 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(_iconFor(n.fileName), color: color),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${n.title}${n.versionNumber > 1 ? '  ·  v${n.versionNumber}' : ''}',
                                  style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Row(children: [
                                if (s != null) Flexible(child: Tag(s.name, color: color)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${n.fileName}  ${sizeStr(n.fileSize)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 3),
                              Text('${c.nameOf(n.uploadedBy)}, ${timeAgo(n.createdAt)}',
                                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                            ]),
                          ),
                          if (c.isTeacher && (n.uploadedBy == myId || c.cls.creatorId == myId))
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
                              onPressed: () async {
                                if (await confirm(context, 'Delete these notes?', 'The file will be removed for everyone.',
                                    yes: 'Delete', danger: true)) {
                                  if (context.mounted) await guarded(context, () => c.deleteNote(n));
                                }
                              },
                            )
                          else
                            Icon(Icons.download_rounded, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                        ]),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  IconData _iconFor(String name) {
    final e = name.toLowerCase().split('.').last;
    if (e == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['png', 'jpg', 'jpeg', 'webp'].contains(e)) return Icons.image_rounded;
    if (['ppt', 'pptx'].contains(e)) return Icons.slideshow_rounded;
    if (['xls', 'xlsx', 'csv'].contains(e)) return Icons.table_chart_rounded;
    if (['doc', 'docx', 'txt'].contains(e)) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }
}

class _UploadSheet extends StatefulWidget {
  final ClassController c;
  final String? initial;
  const _UploadSheet({required this.c, this.initial});
  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _label = TextEditingController();
  Subject? _subject;
  PlatformFile? _file;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final mine = widget.c.manageableSubjects;
    _subject = mine.where((s) => s.id == widget.initial).firstOrNull ?? (mine.length == 1 ? mine.first : null);
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles();
    if (r != null && r.files.isNotEmpty) {
      setState(() {
        _file = r.files.first;
        if (_label.text.isEmpty) {
          _label.text = _file!.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
        }
      });
    }
  }

  Future<void> _save() async {
    if (_subject == null || _file == null || _label.text.trim().isEmpty) {
      snack(context, 'Pick a subject, a file and give it a label.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await widget.c.uploadNote(subject: _subject!, label: _label.text.trim(), file: _file!);
      nav.pop();
    } catch (e) {
      snack(context, friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.c.manageableSubjects;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Upload notes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          const Text('Subject', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in mine)
              ChoiceChip(
                avatar: CircleAvatar(radius: 5, backgroundColor: colorFromHex(s.colorHex)),
                label: Text(s.name),
                selected: _subject?.id == s.id,
                onSelected: (_) => setState(() => _subject = s),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Label', helperText: 'e.g. Unit 3 - Trees and graphs. Students and the assistant search by this.'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(_file == null ? 'Choose file' : '${_file!.name}  (${sizeStr(_file!.size)})',
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Upload and announce'),
          ),
        ]),
      ),
    );
  }
}
