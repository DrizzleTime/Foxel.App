import 'package:flutter/material.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

import 'app/app.dart';

export 'app/app.dart';

void main() {
  VideoPlayerMediaKit.ensureInitialized(linux: true);
  runApp(const FoxelDriveApp());
}
