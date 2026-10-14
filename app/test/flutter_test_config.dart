import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Memuat Figtree asli agar tes tata letak mencerminkan tampilan sebenarnya (bukan font Ahem).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Figtree')..addFont(rootBundle.load('assets/fonts/Figtree.ttf'));
  await loader.load();
  await testMain();
}
