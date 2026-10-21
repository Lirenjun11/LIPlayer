import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

enum ToastKind { info, success, error }

/// Shows short feedback in the middle of the screen instead of a SnackBar,
/// so it never covers the mini player or the playback controls.
class AppToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _dismiss();

    final entry = OverlayEntry(
      builder: (_) => _ToastView(message: message, kind: _inferKind(message)),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, _dismiss);
  }

  static ToastKind _inferKind(String message) {
    if (message.contains('失败') ||
        message.contains('错误') ||
        message.contains('不可用') ||
        message.contains('无效') ||
        message.contains('请先')) {
      return ToastKind.error;
    }
    if (message.startsWith('已') ||
        message.contains('成功') ||
        message.contains('完成')) {
      return ToastKind.success;
    }
    return ToastKind.info;
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    try {
      entry.remove();
    } catch (_) {
      // The overlay may already be gone (route/app disposed).
    }
  }
}

class _ToastView extends StatelessWidget {
  final String message;
  final ToastKind kind;

  const _ToastView({required this.message, required this.kind});

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      ToastKind.success => Icons.check_circle_rounded,
      ToastKind.error => Icons.error_rounded,
      ToastKind.info => Icons.info_rounded,
    };
    final tint = switch (kind) {
      ToastKind.success => const Color(0xFF5FE0A8),
      ToastKind.error => const Color(0xFFFF7A93),
      ToastKind.info => AppColors.accent,
    };

    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: Transform.scale(
                  scale: 0.96 + 0.04 * value,
                  child: child,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.fromLTRB(16, 13, 20, 13),
                decoration: BoxDecoration(
                  color: AppColors.isDark
                      ? const Color(0xE0101319)
                      : const Color(0xF2FFFFFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.isDark
                        ? const Color(0x1FFFFFFF)
                        : const Color(0x14000000),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.isDark
                          ? const Color(0x8C000000)
                          : const Color(0x1F000000),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 16, color: tint),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
