import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'camera/plate_text_engine.dart';
import 'data/pass_repository.dart';

void main() {
  const demo = bool.fromEnvironment('USE_DEMO');
  WidgetsFlutterBinding.ensureInitialized();
  if (!demo &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    unawaited(plateTextEngine.warmUp());
  }
  runApp(PassApp(repository: demo ? DemoPassRepository() : null));
}
