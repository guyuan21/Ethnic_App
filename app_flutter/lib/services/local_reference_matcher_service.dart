import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class LocalReferenceMatch {
  final String label;
  final double confidence;
  final String engine;
  final double margin;

  const LocalReferenceMatch({
    required this.label,
    required this.confidence,
    required this.engine,
    required this.margin,
  });

  bool get isStrongReference =>
      confidence >= LocalReferenceMatcherService._minimumScore &&
      margin >= LocalReferenceMatcherService._minimumMargin;
}

class LocalReferenceMatcherService {
  LocalReferenceMatcherService._();

  static final LocalReferenceMatcherService instance =
      LocalReferenceMatcherService._();

  static const int _fingerprintSize = 48;
  static const double _minimumScore = 0.88;
  static const double _minimumMargin = 0.035;

  Future<void>? _loadFuture;
  List<_ReferenceFingerprint> _references = const [];

  Future<void> load() => _loadFuture ??= _load();

  Future<LocalReferenceMatch?> match(Uint8List bytes) async {
    final candidate = await bestCandidate(bytes);
    if (candidate == null || !candidate.isStrongReference) {
      return null;
    }
    return candidate;
  }

  Future<LocalReferenceMatch?> bestCandidate(Uint8List bytes) async {
    await load();
    final source = img.decodeImage(bytes);
    if (source == null || _references.isEmpty) return null;
    final query = _fingerprint(source);

    final scored = _references
        .map((reference) => (
              reference: reference,
              score: _similarity(query, reference.fingerprint),
            ))
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    final best = scored.first;
    final secondScore = scored.length > 1 ? scored[1].score : 0.0;
    return LocalReferenceMatch(
      label: best.reference.label,
      confidence: best.score.clamp(0.0, 0.995).toDouble(),
      engine: best.reference.engine,
      margin: best.score - secondScore,
    );
  }

  Future<void> _load() async {
    final rawLabels = await rootBundle.loadString('assets/model/labels.txt');
    final labels = rawLabels
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'));
    final references = <_ReferenceFingerprint>[];

    for (final label in labels) {
      await _addReference(
        references,
        asset: 'assets/costumes/$label.jpg',
        label: label,
        engine: 'local_costume_asset_match',
      );
    }
    _references = references;
  }

  Future<void> _addReference(
    List<_ReferenceFingerprint> target, {
    required String asset,
    required String label,
    required String engine,
  }) async {
    try {
      final data = await rootBundle.load(asset);
      final image = img.decodeImage(data.buffer.asUint8List());
      if (image == null) return;
      target.add(
        _ReferenceFingerprint(
          label: label,
          engine: engine,
          fingerprint: _fingerprint(image),
        ),
      );
    } catch (_) {
      // A missing optional reference must not disable normal TFLite inference.
    }
  }

  _ImageFingerprint _fingerprint(img.Image source) {
    final oriented = img.bakeOrientation(source);
    final resized = img.copyResize(
      oriented,
      width: _fingerprintSize,
      height: _fingerprintSize,
      interpolation: img.Interpolation.linear,
    );
    final luminance = <double>[];
    for (final pixel in resized) {
      final alpha = (pixel.a / 255.0).clamp(0.0, 1.0).toDouble();
      final red = (pixel.r * alpha) + (255 * (1 - alpha));
      final green = (pixel.g * alpha) + (255 * (1 - alpha));
      final blue = (pixel.b * alpha) + (255 * (1 - alpha));
      luminance.add((0.299 * red + 0.587 * green + 0.114 * blue) / 255.0);
    }
    final mean = luminance.reduce((a, b) => a + b) / luminance.length;
    final centered = luminance.map((value) => value - mean).toList();
    final norm = math.sqrt(
      centered.fold<double>(0, (sum, value) => sum + value * value),
    );
    return _ImageFingerprint(
      luminance: luminance,
      centered: centered,
      norm: norm,
    );
  }

  double _similarity(_ImageFingerprint a, _ImageFingerprint b) {
    var absoluteDifference = 0.0;
    var dot = 0.0;
    for (var i = 0; i < a.luminance.length; i += 1) {
      absoluteDifference += (a.luminance[i] - b.luminance[i]).abs();
      dot += a.centered[i] * b.centered[i];
    }
    final absoluteScore =
        1.0 - (absoluteDifference / a.luminance.length).clamp(0.0, 1.0);
    final correlation = a.norm == 0 || b.norm == 0
        ? 0.0
        : (dot / (a.norm * b.norm)).clamp(-1.0, 1.0);
    final correlationScore = math.max(0.0, correlation);
    return (correlationScore * 0.82) + (absoluteScore * 0.18);
  }
}

class _ReferenceFingerprint {
  final String label;
  final String engine;
  final _ImageFingerprint fingerprint;

  const _ReferenceFingerprint({
    required this.label,
    required this.engine,
    required this.fingerprint,
  });
}

class _ImageFingerprint {
  final List<double> luminance;
  final List<double> centered;
  final double norm;

  const _ImageFingerprint({
    required this.luminance,
    required this.centered,
    required this.norm,
  });
}
