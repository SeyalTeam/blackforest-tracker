import 'package:flutter_test/flutter_test.dart';
void main() {
  test('uri encoding', () {
    final queryParams = {
      'where[branch][equals]': '123',
    };
    final uri = Uri.parse('https://dev.com/api/billings').replace(queryParameters: queryParams);
    print(uri.toString());
  });
}
