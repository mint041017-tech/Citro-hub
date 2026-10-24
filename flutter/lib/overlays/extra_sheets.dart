import 'package:flutter/material.dart';

import 'fish_sheet.dart';
import 'fortune_sheet.dart';
import 'weather_sheet.dart';

Future<void> showFishSheet(BuildContext context) =>
    showFishSheetDialog(context);
Future<void> showWeatherSheet(BuildContext context) =>
    showWeatherDialog(context);
Future<void> showCheckinOverlay(BuildContext context) =>
    showFortuneOverlay(context);
