import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../models/vouchers.dart';
import '../repo/vouchers_repo.dart';
import '../../../common/widgets/error_view.dart';

class VouchersListScreen extends StatefulWidget {
  static const routePath = '/vouchers';
  static const routeName = 'vouchers';
  const VouchersListScreen({super.key});

  @override
  State<VouchersListScreen> createState() => _VouchersListScreenState();
}

class _VouchersListScreenState extends State<VouchersListScreen> {
  final _repo = VouchersRepo();

  // Separate cached futures for each tab
  Future<List<Voucher>>? _activeFuture;
  Future<List<Voucher>>? _usedFuture;

  // Cached data for each tab to prevent flickering
  List<Voucher>? _activeData;
  List<Voucher>? _usedData;

  /// ACTIVE or USED (matches API `type` param)
  String _filter = 'ACTIVE';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _busy = false;

  // Helper getter to select the appropriate future based on current filter
  Future<List<Voucher>>? get _currentFuture {
    return _filter == 'ACTIVE' ? _activeFuture : _usedFuture;
  }

  // Helper getter to select cached data based on current filter
  List<Voucher>? get _currentData {
    return _filter == 'ACTIVE' ? _activeData : _usedData;
  }

  @override
  void initState() {
    super.initState();
    // Only load ACTIVE tab initially
    _activeFuture = _repo.fetchAll(type: 'ACTIVE').then((data) {
      setState(() => _activeData = data);
      return data;
    });
    _searchCtrl.addListener(() {
      if (_query != _searchCtrl.text) {
        setState(() => _query = _searchCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final fut = _repo.fetchAll(type: _filter).then((data) {
      if (mounted) {
        setState(() {
          if (_filter == 'ACTIVE') {
            _activeData = data;
          } else {
            _usedData = data;
          }
        });
      }
      return data;
    });

    setState(() {
      if (_filter == 'ACTIVE') {
        _activeFuture = fut;
      } else {
        _usedFuture = fut;
      }
    });
    await fut;
  }

  Future<void> _useVoucher(Voucher v) async {
    if (_busy) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Use Voucher'),
            content: const Text('Are you sure you want to use this voucher?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Use'),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _repo.markUsed(v.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as used')));
      // Refresh used tab data as the voucher has moved to USED
      _repo.fetchAll(type: 'USED').then((data) {
        if (mounted) {
          setState(() {
            _usedData = data;
            _usedFuture = Future.value(data);
          });
        }
      });
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Specials')),
      body: FutureBuilder<List<Voucher>>(
        future: _currentFuture,
        builder: (_, s) {
          // Use cached data immediately if available to prevent flickering
          final bool loading =
              s.connectionState == ConnectionState.waiting &&
              _currentData == null;
          final hasError = s.hasError && !loading;

          // Base list of items - prefer cached data to prevent shimmer
          var items = <Voucher>[];
          if (_currentData != null) {
            // Always use cached data if available, regardless of loading state
            items = List<Voucher>.from(s.data ?? _currentData!);
            items.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
            items = items.where((v) => !v.specialCoupon).toList();

            // Apply search
            final q = _query.trim();
            if (q.isNotEmpty) {
              items = items.where((v) => _matchesQuery(v, q)).toList();
            }
          } else if (!loading && !hasError) {
            // Only use snapshot data if we don't have cache yet
            items = List<Voucher>.from(s.data ?? const []);
            items.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
            items = items.where((v) => !v.specialCoupon).toList();

            // Apply search
            final q = _query.trim();
            if (q.isNotEmpty) {
              items = items.where((v) => _matchesQuery(v, q)).toList();
            }
          }

          // 0: search, 1: filter, rest: list/empty/loading/error
          final int listCount;
          if (loading) {
            listCount = 3; // 3 shimmer rows
          } else if (hasError) {
            listCount = 1; // error view
          } else if (items.isEmpty) {
            listCount = 1; // one small "no vouchers" card
          } else {
            listCount = items.length;
          }

          final totalCount = 2 + listCount;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: totalCount,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                // 0 → Search bar
                if (i == 0) {
                  return _SearchBar(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onClear: () {
                      _searchCtrl.clear();
                      _searchFocus.requestFocus();
                    },
                  );
                }

                // 1 → Filter bar
                if (i == 1) {
                  return _FilterBar(
                    current: _filter,
                    onChanged: (f) {
                      if (_filter == f) return;

                      setState(() {
                        _filter = f;

                        // Only fetch if we haven't loaded this tab yet
                        if (f == 'ACTIVE' && _activeFuture == null) {
                          _activeFuture = _repo.fetchAll(type: 'ACTIVE').then((
                            data,
                          ) {
                            if (mounted) setState(() => _activeData = data);
                            return data;
                          });
                        } else if (f == 'USED' && _usedFuture == null) {
                          _usedFuture = _repo.fetchAll(type: 'USED').then((
                            data,
                          ) {
                            if (mounted) setState(() => _usedData = data);
                            return data;
                          });
                        }
                      });
                    },
                  );
                }

                // From here down we are "under the tabs"

                // ⏳ Loading shimmer rows (only under tabs)
                if (loading) {
                  return Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Card(
                      elevation: 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        title: Container(
                          height: 16,
                          width: double.infinity,
                          color: Colors.grey.shade300,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 12,
                                width: 120,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: 12,
                                width: 80,
                                color: Colors.grey.shade300,
                              ),
                            ],
                          ),
                        ),
                        trailing: Container(
                          width: 60,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // ⚠️ ERROR state - show friendly error message
                if (hasError) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: ErrorView(
                      title: 'Unable to load vouchers',
                      message:
                          'Please check your internet connection and try again.',
                      onRetry: _reload,
                    ),
                  );
                }

                // 📨 Empty state (either truly empty) – simple, no error box
                if (items.isEmpty) {
                  return Card(
                    elevation: 0.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.inbox_outlined,
                                size: 28,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'No vouchers found',
                                  style: ts.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Opacity(
                            opacity: .8,
                            child: Text(
                              _query.trim().isNotEmpty
                                  ? 'Try a different search keyword or clear search.'
                                  : 'Pull to refresh or try again later.',
                              style: ts.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // ✅ Normal list items start at index 2
                final v = items[i - 2];
                final expired = v.expired;
                final used = v.used;
                final status =
                    used
                        ? _Status.used
                        : (expired ? _Status.expired : _Status.active);
                final icon = _iconForVoucher(v);
                final color = _colorForStatus(context, status);
                final bool canUse = status == _Status.active;

                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: 1,
                  child: Card(
                    elevation: 0.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withOpacity(.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      title: _highlight(
                        v.title,
                        _query,
                        ts.titleMedium!.copyWith(fontSize: 14),
                      ),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _labelForStatus(status),
                              style: ts.labelMedium!.copyWith(color: color),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Opacity(
                              opacity: .8,
                              child: _highlight(
                                'Expires ${_fmt(v.expiryDate)}',
                                _query,
                                ts.bodyMedium!,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing:
                          canUse
                              ? FilledButton.tonal(
                                onPressed: _busy ? null : () => _useVoucher(v),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Use'),
                              )
                              : const Icon(Icons.chevron_right),
                      onTap: () async {
                        await context.push(
                          '${VouchersListScreen.routePath}/${v.id}',
                        );
                        _reload();
                      },
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ---------- Helpers ----------

  bool _matchesQuery(Voucher v, String query) {
    final q = query.toLowerCase();
    final title = v.title.toLowerCase();
    final desc = v.description.toLowerCase();
    final date = _fmt(v.expiryDate).toLowerCase();

    final tokens = <String>[
      title,
      desc,
      date,
      v.used ? 'used' : 'active',
      v.expired ? 'expired' : '',
      if (title.contains('monthly') || title.contains('member'))
        'member monthly',
    ].where((s) => s.isNotEmpty).join(' ');

    return tokens.contains(q);
  }

  IconData _iconForVoucher(Voucher v) {
    final t = v.title.toLowerCase();
    if (t.contains('massage')) return Icons.self_improvement_outlined;
    if (t.contains('fish')) return Icons.set_meal_outlined;
    if (t.contains('spend') || t.contains('\$')) {
      return Icons.shopping_bag_outlined;
    }
    if (t.contains('member') || t.contains('monthly')) {
      return Icons.local_offer_outlined;
    }
    if (t.contains('herbal') ||
        t.contains('supplement') ||
        t.contains('immune')) {
      return Icons.medication_liquid_outlined;
    }
    if (t.contains('tea')) return Icons.local_cafe_outlined;
    return Icons.card_giftcard_outlined;
  }

  Color _colorForStatus(BuildContext context, _Status s) {
    switch (s) {
      case _Status.used:
        return Colors.grey.shade700;
      case _Status.expired:
        return Colors.red.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  String _labelForStatus(_Status s) {
    switch (s) {
      case _Status.used:
        return 'Used';
      case _Status.expired:
        return 'Expired';
      default:
        return 'Active';
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Widget _highlight(String text, String query, TextStyle base) {
    if (query.isEmpty) {
      return Text(text, style: base);
    }

    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final start = lower.indexOf(q);
    if (start < 0) {
      return Text(
        text,
        style: base,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final end = start + q.length;

    return RichText(
      text: TextSpan(
        style: base,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: base.copyWith(
              backgroundColor: Colors.yellow.withOpacity(.4),
            ),
          ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }
}

enum _Status { active, used, expired }

class _FilterBar extends StatelessWidget {
  final String current; // "ACTIVE" or "USED"
  final ValueChanged<String>? onChanged;
  const _FilterBar({this.current = 'ACTIVE', this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = const ['ACTIVE', 'USED'];
    return Wrap(
      spacing: 8,
      children: [
        for (final k in opts)
          ChoiceChip(
            selected: current == k,
            label: Text(k[0] + k.substring(1).toLowerCase()),
            onSelected:
                onChanged == null
                    ? null
                    : (sel) {
                      if (sel) onChanged!(k);
                    },
          ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onClear;
  const _SearchBar({required this.controller, this.focusNode, this.onClear});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onTapOutside: (event) => focusNode?.unfocus(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search vouchers…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon:
            controller.text.isEmpty
                ? null
                : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }
}
