void main() {
  final queryParams = {
    'where[branch][equals]': '123',
    'where[createdAt][greater_than_equal]': '2026',
    'limit': '1000'
  };
  final uri = Uri.parse('https://dev1-blacforest.vseyal.com/api/billings').replace(queryParameters: queryParams);
  print(uri.toString());
}
