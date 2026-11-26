import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import '../../utils/http_service.dart' as http;

// Personel arası doğrudan sohbet (panel üzerinden, uzak oturum gerekmez).
class UserChat {
  static final RxMap<String, int> unread = <String, int>{}.obs;
  static String? openWith;

  static Future<Uri> _uri(String path, [Map<String, String>? q]) async {
    final base = Uri.parse("${await bind.mainGetApiServer()}$path");
    return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.port,
        path: base.path,
        queryParameters: q);
  }

  static Future<void> pollUnread() async {
    try {
      final resp = await http.get(await _uri('/api/chat/unread'),
          headers: getHttpHeaders());
      if (resp.statusCode != 200) return;
      final json = jsonDecode(decode_http_response(resp));
      final counts = <String, int>{};
      if (json is Map && json['counts'] is Map) {
        (json['counts'] as Map)
            .forEach((k, v) => counts[k.toString()] = (v as num).toInt());
      }
      final grew = counts.entries
          .any((e) => e.value > (unread[e.key] ?? 0) && e.key != openWith);
      unread.value = counts;
      if (grew) showToast('Yeni mesajınız var');
    } catch (e) {
      debugPrint('chat unread: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetch(String peer,
      {int after = 0}) async {
    try {
      final resp = await http.get(
          await _uri('/api/chat',
              {'peer': peer, if (after > 0) 'after': '$after'}),
          headers: getHttpHeaders());
      if (resp.statusCode != 200) return [];
      final json = jsonDecode(decode_http_response(resp));
      if (json is Map && json['data'] is List) {
        return (json['data'] as List).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('chat fetch: $e');
    }
    return [];
  }

  static Future<bool> send(String peer, String text) async {
    try {
      final resp = await http.post(await _uri('/api/chat'),
          headers: {...getHttpHeaders(), 'Content-Type': 'application/json'},
          body: jsonEncode({'to': peer, 'text': text}));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('chat send: $e');
      return false;
    }
  }

  static void open(BuildContext context, UserPayload user) {
    openWith = user.name;
    unread.remove(user.name);
    showDialog(
      context: context,
      builder: (_) => _ChatDialog(user: user),
    ).whenComplete(() => openWith = null);
  }
}

class _ChatDialog extends StatefulWidget {
  final UserPayload user;
  const _ChatDialog({required this.user});

  @override
  State<_ChatDialog> createState() => _ChatDialogState();
}

class _ChatDialogState extends State<_ChatDialog> {
  final _msgs = <Map<String, dynamic>>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  int _last = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await UserChat.fetch(widget.user.name, after: _last);
    if (!mounted || rows.isEmpty) return;
    setState(() {
      for (final r in rows) {
        if (_msgs.any((m) => m['id'] == r['id'])) continue;
        _msgs.add(r);
        final ts = (r['ts'] as num).toInt();
        if (ts > _last) _last = ts;
      }
    });
    UserChat.unread.remove(widget.user.name);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    if (!await UserChat.send(widget.user.name, text)) {
      showToast('Mesaj gönderilemedi');
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
              color: widget.user.online ? Colors.green : Colors.grey,
              shape: BoxShape.circle),
        ).marginOnly(right: 8),
        Expanded(
            child: Text(widget.user.displayNameOrName,
                overflow: TextOverflow.ellipsis)),
        IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18)),
      ]),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(children: [
          Expanded(
            child: _msgs.isEmpty
                ? Center(
                    child: Text('Henüz mesaj yok',
                        style: TextStyle(color: Theme.of(context).hintColor)))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final mine = m['mine'] == true;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(
                            color: mine
                                ? MyTheme.accent.withOpacity(0.85)
                                : color.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(m['text'].toString(),
                              style: TextStyle(
                                  color: mine ? Colors.white : null)),
                        ),
                      );
                    }),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: 2000,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                    hintText: 'Mesaj yazın…',
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder()),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _send, child: const Text('Gönder')),
          ]),
        ]),
      ),
    );
  }
}
