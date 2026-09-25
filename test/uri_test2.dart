import 'package:flutter_test/flutter_test.dart';
void main() {
  test('uri encoding', () {
    const _baseUrl = 'https://dev1-blacforest.vseyal.com/api';
    final queryParams = {
      'where[branch][equals]': '123',
    };
    final uri = Uri.parse('$_baseUrl/billings').replace(queryParameters: queryParams);
    print(uri.toString());
  });
}
