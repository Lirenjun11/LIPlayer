import 'package:flutter/material.dart';

import '../models/music_platform.dart';
import '../theme.dart';

/// Shows a bottom sheet for choosing the active music source.
Future<void> showPlatformPicker(
  BuildContext context, {
  required List<MusicPlatform> platforms,
  required String current,
  required ValueChanged<MusicPlatform> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.text3,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('选择音乐源',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: platforms.length,
                itemBuilder: (context, index) {
                  final p = platforms[index];
                  final active = p.platform == current;
                  return ListTile(
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelect(p);
                    },
                    leading: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: active ? AppColors.accent : AppColors.text3,
                          width: 2,
                        ),
                      ),
                      child: active
                          ? Icon(Icons.check,
                              size: 13, color: AppColors.accent)
                          : null,
                    ),
                    title: Text(p.platform,
                        style: TextStyle(
                            fontSize: 15, color: AppColors.text)),
                    subtitle: p.supportedSearchType.isEmpty
                        ? null
                        : Text(
                            p.supportedSearchType.join(' / '),
                            style: TextStyle(
                                fontSize: 11, color: AppColors.text2),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
