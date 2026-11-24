import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:saboor_browser/extensions/content_script_builder.dart';
import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/permissions.dart';

/// Per-extension `chrome.storage`. Persisted for normal windows; memory-only
/// in private windows so nothing is written to disk.
class ExtensionStorage {
  ExtensionStorage({File? file}) : _file = file {
    if (file != null && file.existsSync() && file.lengthSync() < maxTotalBytes * 2) {
      try {
        final d = jsonDecode(file.readAsStringSync());
        if (d is Map<String, dynamic>) _local.addAll(d);
      } catch (_) {}
    }
  }

  static const int maxTotalBytes = 10 * 1024 * 1024;
  static const int maxKeys = 4096;

  final File? _file;
  final Map<String, dynamic> _local = {};
  final Map<String, dynamic> _session = {};
  Timer? _flushTimer;

  Map<String, dynamic> _area(String area) =>
      area == 'session' ? _session : _local;

  static const Set<String> areas = {'local', 'sync', 'session'};

  Map<String, dynamic> get(String area, Object? keys) {
    final a = _area(area);
    final out = <String, dynamic>{};
    if (keys == null) {
      out.addAll(a);
    } else if (keys is String) {
      if (a.containsKey(keys)) out[keys] = a[keys];
    } else if (keys is List) {
      for (final k in keys) {
        if (k is String && a.containsKey(k)) out[k] = a[k];
      }
    } else if (keys is Map) {
      keys.forEach((k, v) => out['$k'] = a.containsKey(k) ? a[k] : v);
    }
    return jsonDecode(jsonEncode(out)) as Map<String, dynamic>;
  }

  /// Returns the change record for `storage.onChanged`.
  Map<String, dynamic> set(String area, Map<String, dynamic> items) {
    final a = _area(area);
    final changes = <String, dynamic>{};
    final next = Map<String, dynamic>.of(a);
    items.forEach((k, v) {
      changes[k] = {if (a.containsKey(k)) 'oldValue': a[k], 'newValue': v};
      next[k] = v;
    });
    if (next.length > maxKeys || utf8.encode(jsonEncode(next)).length > maxTotalBytes) {
      throw StateError('QUOTA_BYTES quota exceeded');
    }
    a
      ..clear()
      ..addAll(next);
    _scheduleFlush(area);
    return changes;
  }

  void remove(String area, Object? keys) {
    final a = _area(area);
    for (final k in keys is List ? keys : [keys]) {
      a.remove(k);
    }
    _scheduleFlush(area);
  }

  void clear(String area) {
    _area(area).clear();
    _scheduleFlush(area);
  }

  void _scheduleFlush(String area) {
    if (_file == null || area == 'session') return;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), flush);
  }

  void flush() {
    final f = _file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.tmp')..writeAsStringSync(jsonEncode(_local), flush: true);
      if (f.existsSync()) f.deleteSync();
      tmp.renameSync(f.path);
    } catch (_) {}
  }
}

/// What the browser provides to extension pages.
abstract class BridgeHost {
  /// The active tab as the extension may see it, or null.
  ({int id, String url, String title})? activeTab();
  void openTab(String url);
  void openOptionsPage(InstalledExtension ext);
  void resizePopup(int width, int height);
  void closePopup();
  Future<void> writeClipboard(String text);
}

class BridgeException implements Exception {
  const BridgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Handles messages from an extension page. Every message is attacker-shaped
/// data from an extension, so each field is validated and each method is
/// permission-checked.
class ExtensionBridge {
  ExtensionBridge({required this.ext, required this.storage, required this.host});

  final InstalledExtension ext;
  final ExtensionStorage storage;
  final BridgeHost host;

  static const int maxMessageChars = 1024 * 1024;

  /// Returns the JSON text to send back to the page.
  Future<String> handle(Object? raw) async {
    Object? id;
    try {
      if (raw is String) {
        if (raw.length > maxMessageChars) throw const BridgeException('Message too large.');
        raw = jsonDecode(raw);
      }
      if (raw is! Map || raw['cinderExt'] != true) {
        throw const BridgeException('Not an extension message.');
      }
      id = raw['id'];
      if (id is! int) throw const BridgeException('Bad request id.');
      final method = raw['method'];
      if (method is! String || method.length > 64) throw const BridgeException('Bad method.');
      final args = raw['args'] is Map ? Map<String, dynamic>.from(raw['args'] as Map) : <String, dynamic>{};
      final result = await _dispatch(method, args);
      return jsonEncode({'cinderExtReply': true, 'id': id, 'ok': true, 'result': result});
    } on BridgeException catch (e) {
      return jsonEncode({'cinderExtReply': true, 'id': id, 'ok': false, 'error': e.message});
    } catch (e) {
      return jsonEncode({'cinderExtReply': true, 'id': id, 'ok': false, 'error': e is StateError ? e.message : 'Request failed.'});
    }
  }

  bool _can(String permission) =>
      PermissionPolicy.hasApi(ext.manifest, ext.grants, permission);

  void _needs(String permission) {
    if (!_can(permission)) {
      throw BridgeException("The extension does not have the '$permission' permission.");
    }
  }

  String _area(Map<String, dynamic> a) {
    final area = a['area'];
    if (area is! String || !ExtensionStorage.areas.contains(area)) {
      throw const BridgeException('Unknown storage area.');
    }
    return area;
  }

  Future<Object?> _dispatch(String method, Map<String, dynamic> a) async {
    switch (method) {
      case 'storage.get':
        _needs('storage');
        return storage.get(_area(a), a['keys']);
      case 'storage.set':
        _needs('storage');
        final items = a['items'];
        if (items is! Map) throw const BridgeException('Invalid items.');
        return storage.set(_area(a), Map<String, dynamic>.from(items));
      case 'storage.remove':
        _needs('storage');
        final keys = a['keys'];
        if (keys is! String && keys is! List) throw const BridgeException('Invalid keys.');
        storage.remove(_area(a), keys);
        return null;
      case 'storage.clear':
        _needs('storage');
        storage.clear(_area(a));
        return null;
      case 'tabs.query':
        final t = host.activeTab();
        if (t == null) return <Object>[];
        // URL and title only with the `tabs` permission or an activeTab grant
        // for this origin (the user opened the popup by clicking its button).
        final reveal = _can('tabs') ||
            (_can('activeTab') &&
                ext.grants.activeTabOrigins.contains(PermissionPolicy.originOf(t.url)));
        return [
          {
            'id': t.id,
            'active': true,
            'currentWindow': true,
            if (reveal) 'url': t.url,
            if (reveal) 'title': t.title,
          },
        ];
      case 'tabs.create':
        final url = a['url'];
        if (url is! String || url.length > 4096) throw const BridgeException('Invalid url.');
        final u = Uri.tryParse(url);
        if (u == null || (u.scheme != 'https' && u.scheme != 'http')) {
          throw const BridgeException('Only http and https addresses can be opened.');
        }
        host.openTab(url);
        return null;
      case 'runtime.openOptionsPage':
        if (ext.manifest.optionsPage == null) {
          throw const BridgeException('This extension has no options page.');
        }
        host.openOptionsPage(ext);
        return null;
      case 'clipboard.writeText':
        _needs('clipboardWrite');
        final text = a['text'];
        if (text is! String || text.length > 1024 * 1024) throw const BridgeException('Invalid text.');
        await host.writeClipboard(text);
        return null;
      case 'popup.resize':
        final w = a['width'], h = a['height'];
        if (w is num && h is num && w.isFinite && h.isFinite) {
          host.resizePopup(w.round().clamp(120, 800), h.round().clamp(60, 600));
        }
        return null;
      case 'popup.close':
        host.closePopup();
        return null;
      default:
        throw BridgeException("'$method' is not supported by Cinder.");
    }
  }
}

/// JavaScript injected into every extension page before its own scripts.
class ExtensionPageShim {
  const ExtensionPageShim._();

  static String script(InstalledExtension ext) {
    final host = extensionHost(ext.id);
    final manifest = jsonEncode({
      'manifest_version': 3,
      'name': ext.manifest.name,
      'version': ext.manifest.version,
      'description': ext.manifest.description,
      'permissions': ext.manifest.permissions,
      'host_permissions': ext.manifest.hostPermissions,
    });
    return '''
(function(){
if(location.host!=='$host')return;
var pending={},seq=1,wv=window.chrome&&window.chrome.webview;
if(!wv)return;
var messages=${jsonEncode(ext.locale.all)};
var manifest=$manifest;
// Extension pages may not run inline or remote script (MV3 default CSP).
try{var m=document.createElement('meta');m.httpEquiv='Content-Security-Policy';
m.content="script-src 'self' 'wasm-unsafe-eval'; object-src 'self'";
(document.head||document.documentElement).appendChild(m);}catch(e){}
wv.addEventListener('message',function(ev){var d=ev.data;if(typeof d==='string'){try{d=JSON.parse(d);}catch(e){return;}}
if(!d||d.cinderExtReply!==true)return;var p=pending[d.id];if(!p)return;delete pending[d.id];
if(d.ok){p.resolve(d.result);}else{p.reject(new Error(d.error||'Request failed'));}});
function call(method,args){return new Promise(function(resolve,reject){var id=seq++;pending[id]={resolve:resolve,reject:reject};
wv.postMessage(JSON.stringify({cinderExt:true,id:id,method:method,args:args||{}}));});}
function cbify(fn){return function(){var a=[].slice.call(arguments);var last=a[a.length-1];
if(typeof last==='function'){a.pop();var cb=last;fn.apply(null,a).then(function(r){chrome.runtime.lastError=undefined;cb(r);},function(e){chrome.runtime.lastError={message:e.message};cb();chrome.runtime.lastError=undefined;});return;}
return fn.apply(null,a);};}
var listeners=[];
function area(name){return{
get:cbify(function(k){return call('storage.get',{area:name,keys:k===undefined?null:k});}),
set:cbify(function(i){return call('storage.set',{area:name,items:i}).then(function(ch){listeners.forEach(function(l){try{l(ch,name);}catch(e){}});});}),
remove:cbify(function(k){return call('storage.remove',{area:name,keys:k});}),
clear:cbify(function(){return call('storage.clear',{area:name});})};}
var chrome={runtime:{id:'${ext.id}',lastError:undefined,
getManifest:function(){return JSON.parse(JSON.stringify(manifest));},
getURL:function(p){return location.origin+'/'+String(p).replace(/^\\/+/,'');},
openOptionsPage:cbify(function(){return call('runtime.openOptionsPage');}),
sendMessage:function(){return Promise.reject(new Error('Extension messaging is not available in Cinder yet.'));},
onMessage:{addListener:function(){},removeListener:function(){},hasListener:function(){return false;}}},
i18n:{getMessage:function(k){var v=messages[String(k).toLowerCase()];return v===undefined?'':v;},getUILanguage:function(){return navigator.language;}},
storage:{local:area('local'),sync:area('sync'),session:area('session'),
onChanged:{addListener:function(f){listeners.push(f);},removeListener:function(f){listeners=listeners.filter(function(x){return x!==f;});},hasListener:function(f){return listeners.indexOf(f)>=0;}}},
tabs:{query:cbify(function(){return call('tabs.query');}),create:cbify(function(o){return call('tabs.create',{url:o&&o.url});})},
action:{setBadgeText:function(){},setBadgeBackgroundColor:function(){},setTitle:function(){},setIcon:function(){}}};
window.chrome=Object.assign(window.chrome||{},{runtime:chrome.runtime,i18n:chrome.i18n,storage:chrome.storage,tabs:chrome.tabs,action:chrome.action});
window.browser=chrome;
var close=window.close;window.close=function(){call('popup.close').catch(function(){});};
function report(){var d=document.documentElement,b=document.body;if(!b)return;
var w=Math.max(d.scrollWidth,b.scrollWidth),h=Math.max(d.scrollHeight,b.scrollHeight);
call('popup.resize',{width:w,height:h}).catch(function(){});}
window.addEventListener('load',function(){report();try{new ResizeObserver(report).observe(document.body);}catch(e){}});
})();
''';
  }
}

/// Convenience used by tests and the runtime to find a popup entry file.
File? popupFile(InstalledExtension ext) {
  final p = ext.manifest.popup;
  if (p == null) return null;
  final clean = p.split('#').first.split('?').first;
  final f = File('${ext.contentDir}${Platform.pathSeparator}${clean.replaceAll('/', Platform.pathSeparator)}');
  return f.existsSync() ? f : null;
}
