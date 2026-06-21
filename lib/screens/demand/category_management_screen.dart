import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/category_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/demand_provider.dart';

class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Categories'),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Category',
            onPressed: () => _showAddDialog(context),
          ),
        ],
      ),
      body: Consumer2<CategoryProvider, DemandProvider>(
        builder: (context, catProvider, demandProvider, _) {
          final all = catProvider.categories;
          final allItems = demandProvider.allItems;

          // Compute item counts per category
          final catCounts = <String, int>{};
          for (final cat in all) {
            if (cat.id == 'general') {
              catCounts[cat.id] =
                  allItems.where((e) => e.isGeneralCategory).length;
            } else {
              catCounts[cat.id] =
                  allItems.where((e) => e.categoryId == cat.id).length;
            }
          }
          final totalItems = allItems.length;

          return Column(
            children: [
              // ── Summary header ─────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.label_rounded,
                          color: Colors.purple.shade600, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${all.length} ${all.length == 1 ? 'Category' : 'Categories'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          '$totalItems total item${totalItems == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Mini distribution bars
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: all.take(6).toList().asMap().entries.map((e) {
                        final count = catCounts[e.value.id] ?? 0;
                        final frac = totalItems > 0
                            ? (count / totalItems).clamp(0.08, 1.0)
                            : 0.08;
                        return Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Tooltip(
                            message: '${e.value.name}: $count',
                            child: Container(
                              width: 6,
                              height: 28.0 * frac,
                              decoration: BoxDecoration(
                                color: _colorForIndex(e.key),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              // ── Category list ───────────────────────────────────────
              Expanded(
                child: all.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.label_off_rounded,
                                size: 52, color: Colors.grey.shade300),
                            const SizedBox(height: 14),
                            Text('No categories yet',
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            Text('Tap + to add your first category',
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 120),
                        itemCount: all.length,
                        itemBuilder: (ctx, i) {
                          final cat = all[i];
                          final isGeneral = cat.id == 'general';
                          final count = catCounts[cat.id] ?? 0;
                          final color = _colorForIndex(i);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () {
                                // Set filter and always navigate to demand list
                                context
                                    .read<DemandProvider>()
                                    .setCategoryFilter(cat.id);
                                context.go('/demand');
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: Colors.grey.shade200),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.03),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Color avatar with initial
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color:
                                              color.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: color
                                                  .withValues(alpha: 0.30)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            cat.name.isNotEmpty
                                                ? cat.name[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              color: color,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 19,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Name + subtitle
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    cat.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 15,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isGeneral) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.blue.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      border: Border.all(
                                                          color: Colors
                                                              .blue.shade200),
                                                    ),
                                                    child: Text('Default',
                                                        style: TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Colors.blue
                                                                .shade700)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.filter_list_rounded,
                                                  size: 11,
                                                  color: color.withValues(alpha: 0.7),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Tap to view in Demand Book',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: color.withValues(alpha: 0.7),
                                                      fontWeight: FontWeight.w500),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      // Item count badge
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 11, vertical: 6),
                                            decoration: BoxDecoration(
                                              color:
                                                  color.withValues(alpha: 0.10),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: color.withValues(
                                                      alpha: 0.25)),
                                            ),
                                            child: Text(
                                              '$count',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color: color,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            count == 1 ? 'item' : 'items',
                                            style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.grey.shade500),
                                          ),
                                        ],
                                      ),

                                      // Edit / Delete buttons (non-general only)
                                      if (!isGeneral) ...[
                                        const SizedBox(width: 8),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _ActionBtn(
                                              icon: Icons.edit_outlined,
                                              color: Colors.grey.shade600,
                                              bg: Colors.grey.shade100,
                                              onTap: () => _showEditDialog(
                                                  context, cat),
                                            ),
                                            const SizedBox(height: 6),
                                            _ActionBtn(
                                              icon: Icons.delete_outline,
                                              color: Colors.red.shade500,
                                              bg: Colors.red.shade50,
                                              onTap: () => _confirmDelete(
                                                  context,
                                                  cat,
                                                  catProvider,
                                                  count),
                                            ),
                                          ],
                                        ),
                                      ] else ...[
                                        // For general category, show navigate arrow
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 14,
                                          color: Colors.grey.shade400,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Category',
            style: TextStyle(fontWeight: FontWeight.w600)),
        shape: const StadiumBorder(),
      ),
    );
  }

  Color _colorForIndex(int i) {
    const colors = [
      Color(0xFF1565C0),
      Color(0xFF2E7D32),
      Color(0xFF6A1B9A),
      Color(0xFFE65100),
      Color(0xFF00695C),
      Color(0xFF4527A0),
      Color(0xFF558B2F),
      Color(0xFFC62828),
    ];
    return colors[i % colors.length];
  }

  void _showAddDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.label_rounded, color: Colors.purple, size: 22),
            SizedBox(width: 8),
            Text('Add Category'),
          ],
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Category name',
            hintText: 'e.g. Electronics, Grocery, Clothing…',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onSubmitted: (_) => _doAdd(ctx, context, ctrl),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => _doAdd(ctx, context, ctrl),
              child: const Text('Add')),
        ],
      ),
    );
  }

  void _doAdd(BuildContext dialogCtx, BuildContext screenCtx,
      TextEditingController ctrl) {
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(dialogCtx);
    screenCtx.read<CategoryProvider>().addCategory(name);
  }

  void _showEditDialog(BuildContext context, CategoryModel cat) {
    final ctrl = TextEditingController(text: cat.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Colors.purple, size: 22),
            SizedBox(width: 8),
            Text('Edit Category'),
          ],
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Category name',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onSubmitted: (_) => _doEdit(ctx, context, cat, ctrl),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => _doEdit(ctx, context, cat, ctrl),
              child: const Text('Save')),
        ],
      ),
    );
  }

  void _doEdit(BuildContext dialogCtx, BuildContext screenCtx,
      CategoryModel cat, TextEditingController ctrl) {
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(dialogCtx);
    screenCtx.read<CategoryProvider>().updateCategory(cat, name);
  }

  void _confirmDelete(BuildContext context, CategoryModel cat,
      CategoryProvider provider, int itemCount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('Delete Category?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete "${cat.name}"?'),
            if (itemCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$itemCount item${itemCount == 1 ? '' : 's'} in this category will be moved to General.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.orange.shade800,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'This category has no items.',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.deleteCategory(cat.id);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Small action button helper ────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
