import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../shared/models.dart';

final projectionProvider = FutureProvider<Projection>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getProjection();
});

class WhatIfState {
  const WhatIfState({this.change = const WhatIfChange(), this.result, this.loading = false, this.error});
  final WhatIfChange change;
  final WhatIfResult? result;
  final bool loading;
  final String? error;

  WhatIfState copyWith({WhatIfChange? change, WhatIfResult? result, bool? loading, String? error, bool clearResult = false}) =>
      WhatIfState(
        change: change ?? this.change,
        result: clearResult ? null : (result ?? this.result),
        loading: loading ?? this.loading,
        error: error,
      );
}

/// Menghitung ulang proyeksi saat slider digeser. Permintaan di-debounce 300 ms agar tidak
/// memanggil API di setiap piksel geseran.
class WhatIfController extends Notifier<WhatIfState> {
  static const debounce = Duration(milliseconds: 300);
  Timer? _timer;

  @override
  WhatIfState build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(projectionProvider, (_, _) {
      _timer?.cancel();
      state = const WhatIfState();
    });
    return const WhatIfState();
  }

  void update(WhatIfChange change) {
    _timer?.cancel();
    if (change.isEmpty) {
      state = const WhatIfState();
      return;
    }
    state = state.copyWith(change: change, loading: true);
    _timer = Timer(debounce, () => _run(change));
  }

  void reset() => update(const WhatIfChange());

  Future<void> _run(WhatIfChange change) async {
    try {
      final result = await ref.read(apiProvider).whatIf(change);
      if (identical(state.change, change)) state = state.copyWith(result: result, loading: false);
    } on ApiException catch (e) {
      if (identical(state.change, change)) state = state.copyWith(loading: false, error: e.message);
    }
  }
}

final whatIfProvider = NotifierProvider<WhatIfController, WhatIfState>(WhatIfController.new);
