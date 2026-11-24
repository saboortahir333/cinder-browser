import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/services/account_service.dart';
import 'package:saboor_browser/services/app_services.dart';

Future<void> showAccountDialog(BuildContext context, BrowserPalette palette) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _AccountDialog(palette: palette),
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.palette});

  final BrowserPalette palette;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  final _recoveryInput = TextEditingController();

  bool _busy = false;
  bool _useRecovery = false;
  bool _obscure = true;
  bool _savedRecoveryKey = false;
  bool _copiedRecoveryKey = false;
  String? _error;
  String? _info;

  /// Shown once after vault creation, then dropped.
  String? _recoveryKey;

  AccountService get _account => AppServices.account;
  BrowserPalette get _p => widget.palette;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passphrase.dispose();
    _confirm.dispose();
    _recoveryInput.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AccountResult> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) {
        _error = result.message;
      } else {
        _info = result.message;
        _recoveryKey = result.recoveryKey ?? _recoveryKey;
        _password.clear();
        _passphrase.clear();
        _confirm.clear();
        _recoveryInput.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _p.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AnimatedBuilder(
          animation: _account,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_recoveryKey != null)
                  ..._recoveryKeyView()
                else
                  ...switch (_account.state) {
                    AccountState.guest => _guestView(),
                    AccountState.needsVaultSetup => _setupView(),
                    AccountState.locked => _lockedView(),
                    AccountState.unlocked => _unlockedView(),
                  },
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Text(_info!, style: TextStyle(color: _p.ink)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- views ----------------------------------------------------------------

  List<Widget> _guestView() => [
    _title('Sign in to sync'),
    _body(
      'You are browsing as a guest: nothing is saved. Sign in to sync '
      'history, bookmarks, open tabs and settings across devices. Your data '
      'is end-to-end encrypted before it leaves this computer.',
    ),
    const SizedBox(height: 16),
    _field(_email, 'E-mail', keyboard: TextInputType.emailAddress),
    const SizedBox(height: 10),
    _field(_password, 'Account password (12+ characters)', secret: true),
    const SizedBox(height: 16),
    Row(
      children: [
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() => _account.signIn(_email.text, _password.text)),
          child: const Text('Sign in'),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() => _account.signUp(_email.text, _password.text)),
          child: const Text('Create account'),
        ),
        if (_busy) ...[const SizedBox(width: 12), _spinner()],
      ],
    ),
  ];

  List<Widget> _setupView() => [
    _title('Create your sync passphrase'),
    _body(
      'This passphrase encrypts your data on this device. Cinder and our '
      'servers never see it and cannot reset it. You will also get a '
      'one-time recovery key in case you forget it.',
    ),
    const SizedBox(height: 16),
    _field(_passphrase, 'Sync passphrase (12+ characters)', secret: true),
    const SizedBox(height: 10),
    _field(_confirm, 'Repeat passphrase', secret: true),
    const SizedBox(height: 16),
    Row(
      children: [
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (_passphrase.text != _confirm.text) {
                    setState(() => _error = 'The passphrases do not match.');
                    return;
                  }
                  _run(() => _account.createVault(_passphrase.text));
                },
          child: const Text('Create vault'),
        ),
        const SizedBox(width: 10),
        TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
        if (_busy) ...[const SizedBox(width: 12), _spinner()],
      ],
    ),
  ];

  List<Widget> _lockedView() => [
    _title('Unlock your synced data'),
    _body(
      'Signed in as ${_account.email ?? 'your account'}. Enter your sync '
      'passphrase to decrypt your data on this device.',
    ),
    const SizedBox(height: 16),
    if (!_useRecovery)
      _field(_passphrase, 'Sync passphrase', secret: true)
    else
      _field(_recoveryInput, 'Recovery key (XXXX-XXXX-…)'),
    const SizedBox(height: 16),
    Row(
      children: [
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _useRecovery
                      ? _account.unlockWithRecoveryKey(_recoveryInput.text)
                      : _account.unlock(_passphrase.text),
                ),
          child: const Text('Unlock'),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _useRecovery = !_useRecovery;
                  _error = null;
                }),
          child: Text(_useRecovery ? 'Use passphrase' : 'Use recovery key'),
        ),
        TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
        if (_busy) ...[const SizedBox(width: 12), _spinner()],
      ],
    ),
  ];

  List<Widget> _unlockedView() => [
    _title('Sync is on'),
    _body(
      'Signed in as ${_account.email ?? 'your account'}. History, bookmarks, '
      'tabs and settings are end-to-end encrypted and synced. Nothing is '
      'stored on this computer except the browser engine\'s cookies/cache '
      'and your sign-in token (protected by Windows).',
    ),
    const SizedBox(height: 16),
    Text('Change sync passphrase', style: _label()),
    const SizedBox(height: 8),
    _field(_passphrase, 'New passphrase (12+ characters)', secret: true),
    const SizedBox(height: 8),
    Row(
      children: [
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() => _account.changePassphrase(_passphrase.text)),
          child: const Text('Update passphrase'),
        ),
        const Spacer(),
        FilledButton.tonal(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
  ];

  List<Widget> _recoveryKeyView() => [
    _title('Save your recovery key'),
    _body(
      'If you forget your sync passphrase, this key is the ONLY way to get '
      'your data back. It is shown once. Store it somewhere safe, such as a '
      'password manager or a printed copy.',
    ),
    const SizedBox(height: 16),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _p.chrome,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _p.soft),
      ),
      child: SelectableText(
        _recoveryKey!,
        style: TextStyle(
          color: _p.ink,
          fontSize: 16,
          fontFamily: 'Consolas',
          letterSpacing: 1.2,
        ),
      ),
    ),
    const SizedBox(height: 10),
    Row(
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy'),
          onPressed: () {
            _copiedRecoveryKey = true;
            Clipboard.setData(ClipboardData(text: _recoveryKey!));
          },
        ),
      ],
    ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _savedRecoveryKey,
      onChanged: (v) => setState(() => _savedRecoveryKey = v ?? false),
      title: Text('I have saved my recovery key', style: TextStyle(color: _p.ink)),
    ),
    FilledButton(
      onPressed: _savedRecoveryKey
          ? () {
              setState(() => _recoveryKey = null);
              // Do not leave the recovery key on the clipboard.
              if (_copiedRecoveryKey) {
                Clipboard.setData(const ClipboardData(text: ''));
                _copiedRecoveryKey = false;
              }
            }
          : null,
      child: const Text('Done'),
    ),
  ];

  // -- helpers --------------------------------------------------------------

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _account.signOut();
    if (mounted) setState(() => _busy = false);
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(color: _p.ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),
  );

  Widget _body(String text) =>
      Text(text, style: TextStyle(color: _p.muted, fontSize: 13, height: 1.4));

  TextStyle _label() =>
      TextStyle(color: _p.ink, fontSize: 13, fontWeight: FontWeight.w600);

  Widget _spinner() => SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: _p.accent),
  );

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool secret = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      obscureText: secret && _obscure,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: keyboard,
      style: TextStyle(color: _p.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _p.muted),
        filled: true,
        fillColor: _p.chrome,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _p.soft),
        ),
        suffixIcon: secret
            ? IconButton(
                tooltip: _obscure ? 'Show' : 'Hide',
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
    );
  }
}
