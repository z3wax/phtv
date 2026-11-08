import 'package:flutter/services.dart';
import 'uzbek_text.dart';

/// Includes keyboard dictation/paste and preserves the caret after digraphs.
class UzbekLatinFormatter extends TextInputFormatter {
  const UzbekLatinFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = uzbekToLatin(newValue.text);
    int offset(int n) => n < 0
        ? n
        : uzbekToLatin(
            newValue.text.substring(0, n.clamp(0, newValue.text.length)),
          ).length;
    return newValue.copyWith(
      text: text,
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
      composing: newValue.composing.isValid
          ? TextRange(
              start: offset(newValue.composing.start),
              end: offset(newValue.composing.end),
            )
          : TextRange.empty,
    );
  }
}
