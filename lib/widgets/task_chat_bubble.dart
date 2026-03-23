import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/app_theme.dart';

/// تنسيق تاريخ/وقت قصير لعرض فقاعات المحادثة (RTL).
String formatTaskChatDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final dt = DateTime.tryParse(raw.replaceAll(' ', 'T'))?.toLocal() ??
        DateTime.tryParse(raw)?.toLocal();
    if (dt == null) {
      if (raw.length >= 16) return raw.substring(0, 16);
      return raw;
    }
    final months = [
      'يناير', 'فبراير', 'مارس', 'إبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final h = dt.hour;
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final ampm = h >= 12 ? 'م' : 'ص';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} — $hour12:$min $ampm';
  } catch (_) {
    return raw;
  }
}

String roleLabelAr(String? role) {
  switch (role) {
    case 'technician':
      return 'فني';
    case 'admin':
      return 'مسؤول';
    case 'staff':
      return 'موظف';
    case 'user':
      return 'عميل';
    default:
      return role ?? '';
  }
}

/// فقاعة محادثة: في RTL نضع فني/يمين، مشرف/يسار (معكوس بصرياً).
class TaskChatBubble extends StatelessWidget {
  final String authorName;
  final String? authorRole;
  final String dateTimeText;
  final String body;
  final bool alignEnd;
  final Color accent;
  final Widget? footer;

  const TaskChatBubble({
    super.key,
    required this.authorName,
    this.authorRole,
    required this.dateTimeText,
    required this.body,
    required this.alignEnd,
    required this.accent,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final bg = accent.withOpacity(0.12);
    final border = accent.withOpacity(0.35);
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(alignEnd ? 14 : 4),
            bottomRight: Radius.circular(alignEnd ? 4 : 14),
          ),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    authorName.isEmpty ? '—' : authorName,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (authorRole != null && authorRole!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      roleLabelAr(authorRole),
                      style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            if (dateTimeText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                dateTimeText,
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
            const SizedBox(height: 6),
            SelectableText(
              body,
              style: TextStyle(color: AppColors.text, fontSize: 14, height: 1.35),
            ),
            if (footer != null) ...[
              const SizedBox(height: 8),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// صندوق "سجل قديم" قبل نظام الرسائل المنفصلة
class TaskLegacyNoteBox extends StatelessWidget {
  final String title;
  final String content;

  const TaskLegacyNoteBox({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppThemeDecorations.pageBackground(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_edu_outlined, size: 16, color: AppColors.muted.withOpacity(0.9)),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.muted.withOpacity(0.95),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            content,
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
