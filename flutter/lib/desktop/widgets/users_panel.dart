import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/desktop/widgets/user_chat.dart';
import 'package:get/get.dart';

class UsersPanel extends StatefulWidget {
  const UsersPanel({Key? key}) : super(key: key);

  @override
  State<UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<UsersPanel> {
  Timer? _timer;
  Timer? _chatTimer;

  @override
  void initState() {
    super.initState();
    gFFI.groupModel.pull(force: false, quiet: true);
    UserChat.pollUnread();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) gFFI.groupModel.pull(quiet: true);
    });
    _chatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && gFFI.userModel.isLogin) UserChat.pollUnread();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!gFFI.userModel.isLogin) return const Offstage();
      final me = gFFI.userModel.userName.value;
      final users = gFFI.groupModel.users.where((u) => u.name != me).toList()
        ..sort((a, b) {
          if (a.online != b.online) return a.online ? -1 : 1;
          return a.displayNameOrName
              .toLowerCase()
              .compareTo(b.displayNameOrName.toLowerCase());
        });
      if (users.isEmpty) return const Offstage();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
            child: Row(children: [
              Icon(Icons.people_alt_rounded, color: MyTheme.accent, size: 18)
                  .marginOnly(right: 6),
              const Text('Kullanıcılar',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: ListView(
              children: users.map((u) => _row(context, u)).toList(),
            ),
          ),
        ],
      );
    });
  }

  void _connect(UserPayload user) {
    if (user.online && user.deviceId.isNotEmpty) {
      connect(context, user.deviceId);
    } else {
      showToast('${user.displayNameOrName} çevrimdışı');
    }
  }

  Widget _row(BuildContext context, UserPayload user) {
    final online = user.online;
    final hint = Theme.of(context).hintColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (d) => _menu(context, user, d.globalPosition),
      child: InkWell(
      onTap: () => UserChat.open(context, user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: online ? Colors.green : Colors.grey,
                  shape: BoxShape.circle),
            ).marginOnly(right: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayNameOrName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: online ? null : hint)),
                  Text(online ? 'çevrimiçi' : 'çevrimdışı',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: online ? Colors.green : hint)),
                ],
              ),
            ),
            Obx(() {
              final n = UserChat.unread[user.name] ?? 0;
              if (n == 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.red, borderRadius: BorderRadius.circular(9)),
                child: Text('$n',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              );
            }),
            Tooltip(
              message: 'Uzak bağlantı',
              child: InkWell(
                onTap: () => _connect(user),
                child: Icon(Icons.desktop_windows_outlined,
                    size: 16, color: online ? null : hint),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Future<void> _menu(
      BuildContext context, UserPayload user, Offset pos) async {
    if (user.deviceId.isEmpty) {
      showToast('${user.displayNameOrName} için kayıtlı cihaz yok');
      return;
    }
    Peer? peer;
    for (final p in gFFI.groupModel.peers) {
      if (p.id == user.deviceId) {
        peer = p;
        break;
      }
    }
    peer ??= Peer.fromJson({'id': user.deviceId, 'platform': 'Windows'});
    await UserPeerMenu(peer: peer).show(context, pos);
  }
}
