import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/category_model.dart';
import '../../models/demand_item_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/demand_provider.dart';

// ─── Internal data model ──────────────────────────────────────────────────────

class _CatData {
  final String name;
  final List<DemandItemModel> items;

  const _CatData({required this.name, required this.items});

  int get count => items.length;

  double get totalSell => items.fold(0.0, (s, e) => s + e.totalSellPrice);

  double? get totalCost {
    final with_ = items.where((e) => e.costPrice != null).toList();
    if (with_.isEmpty) return null;
    return with_.fold<double>(0.0, (s, e) => s + e.totalCostPrice!);
  }

  double? get totalWholesale {
    final with_ = items.where((e) => e.wholesalePrice != null).toList();
    if (with_.isEmpty) return null;
    return with_.fold<double>(0.0, (s, e) => s + e.totalWholesalePrice!);
  }

  double? get marginPct {
    final cost = totalCost;
    if (cost == null || totalSell == 0) return null;
    return (totalSell - cost) / totalSell * 100;
  }

  int get noCostCount => items.where((e) => e.costPrice == null).length;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen> {
  // Empty set = All. Each element: 'pending'|'urgent'|'available'|'deferred'
  final Set<String> _selected = {};

  static String _fmt(double price) {
    if (price == price.truncateToDouble()) return 'Rs. ${price.toInt()}';
    return 'Rs. ${price.toStringAsFixed(2)}';
  }

  List<DemandItemModel> _applyFilter(List<DemandItemModel> all) {
    if (_selected.isEmpty) return all.toList();
    return all.where((e) => _selected.contains(e.status)).toList();
  }

  void _toggle(String status) {
    setState(() {
      if (_selected.contains(status)) {
        _selected.remove(status);
      } else {
        _selected.add(status);
      }
    });
  }

  List<_CatData> _groupByCategory(
    List<DemandItemModel> items,
    List<CategoryModel> cats,
  ) {
    final result = <_CatData>[];
    for (final cat in cats) {
      final catItems = cat.id == 'general'
          ? items.where((e) => e.isGeneralCategory).toList()
          : items.where((e) => e.categoryId == cat.id).toList();
      if (catItems.isNotEmpty) {
        result.add(_CatData(name: cat.name, items: catItems));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final demand = context.watch<DemandProvider>();
    final catProv = context.watch<CategoryProvider>();

    final filtered = _applyFilter(demand.allItems.toList());
    final grouped = _groupByCategory(filtered, catProv.categories);

    // Overall totals
    final totalSell = filtered.fold(0.0, (s, e) => s + e.totalSellPrice);
    final costItems = filtered.where((e) => e.costPrice != null).toList();
    final totalCost = costItems.isEmpty
        ? null
        : costItems.fold<double>(0.0, (s, e) => s + e.totalCostPrice!);
    final wsItems = filtered.where((e) => e.wholesalePrice != null).toList();
    final totalWs = wsItems.isEmpty
        ? null
        : wsItems.fold<double>(0.0, (s, e) => s + e.totalWholesalePrice!);
    final profit = totalCost != null ? totalSell - totalCost : null;
    final marginPct =
        profit != null && totalSell > 0 ? profit / totalSell * 100 : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pricing Analytics'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.divider,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Overall summary card ──────────────────────────────────────
          _OverallSummaryCard(
            count: filtered.length,
            totalSell: totalSell,
            totalCost: totalCost,
            totalWs: totalWs,
            profit: profit,
            marginPct: marginPct,
            fmt: _fmt,
          ),

          // ── Multi-select status filter chips ─────────────────────────
          _MultiFilterBar(
            selected: _selected,
            onToggle: _toggle,
            onClearAll: () => setState(() => _selected.clear()),
            allItems: demand.allItems.toList(),
          ),

          // ── Monthly trend ────────────────────────────────────────
          if (filtered.isNotEmpty)
            _MonthlyTrendCard(items: filtered, fmt: _fmt),

          // ── Category breakdown list ─────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                    itemCount: grouped.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _CategoryCard(data: grouped[i], fmt: _fmt),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Overall summary card ─────────────────────────────────────────────────────

class _OverallSummaryCard extends StatelessWidget {
  const _OverallSummaryCard({
    required this.count,
    required this.totalSell,
    required this.totalCost,
    required this.totalWs,
    required this.profit,
    required this.marginPct,
    required this.fmt,
  });

  final int count;
  final double totalSell;
  final double? totalCost;
  final double? totalWs;
  final double? profit;
  final double? marginPct;
  final String Function(double) fmt;

  @override
  Widget build(BuildContext context) {
    final hasCost = totalCost != null;
    final profitPositive = profit != null && profit! >= 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.secondary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count items',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (marginPct != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: profitPositive
                        ? AppColors.statusAvailable.withValues(alpha: 0.12)
                        : AppColors.statusUrgent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        profitPositive
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 13,
                        color: profitPositive
                            ? AppColors.statusAvailable
                            : AppColors.statusUrgent,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${marginPct!.toStringAsFixed(1)}% margin',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: profitPositive
                              ? AppColors.statusAvailable
                              : AppColors.statusUrgent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryCell(
                  label: 'Sell Total',
                  value: fmt(totalSell),
                  color: AppColors.statusAvailable,
                  isMain: true,
                ),
              ),
              if (hasCost) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _SummaryCell(
                    label: 'Cost Total',
                    value: fmt(totalCost!),
                    color: AppColors.secondary,
                    isMain: false,
                  ),
                ),
              ],
              if (totalWs != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _SummaryCell(
                    label: 'Wholesale',
                    value: fmt(totalWs!),
                    color: const Color(0xFF7E57C2),
                    isMain: false,
                  ),
                ),
              ],
              if (profit != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _SummaryCell(
                    label: 'Profit',
                    value: fmt(profit!),
                    color: profitPositive
                        ? AppColors.statusAvailable
                        : AppColors.statusUrgent,
                    isMain: false,
                  ),
                ),
              ],
            ],
          ),
          if (!hasCost)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 12,
                      color: Colors.grey.shade500),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Cost prices not set — add them via item edit to see profit margin.',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
    required this.isMain,
  });

  final String label;
  final String value;
  final Color color;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isMain ? 0.09 : 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: isMain ? 13 : 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Multi-select status filter bar ──────────────────────────────────────────

class _MultiFilterBar extends StatelessWidget {
  const _MultiFilterBar({
    required this.selected,
    required this.onToggle,
    required this.onClearAll,
    required this.allItems,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onClearAll;
  final List<DemandItemModel> allItems;

  @override
  Widget build(BuildContext context) {
    final pendingCount = allItems.where((e) => e.isPending).length;
    final urgentCount = allItems.where((e) => e.isUrgent).length;
    final availableCount = allItems.where((e) => e.isAvailable).length;
    final deferredCount = allItems.where((e) => e.isDeferred).length;

    final opts = [
      _ChipOpt('pending', 'Pending', pendingCount, AppColors.statusPending),
      _ChipOpt('urgent', 'Urgent', urgentCount, AppColors.statusUrgent),
      _ChipOpt('available', 'Available', availableCount, AppColors.statusAvailable),
      _ChipOpt('deferred', 'Deferred', deferredCount, AppColors.statusDeferred),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                selected.isEmpty
                    ? 'Showing: All'
                    : 'Showing: ${selected.map((s) => _capitalize(s)).join(', ')}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (selected.isNotEmpty)
                GestureDetector(
                  onTap: onClearAll,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: opts.map((opt) {
              final isOn = selected.contains(opt.key);
              return GestureDetector(
                onTap: () => onToggle(opt.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOn
                        ? opt.color.withValues(alpha: 0.12)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOn ? opt.color : Colors.grey.shade300,
                      width: isOn ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isOn ? FontWeight.w700 : FontWeight.w500,
                          color:
                              isOn ? opt.color : Colors.grey.shade600,
                        ),
                      ),
                      if (opt.count > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isOn
                                ? opt.color.withValues(alpha: 0.15)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${opt.count}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isOn
                                  ? opt.color
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _ChipOpt {
  const _ChipOpt(this.key, this.label, this.count, this.color);
  final String key;
  final String label;
  final int count;
  final Color color;
}

// ─── Category card ────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({required this.data, required this.fmt});

  final _CatData data;
  final String Function(double) fmt;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final marginPct = d.marginPct;
    final hasCost = d.totalCost != null;
    final profitPositive =
        marginPct != null && marginPct >= 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.label_rounded,
                        size: 17, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          '${d.count} items',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Margin badge
                  if (marginPct != null)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: profitPositive
                            ? AppColors.statusAvailable.withValues(alpha: 0.10)
                            : AppColors.statusUrgent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${marginPct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: profitPositive
                              ? AppColors.statusAvailable
                              : AppColors.statusUrgent,
                        ),
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── Price row ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _MiniPriceChip(
                    label: 'Sell',
                    value: widget.fmt(d.totalSell),
                    color: AppColors.statusAvailable,
                  ),
                  if (hasCost) ...[
                    const SizedBox(width: 6),
                    _MiniPriceChip(
                      label: 'Cost',
                      value: widget.fmt(d.totalCost!),
                      color: AppColors.secondary,
                    ),
                  ],
                  if (d.totalWholesale != null) ...[
                    const SizedBox(width: 6),
                    _MiniPriceChip(
                      label: 'WS',
                      value: widget.fmt(d.totalWholesale!),
                      color: const Color(0xFF7E57C2),
                    ),
                  ],
                  if (!hasCost && d.noCostCount > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${d.noCostCount} without cost',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Expanded items list ──────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1, thickness: 1),
            ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: d.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (_, i) {
                final item = d.items[i];
                return _ItemPriceRow(item: item, fmt: widget.fmt);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniPriceChip extends StatelessWidget {
  const _MiniPriceChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemPriceRow extends StatelessWidget {
  const _ItemPriceRow({required this.item, required this.fmt});

  final DemandItemModel item;
  final String Function(double) fmt;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (item.status) {
      'urgent' => AppColors.statusUrgent,
      'available' => AppColors.statusAvailable,
      'deferred' => AppColors.statusDeferred,
      _ => AppColors.statusPending,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (item.quantityInt > 1)
            Text(
              '${item.quantityInt}×',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          Text(
            fmt(item.totalSellPrice),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.statusAvailable,
            ),
          ),
          if (item.costPrice != null) ...[
            Text(
              '  /  ${fmt(item.totalCostPrice!)}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.price_change_outlined,
              size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No items for selected filter',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Monthly Trend Card ───────────────────────────────────────────────────────

class _MonthlyTrendCard extends StatelessWidget {
  const _MonthlyTrendCard({required this.items, required this.fmt});

  final List<DemandItemModel> items;
  final String Function(double) fmt;

  @override
  Widget build(BuildContext context) {
    // Build last 6 months bucket map
    final now = DateTime.now();
    final months = <String, _MonthBucket>{};
    const monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    // Initialize last 6 months (including current)
    for (int i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final label = '${monthNames[d.month]} ${d.year % 100 < 10 ? '0${d.year % 100}' : '${d.year % 100}'}';
      months[key] = _MonthBucket(label: label);
    }

    // Fill buckets from items
    for (final item in items) {
      final d = item.addedBy.at;
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      if (months.containsKey(key)) {
        months[key]!.count++;
        months[key]!.sellTotal += item.totalSellPrice;
      }
    }

    final buckets = months.values.toList();
    final maxSell = buckets.fold<double>(
        0.0, (m, b) => b.sellTotal > m ? b.sellTotal : m);
    final maxCount = buckets.fold<int>(
        0, (m, b) => b.count > m ? b.count : m);

    if (maxCount == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6750A4).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6750A4).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6750A4).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    size: 16, color: Color(0xFF6750A4)),
              ),
              const SizedBox(width: 8),
              const Text(
                'Monthly Trend',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(last 6 months)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bar chart
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: buckets.asMap().entries.map((entry) {
                final b = entry.value;
                final isLast = entry.key == buckets.length - 1;
                final barFraction = maxSell > 0 ? b.sellTotal / maxSell : 0.0;
                final barH = 50.0 * barFraction;
                final isCurrentMonth = entry.key == 5;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Count badge
                        if (b.count > 0)
                          Text(
                            '${b.count}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isCurrentMonth
                                  ? const Color(0xFF6750A4)
                                  : Colors.grey.shade500,
                            ),
                          ),
                        const SizedBox(height: 2),
                        // Bar
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          width: double.infinity,
                          height: b.count == 0 ? 3 : barH.clamp(6.0, 50.0),
                          decoration: BoxDecoration(
                            color: b.count == 0
                                ? Colors.grey.shade200
                                : isCurrentMonth
                                    ? const Color(0xFF6750A4)
                                    : const Color(0xFF6750A4)
                                        .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Month label
                        Text(
                          b.label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isCurrentMonth
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isCurrentMonth
                                ? const Color(0xFF6750A4)
                                : Colors.grey.shade400,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Sell total for current month
          if (buckets.last.sellTotal > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: Color(0xFF6750A4)),
                const SizedBox(width: 4),
                Text(
                  'This month: ${fmt(buckets.last.sellTotal)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6750A4),
                  ),
                ),
                const Spacer(),
                Text(
                  '${buckets.last.count} items',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthBucket {
  final String label;
  int count = 0;
  double sellTotal = 0.0;

  _MonthBucket({required this.label});
}
