import 'package:flutter/material.dart';

void popOrHome(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    navigator.pushNamed('/home');
  }
}
