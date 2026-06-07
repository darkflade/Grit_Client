class ApiEndpointOption {
  final String label;
  final String baseUrl;
  final String description;

  const ApiEndpointOption({
    required this.label,
    required this.baseUrl,
    required this.description,
  });
}

const defaultApiBaseUrl = 'https://msk.api.diogen.space';

const defaultApiEndpoints = [
  ApiEndpointOption(
    label: 'MSK',
    baseUrl: 'https://msk.api.diogen.space',
    description: 'Основной endpoint',
  ),
  ApiEndpointOption(
    label: 'Default',
    baseUrl: 'https://api.diogen.space',
    description: 'Резервный endpoint',
  ),
];

String normalizeApiBaseUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Введите домен API.');
  }

  final raw =
      RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(trimmed)
      ? trimmed
      : 'https://$trimmed';
  final uri = Uri.parse(raw);
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError('Некорректный домен API.');
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw ArgumentError('Поддерживаются только http и https endpoint.');
  }

  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
