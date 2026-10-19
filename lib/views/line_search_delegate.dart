import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/bridge_generated.dart';
import '../providers/timetable_provider.dart';

/// SearchDelegate that queries local SQLite R-Tree / stop indexes across both BKK and MÁV.
class LineAndStopSearchDelegate extends SearchDelegate<StopNode?> {
  final WidgetRef ref;

  LineAndStopSearchDelegate(this.ref)
      : super(
          searchFieldLabel: 'Search BKK / MÁV stations (e.g. Kelenföld, Keleti)...',
        );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchResultsList(
      query: query,
      onSelected: (stop) => close(context, stop),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SearchResultsList(
      query: query,
      onSelected: (stop) => close(context, stop),
    );
  }
}

class _SearchResultsList extends ConsumerWidget {
  final String query;
  final ValueChanged<StopNode> onSelected;

  const _SearchResultsList({
    required this.query,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) {
      return const Center(
        child: Text(
          'Type a station or stop name across Hungary (BKK & MÁV)',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final resultsAsync = ref.watch(stopSearchProvider(query));
    return resultsAsync.when(
      data: (stops) {
        if (stops.isEmpty) {
          return const Center(
            child: Text(
              'No matching BKK or MÁV stations found.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ListView.separated(
          itemCount: stops.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Colors.white10),
          itemBuilder: (context, idx) {
            final stop = stops[idx];
            return ListTile(
              leading: Icon(
                stop.isMultimodalHub
                    ? Icons.hub_outlined
                    : (stop.operator == Operator.mav
                        ? Icons.train
                        : Icons.directions_transit),
                color: stop.isMultimodalHub
                    ? const Color(0xFF818CF8)
                    : (stop.operator == Operator.mav
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFF22D3EE)),
              ),
              title: Text(
                stop.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                stop.isMultimodalHub
                    ? 'Multimodal Hub (BKK + MÁV) • ${stop.id}'
                    : '${stop.operator.name.toUpperCase()} • ${stop.id}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () => onSelected(stop),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          'Search error: $err',
          style: const TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }
}
