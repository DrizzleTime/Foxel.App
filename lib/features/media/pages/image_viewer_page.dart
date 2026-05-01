import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.api,
    required this.path,
    required this.name,
  });

  final FoxelApi api;
  final String path;
  final String name;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final Future<Uint8List> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = widget.api.readFile(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      backgroundColor: Colors.black,
      body: FutureBuilder<Uint8List>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Center(
              child: Image.memory(snapshot.data!, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}
