import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../util.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _signUp = false, _busy = false, _hide = true;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    final name = _name.text.trim();
    if (email.isEmpty || pass.isEmpty || (_signUp && name.isEmpty)) {
      snack(context, 'Fill in all the fields.');
      return;
    }
    if (_signUp && pass.length < 6) {
      snack(context, 'Password must be at least 6 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_signUp) {
        final res = await auth.signUp(
            email: email, password: pass, data: {'full_name': name});
        if (res.session == null && mounted) {
          snack(context,
              'Account created. Check your email to confirm, then sign in.');
          setState(() => _signUp = false);
        }
      } else {
        await auth.signInWithPassword(email: email, password: pass);
      }
    } on AuthException catch (e) {
      snack(context, e.message);
    } catch (e) {
      snack(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          // Hero: a timetable that is being filled in
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                28, MediaQuery.of(context).padding.top + 40, 28, 34),
            decoration: const BoxDecoration(
              color: Brand.ink,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Brand.marigold,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.school_rounded, color: Brand.ink),
                ),
                const SizedBox(width: 12),
                Text('CampusIQ',
                    style: text.titleLarge?.copyWith(color: Colors.white, fontSize: 22)),
              ]),
              const SizedBox(height: 34),
              Text('Your class,\nsorted.',
                  style: text.headlineMedium?.copyWith(
                      color: Colors.white, fontSize: 38, height: 1.05)),
              const SizedBox(height: 14),
              Text(
                'Timetable, deadlines, notes and announcements in one place for every teacher and student.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72), height: 1.45, fontSize: 15),
              ),
              const SizedBox(height: 26),
              Row(children: [
                for (final c in const [
                  Color(0xFF8E96FF), Color(0xFF5ED3C0), Color(0xFFFF8A8E), Brand.marigold
                ])
                  Expanded(
                    child: Container(
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                          color: c, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Sign in')),
                  ButtonSegment(value: true, label: Text('Create account')),
                ],
                selected: {_signUp},
                onSelectionChanged: (s) => setState(() => _signUp = s.first),
              ),
              const SizedBox(height: 22),
              if (_signUp) ...[
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pass,
                obscureText: _hide,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(_signUp ? 'Create account' : 'Sign in'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'One account works as a teacher in some classes and a student in another.',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
