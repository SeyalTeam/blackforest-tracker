class ApiConfig {
  static const String domain = 'https://blackforest.vseyal.com';
  static const String baseUrl = '$domain/api';
  static const String apiKey = 'tracker_fe496582-7212-411a-a169-2a9009f582f6'; // Placeholder - Replace with actual key
  
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
  };
}
