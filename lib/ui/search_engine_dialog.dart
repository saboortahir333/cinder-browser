import 'package:flutter/material.dart';

import 'package:saboor_browser/browser/search_engines.dart';
import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/services/app_services.dart';

/// Lets the user pick the default search engine (or a validated custom one)
/// and stores the choice in the encrypted cloud store.
Future<void> showSearchEngineDialog(
  BuildContext context,
  BrowserPalette palette,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SearchEngineDialog(palette: palette),
  );
}

class _SearchEngineDialog extends StatefulWidget {
  const _SearchEngineDialog({required this.palette});

  final BrowserPalette palette;

  @override
  State<_SearchEngineDialog> createState() => _SearchEngineDialogState();
}

class _SearchEngineDialogState extends State<_SearchEngineDialog> {
  late String _selected = AppServices.searchEngine.isCustom
      ? 'custom'
      : AppServices.searchEngine.id;
  final _name = TextEditingController();
  final _template = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = AppServices.searchEngine;
    if (current.isCustom) {
      _name.text = current.name;
      _template.text = current.template;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _template.dispose();
    super.dispose();
  }

  void _save() {
    SearchEngine engine;
    if (_selected == 'custom') {
      final problem = SearchEngine.validateTemplate(_template.text.trim());
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      engine = SearchEngines.customFromStored(
        _name.text,
        _template.text.trim(),
      )!;
    } else {
      engine = SearchEngines.byId(_selected);
    }
    AppServices.searchEngine = engine;
    AppServices.cloud.put('setting', 'search', {
      'engine': engine.id,
      if (engine.isCustom) 'customName': engine.name,
      if (engine.isCustom) 'customTemplate': engine.template,
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return AlertDialog(
      backgroundColor: p.raised,
      title: Text('Search engine', style: TextStyle(color: p.ink)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<String>(
                groupValue: _selected,
                onChanged: (v) => setState(() {
                  _selected = v ?? _selected;
                  _error = null;
                }),
                child: Column(
                  children: [
                    for (final e in SearchEngines.builtIn)
                      RadioListTile<String>(
                        dense: true,
                        value: e.id,
                        title: Text(e.name, style: TextStyle(color: p.ink)),
                      ),
                    RadioListTile<String>(
                      dense: true,
                      value: 'custom',
                      title: Text('Custom', style: TextStyle(color: p.ink)),
                    ),
                  ],
                ),
              ),
              if (_selected == 'custom') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _template,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'https://example.com/search?q=%s',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB42318)),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
