import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:herbalwisdom/features/home/models/banner_items.dart';
import 'package:herbalwisdom/features/home/repo/banner_repo.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../common/widgets/back_exit_guard.dart';
import '../../../common/utils/link_utils.dart';
import '../../../app/theme/typography.dart';

import '../../vouchers/models/vouchers.dart';
import '../../vouchers/repo/vouchers_repo.dart';
import '../../vouchers/view/vouchers_details_screen.dart';
import '../../vouchers/view/vouchers_list_screen.dart';
import '../../news/view/news_screen.dart';

// 👇 ADD this import (adjust path if different in your project)
import '../../auth/repo/auth_repo.dart';

class HomeScreen extends StatefulWidget {
  static const routePath = '/home';
  static const routeName = 'home';
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _vouchers = VouchersRepo();
  final _bannersRepo = BannersRepo();

  // 👇 Auth repo for logout
  final _authRepo = AuthRepo();

  late Future<List<Voucher>> _specialCouponFuture;
  late Future<List<BannerItem>> _bannersFuture;

  int _activeBanner = 0;

  @override
  void initState() {
    super.initState();
    _specialCouponFuture = _fetchSpecialCoupon();
    _bannersFuture = _bannersRepo.fetchAll();
  }

  Future<List<Voucher>> _fetchSpecialCoupon() async {
    try {
      // Fetch both active and used coupons
      await _vouchers.fetchAll(type: 'ACTIVE');
      await _vouchers.fetchAll(type: 'USED');

      // After fetching both, get all from cache and filter special coupons
      final allCached = await _vouchers.fetchAll(
        type: 'ACTIVE',
      ); // This returns from merged cache
      final allVouchers = [
        ...allCached,
        ...await _vouchers.fetchAll(type: 'USED'),
      ];

      // Remove duplicates and filter special coupons
      final Map<String, Voucher> uniqueMap = {};
      for (final v in allVouchers) {
        uniqueMap[v.id] = v;
      }

      return uniqueMap.values.where((v) => v.specialCoupon).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _refreshSpecialCoupon() async {
    final fut = _fetchSpecialCoupon();
    setState(() {
      _specialCouponFuture = fut;
    });
    await fut;
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ---------- Logout ----------
  Future<void> _confirmLogout() async {
    final ctx = context;
    final theme = Theme.of(ctx);

    final bool? ok = await showDialog<bool>(
      context: ctx,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    await _authRepo.logout();

    // 👇 Go back to your auth / welcome route.
    // Change this to your real login route if needed.
    if (!mounted) return;
    context.go('/'); // e.g. root shows login/landing
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return BackExitGuard(
      child: Scaffold(
        appBar: AppBar(
          leading: Image.asset(
            'assets/icons/herbal_logo_transparent.png',
            height: 40,
          ),
          title: const Text('Herbal Wisdom'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: _confirmLogout,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshSpecialCoupon,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // =======================
              // 🚀 BANNERS CAROUSEL
              // =======================
              FutureBuilder<List<BannerItem>>(
                future: _bannersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    // 🟡 Shimmer placeholder for loading banners
                    return Shimmer.fromColors(
                      baseColor: Colors.grey.shade300,
                      highlightColor: Colors.grey.shade100,
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 8,
                            width: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final banners = snapshot.data!;
                  return Column(
                    children: [
                      CarouselSlider(
                        options: CarouselOptions(
                          aspectRatio: 16 / 9, // ✅ keep banner aspect ratio
                          enlargeCenterPage: true,
                          viewportFraction: 0.9,
                          autoPlay: true,
                          autoPlayInterval: const Duration(seconds: 8),
                          onPageChanged:
                              (index, reason) =>
                                  setState(() => _activeBanner = index),
                        ),
                        items:
                            banners.map((b) {
                              Widget bannerWidget;
                              if (b.type == 'TEXT') {
                                bannerWidget = Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Color(_parseColor(b.color)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        b.content,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                );
                              } else {
                                bannerWidget = ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Image.network(
                                      b.content,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder:
                                          (_, __, ___) => Container(
                                            color: Colors.grey.shade300,
                                            child: const Icon(
                                              Icons.broken_image,
                                            ),
                                          ),
                                    ),
                                  ),
                                );
                              }
                              return bannerWidget;
                            }).toList(),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSmoothIndicator(
                        activeIndex: _activeBanner,
                        count: banners.length,
                        effect: ExpandingDotsEffect(
                          dotHeight: 8,
                          dotWidth: 8,
                          spacing: 6,
                          activeDotColor: Theme.of(context).colorScheme.primary,
                          dotColor: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),

              // ==== Special Coupon + Specials section ====
              LayoutBuilder(
                builder: (context, box) {
                  final isWide = box.maxWidth >= 680;

                  final specialCouponsWidget = FutureBuilder<List<Voucher>>(
                    future: _specialCouponFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const _CompactSkeleton();
                      }

                      final vouchers = snap.data ?? [];
                      if (vouchers.isEmpty) return const SizedBox.shrink();

                      return Column(
                        children:
                            vouchers.map((v) {
                              final expired = v.expiryDate.isBefore(
                                DateTime.now(),
                              );
                              final used = v.used == true;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _MonthlyChipTile(
                                  title: v.title,
                                  status:
                                      used
                                          ? _Status.used
                                          : (expired
                                              ? _Status.expired
                                              : _Status.active),
                                  expiresText: 'Expires ${_fmt(v.expiryDate)}',
                                  onTap: () async {
                                    final changed = await context.push<bool?>(
                                      '${VoucherDetailScreen.routeBase}/${v.id}',
                                    );
                                    if (changed == true)
                                      await _refreshSpecialCoupon();
                                  },
                                  onUse: () async {
                                    if (v.used || expired) return;

                                    // Show confirmation dialog
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder:
                                          (context) => AlertDialog(
                                            title: const Text('Use Voucher'),
                                            content: const Text(
                                              'Are you sure you want to use this voucher?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.of(
                                                      context,
                                                    ).pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed:
                                                    () => Navigator.of(
                                                      context,
                                                    ).pop(true),
                                                child: const Text('Use'),
                                              ),
                                            ],
                                          ),
                                    );

                                    if (confirmed != true) return;

                                    try {
                                      await _vouchers.markUsed(v.id);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Voucher marked used successfully!',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Unable to use voucher. Please try again.',
                                          ),
                                        ),
                                      );
                                    }

                                    if (!mounted) return;
                                    await _refreshSpecialCoupon();
                                  },
                                ),
                              );
                            }).toList(),
                      );
                    },
                  );

                  final specials = _SpecialsChipTile(
                    title: 'Special offers',
                    subtitle: 'View all current deals',
                    onTap: () => context.push(VouchersListScreen.routePath),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: specialCouponsWidget),
                        const SizedBox(width: 8),
                        Expanded(child: specials),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      specialCouponsWidget,
                      const SizedBox(height: 8),
                      specials,
                    ],
                  );
                },
              ),

              // ==== Quick Actions ====
              const SizedBox(height: 16),
              _ActionChipTile(
                icon: Icons.medical_services_outlined,
                title: 'Naturopath',
                subtitle: 'Book',
                onTap:
                    () => LinkUtils.open(
                      "https://www.herbalwisdom.com.au/our-practitioners",
                    ),
              ),
              const SizedBox(height: 8),
              _ActionChipTile(
                icon: Icons.self_improvement_outlined,
                title: 'Massage',
                subtitle: 'Book',
                onTap:
                    () => LinkUtils.open(
                      "https://www.fresha.com/a/bangalow-massage-herbal-wisdom-bangalow-64-byron-street-mmiawqte?pId=66982",
                    ),
              ),
              const SizedBox(height: 8),
              _ActionChipTile(
                icon: Icons.article_outlined,
                title: 'News',
                subtitle: 'Updates',
                onTap: () => context.push(NewsScreen.routePath),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Helpers ----------
  int _parseColor(String hex) {
    if (hex.isEmpty) return 0xFF444444;
    String cleaned = hex.replaceAll('#', '');
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    return int.tryParse('0x$cleaned') ?? 0xFF444444;
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// ================= Hero Banner =================
enum _Status { active, used, expired }

class _MonthlyChipTile extends StatelessWidget {
  final String title;
  final _Status status;
  final String expiresText;
  final VoidCallback onTap;
  final Future<void> Function()? onUse;

  const _MonthlyChipTile({
    required this.title,
    required this.status,
    required this.expiresText,
    required this.onTap,
    this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    Color fg;
    String label;
    IconData icon;
    switch (status) {
      case _Status.used:
        fg = Colors.grey.shade700;
        label = 'Used';
        icon = Icons.check_circle_outline;
        break;
      case _Status.expired:
        fg = Colors.red.shade700;
        label = 'Expired';
        icon = Icons.lock_clock;
        break;
      default:
        fg = Colors.green.shade700;
        label = 'Active';
        icon = Icons.local_offer_outlined;
    }

    final bool canUse = status == _Status.active;
    final bool showUse = status == _Status.active || status == _Status.expired;

    final Widget trailing =
        showUse
            ? FilledButton.tonal(
              onPressed: canUse && onUse != null ? () => onUse!() : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Use'),
            )
            : const Icon(Icons.chevron_right);

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: fg.withOpacity(.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: fg, size: 22),
        ),
        title: Text(title, style: ts.titleMedium?.copyWith(fontSize: 14)),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: fg.withOpacity(.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label, style: ts.labelMedium!.copyWith(color: fg)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Opacity(
                opacity: .8,
                child: Text(
                  expiresText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        trailing: trailing,
        onTap: onTap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      ),
    );
  }
}

class _SpecialsChipTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SpecialsChipTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: primary.withOpacity(.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.favorite_border, color: primary, size: 22),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Opacity(
          opacity: .8,
          child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      ),
    );
  }
}

class _ActionChipTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionChipTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: primary.withOpacity(.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: primary, size: 22),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Opacity(
          opacity: .8,
          child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      ),
    );
  }
}

class _CompactSkeleton extends StatelessWidget {
  const _CompactSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        title: const SizedBox(height: 14, child: LinearProgressIndicator()),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: SizedBox(height: 12, child: LinearProgressIndicator()),
        ),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      ),
    );
  }
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: const ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Icon(Icons.local_offer_outlined),
        title: Text('Monthly 10% coupon unavailable'),
        subtitle: Text('Please check back later'),
        visualDensity: VisualDensity(horizontal: -2, vertical: -2),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? statusLabel;
  final Color? statusColor;

  const _HeroBanner({
    required this.title,
    required this.subtitle,
    this.statusLabel,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return Container(
      height: 170,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        image: const DecorationImage(
          image: NetworkImage(
            'https://images.unsplash.com/photo-1589923188900-85dae523342b?w=1600',
          ),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black38, BlendMode.darken),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            bottom: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ts.headlineSmall!.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: ts.bodyMedium!.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          if (statusLabel != null)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (statusColor ?? Colors.black87).withOpacity(.85),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Monthly 10%: $statusLabel',
                  style: ts.labelLarge!.copyWith(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
