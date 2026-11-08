const uzbekLetters = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'yo',
  'ж': 'j',
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'x',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sh',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
  'ў': 'o‘',
  'қ': 'q',
  'ғ': 'g‘',
  'ҳ': 'h',
  'ъ': '’',
  'ь': '',
};

/// O‘zbekcha kirill buyruqlarini va talaffuz matnini lotinga o‘tkazadi.
String uzbekToLatin(String text) {
  return text.split('').map((ch) {
    final lower = ch.toLowerCase();
    final replacement = uzbekLetters[lower];
    if (replacement == null || replacement.isEmpty || ch == lower) {
      return replacement ?? ch;
    }
    return replacement[0].toUpperCase() + replacement.substring(1);
  }).join();
}
