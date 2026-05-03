import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';

export 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const FoxelDriveApp());
}
