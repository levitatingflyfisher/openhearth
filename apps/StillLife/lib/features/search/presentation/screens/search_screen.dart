import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../inventory/domain/entities/item.dart';
import '../../../inventory/presentation/controllers/inventory_controller.dart';
import '../../../inventory/presentation/controllers/photo_controller.dart';
import '../../../inventory/presentation/widgets/item_list_tile.dart';
import '../../../locations/domain/entities/room.dart';
import '../../../locations/presentation/controllers/location_controller.dart';
import '../../data/services/saved_search_service.dart';
import '../../domain/services/nl_query_parser.dart';
import '../controllers/search_controller.dart';
import 'package:still_life/core/widgets/failure_feedback.dart';
import 'package:still_life/core/widgets/read_failure.dart';
import 'package:openhearth_design/openhearth_design.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _saveSearch() async {
    final q = _query.trim();
    if (q.isEmpty) return;
    await ref
        .read(savedSearchServiceProvider)
        .save(SavedSearch(label: q, query: q));
    ref.invalidate(savedSearchesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final parser = ref.watch(nlQueryParserProvider);
    final savedAsync = ref.watch(savedSearchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search all items…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        actions: [OhBarActions(children: [
          if (_query.isNotEmpty)
            OhBarAction(
              icon: Icons.close,
              label: 'Clear',
              onPressed: () {
                _ctrl.clear();
                setState(() => _query = '');
              },
            ),
        ])],
      ),
      body: OhPage(
        padding: EdgeInsets.zero,
        child: _query.isEmpty
          ? _EmptyState(
              savedAsync: savedAsync,
              onChipTap: (q) {
                _ctrl.text = q;
                setState(() => _query = q.trim());
              },
            )
          : _ResultsView(
              query: _query,
              parser: parser,
              onSave: _saveSearch,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final AsyncValue<List<SavedSearch>> savedAsync;
  final ValueChanged<String> onChipTap;

  const _EmptyState({required this.savedAsync, required this.onChipTap});

  @override
  Widget build(BuildContext context) {
    final searches = savedAsync.value ?? [];

    return Column(
      children: [
        // A failed read of the saved searches is said, never a row that
        // silently vanishes.
        if (savedAsync.hasError && !savedAsync.hasValue)
          Consumer(
            builder: (context, ref, _) => InlineReadError(
              title: 'Couldn’t read your saved searches',
              onRetry: () => ref.invalidate(savedSearchesProvider),
            ),
          )
        else if (searches.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: searches.length,
              separatorBuilder: (_, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = searches[i];
                return FilterChip(
                  label: Text(s.label),
                  onSelected: (_) => onChipTap(s.query),
                );
              },
            ),
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(60),
                ),
                const SizedBox(height: 12),
                Text(
                  'Type to search all items',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultsView extends ConsumerWidget {
  final String query;
  final NlQueryParser parser;
  final VoidCallback onSave;

  const _ResultsView({
    required this.query,
    required this.parser,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = parser.parse(query);
    // Use a stable provider that re-subscribes when [query] changes — the
    // family argument becomes part of the provider key, so prop changes
    // automatically swap streams without manual StreamBuilder bookkeeping.
    final asyncItems = parsed.hasStructuredFilters
        ? ref.watch(searchItemsProvider(query)) // dummy — fall through below
        : ref.watch(
            searchItemsProvider(
              parsed.residualText.isNotEmpty ? parsed.residualText : query,
            ),
          );
    // Structured-filter path needs the full ItemQuery — fall back to a
    // direct stream there since the simple text family can't represent it.
    final useStructured = parsed.hasStructuredFilters;

    return useStructured
        // Rereadable: Try again builds, and so reads, the stream again.
        ? Rereadable(
            builder: (context, reread) => StreamBuilder<List<Item>>(
            stream: ref.read(itemRepositoryProvider).watchItems(parsed.query),
            builder: (context, snapshot) {
              // Said, never "No results": the items are there, the read
              // failed.
              if (snapshot.hasError) {
                return loadFailure(
                  snapshot.error!,
                  snapshot.stackTrace,
                  title: "Couldn’t search your items",
                  onRetry: reread,
                );
              }
              final items = snapshot.data ?? <Item>[];
              return _renderResults(
                context,
                ref,
                items,
                isLoading:
                    snapshot.connectionState == ConnectionState.waiting &&
                    items.isEmpty,
              );
            },
          ))
        : asyncItems.when(
            data: (items) =>
                _renderResults(context, ref, items, isLoading: false),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => loadFailure(
              e,
              st,
              title: "Couldn’t search your items",
              onRetry: () => ref.invalidate(searchItemsProvider),
            ),
          );
  }

  Widget _renderResults(
    BuildContext context,
    WidgetRef ref,
    List<Item> items, {
    required bool isLoading,
  }) {
    final parsed = parser.parse(query);
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No results for “$query”',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    final primaryThumbs =
        ref.watch(primaryThumbnailsProvider).value ?? const {};
    return Column(
      children: [
        if (parsed.isWhereIs) _WhereIsCard(items: items),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_outline, size: 18),
              label: const Text('Save search'),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return ItemListTile(
                item: item,
                primaryPhotoBytes: primaryThumbs[item.id],
                onTap: () => context.pushNamed(
                  'itemDetail',
                  pathParameters: {'itemId': item.id},
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WhereIsCard extends ConsumerWidget {
  final List<Item> items;

  const _WhereIsCard({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsProvider);
    // A failed read of the rooms is said in the card, never "Unknown" for
    // a room that is there.
    final roomsFailed = roomsAsync.hasError && !roomsAsync.hasValue;
    final rooms = roomsAsync.value ?? <Room>[];
    final roomMap = {for (final r in rooms) r.id: r.name};
    final displayItems = items.take(3).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            if (roomsFailed)
              InlineReadError(
                title: 'Couldn’t read your rooms',
                onRetry: () => ref.invalidate(roomsProvider),
              ),
            ...displayItems.map((item) {
              final known = roomMap[item.roomId] ?? item.roomName;
              // With the rooms unread, a room not known is left out, never
              // called "Unknown".
              if (known == null && roomsFailed) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }
              final roomName = known ?? 'Unknown';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(150),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '  ›  ',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(150),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              roomName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(150),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
