import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  try {
    await initNotifications();
  } catch (e) {
    debugPrint('Erreur init notifications: $e');
  }
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

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final SmsQuery query = SmsQuery();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _waveSenderController = TextEditingController(
    text: 'WAVE CI',
  );
  final TextEditingController _omSenderController = TextEditingController(
    text: 'Orange Money',
  );

  late TabController _tabController;

  bool _isListening = false;
  bool _isConnected = false;
  String _lastActivity = 'En attente...';
  String _lastResult = '';

  List<dynamic> _unpaidOrders = [];
  bool _loadingOrders = false;

  // Historique des paiements détectés
  List<Map<String, String>> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);

    try {
      // ✅ _processMissedSms s'exécute APRÈS _loadSettings
      _loadSettings().then((_) {
        _startSmsListener();
      });
      _startNotificationListener();
      _loadUnpaidOrders();
    } catch (e) {
      debugPrint('Erreur initState: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  // ✅ Ajoute cette méthode — appelée quand l'app revient au premier plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Réinitialise l'écoute des notifications quand l'app revient
      _startNotificationListener();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token') ?? '';
    final waveSender = prefs.getString('wave_sender') ?? 'WAVE CI';
    final omSender = prefs.getString('om_sender') ?? 'Orange Money';

    setState(() {
      _tokenController.text = token;
      _waveSenderController.text = waveSender;
      _omSenderController.text = omSender;
      SmsParser.waveSenderName = waveSender;
      SmsParser.omSenderName = omSender;
    });
  }

  static const _smsChannel = EventChannel('msy_secret/sms');

  Future<void> _startSmsListener() async {
    final permission = await Permission.sms.request();
    if (!permission.isGranted) return;

    _smsChannel.receiveBroadcastStream().listen((event) async {
      final sender = event['address'] as String? ?? '';
      final body = event['body'] as String? ?? '';

      debugPrint('SMS reçu de: $sender | $body');

      final result = SmsParser.parse(body, sender);
      if (result == null) {
        setState(() => _lastResult = '❌ SMS ignoré — $sender');
        return;
      }

      setState(() {
        _lastActivity = '[SMS OM]\n$body';
        _lastResult = '✅ OM — ${result['amount']} FCFA de ${result['phone']}';
      });

      final response = await ApiService.notifyPayment(
        amount: result['amount'],
        phone: result['phone'],
        paymentMethod: result['payment_method'],
      );

      _addToHistory(
        method: 'orange_money',
        amount: result['amount'].toString(),
        phone: result['phone'],
        order: response['order_number'] ?? '',
        success: response['success'] == true,
      );

      if (response['success'] == true) {
        _loadUnpaidOrders();
        await _showNotification(
          title: '✅ Paiement OM confirmé',
          body:
              'Commande ${response['order_number']} — ${result['amount'].toStringAsFixed(0)} FCFA',
        );
      } else {
        await _showNotification(
          title: '⚠️ Paiement OM non trouvé',
          body:
              '${result['amount'].toStringAsFixed(0)} FCFA de ${result['phone']}',
        );
      }
    });

    setState(() => _isListening = true);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_token', _tokenController.text.trim());
    debugPrint('Token sauvegardé: ${_tokenController.text.trim()}');
    await prefs.setString('wave_sender', _waveSenderController.text.trim());
    await prefs.setString('om_sender', _omSenderController.text.trim());

    SmsParser.waveSenderName = _waveSenderController.text.trim();
    SmsParser.omSenderName = _omSenderController.text.trim();
    await _loadUnpaidOrders();
    await ApiService.saveToken(_tokenController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Paramètres sauvegardés ✅')));
    }
  }

  Future<void> _testConnection() async {
    final result = await ApiService.ping();
    setState(() => _isConnected = result['success'] == true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? '✅ Connexion OK'
                : '❌ ${result['message']}',
          ),
        ),
      );
    }
  }

  Future<void> _loadUnpaidOrders() async {
    setState(() => _loadingOrders = true);
    final orders = await ApiService.getUnpaidOrders();
    debugPrint('Commandes reçues: ${orders.length}');
    setState(() {
      _unpaidOrders = orders;
      _loadingOrders = false;
    });
  }

  Future<void> _refreshOrders() async {
    await _loadUnpaidOrders();
    await _startSmsListener();
  }

  Future<void> _confirmOrder(int orderId, String paymentMethod) async {
    final result = await ApiService.confirmPayment(
      orderId: orderId,
      paymentMethod: paymentMethod,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? '✅ Commande ${result['order_number']} confirmée'
                : '❌ ${result['message']}',
          ),
        ),
      );
    }

    if (result['success'] == true) {
      _loadUnpaidOrders();
    }
  }

  Future<void> _updatePaymentPhone(int orderId, String phone) async {
    final result = await ApiService.updatePaymentPhone(
      orderId: orderId,
      phone: phone,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? '✅ Numéro mis à jour'
                : '❌ ${result['message']}',
          ),
        ),
      );
    }
  }

  Future<void> _processMissedSms() async {
    final permission = await Permission.sms.request();
    debugPrint('Permission SMS: $permission');

    if (!permission.isGranted) return;
    debugPrint('Sender OM: ${SmsParser.omSenderName}');

    final messages = await query.querySms(
      kinds: [SmsQueryKind.inbox],
      address: SmsParser.omSenderName,
      count: 50,
    );
    debugPrint('Nombre de SMS trouvés: ${messages.length}');

    final cutoff = DateTime.now().subtract(const Duration(hours: 48));

    for (final msg in messages) {
      debugPrint('FROM: ${msg.address} | BODY: ${msg.body?.substring(0, 30)}');

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
        _addToHistory(
          method: 'orange_money',
          amount: result['amount'].toString(),
          phone: result['phone'],
          order: response['order_number'] ?? '',
          success: true,
        );
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

      setState(() => _lastActivity = '[Wave]\n$body');

      final result = SmsParser.parseWaveNotification(body);

      if (result == null) {
        setState(() => _lastResult = '❌ Notification Wave ignorée');
        return;
      }

      setState(() {
        _lastResult = '✅ Wave — ${result['amount']} FCFA de ${result['phone']}';
      });

      final response = await ApiService.notifyPayment(
        amount: result['amount'],
        phone: result['phone'],
        paymentMethod: result['payment_method'],
      );

      _addToHistory(
        method: 'wave',
        amount: result['amount'].toString(),
        phone: result['phone'],
        order: response['order_number'] ?? '',
        success: response['success'] == true,
      );

      if (response['success'] == true) {
        _loadUnpaidOrders();
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

  void _addToHistory({
    required String method,
    required String amount,
    required String phone,
    required String order,
    required bool success,
  }) {
    setState(() {
      _history.insert(0, {
        'method': method,
        'amount': amount,
        'phone': phone,
        'order': order,
        'success': success.toString(),
        'time': TimeOfDay.now().format(context),
      });
      if (_history.length > 20) _history.removeLast();
    });
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
        actions: [
          // Statut connexion
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4D0E14)),
            onPressed: _refreshOrders, // ✅ Au lieu de _loadUnpaidOrders
            tooltip: 'Rafraîchir',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFEEE0CB),
          unselectedLabelColor: const Color(0xFF4D0E14),
          indicatorColor: const Color(0xFFEEE0CB),
          tabs: const [
            Tab(icon: Icon(Icons.sms), text: 'Activité'),
            Tab(icon: Icon(Icons.list_alt), text: 'Commandes'),
            Tab(icon: Icon(Icons.settings), text: 'Config'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildActivityTab(), _buildOrdersTab(), _buildConfigTab()],
      ),
    );
  }

  // ===== ONGLET ACTIVITÉ =====
  Widget _buildActivityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Statut écoute
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
                      ? 'En écoute — Wave & Orange Money'
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

          // Dernière activité
          _sectionTitle('DERNIÈRE ACTIVITÉ'),
          const SizedBox(height: 8),
          _card(
            child: Text(
              _lastActivity,
              style: const TextStyle(fontSize: 13, color: Color(0xFF110201)),
            ),
          ),

          if (_lastResult.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('RÉSULTAT'),
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

          const SizedBox(height: 20),

          // Historique
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('HISTORIQUE'),
              TextButton(
                onPressed: () => setState(() => _history.clear()),
                child: const Text(
                  'Effacer',
                  style: TextStyle(color: Color(0xFF4D0E14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_history.isEmpty)
            _card(
              child: const Text(
                'Aucune activité récente.',
                style: TextStyle(color: Color(0xFF4D0E14)),
              ),
            )
          else
            ..._history.map(
              (h) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: h['success'] == 'true'
                      ? const Color(0xFFf0fdf4)
                      : const Color(0xFFfef9ec),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: h['success'] == 'true'
                        ? const Color(0xFF15803d)
                        : const Color(0xFFb45309),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      h['method'] == 'wave' ? '💙' : '🧡',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${h['amount']} FCFA de ${h['phone']}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF110201),
                            ),
                          ),
                          if (h['order']!.isNotEmpty)
                            Text(
                              'Commande ${h['order']}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF4D0E14),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      h['time'] ?? '',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4D0E14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===== ONGLET COMMANDES =====
  Widget _buildOrdersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_unpaidOrders.length} commande(s) en attente',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF110201),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF4D0E14)),
                onPressed: _loadUnpaidOrders,
                tooltip: 'Rafraîchir',
              ),
            ],
          ),
        ),

        if (_loadingOrders)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF4D0E14)),
            ),
          )
        else if (_unpaidOrders.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                '✅ Aucune commande en attente',
                style: TextStyle(color: Color(0xFF4D0E14)),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _unpaidOrders.length,
              itemBuilder: (context, index) {
                final order = _unpaidOrders[index];
                return _OrderCard(
                  order: order,
                  onConfirm: (method) => _confirmOrder(order['id'], method),
                  onUpdatePhone: (phone) =>
                      _updatePaymentPhone(order['id'], phone),
                  onCopyNumber: () {
                    Clipboard.setData(
                      ClipboardData(text: order['order_number'] ?? ''),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Numéro copié ✅')),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  // ===== ONGLET CONFIG =====
  Widget _buildConfigTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('TOKEN API LARAVEL'),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            decoration: _inputDecoration('1|xxxxxxxxxxxxxxxxxxxx'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),

          const SizedBox(height: 20),

          _sectionTitle('NOM EXPÉDITEUR WAVE'),
          const SizedBox(height: 8),
          TextField(
            controller: _waveSenderController,
            decoration: _inputDecoration('ex: WAVE CI'),
          ),

          const SizedBox(height: 16),

          _sectionTitle('NOM EXPÉDITEUR ORANGE MONEY'),
          const SizedBox(height: 8),
          TextField(
            controller: _omSenderController,
            decoration: _inputDecoration('ex: Orange Money'),
          ),

          const SizedBox(height: 24),

          // Bouton sauvegarder
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4D0E14),
                foregroundColor: const Color(0xFFEEE0CB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Sauvegarder les paramètres'),
            ),
          ),

          const SizedBox(height: 12),

          // Bouton test connexion
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testConnection,
              icon: Icon(
                _isConnected ? Icons.cloud_done : Icons.cloud_off,
                color: _isConnected
                    ? const Color(0xFF15803d)
                    : const Color(0xFFdc2626),
              ),
              label: Text(
                _isConnected ? 'Connexion active' : 'Tester la connexion',
                style: TextStyle(
                  color: _isConnected
                      ? const Color(0xFF15803d)
                      : const Color(0xFFdc2626),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: _isConnected
                      ? const Color(0xFF15803d)
                      : const Color(0xFFdc2626),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      letterSpacing: 2,
      color: Color(0xFF4D0E14),
      fontWeight: FontWeight.bold,
    ),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFd4c4ae)),
    ),
    child: child,
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
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
  );
}

// ===== WIDGET CARTE COMMANDE =====
class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final Function(String) onConfirm;
  final Function(String) onUpdatePhone;
  final VoidCallback onCopyNumber;

  const _OrderCard({
    required this.order,
    required this.onConfirm,
    required this.onUpdatePhone,
    required this.onCopyNumber,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _editingPhone = false;
  String _selectedMethod = 'wave';
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(
      text:
          widget.order['payment_phone'] ?? widget.order['customer_phone'] ?? '',
    );
    // ✅ Initialise avec la valeur reçue du serveur
    _selectedMethod = widget.order['payment_method'] ?? 'wave';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFd4c4ae)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header commande
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: widget.onCopyNumber,
                  child: Text(
                    order['order_number'] ?? '#${order['id']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF110201),
                    ),
                  ),
                ),
              ),
              Text(
                order['created_at'] ?? '',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4D0E14)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Montant
          Text(
            '${double.tryParse(order['total_amount'].toString())?.toStringAsFixed(0) ?? order['total_amount']} FCFA',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4D0E14),
            ),
          ),

          const SizedBox(height: 4),

          // Numéro contact
          Text(
            'Contact : ${order['customer_phone']}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF110201)),
          ),

          const SizedBox(height: 8),

          // Numéro paiement éditable
          if (_editingPhone) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      hintText: 'Numéro de paiement',
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFf9f6f1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFd4c4ae)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    widget.onUpdatePhone(_phoneController.text);
                    setState(() => _editingPhone = false);
                  },
                  child: const Text(
                    'OK',
                    style: TextStyle(color: Color(0xFF4D0E14)),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _editingPhone = false),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Color(0xFFdc2626)),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Text(
                  'Paiement : ${order['payment_phone'] ?? order['customer_phone']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF110201),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _editingPhone = true),
                  child: const Icon(
                    Icons.edit,
                    size: 14,
                    color: Color(0xFF4D0E14),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Sélection méthode + bouton confirmer
          Row(
            children: [
              // Dropdown méthode
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFd4c4ae)),
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFFf9f6f1),
                ),
                child: DropdownButton<String>(
                  value: _selectedMethod,
                  isDense: true,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF110201),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'wave', child: Text('💙 Wave')),
                    DropdownMenuItem(
                      value: 'orange_money',
                      child: Text('🧡 Orange Money'),
                    ),
                  ],
                  onChanged: (val) => setState(() => _selectedMethod = val!),
                ),
              ),

              const SizedBox(width: 8),

              // Bouton confirmer
              Expanded(
                child: ElevatedButton(
                  onPressed: () => widget.onConfirm(_selectedMethod),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4D0E14),
                    foregroundColor: const Color(0xFFEEE0CB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    'Confirmer',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
