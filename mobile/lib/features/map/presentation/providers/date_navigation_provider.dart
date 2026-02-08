import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Strips time components from a [DateTime], returning date-only at midnight.
DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Manages the currently selected date for map pin display.
///
/// Initialized to today's date. Navigation forward is capped at today so the
/// user cannot browse into the future. Plan 03 will wire date changes to API
/// calls that fetch conversation pins for the selected day.
class DateNavigationNotifier extends StateNotifier<DateTime> {
  DateNavigationNotifier() : super(_dateOnly(DateTime.now()));

  /// Move to the previous day.
  void goToPreviousDay() {
    state = state.subtract(const Duration(days: 1));
  }

  /// Move to the next day, capped at today.
  void goToNextDay() {
    final next = state.add(const Duration(days: 1));
    final today = _dateOnly(DateTime.now());
    if (!next.isAfter(today)) {
      state = next;
    }
  }

  /// Jump to a specific date. Capped at today if [date] is in the future.
  void goToDate(DateTime date) {
    final dateOnlyValue = _dateOnly(date);
    final today = _dateOnly(DateTime.now());
    state = dateOnlyValue.isAfter(today) ? today : dateOnlyValue;
  }

  /// Whether the user can navigate forward (selected date is before today).
  bool get canGoNext => state.isBefore(_dateOnly(DateTime.now()));
}

/// Provides the selected date for the map screen's date navigation bar.
///
/// Uses [StateNotifierProvider] with manual provider (not code-gen) matching
/// the existing project pattern established in Phase 3.
final dateNavigationProvider =
    StateNotifierProvider<DateNavigationNotifier, DateTime>((ref) {
  return DateNavigationNotifier();
});
