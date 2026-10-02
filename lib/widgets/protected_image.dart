import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants.dart';

/// Worker photos and ID documents are no longer public files (they used to be
/// served from an open /uploads folder). They are fetched through the
/// authenticated API (`/workers/:id/files/:type`, Admin only), so the JWT is
/// sent by the shared Dio client.
class ProtectedImageCache {
  static final Map<String, Uint8List> _cache = {};

  static Future<Uint8List?> load(String url) async {
    if (url.trim().isEmpty) return null;
    final cached = _cache[url];
    if (cached != null) return cached;
    try {
      final r = await ApiConfig.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = r.data;
      if (data == null || data.isEmpty) return null;
      final bytes = Uint8List.fromList(data);
      _cache[url] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static bool isUsable(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty && value.toString().startsWith('http');
}

class ProtectedAvatar extends StatefulWidget {
  final String? url;
  final double radius;
  final Color backgroundColor;
  final Color iconColor;

  const ProtectedAvatar({
    super.key,
    required this.url,
    this.radius = 20,
    required this.backgroundColor,
    required this.iconColor,
  });

  @override
  State<ProtectedAvatar> createState() => _ProtectedAvatarState();
}

class _ProtectedAvatarState extends State<ProtectedAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProtectedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    if (!ProtectedImageCache.isUsable(widget.url)) {
      if (mounted) setState(() => _bytes = null);
      return;
    }
    final b = await ProtectedImageCache.load(widget.url!);
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      backgroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
      child: _bytes == null ? Icon(Icons.person, size: widget.radius * 1.1, color: widget.iconColor) : null,
    );
  }
}

/// Opens a protected image (e.g. ID document) in a dialog.
Future<void> showProtectedImageDialog(BuildContext context, String url, {String title = 'Document'}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final bytes = await ProtectedImageCache.load(url);
  if (!context.mounted) return;
  Navigator.pop(context);
  if (bytes == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not load the file (Admin access required).')),
    );
    return;
  }
  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ),
          Flexible(
            child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
