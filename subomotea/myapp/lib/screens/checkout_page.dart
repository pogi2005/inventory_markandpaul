import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../data/inventory_store.dart';
import '../ui/shared_widgets.dart';
// Xendit hosted checkout. Payment confirmation comes from the Xendit webhook.
// ---------------------------------------------------------------------------

const String kStoreName = 'Simple Inventory';
const Color kPayButton = Color(0xFF455F94);

class CheckoutPage extends StatefulWidget {
  /// {productId: quantity} of the items being paid.
  final Map<String, int> items;
  const CheckoutPage({super.key, required this.items});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  bool _processing = false;
  bool _waitingForPayment = false;
  bool _checkingPayment = false;
  String? _paymentId;
  Uri? _invoiceUrl;
  String? _statusMessage;
  Timer? _pollTimer;
  late double _total;
  late final String _description;

  @override
  void initState() {
    super.initState();
    double total = 0;
    final parts = <String>[];
    for (final entry in widget.items.entries) {
      final p = store.findProduct(entry.key);
      if (p == null) continue;
      total += p.price * entry.value;
      parts.add('${entry.value} × ${p.name}');
    }
    _total = roundMoney(total);
    _description = parts.join(', ');
  }

  Future<void> _pay() async {
    if (_processing || _waitingForPayment) return;
    setState(() => _processing = true);
    try {
      final invoice = await store.createXenditInvoice(widget.items);
      final paymentId = invoice['payment_id'] as String;
      final invoiceUrl = Uri.parse(invoice['invoice_url'] as String);
      final invoiceAmount = (invoice['amount'] as num).toDouble();
      final invoiceHost = invoiceUrl.host.toLowerCase();
      if (invoiceUrl.scheme != 'https' ||
          (invoiceHost != 'xendit.co' && !invoiceHost.endsWith('.xendit.co'))) {
        throw StateError('Xendit returned an invalid checkout link.');
      }
      if (!mounted) return;
      setState(() {
        _paymentId = paymentId;
        _invoiceUrl = invoiceUrl;
        _total = invoiceAmount;
        _processing = false;
        _waitingForPayment = true;
        _statusMessage = 'Complete payment in Xendit, then return here.';
      });
      await _openInvoice();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _checkPayment(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _waitingForPayment = false;
        _statusMessage = null;
      });
      showSnack(
        context,
        'Could not start Xendit checkout: $error',
        error: true,
      );
    }
  }

  Future<void> _openInvoice() async {
    final invoiceUrl = _invoiceUrl;
    if (invoiceUrl == null) return;
    try {
      final opened = await launchUrl(
        invoiceUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        showSnack(
          context,
          'Could not open the Xendit checkout page.',
          error: true,
        );
      }
    } catch (error) {
      if (mounted) {
        showSnack(
          context,
          'Could not open Xendit checkout: $error',
          error: true,
        );
      }
    }
  }

  Future<void> _checkPayment() async {
    final paymentId = _paymentId;
    if (paymentId == null || _checkingPayment) return;
    _checkingPayment = true;
    try {
      final status = await store.getPaymentStatus(paymentId);
      if (!mounted) return;
      if (status == 'paid') {
        _pollTimer?.cancel();
        Navigator.of(context).pop(true);
      } else if (status == 'failed') {
        _pollTimer?.cancel();
        setState(() {
          _waitingForPayment = false;
          _statusMessage = 'This invoice expired or payment failed. Try again.';
        });
      } else {
        setState(() {
          _statusMessage = 'Payment is not confirmed yet. Checking again…';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _statusMessage = 'Could not check payment status: $error',
        );
      }
    } finally {
      _checkingPayment = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Secure checkout',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          titleTextStyle: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEFC2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD9C27A)),
              ),
              child: const Text(
                'XENDIT',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: cardDecoration(),
              child: Column(
                children: [
                  Text('Pay $kStoreName', style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      peso(_total),
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _description,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Choose an available payment option on the secure Xendit page.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 28),
            if (_statusMessage != null) ...[
              Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
            ],
            if (_waitingForPayment) ...[
              OutlinedButton.icon(
                onPressed: _openInvoice,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Xendit checkout'),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _processing
                    ? null
                    : _waitingForPayment
                    ? _checkPayment
                    : _pay,
                style: FilledButton.styleFrom(
                  backgroundColor: kPayButton,
                  disabledBackgroundColor: kPayButton.withValues(alpha: 0.7),
                  shape: const StadiumBorder(),
                ),
                child: _processing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _waitingForPayment
                            ? 'Check payment status'
                            : 'Continue to Xendit · ${peso(_total)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your inventory is reserved until the invoice is paid or expires.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
