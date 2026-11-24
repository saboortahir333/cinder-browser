import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saboor_browser/src/rust/api/simple.dart';
import 'package:saboor_browser/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(RustLib.init);

  test('Rust bridge returns a greeting', () {
    expect(greet(name: 'Tom'), 'Hello, Tom!');
  });
}
