import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../inventory/domain/repositories/item_repository.dart';
import '../../../inventory/presentation/controllers/photo_controller.dart';
import '../../../inventory/presentation/controllers/quantity_controller.dart';
import '../../../inventory/presentation/helpers/item_add_helpers.dart';
import '../../../inventory/presentation/widgets/item_list_tile.dart';
import '../../../inventory/presentation/widgets/speed_dial_fab.dart';
import '../../../loans/presentation/controllers/loan_controller.dart';
import '../controllers/location_controller.dart';
import 'package:still_life/core/widgets/read_failure.dart';
import 'package:openhearth_design/openhearth_design.dart';

class ContainerDetailScreen extends ConsumerWidget {
  final String containerId;

  const ContainerDetailScreen({super.key, required this.containerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final containerAsync = ref.watch(containerDetailProvider(containerId));
    final itemRepo = ref.watch(itemRepositoryProvider);
    final loanedIds = ref.watch(activeLoanedItemIdsProvider).value ?? {};
    final primaryThumbs =
        ref.watch(primaryThumbnailsProvider).value ?? const {};
    final lowStockIds =
        ref
            .watch(lowStockItemsProvider)
            .value
            ?.map((i) => i.id)
            .toSet() ??
        {};
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: containerAsync.when(
          data: (c) => Text(c?.name ?? 'Container'),
          loading: () => const Text('Container'),
          error: (_, _) => const Text('Container'),
        ),
        actions: [OhBarActions(children: [
          OhBarAction(
            icon: Icons.qr_code_outlined,
            label: 'QR label',
            onPressed: () => context.pushNamed(
              'containerLabel',
              pathParameters: {'containerId': containerId},
            ),
          ),
        ])],
      ),
      body: OhPage(
        padding: EdgeInsets.zero,
        // Try again makes the stream, and so the read, again.
        child: Rereadable(
        builder: (context, reread) => StreamBuilder(
        stream: itemRepo.watchItems(ItemQuery(containerId: containerId)),
        builder: (context, snapshot) {
          // Said, never drawn as "No items in this container".
          if (snapshot.hasError) {
            return OhReadError(
              title: 'Couldn’t read what’s in this container',
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
              onRetry: reread,
            );
          }
          final items = snapshot.data ?? [];

          if (snapshot.connectionState == ConnectionState.waiting &&
              items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No items in this container',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // A failed read of the loans or the low-stock list.
              const ItemMarksReadError(),
              Expanded(
                child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ItemListTile(
                item: item,
                primaryPhotoBytes: primaryThumbs[item.id],
                isOnLoan: loanedIds.contains(item.id),
                isLowStock: lowStockIds.contains(item.id),
                quantity: item.quantity,
                quantityUnit: item.quantityUnit,
                onDecrement: item.isConsumable
                    ? () => ref
                          .read(quantityControllerProvider)
                          .decrement(item.id)
                    : null,
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
        },
      ),
      ),
      ),
      floatingActionButton: containerAsync.when(
        data: (container) => SpeedDialFab(
          onPhoto: () => onPhotoAddItem(
            context,
            ref,
            roomId: container?.roomId,
            containerId: containerId,
          ),
          onVoice: kIsWeb
              ? null
              : () => onVoiceAddItem(
            context,
            ref,
            roomId: container?.roomId,
            containerId: containerId,
          ),
          // The capture flow scopes to a room; the container's room is the
          // closest honest target (containers aren't selectable there).
          onVideo: kIsWeb
              ? null
              : () => context.pushNamed(
                    'videoCapture',
                    queryParameters: {
                      if (container?.roomId != null)
                        'roomId': container!.roomId,
                    },
                  ),
          onManual: () => context.pushNamed(
            'addItem',
            queryParameters: {
              if (container?.roomId != null) 'roomId': container!.roomId,
              'containerId': containerId,
            },
          ),
        ),
        loading: () => null,
        error: (_, _) => null,
      ),
    );
  }
}
