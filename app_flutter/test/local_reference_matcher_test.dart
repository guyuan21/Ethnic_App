import 'package:app_flutter/services/local_reference_matcher_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matches resized and compressed Mulao costume reference', () async {
    final data = await rootBundle.load('assets/costumes/mulaozu.jpg');
    final source = img.decodeImage(data.buffer.asUint8List());
    expect(source, isNotNull);
    final resized = img.copyResize(source!, width: 720);
    final query = Uint8List.fromList(img.encodeJpg(resized, quality: 72));

    final match = await LocalReferenceMatcherService.instance.match(query);

    expect(match, isNotNull);
    expect(match!.label, 'mulaozu');
    expect(match.engine, 'local_costume_asset_match');
    expect(match.confidence, greaterThanOrEqualTo(0.88));
  });

  test('does not accept a Mulao totem as a costume reference', () async {
    final data = await rootBundle.load('assets/totems/mulaozu.png');
    final query = data.buffer.asUint8List();

    final match = await LocalReferenceMatcherService.instance.match(query);

    expect(match, isNull);
  });
}
