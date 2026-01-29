import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../models/vouchers.dart';
import '../repo/vouchers_repo.dart';

class VoucherDetailScreen extends StatefulWidget {
  static const routeBase = '/vouchers';
  static const subPath = ':id';
  static const routeName = 'voucherDetail';

  final String voucherId;
  const VoucherDetailScreen({super.key, required this.voucherId});

  @override
  State<VoucherDetailScreen> createState() => _VoucherDetailScreenState();
}

class _VoucherDetailScreenState extends State<VoucherDetailScreen> {
  final _repo = VouchersRepo();
  Voucher? _voucher;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _repo.getById(widget.voucherId);
    if (!mounted) return;
    setState(() => _voucher = v);
  }

  Future<void> _useVoucher() async {
    final v = _voucher;
    if (v == null) return;
    if (v.used) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already used.')));
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Use Voucher'),
            content: const Text('Are you sure you want to use this voucher?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Use')),
            ],
          ),
    );

    if (confirmed != true) return;

    await _repo.markUsed(v.id);
    final updated = await _repo.getById(v.id);
    if (!mounted) return;
    setState(() {
      _voucher = updated;
      _changed = true; // tell previous screen to refresh
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as used')));
  }

  void _popWithResult() {
    // Return whether anything changed; VouchersList can decide to reload
    context.pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return WillPopScope(
      onWillPop: () async {
        _popWithResult();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Voucher'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _popWithResult, tooltip: 'Back')),
        body:
            _voucher == null
                ? Shimmer.fromColors(
                  baseColor: Colors.grey.shade300,
                  highlightColor: Colors.grey.shade100,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Title
                      Container(height: 32, width: 200, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 16),
                      // Chips
                      Row(
                        children: [
                          Container(height: 32, width: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
                          const SizedBox(width: 8),
                          Container(height: 32, width: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Description
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 16, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 8),
                          Container(height: 16, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 8),
                          Container(height: 16, width: 200, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                        ],
                      ),
                      const SizedBox(height: 40),
                      // Button
                      Container(height: 48, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
                    ],
                  ),
                )
                : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(_voucher!.title, style: ts.headlineSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text(_voucher!.used ? 'Used' : (_voucher!.expired ? 'Expired' : 'Active'))),
                        Chip(label: Text('Expires ${_fmt(_voucher!.expiryDate)}')),
                        if (_voucher!.usedAt != null) Chip(label: Text('Used on ${_fmt(_voucher!.usedAt!)}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(_voucher!.description, style: ts.bodyLarge),
                    const SizedBox(height: 20),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: (_voucher!.used || _voucher!.expired) ? null : _useVoucher, child: Text(_voucher!.used ? 'Already used' : 'Use'))),
                  ],
                ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
