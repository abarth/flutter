// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:coverage/coverage.dart' as coverage;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import '../base/file_system.dart';
import '../base/io.dart';
import '../dart/package_map.dart';
import '../globals.dart';

class CoverageLock {
  CoverageLock(this.collector) {
    assert(collector.enabled);
  }

  final CoverageCollector collector;

  final Completer<Null> _completer = new Completer<Null>();

  bool get isHeld => collector._currentLock == this;

  Future<Null> acquire() async {
    print('CoverageLock acquire $hashCode');
    while (collector._currentLock != null)
      await collector._currentLock._completer.future;
    collector._currentLock = this;
    print('CoverageLock acquired $hashCode');
  }

  void release() {
    print('CoverageLock release $hashCode');
    assert(isHeld);
    collector._currentLock = null;
    _completer.complete();
  }

  void releaseError(Object error, [StackTrace stackTrace]) {
    assert(isHeld);
    collector._currentLock = null;
    _completer.completeError(error, stackTrace);
  }

  void ensureReleased() {
    if (isHeld)
      release();
  }
}

/// A class that's used to collect coverage data during tests.
class CoverageCollector {
  CoverageCollector._();

  /// The singleton instance of the coverage collector.
  static final CoverageCollector instance = new CoverageCollector._();

  /// By default, coverage collection is not enabled. Set [enabled] to true
  /// to turn on coverage collection.
  bool enabled = false;
  int observatoryPort;

  CoverageLock _currentLock;

  Future<Null> collectCoverageData({
    @required CoverageLock lock,
    @required String host,
    @required int port,
    @required Process processToKill,
  }) async {
    assert(enabled);
    assert(lock.isHeld);
    try {
      final int pid = processToKill.pid;
      printTrace('collecting coverage data from pid $pid on port $port');
      Map<dynamic, dynamic> data = await coverage.collect(host, port, false, false);
      printTrace('done collecting coverage data from pid $pid');
      _addHitmap(coverage.createHitmap(data['coverage']));
      printTrace('done merging data from pid $pid into global coverage map');
    } catch (error, stackTrace) {
      lock.releaseError(error, stackTrace);
      return;
    } finally {
      processToKill.kill();
    }
    _currentLock.release();
  }

  Map<String, dynamic> _globalHitmap;

  void _addHitmap(Map<String, dynamic> hitmap) {
    if (_globalHitmap == null)
      _globalHitmap = hitmap;
    else
      coverage.mergeHitmaps(hitmap, _globalHitmap);
  }

  /// Returns a future that will complete with the formatted coverage data
  /// (using [formatter]) once all coverage data has been collected.
  ///
  /// This must only be called if this collector is [enabled].
  Future<String> formatCoverageData({ coverage.Formatter formatter}) async {
    assert(enabled);
    final CoverageLock lock = new CoverageLock(this);
    await lock.acquire();
    try {
      printTrace('formating coverage data');
      if (_globalHitmap == null)
        return null;
      if (formatter == null) {
        coverage.Resolver resolver = new coverage.Resolver(packagesPath: PackageMap.globalPackagesPath);
        String packagePath = fs.currentDirectory.path;
        List<String> reportOn = <String>[path.join(packagePath, 'lib')];
        formatter = new coverage.LcovFormatter(resolver, reportOn: reportOn, basePath: packagePath);
      }
      return await formatter.format(_globalHitmap);
    } finally {
      lock.release();
    }
  }
}
