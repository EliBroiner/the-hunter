import 'package:flutter/material.dart';
import 'app/the_hunter_app.dart';
import 'bootstrap/app_bootstrap.dart';

void main() async {
  await bootstrapApp();
  runApp(const TheHunterApp());
}
