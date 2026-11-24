import 'package:flutter/material.dart';

import 'ledger.dart';
import 'ledger_store.dart';
import 'ui.dart';

Future<String?> editEntry(
  BuildContext context,
  LedgerStore store, [
  Entry? entry,
]) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: AnimationStyle(
    duration: motion(context, 240),
    reverseDuration: motion(context, 180),
  ),
  builder: (_) => _EntryEditor(store: store, entry: entry),
);

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.store, this.entry});
  final LedgerStore store;
  final Entry? entry;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.entry == null ? '' : amountText(widget.entry!.cents),
  );
  late final counterparty = TextEditingController(
    text: widget.entry?.counterparty,
  );
  late var kind = widget.entry?.kind ?? EntryKind.expense;
  late var date = widget.entry?.date ?? day(DateTime.now());
  late String? category = widget.entry?.category;
  late Future<List<EntryOption>> options = widget.store.options();
  bool busy = false;
  bool showCategoryError = false;

  @override
  void dispose() {
    amount.dispose();
    counterparty.dispose();
    super.dispose();
  }

  Future<void> addOption(List<String> existing) async {
    final optionForm = GlobalKey<FormState>();
    String label = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加${kind.categoryLabel}'),
        content: Form(
          key: optionForm,
          child: TextFormField(
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(labelText: kind.categoryLabel),
            onSaved: (value) => label = value!.trim(),
            validator: (value) {
              final normalized = value?.trim() ?? '';
              if (normalized.isEmpty) return '请输入名称';
              if (normalized.length > 40) return '最多输入 40 个字符';
              if (existing.contains(normalized)) return '已存在同名候选值';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final state = optionForm.currentState!;
              if (state.validate()) {
                state.save();
                Navigator.pop(context, label);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    await run(() async {
      await widget.store.saveOption(EntryOption(kind, value));
      if (!mounted) return;
      setState(() {
        category = value;
        options = widget.store.options();
        showCategoryError = false;
      });
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) notice(context, '写入账本失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final valid = form.currentState!.validate();
    setState(() => showCategoryError = category == null);
    if (!valid || category == null) return;
    await run(() async {
      final name = counterparty.text.trim();
      final entry = Entry(
        id: widget.entry?.id ?? newId(),
        kind: kind,
        cents: parseAmount(amount.text)!,
        category: category!,
        date: date,
        counterparty: name.isEmpty ? null : name,
      );
      await widget.store.saveEntry(entry);
      if (mounted) Navigator.pop(context, entry.id);
    });
  }

  Future<void> remove() async {
    if (!await confirm(
          context,
          '删除这笔账目？',
          '删除后将从账本和统计中移除。',
          '删除',
          destructive: true,
        ) ||
        !mounted)
      return;
    await run(() async {
      await widget.store.deleteEntry(widget.entry!.id);
      if (mounted) Navigator.pop(context, '');
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      top: false,
      child: _KeyboardInset(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.entry == null ? '记一笔' : '编辑账目',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SlidingSegments<EntryKind>(
                  values: EntryKind.values,
                  label: (kind) => kind.label,
                  selected: kind,
                  onChanged: busy
                      ? null
                      : (selection) => setState(() {
                          if (kind != selection) {
                            kind = selection;
                            category = null;
                            showCategoryError = false;
                          }
                        }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: const InputDecoration(
                    labelText: '金额',
                    prefixText: '¥ ',
                  ),
                  validator: (value) => parseAmount(value ?? '') == null
                      ? '请输入大于零的金额，最多两位小数'
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  kind.categoryLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FutureBuilder<List<EntryOption>>(
                  future: options,
                  builder: (context, snapshot) {
                    return SlidingEntryContent(
                      kind: kind,
                      builder: (side) {
                        final values = <String>{
                          for (final option in [
                            ...EntryOption.defaults,
                            ...?snapshot.data,
                          ])
                            if (option.kind == side) option.label,
                          if (side == kind) ?category,
                        }.toList();
                        return Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                            for (final value in values)
                              ChoiceChip(
                                label: Text(value),
                                selected: side == kind && category == value,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() {
                                        category = value;
                                        showCategoryError = false;
                                      }),
                                chipAnimationStyle: ChipAnimationStyle(
                                  selectAnimation: AnimationStyle(
                                    duration: motion(context, 140),
                                  ),
                                ),
                              ),
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 18),
                              label: const Text('添加'),
                              onPressed: busy ? null : () => addOption(values),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                if (showCategoryError)
                  Text(
                    '请选择${kind.categoryLabel}',
                    style: const TextStyle(color: expenseColor),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: counterparty,
                  enabled: !busy,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: kind == EntryKind.income ? '发钱方（选填）' : '收钱方（选填）',
                    counterText: '',
                  ),
                  validator: (value) =>
                      (value?.length ?? 0) > 80 ? '最多输入 80 个字符' : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(9998, 12, 31),
                          );
                          if (mounted && picked != null)
                            setState(() => date = picked);
                        },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('发生日期  ${dayKey(date)}'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? '正在保存…' : '保存账目'),
                ),
                if (widget.entry != null)
                  TextButton(
                    onPressed: busy ? null : remove,
                    style: TextButton.styleFrom(foregroundColor: expenseColor),
                    child: const Text('删除账目'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('editor-keyboard-inset'),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}
