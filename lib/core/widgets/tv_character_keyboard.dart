const List<List<String>> tvCharacterKeyboardRows = <List<String>>[
  <String>['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'],
  <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
  <String>['Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X'],
  <String>['Y', 'Z', '1', '2', '3', '4', '5', '6'],
  <String>['7', '8', '9', '0', 'SP', 'DEL', 'CLR', '\u2190', '\u2192'],
];

bool isSupportedTvKeyboardCharacter(String value) {
  return RegExp(r'^[A-Z0-9 ]$').hasMatch(value);
}
