import 'package:flutter/material.dart';

Route smoothPageRoute(Widget destination) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => destination,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeInCirc)),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}
