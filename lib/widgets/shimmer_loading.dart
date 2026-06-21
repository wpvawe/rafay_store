import 'package:flutter/material.dart';

/// A lightweight shimmer widget that works without any external package.
/// Uses a sweeping LinearGradient animation over a base color.
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({super.key, required this.child});
  final Widget child;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(_anim.value - 1, 0),
          end: Alignment(_anim.value + 1, 0),
          colors: const [
            Color(0xFFE8E8E8),
            Color(0xFFF5F5F5),
            Color(0xFFFFFFFF),
            Color(0xFFF5F5F5),
            Color(0xFFE8E8E8),
          ],
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ── Ready-made shimmer cards ────────────────────────────────────────────────

/// A rectangular shimmer placeholder box.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// A single shimmer card for a demand list item.
class DemandItemShimmer extends StatelessWidget {
  const DemandItemShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent strip shimmer
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(11),
                      bottomLeft: Radius.circular(11),
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShimmerBox(width: 180, height: 14),
                              const SizedBox(height: 6),
                              ShimmerBox(width: 100, height: 11),
                              const SizedBox(height: 8),
                              Row(children: [
                                ShimmerBox(width: 70, height: 22, borderRadius: 20),
                                const SizedBox(width: 6),
                                ShimmerBox(width: 55, height: 22, borderRadius: 20),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShimmerBox(width: 70, height: 26, borderRadius: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

/// A single shimmer card for a supplier list item.
class SupplierItemShimmer extends StatelessWidget {
  const SupplierItemShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 44, height: 44, borderRadius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 140, height: 14),
                    const SizedBox(height: 7),
                    ShimmerBox(width: 100, height: 11),
                    const SizedBox(height: 7),
                    ShimmerBox(width: 180, height: 11),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ShimmerBox(width: 88, height: 26, borderRadius: 20),
                        const SizedBox(width: 8),
                        ShimmerBox(width: 68, height: 26, borderRadius: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders [count] shimmer placeholders inside a scrollable list.
class ShimmerList extends StatelessWidget {
  const ShimmerList({
    super.key,
    required this.count,
    required this.itemBuilder,
  });

  final int count;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: itemBuilder,
    );
  }
}
