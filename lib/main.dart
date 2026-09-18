import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';

import 'sms_parser.dart';
import 'api_service.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> _showNotification({
  required String title,
  required String body,
}) async {
  const androidDetails = AndroidNotificationDetails(
    'msy_secret_channel',
    'Msy Secret Paiements',
    channelDescription: 'Notifications de paiement Msy Secret',
    importance: Importance.high,
    priority: Priority.high,
  );

  await notifications.show(
    id: 0,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: androidDetails),
  );
}

Future<void> initNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(
    settings: const InitializationSettings(android: androidInit),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  runApp(const MsySecretApp());
}

class MsySecretApp extends StatelessWidget {
  const MsySecretApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Msy Secret Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D0E14)),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SmsQuery query = SmsQuery();
  final TextEditingController _tokenController = TextEditingController();
  bool _isListening = false;
  String _lastSms = 'En attente de SMS...';
  String _lastResult = '';

  @override
  void initState() {
    super.initState();
    _loadToken();
    _processMissedSms();
    _startNotificationListener();
  }

  // Traite les SMS manqués depuis les dernières 48h
  Future<void> _processMissedSms() async {
    final permission = await Permission.sms.request();
    if (!permission.isGranted) return;

    final messages = await query.querySms(
      kinds: [SmsQueryKind.inbox],
      address: SmsParser.omSenderName,
      count: 50,
    );

    final cutoff = DateTime.now().subtract(const Duration(hours: 48));

    for (final msg in messages) {
      final date = msg.date;
      if (date == null || date.isBefore(cutoff)) continue;

      final result = SmsParser.parse(msg.body ?? '', msg.address ?? '');
      if (result == null) continue;

      final response = await ApiService.notifyPayment(
        amount: result['amount'],
        phone: result['phone'],
        paymentMethod: result['payment_method'],
      );

      if (response['success'] == true) {
        await _showNotification(
          title: '✅ Paiement OM confirmé (rattrapage)',
          body:
              'Commande ${response['order_number']} — ${result['amount'].toStringAsFixed(0)} FCFA',
        );
      }
    }

    setState(() => _isListening = true);
  }

  Future<void> _startNotificationListener() async {
    final permitted = await NotificationListenerService.isPermissionGranted();

    if (!permitted) {
      await NotificationListenerService.requestPermission();
      return;
    }

    NotificationListenerService.notificationsStream.listen((event) async {
      if (event.packageName != SmsParser.wavePackageId) return;

      final body = event.content ?? '';

      setState(() {
        _lastSms = '[Wave Business Notif]\n$body';
      });

      final result = SmsParser.parseWaveNotification(body);

      if (result == null) {
        setState(() => _lastResult = '❌ Notification Wave ignorée');
        return;
      }

      setState(() {
        _lastResult =
            '✅ Parsé : wave — ${result['amount']} FCFA de ${result['phone']}';
      });

      final response = await ApiService.notifyPayment(
        amount: result['amount'],
        phone: result['phone'],
        paymentMethod: result['payment_method'],
      );

      if (response['success'] == true) {
        await _showNotification(
          title: '✅ Paiement Wave confirmé',
          body:
              'Commande ${response['order_number']} — ${result['amount'].toStringAsFixed(0)} FCFA',
        );
      } else {
        await _showNotification(
          title: '⚠️ Paiement Wave non trouvé',
          body:
              '${result['amount'].toStringAsFixed(0)} FCFA de ${result['phone']}',
        );
      }
    });
  }

  Future<void> _loadToken() async {
    final token = await ApiService.getToken();
    if (token != null) {
      _tokenController.text = token;
    }
  }

  Future<void> _saveToken() async {
    await ApiService.saveToken(_tokenController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Token sauvegardé ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEE0CB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF110201),
        title: const Text(
          'Msy Secret Admin',
          style: TextStyle(
            color: Color(0xFFEEE0CB),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statut
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isListening
                    ? const Color(0xFFf0fdf4)
                    : const Color(0xFFfef2f2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isListening
                      ? const Color(0xFF15803d)
                      : const Color(0xFFdc2626),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isListening ? Icons.check_circle : Icons.error,
                    color: _isListening
                        ? const Color(0xFF15803d)
                        : const Color(0xFFdc2626),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isListening
                        ? 'En écoute des notifications Wave'
                        : 'Initialisation...',
                    style: TextStyle(
                      color: _isListening
                          ? const Color(0xFF15803d)
                          : const Color(0xFFdc2626),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Token
            const Text(
              'TOKEN API LARAVEL',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Color(0xFF4D0E14),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      hintText: '1|xxxxxxxxxxxxxxxxxxxx',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFd4c4ae)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFd4c4ae)),
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveToken,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4D0E14),
                    foregroundColor: const Color(0xFFEEE0CB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Sauvegarder'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Dernière activité
            const Text(
              'DERNIÈRE ACTIVITÉ',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Color(0xFF4D0E14),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFd4c4ae)),
              ),
              child: Text(
                _lastSms,
                style: const TextStyle(fontSize: 13, color: Color(0xFF110201)),
              ),
            ),

            const SizedBox(height: 16),

            if (_lastResult.isNotEmpty) ...[
              const Text(
                'RÉSULTAT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Color(0xFF4D0E14),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _lastResult.startsWith('✅')
                      ? const Color(0xFFf0fdf4)
                      : const Color(0xFFfef9ec),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _lastResult.startsWith('✅')
                        ? const Color(0xFF15803d)
                        : const Color(0xFFb45309),
                  ),
                ),
                child: Text(
                  _lastResult,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _lastResult.startsWith('✅')
                        ? const Color(0xFF15803d)
                        : const Color(0xFFb45309),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
