import 'package:flutter/material.dart';

/// 单个识别元素的展示卡片。
///
/// 该组件只展示"文化元素"相关介绍，不展示任何对人物民族身份的判断。
class ResultCard extends StatelessWidget {
  final String name;
  final String elementName;
  final String totemAsset;
  final String totemUrl;
  final double confidence;
  final String intro;
  final String historyIntro;
  final String regionGroup;
  final List<dynamic> features;
  final List<dynamic> regions;
  final List<dynamic> festivals;
  final List<dynamic> relatedGroups;
  final List<dynamic> interactionEvents;

  const ResultCard({
    super.key,
    required this.name,
    this.elementName = '',
    this.totemAsset = '',
    this.totemUrl = '',
    required this.confidence,
    required this.intro,
    this.historyIntro = '',
    this.regionGroup = '',
    this.features = const [],
    this.regions = const [],
    this.festivals = const [],
    this.relatedGroups = const [],
    this.interactionEvents = const [],
  });

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );

  Widget _bulletList(List<dynamic> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map<Widget>((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $f', style: const TextStyle(height: 1.45)),
                ))
            .toList(),
      );

  Widget _imagePlaceholder(double height) {
    return SizedBox(
      height: height,
      child: const Center(
        child: Text('图腾暂未加载'),
      ),
    );
  }

  Widget _networkImage(String url,
      {double height = 180, BoxFit fit = BoxFit.cover}) {
    if (url.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            height: height,
            child: const Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _imagePlaceholder(height);
        },
      ),
    );
  }

  Widget _totemImage({double height = 180}) {
    if (totemAsset.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          totemAsset,
          height: height,
          width: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _networkImage(
              totemUrl,
              height: height,
              fit: BoxFit.contain,
            );
          },
        ),
      );
    }

    return _networkImage(
      totemUrl,
      height: height,
      fit: BoxFit.contain,
    );
  }

  Widget _chipList(BuildContext context, List<dynamic> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Chip(
              label: Text(item.toString()),
              visualDensity: VisualDensity.compact,
              side: BorderSide(
                color: Theme.of(context).colorScheme.secondary.withAlpha(61),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _infoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6E5C55),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (totemAsset.isNotEmpty || totemUrl.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF0D4CA)),
                ),
                child: _totemImage(height: 170),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              name,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('置信度：${(confidence * 100).toStringAsFixed(1)}%'),
            _infoRow('识别元素', elementName),
            const SizedBox(height: 12),
            Text(
              intro,
              style: const TextStyle(height: 1.5),
            ),
            if (regions.isNotEmpty) ...[
              _sectionTitle('主要分布地区：'),
              _chipList(context, regions),
            ],
            if (festivals.isNotEmpty) ...[
              _sectionTitle('相关节日：'),
              _chipList(context, festivals),
            ],
            if (regionGroup.isNotEmpty) ...[
              _sectionTitle('所属历史片区：'),
              Text(regionGroup),
            ],
            if (relatedGroups.isNotEmpty) ...[
              _sectionTitle('相关民族：'),
              _chipList(context, relatedGroups),
            ],
            if (historyIntro.isNotEmpty) ...[
              _sectionTitle('历史交往资料：'),
              Text(
                historyIntro,
                style: const TextStyle(height: 1.55),
              ),
            ],
            if (interactionEvents.isNotEmpty) ...[
              _sectionTitle('典型交往事件：'),
              _bulletList(interactionEvents),
            ],
            if (features.isNotEmpty) ...[
              _sectionTitle('文化特征：'),
              _bulletList(features),
            ],
          ],
        ),
      ),
    );
  }
}
