import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:get/get.dart';

class UsersPanel extends StatefulWidget {
  const UsersPanel({Key? key}) : super(key: key);

  @override
  State<UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<UsersPanel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    gFFI.groupModel.pull(force: false, quiet: true);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) gFFI.groupModel.pull(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  Widget _row(BuildContext context, UserPayload user) {
    final online = user.online;
    final hint = Theme.of(context).hintColor;
    return InkWell(
      onTap: () {
        if (online && user.deviceId.isNotEmpty) {
          connect(context, user.deviceId);
        } else {
          showToast('${user.displayNameOrName} çevrimdışı');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
          ],
        ),
      ),
    );
  }
}
