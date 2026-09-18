class SmsParser {
  // Noms configurables — seront lus depuis SharedPreferences
  static String waveSenderName = 'WAVE CI';
  static String omSenderName = 'Orange Money';

  // Package ID de l'app Wave Business
  static const String wavePackageId = 'com.wave.mobile.ci';

  /// Parse une notification Wave Business
  /// Format : "Paiement À DISTANCE reçu: Marie Paule (0787030631) a payé 12.000F le 16/09/2026 19h47."
  static Map<String, dynamic>? parseWaveNotification(String notifBody) {
    // Numéro entre parenthèses
    final phoneRegex = RegExp(r'\((\d{10})\)');
    // Montant avant "F le"
    final amountRegex = RegExp(r'payé\s+([\d\.]+)F');

    final phoneMatch = phoneRegex.firstMatch(notifBody);
    final amountMatch = amountRegex.firstMatch(notifBody);

    if (phoneMatch == null || amountMatch == null) return null;

    // Vérifie que c'est bien un paiement reçu
    if (!notifBody.contains('reçu') && !notifBody.contains('recu')) return null;

    // "12.000" → retire le point séparateur → 12000
    final amountStr = amountMatch.group(1)!.replaceAll('.', '');
    final amount = double.tryParse(amountStr);
    if (amount == null) return null;

    return {
      'amount': amount,
      'phone': phoneMatch.group(1)!,
      'payment_method': 'wave',
    };
  }

  /// Parse un SMS entrant (SMS ou notification)
  static Map<String, dynamic>? parse(String body, String sender) {
    if (sender == waveSenderName) {
      return _parseWaveSms(body);
    }
    if (sender == omSenderName) {
      return _parseOrangeMoney(body);
    }
    return null;
  }

  /// Parse SMS Wave CI (ancien format par SMS)
  static Map<String, dynamic>? _parseWaveSms(String sms) {
    final amountRegex = RegExp(r'recu\s+([\d\.]+)F', caseSensitive: false);
    final phoneRegex = RegExp(r'\((\d{10})\)');

    final amountMatch = amountRegex.firstMatch(sms);
    final phoneMatch = phoneRegex.firstMatch(sms);

    if (amountMatch == null || phoneMatch == null) return null;

    final amountStr = amountMatch.group(1)!.replaceAll('.', '');
    final amount = double.tryParse(amountStr);
    if (amount == null) return null;

    return {
      'amount': amount,
      'phone': phoneMatch.group(1)!,
      'payment_method': 'wave',
    };
  }

  /// Parse SMS Orange Money CI
  static Map<String, dynamic>? _parseOrangeMoney(String sms) {
    final amountRegex = RegExp(
      r'Transfert de ([\d\.]+)F recu du',
      caseSensitive: false,
    );
    final phoneRegex = RegExp(r'recu du (\d{10})', caseSensitive: false);

    final amountMatch = amountRegex.firstMatch(sms);
    final phoneMatch = phoneRegex.firstMatch(sms);

    if (amountMatch == null || phoneMatch == null) return null;

    final amountStr = amountMatch.group(1)!.split('.')[0];
    final amount = double.tryParse(amountStr);
    if (amount == null) return null;

    return {
      'amount': amount,
      'phone': phoneMatch.group(1)!,
      'payment_method': 'orange_money',
    };
  }
}
