import 'package:flutter/material.dart';

import 'models/scenario_model.dart';

/// Icons shown in the scenario editor picker (order = display order).
final List<IconData> scenarioIcons = [
  Icons.wb_sunny,
  Icons.nights_stay,
  Icons.home,
  Icons.exit_to_app,
  Icons.movie,
  Icons.dinner_dining,
  Icons.work,
  Icons.videogame_asset,
  Icons.directions_run,
];

/// Picker icon whose [IconData.codePoint] equals [codePoint], or null.
/// Avoids `IconData(codePoint, fontFamily: …)` so release builds can tree-shake icons.
IconData? scenarioPickerIconMatchingCodePoint(int codePoint) {
  for (final icon in scenarioIcons) {
    if (icon.codePoint == codePoint) return icon;
  }
  return null;
}

/// Resolves the icon for a card: saved [ScenarioModel.iconCodePoint], else keyword fallback.
IconData scenarioDisplayIcon(ScenarioModel scenario) {
  final cp = scenario.iconCodePoint;
  if (cp != null) {
    final fromPicker = scenarioPickerIconMatchingCodePoint(cp);
    if (fromPicker != null) return fromPicker;
  }
  return scenarioFallbackIconForName(scenario.name);
}

/// Keyword-based fallback when no custom icon was chosen (Arabic + English).
IconData scenarioFallbackIconForName(String name) {
  final lowerName = name.toLowerCase();
  if (lowerName.contains('نوم') ||
      lowerName.contains('ليل') ||
      lowerName.contains('sleep') ||
      lowerName.contains('night')) {
    return Icons.nights_stay_rounded;
  }
  if (lowerName.contains('صباح') ||
      lowerName.contains('صحو') ||
      lowerName.contains('morning') ||
      lowerName.contains('wake')) {
    return Icons.wb_sunny_rounded;
  }
  if (lowerName.contains('خروج') ||
      lowerName.contains('وداع') ||
      lowerName.contains('away') ||
      lowerName.contains('leave')) {
    return Icons.exit_to_app_rounded;
  }
  if (lowerName.contains('دخول') ||
      lowerName.contains('عودة') ||
      lowerName.contains('return')) {
    return Icons.home_rounded;
  }
  if (lowerName.contains('فيلم') ||
      lowerName.contains('سينما') ||
      lowerName.contains('movie') ||
      lowerName.contains('cinema')) {
    return Icons.movie_rounded;
  }
  return Icons.play_arrow_rounded;
}
