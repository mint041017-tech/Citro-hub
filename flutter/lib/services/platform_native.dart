import 'dart:io';

final bool isAndroid = Platform.isAndroid;
final bool isIOS = Platform.isIOS;
final bool isWindows = Platform.isWindows;
final bool isMacOS = Platform.isMacOS;
final bool isLinux = Platform.isLinux;
final bool isDesktop = isWindows || isMacOS || isLinux;
final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');
const String compileAiKey = String.fromEnvironment('GLM_API_KEY');

String? platformEnvironment(String name) => Platform.environment[name];
