import 'dart:convert';
import 'dart:io';

import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/manifest.dart';
import 'package:saboor_browser/extensions/match_pattern.dart';
import 'package:saboor_browser/extensions/permissions.dart';

/// Virtual host used for an extension's own pages (popup, options).
String extensionHost(String id) => '$id.extension.cinder.local';

/// Builds the JavaScript registered with `addScriptToExecuteOnDocumentCreated`
/// for one extension.
///
/// Honest limitations (see docs/extensions.md):
///  * Content scripts run in the page's main world (the WebView2 plugin has
///    no isolated worlds), so they get a *minimal* `chrome` object with no
///    privileged bridge: nothing secret is reachable from the page.
///  * Privileged APIs (storage, tabs) exist only in extension pages (popup)
///    served from the extension's own origin.
class ContentScriptBuilder {
  const ContentScriptBuilder._();

  static const int maxSourceBytes = 8 * 1024 * 1024;

  /// Returns null when there is nothing to inject.
  ///
  /// [force] skips the site gate and run_at timing; used for "run now" after
  /// the user clicks the toolbar button on an "on click" extension.
  static String? build(InstalledExtension ext, {bool force = false}) {
    final m = ext.manifest;
    if (m.contentScripts.isEmpty) return null;
    final g = ext.grants;
    if (!force && g.siteAccess == SiteAccess.onClick) return null;

    // Effective gate: the user's chosen sites narrow what the manifest asks for.
    final gate = (!force && g.siteAccess == SiteAccess.onSpecificSites)
        ? g.specificSites
            .map(MatchPattern.tryParse)
            .whereType<MatchPattern>()
            .map((p) => p.toJsRegexSource())
            .toList()
        : null;
    if (gate != null && gate.isEmpty) return null;

    final entries = StringBuffer();
    var total = 0;
    for (final cs in m.contentScripts) {
      final matches = cs.matches
          .map(MatchPattern.tryParse)
          .whereType<MatchPattern>()
          .map((p) => p.toJsRegexSource())
          .toList();
      if (matches.isEmpty) continue;
      final excludes = cs.excludeMatches
          .map(MatchPattern.tryParse)
          .whereType<MatchPattern>()
          .map((p) => p.toJsRegexSource())
          .toList();
      final css = <String>[];
      for (final rel in cs.css) {
        final t = _read(ext.contentDir, rel);
        total += t.length;
        css.add(t);
      }
      final js = StringBuffer();
      for (final rel in cs.js) {
        final t = _read(ext.contentDir, rel);
        total += t.length;
        js.write('function(chrome,browser){\n$t\n},\n');
      }
      if (total > maxSourceBytes) return null;
      entries.write(
        '{m:${jsonEncode(matches)},x:${jsonEncode(excludes)},'
        'all:${cs.allFrames},run:${jsonEncode(switch (cs.runAt) {
          RunAt.documentStart => 'start',
          RunAt.documentEnd => 'end',
          RunAt.documentIdle => 'idle',
        })},css:${jsonEncode(css)},js:[$js]},\n',
      );
    }
    if (entries.isEmpty) return null;

    final messages = jsonEncode(ext.locale.all);
    final manifestJson = jsonEncode(_publicManifest(m));
    final guard = '__cx_${ext.id}';
    return '''
(function(){
'use strict';
try{
var href=location.href.split('#')[0];
if(/^https:\\/\\/(chromewebstore\\.google\\.com|chrome\\.google\\.com\\/webstore)/.test(href))return;
var FORCE=${force ? 'true' : 'false'};
function any(list,s){for(var i=0;i<list.length;i++){try{if(new RegExp(list[i]).test(s))return true;}catch(e){}}return false;}
var gate=${gate == null ? 'null' : jsonEncode(gate)};
if(!FORCE&&gate&&!any(gate,href))return;
var top_=false;try{top_=window===window.top;}catch(e){}
var messages=$messages;
var manifest=$manifestJson;
function mem(){var s={};function cb(f,v){if(typeof f==='function'){f(v);return;}return Promise.resolve(v);}
return{get:function(k,f){var o={};if(k===null||k===undefined){for(var a in s)o[a]=s[a];}else if(typeof k==='string'){if(k in s)o[k]=s[k];}else if(Array.isArray(k)){k.forEach(function(x){if(x in s)o[x]=s[x];});}else{for(var d in k)o[d]=(d in s)?s[d]:k[d];}return cb(f,o);},
set:function(i,f){for(var a in i)s[a]=i[a];return cb(f,undefined);},remove:function(k,f){[].concat(k).forEach(function(x){delete s[x];});return cb(f,undefined);},clear:function(f){s={};return cb(f,undefined);}};}
var store=mem();
var chrome={runtime:{id:'${ext.id}',getManifest:function(){return JSON.parse(JSON.stringify(manifest));},
getURL:function(p){return 'https://${extensionHost(ext.id)}/'+String(p).replace(/^\\/+/,'');},
sendMessage:function(){return Promise.reject(new Error('Extension messaging is not available in Cinder yet.'));},
onMessage:{addListener:function(){},removeListener:function(){},hasListener:function(){return false;}},lastError:undefined},
i18n:{getMessage:function(k){var v=messages[String(k).toLowerCase()];return v===undefined?'':v;},getUILanguage:function(){return navigator.language;}},
storage:{local:store,sync:store,session:store,onChanged:{addListener:function(){},removeListener:function(){}}}};
var entries=[
$entries];
function when(run,fn){if(FORCE||run==='start'){fn();return;}
if(run==='end'){if(document.readyState!=='loading')fn();else document.addEventListener('DOMContentLoaded',fn,{once:true});return;}
if(document.readyState==='complete')setTimeout(fn,0);else window.addEventListener('load',function(){setTimeout(fn,0);},{once:true});}
function addCss(text){try{if(typeof CSSStyleSheet!=='undefined'&&document.adoptedStyleSheets!==undefined){var sh=new CSSStyleSheet();sh.replaceSync(text);document.adoptedStyleSheets=document.adoptedStyleSheets.concat([sh]);return;}}catch(e){}
try{var st=document.createElement('style');st.textContent=text;(document.head||document.documentElement).appendChild(st);}catch(e){}}
entries.forEach(function(e){
if(!e.all&&!top_)return;
if(!any(e.m,href)||any(e.x,href))return;
when(e.run,function(){
var key=Symbol.for('cinder.ext.${ext.id}.'+entries.indexOf(e));
if(!FORCE&&window[key])return;
try{Object.defineProperty(window,key,{value:true,enumerable:false});}catch(x){}
e.css.forEach(addCss);
e.js.forEach(function(f){try{f.call(window,chrome,chrome);}catch(err){console.error('[Cinder extension ${ext.id}]',err);}});
});});
}catch(err){try{console.error('[Cinder extension]',err);}catch(x){}}
})();
//# sourceURL=cinder-extension-$guard.js
''';
  }

  static String _read(String dir, String rel) {
    final f = File('$dir${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
    if (!f.existsSync()) return '';
    if (f.lengthSync() > maxSourceBytes) return '';
    try {
      return utf8.decode(f.readAsBytesSync(), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// The subset of the manifest exposed to scripts.
  static Map<String, dynamic> _publicManifest(ExtensionManifest m) => {
    'manifest_version': 3,
    'name': m.name,
    'version': m.version,
    'description': m.description,
    'permissions': m.permissions,
    'host_permissions': m.hostPermissions,
  };
}
