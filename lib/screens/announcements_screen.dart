import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../logic/class_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

class AnnouncementsScreen extends StatefulWidget {
  final ClassController c;
  const AnnouncementsScreen({super.key, required this.c});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  String? _subjectId; // null = whole class feed (everything)

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final list = _subjectId == null
        ? c.announcements
        : c.announcements.where((a) => a.subjectId == _subjectId).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: c.isTeacher
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ComposeAnnouncementScreen(c: c, initialSubjectId: _subjectId))),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Post'),
            )
          : null,
      body: Column(children: [
        const SizedBox(height: 4),
        SubjectChips(
          subjects: c.subjects,
          selectedId: _subjectId,
          allLabel: 'Whole class',
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
                        icon: Icons.campaign_outlined,
                        title: _subjectId == null ? 'Nothing posted yet' : 'No posts for this subject',
                        message: c.isTeacher
                            ? 'Post an update, or change the timetable, calendar or notes and the class is told automatically.'
                            : 'Announcements and automatic updates will show up here.',
                      ),
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _AnnouncementCard(c: c, a: list[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final ClassController c;
  final Announcement a;
  const _AnnouncementCard({required this.c, required this.a});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subject = c.subjectById(a.subjectId);
    final accent = a.isAuto ? cs.onSurfaceVariant : (subject != null ? colorFromHex(subject.colorHex) : Brand.primary);
    final mine = !a.isAuto && c.isTeacher && (a.createdBy == myId || c.cls.creatorId == myId);

    return Panel(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (a.isAuto) Tag('Automatic', color: cs.onSurfaceVariant, icon: Icons.bolt_rounded),
                  if (subject != null) ...[
                    if (a.isAuto) const SizedBox(width: 6),
                    Flexible(child: Tag(subject.name, color: colorFromHex(subject.colorHex))),
                  ],
                  if (!a.isAuto && subject == null) const Tag('Whole class', color: Brand.primary),
                  const Spacer(),
                  Text(timeAgo(a.createdAt), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  if (mine)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, size: 20, color: cs.onSurfaceVariant),
                      onSelected: (action) async {
                        if (action == 'copy') {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ComposeAnnouncementScreen(
                              c: c,
                              initialSubjectId: a.subjectId,
                              copyFrom: a,
                            ),
                          ));
                        } else if (action == 'del') {
                          if (await confirm(context, 'Delete this post?', 'Everyone in the class will no longer see it.',
                              yes: 'Delete', danger: true)) {
                            if (context.mounted) await guarded(context, () => c.deleteAnnouncement(a));
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'copy', child: Text('Create a new announcement from this')),
                        PopupMenuItem(value: 'del', child: Text('Delete')),
                      ],
                    )
                  else
                    const SizedBox(width: 8),
                ]),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(a.title, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (a.body != null && a.body!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(a.body!, style: TextStyle(height: 1.4, color: cs.onSurface.withValues(alpha: 0.85))),
                  ),
                ],
                if (a.attachments.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final f in a.attachments)
                      ActionChip(
                        avatar: const Icon(Icons.attach_file_rounded, size: 16),
                        label: Text('${f.name}${f.size != null ? '  ${sizeStr(f.size)}' : ''}',
                            overflow: TextOverflow.ellipsis),
                        onPressed: () => guarded(context, () => c.openFile(f.path, f.name)),
                      ),
                  ]),
                ],
                const SizedBox(height: 8),
                Text('${a.isAuto ? 'By' : 'Posted by'} ${c.nameOf(a.createdBy)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class ComposeAnnouncementScreen extends StatefulWidget {
  final ClassController c;
  final String? initialSubjectId;
  final Announcement? copyFrom;
  const ComposeAnnouncementScreen({super.key, required this.c, this.initialSubjectId, this.copyFrom});
  @override
  State<ComposeAnnouncementScreen> createState() => _ComposeAnnouncementScreenState();
}

class _ComposeAnnouncementScreenState extends State<ComposeAnnouncementScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _subjectId; // null = whole class
  final List<PlatformFile> _files = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final mine = widget.c.manageableSubjects.map((s) => s.id).toSet();
    _subjectId = mine.contains(widget.initialSubjectId) ? widget.initialSubjectId : null;
    if (widget.copyFrom != null) {
      _title.text = widget.copyFrom!.title;
      _body.text = widget.copyFrom!.body ?? '';
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r != null) setState(() => _files.addAll(r.files));
  }

  Future<void> _post() async {
    if (_title.text.trim().isEmpty) {
      snack(context, 'Add a title.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.c.postAnnouncement(
        subjectId: _subjectId,
        title: _title.text.trim(),
        body: _body.text,
        files: _files,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      snack(context, friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.c.manageableSubjects;
    return Scaffold(
      appBar: AppBar(title: Text(widget.copyFrom == null ? 'New announcement' : 'Create new announcement')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        const Text('Post to', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            label: const Text('Whole class'),
            selected: _subjectId == null,
            onSelected: (_) => setState(() => _subjectId = null),
          ),
          for (final s in mine)
            ChoiceChip(
              avatar: CircleAvatar(radius: 5, backgroundColor: colorFromHex(s.colorHex)),
              label: Text(s.name),
              selected: _subjectId == s.id,
              onSelected: (_) => setState(() => _subjectId = s.id),
            ),
        ]),
        if (mine.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Add your subject in class details to post subject updates.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        const SizedBox(height: 20),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _body,
          minLines: 4,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Message (optional)', alignLabelWithHint: true),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _files.length; i++)
            InputChip(
              avatar: const Icon(Icons.attach_file_rounded, size: 16),
              label: Text(_files[i].name, overflow: TextOverflow.ellipsis),
              onDeleted: () => setState(() => _files.removeAt(i)),
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Attach file'),
            onPressed: _pick,
          ),
        ]),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _busy ? null : _post,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Post announcement'),
        ),
      ]),
    );
  }
}
