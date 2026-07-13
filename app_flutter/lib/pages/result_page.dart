import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../widgets/result_card.dart';
import 'chat_page.dart';

const double minConfidence = 0.70;

class ResultPage extends StatefulWidget {
  final XFile imageFile;
  final Map<String, dynamic> result;

  const ResultPage({
    super.key,
    required this.imageFile,
    required this.result,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late final Future<Uint8List> _imageBytesFuture;

  @override
  void initState() {
    super.initState();
    _imageBytesFuture = widget.imageFile.readAsBytes();
  }

  String _engineText(String engine) {
    if (engine == 'local_cartoon_tflite') {
      return '本地卡通模型识别';
    }
    if (engine == 'local_costume_asset_match') {
      return '本地书册服饰图库匹配';
    }
    if (engine == 'local_title_ocr_match') {
      return '标题文字识别匹配';
    }
    if (engine == 'local_filename_match') {
      return '图片文件名匹配';
    }
    return '图像识别模型匹配';
  }

  @override
  Widget build(BuildContext context) {
    final engine = (widget.result['engine'] ?? '').toString();
    final allResults = ((widget.result['results'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final highConfidenceResults = allResults.where((item) {
      final confidence = (item['confidence'] as num? ?? 0).toDouble();
      return confidence >= minConfidence;
    }).toList();

    final bestResult =
        highConfidenceResults.isEmpty ? null : highConfidenceResults.first;

    final notice =
        (widget.result['notice'] ?? '本结果仅识别民族服饰卡通图片，不代表对真人民族身份的判断。').toString();
    final warning = (widget.result['warning'] ?? '').toString();
    final chatContext = Map<String, dynamic>.from(widget.result);
    if (bestResult != null) {
      chatContext['results'] = [bestResult];
    }
    final bestLabel =
        bestResult == null ? '' : (bestResult['label'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('识别结果'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FutureBuilder<Uint8List>(
                  future: _imageBytesFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Container(
                        height: 300,
                        width: double.infinity,
                        alignment: Alignment.center,
                        color: Colors.grey.withAlpha(31),
                        child: const CircularProgressIndicator(),
                      );
                    }

                    return Image.memory(
                      snapshot.data!,
                      height: 300,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Text(
                bestResult == null ? '识别完成' : '识别完成：最佳匹配',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              if (engine.isNotEmpty)
                Text(
                  '${_engineText(engine)}，仅供文化学习参考',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: warning.isNotEmpty
                            ? Colors.deepOrange
                            : Colors.black.withAlpha(143),
                      ),
                ),
              if (warning.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  warning,
                  style:
                      const TextStyle(color: Colors.deepOrange, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              if (bestResult == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    allResults.isEmpty
                        ? '暂未识别到支持的民族服饰卡通图片。'
                        : '识别结果置信度不足，暂不展示具体民族文化结果。建议重新拍摄，尽量保持图片清晰、完整、光线充足。',
                  ),
                )
              else ...[
                ResultCard(
                  name:
                      (bestResult['group'] ?? bestResult['name'] ?? '未知民族文化元素')
                          .toString(),
                  elementName: (bestResult['element_name'] ?? '').toString(),
                  totemAsset:
                      bestLabel.isEmpty ? '' : 'assets/totems/$bestLabel.png',
                  totemUrl: ApiService.resolveUrl(
                    (bestResult['totem_url'] ?? '').toString(),
                  ),
                  confidence:
                      (bestResult['confidence'] as num? ?? 0).toDouble(),
                  intro: (bestResult['intro'] ?? '').toString(),
                  historyIntro: (bestResult['history_intro'] ?? '').toString(),
                  regionGroup: (bestResult['region_group'] ?? '').toString(),
                  features: bestResult['features'] ?? const [],
                  regions: bestResult['regions'] ?? const [],
                  festivals: bestResult['festivals'] ?? const [],
                  relatedGroups: bestResult['related_groups'] ?? const [],
                  interactionEvents:
                      bestResult['interaction_events'] ?? const [],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                notice,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(initialContext: chatContext),
                    ),
                  );
                },
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('了解更多，大模型讲解'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
