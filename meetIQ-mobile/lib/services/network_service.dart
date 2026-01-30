import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Stream<ConnectivityResult> get onChange => _connectivity.onConnectivityChanged.map(
        (results) => results.isNotEmpty ? results.first : ConnectivityResult.none,
      );
}
