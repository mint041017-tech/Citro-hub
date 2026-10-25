import 'dart:io';

final bool isAndroid = Platform.isAndroid;
final bool isIOS = Platform.isIOS;
final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');
