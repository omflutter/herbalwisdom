import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import 'package:flutter/rendering.dart';

/// A polished auth layout:
/// - Gradient herbal background
/// - On wide screens: left brand/visual panel + right form
/// - On phones: stacked hero + form card
class AuthFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget form;
  final Widget? footer; // e.g., "Don't have an account?"
  final Widget? topRightAction; // e.g., close/back override
  final String? heroImageUrl;

  const AuthFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    this.footer,
    this.topRightAction,
    this.heroImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEFF6F1), Color(0xFFDBEADF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final isWide = box.maxWidth >= 900;
            final content =
                isWide
                    ? Row(
                      children: [
                        // Visual / brand panel
                        Expanded(
                          child: _LeftVisualPanel(
                            title: 'Herbal Wisdom',
                            subtitle: 'Bangalow • NSW',
                            imageUrl:
                                heroImageUrl ??
                                'https://images.unsplash.com/photo-1545235617-9465d2a55698?w=1600',
                          ),
                        ),
                        // Form panel
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: _FormCard(
                                title: title,
                                subtitle: subtitle,
                                child: form,
                                footer: footer,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                    : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            children: [
                              _MobileHero(imageUrl: heroImageUrl),
                              const SizedBox(height: 16),
                              _FormCard(
                                title: title,
                                subtitle: subtitle,
                                child: form,
                                footer: footer,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

            return Stack(
              children: [
                Positioned.fill(child: content),
                if (topRightAction != null)
                  Positioned(top: 8, right: 8, child: topRightAction!),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  const _FormCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    return Card(
      elevation: 6,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: ts.bodyMedium!.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            child,
            if (footer != null) ...[
              const SizedBox(height: 14),
              const Divider(height: 24),
              Center(child: footer!),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeftVisualPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  const _LeftVisualPanel({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Image.asset(
              'assets/icons/herbal_title_logo.png',
              width: 300,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                '$title\n$subtitle',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall!.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileHero extends StatelessWidget {
  final String? imageUrl;
  const _MobileHero({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Image.asset(
                  'assets/icons/herbal_title_logo.png',
                  width: 220,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
