import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/map/presentation/providers/date_navigation_provider.dart';

/// A horizontal bar with left/right chevron arrows and a date label.
///
/// Tapping the left chevron goes to the previous day. Tapping the right chevron
/// goes to the next day, but is disabled when the selected date is today (users
/// cannot browse into the future).
///
/// The center label shows "Today" when the selected date matches the current
/// date, otherwise it shows the date formatted as "Feb 7, 2026".
class DateNavigationBar extends ConsumerWidget {
  const DateNavigationBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(dateNavigationProvider);
    final notifier = ref.read(dateNavigationProvider.notifier);
    final canGoForward = notifier.canGoNext;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => notifier.goToPreviousDay(),
            tooltip: 'Previous day',
          ),
          Text(
            _formatDateLabel(selectedDate),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoForward ? () => notifier.goToNextDay() : null,
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }

  /// Formats the selected date for display.
  ///
  /// Returns "Today" if the date matches the current date, otherwise returns
  /// a string like "Feb 7, 2026". Uses manual formatting without the intl
  /// dependency, matching the pattern established in PlaybackScreen._formatDate.
  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(date.year, date.month, date.day);

    if (selected == today) {
      return 'Today';
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }
}
