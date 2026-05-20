import 'package:cim_forge/features/schema/metamodel.dart';
import 'package:flutter/material.dart';

/// A read-only browser for a [Metamodel]: lists CIM classes in their
/// inheritance tree on the left, attributes and associations (own +
/// inherited) of the selected class on the right.
class ClassBrowserPanel extends StatelessWidget {
  const ClassBrowserPanel({
    required this.metamodel,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final Metamodel metamodel;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roots = _rootClasses(metamodel);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final root in roots)
                  ..._classRows(context, root, depth: 0),
              ],
            ),
          ),
        ),
        Expanded(
          child: selected == null
              ? const _EmptyState()
              : _ClassDetails(
                  metamodel: metamodel,
                  className: selected!,
                ),
        ),
      ],
    );
  }

  Iterable<Widget> _classRows(
    BuildContext context,
    CimClass cls, {
    required int depth,
  }) sync* {
    yield _ClassRow(
      cls: cls,
      depth: depth,
      selected: cls.name == selected,
      onTap: () => onSelect(cls.name),
    );
    final children = _childrenOf(metamodel, cls.name);
    for (final child in children) {
      yield* _classRows(context, child, depth: depth + 1);
    }
  }

  static List<CimClass> _rootClasses(Metamodel m) {
    final list = m.classes.where((c) => c.parent == null).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  static List<CimClass> _childrenOf(Metamodel m, String parent) {
    final list = m.classes.where((c) => c.parent == parent).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({
    required this.cls,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final CimClass cls;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
        padding: EdgeInsets.only(left: 12.0 + depth * 16, right: 12),
        height: 28,
        alignment: Alignment.centerLeft,
        child: Text(
          cls.name,
          style: Theme.of(context).textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select a class to see its attributes and associations',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _ClassDetails extends StatelessWidget {
  const _ClassDetails({required this.metamodel, required this.className});

  final Metamodel metamodel;
  final String className;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chain = metamodel.ancestorChain(className);
    final attrs = metamodel.attributesOf(className);
    final assocs = metamodel.associationsOf(className);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(className, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        if (chain.length > 1)
          Text(
            'Inherits: '
            '${chain.take(chain.length - 1).map((c) => c.name).join(' → ')}',
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 16),
        Text('Attributes', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (attrs.isEmpty)
          Text('(none)', style: theme.textTheme.bodySmall)
        else
          for (final a in attrs)
            _PropertyRow(
              name: a.name,
              type: a.dataType,
              cardinality: a.cardinality.toString(),
            ),
        const SizedBox(height: 16),
        Text('Associations', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (assocs.isEmpty)
          Text('(none)', style: theme.textTheme.bodySmall)
        else
          for (final a in assocs)
            _PropertyRow(
              name: a.name,
              type: a.targetClass,
              cardinality: a.cardinality.toString(),
            ),
      ],
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.name,
    required this.type,
    required this.cardinality,
  });

  final String name;
  final String type;
  final String cardinality;

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name, style: mono)),
          const SizedBox(width: 8),
          Text(type, style: mono),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              cardinality,
              style: mono,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
