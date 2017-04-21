// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('ListView itemSpacing', (WidgetTester tester) async {
    final List<Widget> children = new List<Widget>.generate(20, (int i) {
      return new Container(height: 190.0, child: new Text('$i'));
    });

    await tester.pumpWidget(
      new ListView(
        itemSpacing: 5.0,
        children: children,
      ),
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsNothing);

    expect(tester.getBottomLeft(find.text('0')), const Offset(0.0, 190.0));
    expect(tester.getTopLeft(find.text('1')), const Offset(0.0, 195.0));
    expect(tester.getBottomLeft(find.text('1')), const Offset(0.0, 385.0));
    expect(tester.getTopLeft(find.text('2')), const Offset(0.0, 390.0));

    await tester.drag(find.byType(Scrollable), const Offset(0.0, -179.0));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsNothing);

    await tester.drag(find.byType(Scrollable), const Offset(0.0, -2.0));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsNothing);
  });
}
