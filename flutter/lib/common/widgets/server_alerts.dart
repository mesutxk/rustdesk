import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import '../../utils/http_service.dart' as http;

class _ServerAlert {
  final String severity, kind, title, detail, host, customer;
  _ServerAlert(this.severity, this.kind, this.title, this.detail, this.host,
      this.customer);

  int get rank => severity == 'CRITICAL' ? 0 : (severity == 'WARNING' ? 1 : 2);
  Color get color => severity == 'CRITICAL'
      ? const Color(0xFFDC2626)
      : (severity == 'WARNING' ? const Color(0xFFD97706) : const Color(0xFF0284C7));
  String get kindLabel {
    switch (kind) {
      case 'UPDATES':
        return 'Güncelleme';
      case 'SYSTEM':
        return 'Sistem';
      case 'HARDWARE':
        return 'Donanım';
      case 'POWER':
        return 'Güç / Açılış';
      case 'DISK':
        return 'Disk';
    }
    return kind;
  }
}

/// Panelden gelen sunucu uyarılarını (kritik/uyarı/bilgi) renkli bir şerit
/// olarak gösterir; ayrıntılar için tıklanınca liste açılır.
class ServerAlertsBar extends StatefulWidget {
  const ServerAlertsBar({Key? key}) : super(key: key);

  @override
  State<ServerAlertsBar> createState() => _ServerAlertsBarState();
}

class _ServerAlertsBarState extends State<ServerAlertsBar> {
  Timer? _timer;
  List<_ServerAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (!gFFI.userModel.isLogin) {
        if (_alerts.isNotEmpty && mounted) setState(() => _alerts = []);
        return;
      }
      // Sunucu olarak işaretli / izlenen cihazlarda panel boş liste döner (müşteri sunucusunda başka müşterilerin uyarıları görünmesin).
      final myId = (await bind.mainGetMyId()).replaceAll(" ", "");
      final api = "${await bind.mainGetApiServer()}/api/alerts?id=$myId";
      final resp = await http.get(Uri.parse(api), headers: getHttpHeaders());
      if (resp.statusCode != 200) return;
      final json = jsonDecode(decode_http_response(resp));
      final data = json['data'];
      if (data is! List) return;
      final list = data
          .map((e) => _ServerAlert(
              (e['severity'] ?? '').toString(),
              (e['kind'] ?? '').toString(),
              (e['title'] ?? '').toString(),
              (e['detail'] ?? '').toString(),
              (e['host'] ?? '').toString(),
              (e['customer'] ?? '').toString()))
          .toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      if (mounted) setState(() => _alerts = list);
    } catch (e) {
      debugPrint('server alerts: $e');
    }
  }

  void _showAll() {
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: const Text('Sunucu uyarıları'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: ListView(
            children: _alerts
                .map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: a.color.withOpacity(0.12),
                        border: Border(left: BorderSide(color: a.color, width: 4)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${a.kindLabel} · ${a.host}${a.customer.isNotEmpty ? ' · ${a.customer}' : ''}',
                              style: TextStyle(
                                  fontSize: 12, color: a.color, fontWeight: FontWeight.w600)),
                          Text(a.title,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (a.detail.isNotEmpty)
                            Text(a.detail,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
        actions: [dialogButton('Close', onPressed: close, isOutline: true)],
        onCancel: close,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_alerts.isEmpty) return const SizedBox.shrink();
    final crit = _alerts.where((a) => a.severity == 'CRITICAL').length;
    final warn = _alerts.where((a) => a.severity == 'WARNING').length;
    final info = _alerts.length - crit - warn;
    final top = _alerts.first;
    final more = _alerts.length - 1;
    Widget chip(int n, String label, Color c) => n == 0
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
            child: Text('$n $label',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          );
    return InkWell(
      onTap: _showAll,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: top.color.withOpacity(0.14),
          border: Border(left: BorderSide(color: top.color, width: 4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(top.severity == 'INFO' ? Icons.info_outline : Icons.warning_amber_rounded,
                color: top.color),
            const SizedBox(width: 10),
            chip(crit, 'kritik', const Color(0xFFDC2626)),
            chip(warn, 'uyarı', const Color(0xFFD97706)),
            chip(info, 'bilgi', const Color(0xFF0284C7)),
            Expanded(
              child: Text(
                '${top.host}: ${top.title}${more > 0 ? '  (+$more)' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Text('Ayrıntı', style: TextStyle(fontSize: 12)),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
